#include "Snapshot.h"

#include "EditorModel.h"
#include "ProjectStore.h"

#include <QCoreApplication>
#include <QDirIterator>
#include <QImage>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>
#include <cstdio>

namespace of {

namespace {

QString idString(const QUuid &id) { return ProjectStore::uuidString(id); }

/// Primeiro segmento da faixa principal, ou vazio.
QString firstMainSegment(const Project &p)
{
    const auto main = p.mainTrackIndex();
    if (!main || p.tracks[*main].segments.isEmpty())
        return {};
    return idString(p.tracks[*main].segments.first().id);
}

QString firstOfKind(const Project &p, TrackKind kind)
{
    for (const auto &t : p.tracks)
        if (t.kind == kind && !t.segments.isEmpty())
            return idString(t.segments.first().id);
    return {};
}

} // namespace

void Snapshot::runIfRequested(QQmlApplicationEngine *engine, EditorModel *model)
{
    const QString dir = qEnvironmentVariable("OPENFRAME_SNAPSHOT_DIR");
    if (dir.isEmpty())
        return;
    QDir().mkpath(dir);
    auto *snapshot = new Snapshot(engine, model, dir);
    const QString media = qEnvironmentVariable("OPENFRAME_SNAPSHOT_MEDIA");
    const QString scenario = qEnvironmentVariable("OPENFRAME_SNAPSHOT_SCENARIO");
    snapshot->then(1500, [] {});
    if (!media.isEmpty())
        snapshot->mediaScenario(media);
    else if (model->screen() == "home")
        snapshot->homeScenario();
    else if (scenario == "arraste")
        snapshot->dragScenario();
    else
        snapshot->editorScenario();
    snapshot->then(300, [snapshot] { snapshot->finish(); });
    snapshot->next();
}

Snapshot::Snapshot(QQmlApplicationEngine *engine, EditorModel *model, const QString &dir)
    : QObject(model), m_engine(engine), m_model(model), m_dir(dir)
{
}

void Snapshot::then(int ms, Step step)
{
    m_steps.emplace_back(ms, std::move(step));
}

void Snapshot::next()
{
    if (m_steps.empty())
        return;
    auto [ms, step] = std::move(m_steps.front());
    m_steps.pop_front();
    QTimer::singleShot(ms, this, [this, step] {
        step();
        next();
    });
}

void Snapshot::finish()
{
    log("fim");
    QCoreApplication::quit();
}

QQuickWindow *Snapshot::window() const
{
    for (QObject *root : m_engine->rootObjects())
        if (auto *w = qobject_cast<QQuickWindow *>(root))
            return w;
    return nullptr;
}

QQuickItem *Snapshot::findItem(const QString &objectName) const
{
    QQuickWindow *w = window();
    return w ? w->contentItem()->findChild<QQuickItem *>(objectName) : nullptr;
}

void Snapshot::log(const QString &message) const
{
    std::fprintf(stderr, "[snapshot] %s\n", qPrintable(message));
    std::fflush(stderr);
}

void Snapshot::capture(const QString &name)
{
    QQuickWindow *w = window();
    if (!w)
        return;
    const QImage image = w->grabWindow();
    const QString path = m_dir.filePath(name + ".png");
    if (image.save(path))
        log(QStringLiteral("%1 (%2×%3)").arg(name).arg(image.width()).arg(image.height()));
    else
        log("falhou: " + name);
}

void Snapshot::captureItem(const QString &objectName, const QString &name, int above)
{
    QQuickWindow *w = window();
    QQuickItem *item = findItem(objectName);
    if (!w || !item)
        return;
    const QImage image = w->grabWindow();
    const qreal dpr = image.devicePixelRatio();
    QRectF r = item->mapRectToScene(QRectF(0, 0, item->width(), item->height()));
    r.adjust(-8, -above, 8, 0);
    const QRect pixels = QRectF(r.x() * dpr, r.y() * dpr, r.width() * dpr, r.height() * dpr).toAlignedRect()
                             .intersected(image.rect());
    image.copy(pixels).save(m_dir.filePath(name + ".png"));
    log(name);
}

void Snapshot::scrollInspector(double fraction)
{
    QQuickItem *flick = findItem(QStringLiteral("inspectorScroll"));
    if (!flick)
        return;
    const qreal travel = std::max<qreal>(0, flick->property("contentHeight").toReal() - flick->height());
    flick->setProperty("contentY", travel * fraction);
}

// MARK: - Cenários

/// Lista, abre o projeto mais recente (ou cria um), volta e captura de novo.
void Snapshot::homeScenario()
{
    then(500, [this] { capture("inicio-1-lista"); });
    then(0, [this] {
        if (m_model->entries()->count() > 0)
            m_model->openLibraryProject(m_model->entries()->get(0).value("id").toString());
        else
            m_model->createProject("r9x16");
    });
    then(1500, [this] { capture("inicio-2-editor"); });
    then(0, [this] { m_model->showHome(); });
    then(2500, [this] { m_model->refreshLibrary(); });
    then(800, [this] { capture("inicio-3-de-volta"); });
}

/// Projeto novo com as mídias de uma pasta (a CI gera vídeo, foto e áudio de teste).
void Snapshot::mediaScenario(const QString &mediaDir)
{
    then(0, [this, mediaDir] {
        m_model->createProject("original");
        QList<QUrl> urls;
        QDirIterator it(mediaDir, QDir::Files);
        while (it.hasNext())
            urls << QUrl::fromLocalFile(it.next());
        std::sort(urls.begin(), urls.end());
        log(QStringLiteral("importando %1 arquivos de %2").arg(urls.size()).arg(mediaDir));
        m_model->importMedia(urls);
    });
    then(4000, [this] {
        // Visuais na faixa principal, áudio na faixa de áudio, e um texto.
        const Project p = m_model->project();
        for (const auto &m : p.materials)
            m_model->addToTimeline(idString(m.id));
        m_model->seekMicros(500'000);
        m_model->addText("classic");
        m_model->setSelection({});
        log(QStringLiteral("projeto: %1 materiais, %2 clipes").arg(p.materials.size()).arg(m_model->clipCount()));
    });
    then(2000, [] {});
    editorScenario();
}

void Snapshot::editorScenario()
{
    then(0, [this] { m_model->seek(1.5); });
    then(1200, [this] { capture("1-projeto"); });

    then(0, [this] {
        m_model->setSelection(firstMainSegment(m_model->project()));
        m_model->setInspectorTab("basic");
    });
    then(800, [this] { capture("2-clipe-basico"); });
    then(0, [this] { m_model->setInspectorTab("filters"); });
    then(1500, [this] { capture("3-clipe-filtros"); });
    then(0, [this] { m_model->setInspectorTab("transition"); });
    then(800, [this] { capture("4-clipe-transicao"); });

    // Texto: aba Texto, depois os recursos de estilo ligados e o inspetor rolado.
    then(0, [this] {
        m_model->setSelection(firstOfKind(m_model->project(), TrackKind::Text));
        m_model->setInspectorTab("text");
    });
    then(800, [this] {
        if (!m_model->selection().isEmpty())
            capture("5-texto");
    });
    then(0, [this] {
        if (m_model->selection().isEmpty())
            return;
        const QList<std::pair<QString, QVariant>> values{
            {"text.style.letterSpacing", 0.12}, {"text.style.lineSpacing", 0.3}, {"text.style.underline", true},
            {"text.style.strokeWidth", 6},      {"text.style.backgroundEnabled", true},
            {"text.style.backgroundRadius", 0.5}, {"text.style.shadowAngle", -45},
            {"text.style.shadowDistance", 0.1},
        };
        for (const auto &[path, value] : values)
            m_model->setSegmentValue(path, value);
    });
    then(600, [this] { scrollInspector(0.5); });
    then(500, [this] {
        if (!m_model->selection().isEmpty())
            capture("5b-texto-rolado-1");
    });
    then(0, [this] { scrollInspector(1); });
    then(500, [this] {
        if (!m_model->selection().isEmpty())
            capture("5b-texto-rolado-2");
    });
    then(0, [this] { scrollInspector(0); });
    inspectorTabs(QStringLiteral("text"), QStringLiteral("17-inspetor-texto"));
    then(0, [this] {
        if (m_model->canUndo())
            m_model->undo();
    });
    inspectorTabs(QStringLiteral("main"), QStringLiteral("18-inspetor-clipe"));

    then(0, [this] { m_model->setSelection(firstOfKind(m_model->project(), TrackKind::Audio)); });
    then(800, [this] {
        if (!m_model->selection().isEmpty())
            capture("7-audio");
    });

    // Apagar o clipe selecionado com o inspetor aberto (derrubava o app Swift).
    then(0, [this] {
        m_model->setSelection(firstMainSegment(m_model->project()));
        m_model->setInspectorTab("basic");
    });
    then(500, [this] { m_model->deleteSelection(); });
    then(500, [this] {
        log("apagar com o inspetor aberto: app continua aberto");
        m_model->undo();
    });

    // Barra de ações do clipe na primeira e na última faixa exibidas.
    then(300, [this] {
        const Project &p = m_model->project();
        const QList<int> order = m_model->displayTrackOrder();
        for (int i : order) {
            if (!p.tracks[i].segments.isEmpty()) {
                m_model->setSelection(idString(p.tracks[i].segments.first().id));
                break;
            }
        }
    });
    then(800, [this] { capture("10-barra-primeira-faixa"); });
    then(0, [this] {
        const Project &p = m_model->project();
        const QList<int> order = m_model->displayTrackOrder();
        if (order.size() < 2 || p.tracks[order.last()].segments.isEmpty())
            return;
        const Segment last = p.tracks[order.last()].segments.last();
        m_model->setSelection(idString(last.id));
        m_model->seekMicros(last.targetEnd() - 200'000);
    });
    then(800, [this] { capture("11-barra-ultima-faixa"); });

    // Zoom: o playhead (ou o ponto da roda) fica no mesmo lugar da tela.
    then(0, [this] {
        m_model->setSelection({});
        m_model->seek(m_model->duration() * 3 / 4);
    });
    then(400, [this] {
        const auto x = [this] { return m_model->playhead() * m_model->zoom() - m_model->timelineScrollX(); };
        const double before = x();
        m_model->setZoom(m_model->zoom() * 3);
        log(QStringLiteral("zoom ×3: %1 pt/s; playhead na tela em x=%2 → %3")
                .arg(m_model->zoom(), 0, 'f', 2).arg(before, 0, 'f', 1).arg(x(), 0, 'f', 1));
    });
    then(800, [this] { capture("12-zoom-aproximado"); });
    then(0, [this] {
        const double time = (m_model->timelineScrollX() + 200) / m_model->zoom();
        m_model->zoomAtViewportX(0.5, 200);
        log(QStringLiteral("zoom ÷2 na roda em x=200: %1 s agora em x=%2")
                .arg(time, 0, 'f', 3)
                .arg(time * m_model->zoom() - m_model->timelineScrollX(), 0, 'f', 1));
        m_model->zoomToFit();
    });
    then(800, [this] { capture("13-zoom-ajustado"); });

    // Arraste vertical: o clipe mostra a faixa de destino antes de soltar.
    then(0, [this] {
        const QString first = firstMainSegment(m_model->project());
        if (!first.isEmpty())
            m_model->dragMove(first, 120, -1);
        log("arraste: linha de destino " + QString::number(m_model->dragTargetRow()));
    });
    then(800, [this] { capture("14-arraste-outra-faixa"); });
    then(0, [this] {
        const QString dragged = m_model->dragSegment();
        if (!dragged.isEmpty())
            m_model->endDragMove(dragged);
    });
    then(800, [this] {
        capture("15-apos-soltar");
        if (m_model->canUndo())
            m_model->undo();
    });

    // Cortes e reprodução com rolagem automática.
    then(300, [this] {
        m_model->seek(0);
        for (int i = 0; i < 3; ++i)
            m_model->jumpToEdit(true);
        log("cortes: 3× próximo → " + m_model->playheadText());
        m_model->setZoom(500);
        m_model->goToStart();
        m_model->togglePlay();
    });
    then(3000, [this] {
        if (m_model->isPlaying())
            m_model->togglePlay();
        log(QStringLiteral("reprodução: playhead %1, rolagem %2").arg(m_model->playheadText()).arg(m_model->timelineScrollX()));
        capture("16-reproducao-rolagem");
        m_model->zoomToFit();
    });

    // Painéis da biblioteca e grade.
    then(300, [this] {
        m_model->setSelection({});
        m_model->setShowGrid(true);
        m_model->setLibraryPanel("text");
    });
    then(800, [this] { capture("8-painel-texto-grade"); });
    then(0, [this] {
        m_model->setShowGrid(false);
        m_model->setLibraryPanel("captions");
    });
    then(800, [this] { capture("9-painel-legendas"); });
    then(0, [this] { m_model->setLibraryPanel("shortcuts"); });
    then(800, [this] { capture("19-painel-atalhos"); });
    then(0, [this] { m_model->setLibraryPanel("media"); });
    then(800, [this] { capture("20-painel-midia"); });
    then(0, [this] { m_model->setShowExport(true); });
    then(1200, [this] { capture("6-exportar"); });
    then(0, [this] { m_model->setShowExport(false); });
}

/// Todas as abas do inspetor do segmento (texto ou primeiro da faixa principal),
/// no topo, no meio e no fim da rolagem, só a área do inspetor.
void Snapshot::inspectorTabs(const QString &segment, const QString &prefix)
{
    static const QStringList tabs{"basic", "adjust", "filters", "effects", "animation", "transition", "text", "audio"};
    for (const QString &tab : tabs) {
        then(0, [this, segment, tab] {
            const Project &p = m_model->project();
            m_model->setSelection(segment == "text" ? firstOfKind(p, TrackKind::Text) : firstMainSegment(p));
            m_model->setInspectorTab(tab);
        });
        for (int i = 0; i < 3; ++i) {
            then(i == 0 ? 700 : 0, [this, i] { scrollInspector(i * 0.5); });
            then(400, [this, tab, prefix, i] {
                if (m_model->selection().isEmpty() || m_model->inspectorTab() != tab)
                    return;
                captureItem(QStringLiteral("inspector"), QStringLiteral("%1-%2-%3").arg(prefix, tab).arg(i + 1));
            });
        }
        then(0, [this] { scrollInspector(0); });
    }
}

/// Arrastes espelhados (mesma distância para a direita e para a esquerda),
/// capturados no meio do gesto, para comparar os dois sentidos.
void Snapshot::dragScenario()
{
    then(0, [this] {
        m_model->setZoom(120);
        m_model->seek(0);
    });
    const QList<qreal> distances{-560, -260, 260, 560};
    for (qreal dx : distances) {
        then(300, [this, dx] {
            const Project &p = m_model->project();
            const auto main = p.mainTrackIndex();
            if (!main || p.tracks[*main].segments.size() < 3)
                return;
            m_model->dragMove(idString(p.tracks[*main].segments[1].id), dx, 0);
        });
        then(700, [this, dx] {
            if (m_model->dragSegment().isEmpty())
                return;
            capture(QStringLiteral("arraste-principal%1%2").arg(dx > 0 ? "+" : "").arg(int(dx)));
            m_model->endDragMove(m_model->dragSegment());
        });
        then(400, [this] {
            if (m_model->canUndo())
                m_model->undo();
        });
    }
    for (bool leading : {true, false}) {
        then(300, [this, leading] {
            const Project &p = m_model->project();
            const auto main = p.mainTrackIndex();
            if (!main || p.tracks[*main].segments.size() < 2)
                return;
            m_model->dragTrim(idString(p.tracks[*main].segments[1].id), leading, leading ? 90 : -90);
        });
        then(700, [this, leading] {
            capture(leading ? "aparar-inicio" : "aparar-fim");
            m_model->endDragTrim();
        });
        then(400, [this] {
            if (m_model->canUndo())
                m_model->undo();
        });
    }
}

} // namespace of
