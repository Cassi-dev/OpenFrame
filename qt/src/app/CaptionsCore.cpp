#include "CaptionsCore.h"

#include "TimelineEditor.h"

#include <QHash>
#include <QSet>

namespace of::CaptionsCore {

// O núcleo ainda não tem as legendas: catálogos com os nomes do Mac e geração de mentira.
// Com a etapa 1, este arquivo passa a chamar WhisperModel/ModelStore/Transcriber/CaptionBuilder.

QList<ModelInfo> models()
{
    return {
        {"base", "Rápido", "O mais leve. Bom para fala clara e pouco ruído.", 147'951'465},
        {"small", "Equilibrado", "Bom equilíbrio entre velocidade e precisão.", 487'601'967},
        {"turbo", "Máxima precisão", "Mais lento e mais preciso. Melhor para áudio difícil.", 574'041'195},
    };
}

QString recommendedModel()
{
    return QStringLiteral("small");
}

QList<Language> languages()
{
    return {{"pt", "Português"}, {"en", "Inglês"},     {"es", "Espanhol"},  {"fr", "Francês"},   {"de", "Alemão"},
            {"it", "Italiano"},  {"ja", "Japonês"},    {"ko", "Coreano"},   {"zh", "Chinês"},    {"ru", "Russo"},
            {"ar", "Árabe"},     {"hi", "Hindi"},      {"nl", "Holandês"},  {"pl", "Polonês"},   {"tr", "Turco"},
            {"uk", "Ucraniano"}, {"sv", "Sueco"},      {"he", "Hebraico"},  {"id", "Indonésio"}, {"vi", "Vietnamita"}};
}

QList<PresetInfo> presets()
{
    const QString classic = QStringLiteral("Clássicos"), reveal = QStringLiteral("Revelação"),
                  editorial = QStringLiteral("Editorial");
    return {
        {"phrases", "Frases", "Até duas linhas embaixo, como no cinema.", "classic", classic, "phrases", false},
        {"highlight", "Destaque", "Uma linha; a palavra falada acende.", "classic", classic, "highlight", true},
        {"punch", "Impacto", "Poucas palavras grandes no centro.", "classic", classic, "punch", false},
        {"rise", "Surgir", "Cada palavra surge quando é dita.", "reveal", reveal, "highlight", true},
        {"guided", "Leitura guiada", "A frase inteira, acendendo palavra por palavra.", "reveal", reveal, "phrases",
         true},
        {"fill", "Preenchimento", "A cor enche cada palavra no ritmo da fala.", "reveal", reveal, "highlight", true},
        {"typing", "Digitação", "As letras são digitadas no tempo da fala.", "reveal", reveal, "highlight", true},
        {"editorial", "Editorial", "Texto leve, com a palavra-chave em serifa itálica.", "editorial", editorial,
         "phrases", true},
        {"cinema", "Cinema", "Discreta: fina, espaçada e pequena, embaixo.", "editorial", editorial, "highlight",
         false},
        {"stacked", "Empilhado", "Blocos em caixa alta, justificados, linha a linha.", "editorial", editorial,
         "stacked", true},
    };
}

QColor defaultHighlight()
{
    return RGBA::yellow().color();
}

bool hasAutoCaptions(const Project &)
{
    return false;
}

bool isAutoCaption(const Project &, const QUuid &)
{
    return false;
}

void applyStyleToAll(Project &, const Segment &)
{
}

// MARK: - Engine (de mentira)

namespace {
const QString sampleSpeech = QStringLiteral(
    "Olá, pessoal! Hoje eu vou mostrar como gerar legendas automáticas no OpenFrame. É tudo feito no seu "
    "computador, sem enviar nada para a internet. Você escolhe o estilo, e as legendas aparecem na timeline.");
}

struct Engine::Impl {
    QSet<QString> installed;
    QHash<QString, QTimer *> downloads;
    QHash<QString, double> fractions;
    QTimer *job = nullptr;
    double overall = 0;
    struct Cue {
        QString text;
        Micros start = 0;
        Micros end = 0;
    };
    QList<Cue> cues;
};

Engine::Engine(QObject *parent) : QObject(parent), d(std::make_unique<Impl>()) {}

Engine::~Engine() = default;

bool Engine::isInstalled(const QString &model) const
{
    return d->installed.contains(model);
}

void Engine::download(const QString &model)
{
    if (d->downloads.contains(model) || d->installed.contains(model))
        return;
    auto *timer = new QTimer(this);
    timer->setInterval(80);
    d->downloads.insert(model, timer);
    connect(timer, &QTimer::timeout, this, [this, model, timer] {
        double &f = d->fractions[model];
        f = std::min(1.0, f + 0.04);
        emit downloadProgress(model, f);
        if (f < 1)
            return;
        timer->deleteLater();
        d->downloads.remove(model);
        d->fractions.remove(model);
        d->installed.insert(model);
        emit downloadFinished(model, {});
    });
    timer->start();
}

void Engine::cancelDownload(const QString &model)
{
    if (QTimer *timer = d->downloads.take(model))
        timer->deleteLater();
}

bool Engine::remove(const QString &model, QString *)
{
    cancelDownload(model);
    d->fractions.remove(model);
    d->installed.remove(model);
    return true;
}

std::optional<TimeRange> Engine::sourceRange(const Project &p, const std::optional<QUuid> &segment,
                                             QString *error) const
{
    if (segment) {
        const auto seg = p.segment(*segment);
        const Material *m = seg ? p.material(seg->materialId) : nullptr;
        if (!m || !(m->kind == MaterialKind::Audio || m->hasAudio)) {
            if (error)
                *error = QStringLiteral("O clipe não tem áudio.");
            return std::nullopt;
        }
        return seg->targetRange();
    }
    if (p.duration() <= 0) {
        if (error)
            *error = QStringLiteral("A timeline não tem áudio para transcrever.");
        return std::nullopt;
    }
    return TimeRange{0, p.duration()};
}

void Engine::transcribe(const Project &p, const std::optional<QUuid> &segment, const QString &, const QString &,
                        const QString &)
{
    cancel();
    QString error;
    const auto range = sourceRange(p, segment, &error);
    if (!range) {
        QTimer::singleShot(0, this, [this, error] { emit finished(0, error); });
        return;
    }
    // Frases da fala falsa espalhadas pelo trecho, ~2,5 s cada.
    d->cues.clear();
    const QStringList words = sampleSpeech.split(' ');
    const int perCue = 5;
    const int count = int(std::min<qint64>((words.size() + perCue - 1) / perCue, std::max<qint64>(1, range->duration / 2'000'000)));
    const Micros step = range->duration / std::max(1, count);
    for (int i = 0; i < count; ++i)
        d->cues.append({words.mid(i * perCue, perCue).join(' '), range->start + i * step,
                        range->start + (i + 1) * step - 100'000});
    d->overall = 0;
    d->job = new QTimer(this);
    d->job->setInterval(60);
    connect(d->job, &QTimer::timeout, this, [this] {
        d->overall = std::min(1.0, d->overall + 0.025);
        emit progress(d->overall < 0.2 ? QStringLiteral("mixing") : QStringLiteral("transcribing"), d->overall);
        if (d->overall < 1)
            return;
        d->job->deleteLater();
        d->job = nullptr;
        emit finished(int(d->cues.size()), {});
    });
    d->job->start();
}

void Engine::cancel()
{
    if (d->job) {
        d->job->deleteLater();
        d->job = nullptr;
    }
}

void Engine::apply(Project &p, const QString &, const QColor &, bool, TimeRange) const
{
    TextContent content;
    content.style.fontSize = 0.06;
    content.style.y = -0.75;
    for (const auto &cue : d->cues) {
        content.text = cue.text;
        TimelineEditor::addText(content, p, cue.start, cue.end - cue.start);
    }
}

} // namespace of::CaptionsCore
