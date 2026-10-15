#include "WhisperModels.h"

#include "WhisperEngine.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QHash>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPointer>
#include <QStandardPaths>
#include <QTimer>
#include <QtConcurrent>

namespace of {

QString displayName(WhisperModel m)
{
    switch (m) {
    case WhisperModel::Base: return QStringLiteral("Rápido");
    case WhisperModel::Small: return QStringLiteral("Equilibrado");
    case WhisperModel::Turbo: return QStringLiteral("Máxima precisão");
    }
    return {};
}

QString fileName(WhisperModel m)
{
    switch (m) {
    case WhisperModel::Base: return QStringLiteral("ggml-base.bin");
    case WhisperModel::Small: return QStringLiteral("ggml-small.bin");
    case WhisperModel::Turbo: return QStringLiteral("ggml-large-v3-turbo-q5_0.bin");
    }
    return {};
}

qint64 byteSize(WhisperModel m)
{
    switch (m) {
    case WhisperModel::Base: return 147'951'465;
    case WhisperModel::Small: return 487'601'967;
    case WhisperModel::Turbo: return 574'041'195;
    }
    return 0;
}

QUrl downloadUrl(WhisperModel m)
{
    return QUrl(QStringLiteral("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/") + fileName(m));
}

QString sha256(WhisperModel m)
{
    switch (m) {
    case WhisperModel::Base: return QStringLiteral("60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe");
    case WhisperModel::Small: return QStringLiteral("1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b");
    case WhisperModel::Turbo: return QStringLiteral("394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2");
    }
    return {};
}

WhisperModel recommendedModel() { return WhisperModel::Small; }

ModelStore::ModelStore(const QString &directory, QObject *parent)
    : QObject(parent), m_directory(directory), m_jobs(std::make_unique<Impl>())
{
}

QString ModelStore::defaultDirectory()
{
    const QString custom = qEnvironmentVariable("OPENFRAME_MODELS_DIR");
    if (!custom.isEmpty())
        return custom;
    return QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + QStringLiteral("/Models");
}

ModelStore &ModelStore::shared()
{
    static ModelStore store(defaultDirectory());
    return store;
}

QString ModelStore::path(WhisperModel m) const { return QDir(m_directory).filePath(fileName(m)); }

bool ModelStore::isInstalled(WhisperModel m) const
{
    const QFileInfo info(path(m));
    return info.isFile() && info.size() == byteSize(m);
}

struct ModelStore::Impl {
    /// Um download em andamento.
    struct Job;
    QNetworkAccessManager *network = nullptr;
    QHash<WhisperModel, std::shared_ptr<Job>> jobs;
};

struct ModelStore::Impl::Job {
    QPointer<QNetworkReply> reply;
    QFile file;
    qint64 have = 0;
    qint64 size = 0;
    QString sha256;
    bool cancelled = false;
    bool started = false;
    qint64 lastReport = 0;
};

ModelStore::~ModelStore()
{
    for (const auto &job : std::as_const(m_jobs->jobs)) {
        job->cancelled = true;
        if (job->reply)
            job->reply->abort();
    }
}

void ModelStore::download(WhisperModel m) { download(m, downloadUrl(m), byteSize(m), sha256(m)); }

void ModelStore::download(WhisperModel m, const QUrl &source, qint64 size, const QString &sha)
{
    if (m_jobs->jobs.contains(m))
        return;
    auto job = std::make_shared<Impl::Job>();
    m_jobs->jobs.insert(m, job);
    job->size = size;
    job->sha256 = sha.toLower();
    QDir().mkpath(m_directory);
    job->file.setFileName(partialPath(m));
    if (!job->file.open(QIODevice::ReadWrite)) {
        const QString error = job->file.errorString();
        QTimer::singleShot(0, this, [this, m, error] { finish(m, false, error); });
        return;
    }
    job->have = job->file.size();
    if (job->have > size) {
        job->file.resize(0);
        job->have = 0;
    }
    job->file.seek(job->have);
    // Tudo já veio (download interrompido na conferência): só confere.
    const auto verify = [this, m, job] {
        job->file.close();
        if (job->have != job->size) {
            // Um arquivo maior que o esperado não serve para retomar.
            if (job->have > job->size)
                QFile::remove(partialPath(m));
            finish(m, false, QStringLiteral("O download veio incompleto (%1 de %2 bytes). Tente de novo.")
                                 .arg(job->have).arg(job->size));
            return;
        }
        emit downloadProgress(m, 1);
        // O sha256 de centenas de MB leva alguns segundos: fora da thread da interface.
        auto *watcher = new QFutureWatcher<QString>(this);
        connect(watcher, &QFutureWatcher<QString>::finished, this, [this, m, job, watcher] {
            watcher->deleteLater();
            const QString partial = partialPath(m), dest = path(m);
            if (job->cancelled) {
                finish(m, false, {});
            } else if (watcher->result() != job->sha256) {
                QFile::remove(partial);
                finish(m, false, QStringLiteral("O arquivo baixado está corrompido (o sha256 não confere). Tente de novo."));
            } else {
                QFile::remove(dest);
                if (QFile::rename(partial, dest))
                    finish(m, true, {});
                else
                    finish(m, false, QStringLiteral("Não foi possível mover o modelo para %1.").arg(dest));
            }
        });
        watcher->setFuture(QtConcurrent::run([file = partialPath(m)] { return sha256Of(file); }));
    };
    if (job->have == size) {
        QTimer::singleShot(0, this, verify);
        return;
    }

    if (!m_jobs->network)
        m_jobs->network = new QNetworkAccessManager(this);
    QNetworkRequest request(source);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    if (job->have > 0)
        request.setRawHeader("Range", QByteArrayLiteral("bytes=") + QByteArray::number(job->have) + '-');
    QNetworkReply *reply = m_jobs->network->get(request);
    job->reply = reply;
    emit downloadProgress(m, double(job->have) / double(size));
    // Antes do primeiro pedaço: o servidor aceitou o Range (206) ou mandou tudo de novo (200)?
    const auto begin = [m, job, this, reply] {
        if (job->started)
            return true;
        job->started = true;
        const QVariant status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute);
        if (status.isValid()) {
            const int code = status.toInt();
            if (code == 200) {
                job->file.resize(0);
                job->file.seek(0);
                job->have = 0;
            } else if (code != 206) {
                job->cancelled = true;
                reply->abort();
                finish(m, false, QStringLiteral("O servidor do modelo respondeu com o erro %1.").arg(code));
                return false;
            }
        } else if (job->have > 0) {
            // file:// não tem Range: recomeça.
            job->file.resize(0);
            job->file.seek(0);
            job->have = 0;
        }
        return true;
    };
    connect(reply, &QNetworkReply::readyRead, this, [this, m, job, reply, begin] {
        if (job->cancelled || !begin())
            return;
        const QByteArray chunk = reply->readAll();
        if (job->file.write(chunk) != chunk.size()) {
            job->cancelled = true;
            reply->abort();
            finish(m, false, job->file.errorString());
            return;
        }
        job->have += chunk.size();
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (now - job->lastReport > 100) {
            job->lastReport = now;
            emit downloadProgress(m, std::min(1.0, double(job->have) / double(job->size)));
        }
    });
    connect(reply, &QNetworkReply::finished, this, [this, m, job, reply, begin, verify] {
        reply->deleteLater();
        if (!m_jobs->jobs.contains(m) || m_jobs->jobs.value(m) != job)
            return; // já terminou (erro do servidor, falha de escrita)
        if (job->cancelled) {
            job->file.close();
            finish(m, false, {});
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            const QVariant status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute);
            job->file.close();
            if (status.isValid() && status.toInt() >= 400)
                finish(m, false, QStringLiteral("O servidor do modelo respondeu com o erro %1.").arg(status.toInt()));
            else
                finish(m, false, QStringLiteral("Não foi possível baixar o modelo: %1").arg(reply->errorString()));
            return;
        }
        if (!begin())
            return;
        const QByteArray rest = reply->readAll();
        job->file.write(rest);
        job->have += rest.size();
        job->file.flush();
        verify();
    });
}

