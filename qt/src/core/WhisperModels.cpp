#include "WhisperModels.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTimer>

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

ModelStore::ModelStore(const QString &directory, QObject *parent) : QObject(parent), m_directory(directory) {}

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

void ModelStore::download(WhisperModel m)
{
    // Provisório (etapa 1): o download real chega com o whisper.
    QTimer::singleShot(0, this, [this, m] {
        emit downloadFinished(m, false, QStringLiteral("O download dos modelos ainda não está disponível nesta versão."));
    });
}

void ModelStore::cancel(WhisperModel) {}

bool ModelStore::isDownloading(WhisperModel) const { return false; }

bool ModelStore::remove(WhisperModel m, QString *error)
{
    for (const QString &file : {path(m), path(m) + QStringLiteral(".partial")}) {
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