void ModelStore::finish(WhisperModel m, bool ok, const QString &error)
{
    if (!m_jobs->jobs.contains(m))
        return;
    m_jobs->jobs.remove(m);
    if (ok)
        emit downloadProgress(m, 1);
    emit downloadFinished(m, ok, error);
}

void ModelStore::cancel(WhisperModel m)
{
    const auto job = m_jobs->jobs.value(m);
    if (!job || job->cancelled)
        return;
    job->cancelled = true;
    // O parcial fica para retomar; fechado já (no Windows, um arquivo aberto não pode ser apagado).
    job->file.close();
    if (job->reply)
        job->reply->abort(); // termina pelo `finished` da resposta
}

bool ModelStore::isDownloading(WhisperModel m) const { return m_jobs->jobs.contains(m); }

QString ModelStore::sha256Of(const QString &file)
{
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    QCryptographicHash hash(QCryptographicHash::Sha256);
    hash.addData(&f);
    return QString::fromLatin1(hash.result().toHex());
}

bool ModelStore::remove(WhisperModel m, QString *error)
{
    // O modelo pode estar carregado na memória: solta antes de apagar.
    WhisperEngine::unload();
    cancel(m);
    for (const QString &file : {path(m), partialPath(m)}) {
        QFile f(file);
        if (f.exists() && !f.remove()) {
            if (error)
                *error = f.errorString();
            return false;
        }
    }
    return true;
}

} // namespace of
