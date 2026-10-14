#pragma once

#include <QDir>
#include <QObject>
#include <deque>
#include <functional>

class QQmlApplicationEngine;
class QQuickWindow;
class QQuickItem;

namespace of {

class EditorModel;

/// Ferramenta de desenvolvimento (o `DebugSnapshot` do app Swift): com
/// `OPENFRAME_SNAPSHOT_DIR` definido, o app percorre as telas principais, salva
/// capturas da própria janela (`grabWindow`) e fecha. Roda sem tela com
/// `QT_QPA_PLATFORM=offscreen`, que é como a CI e os agentes conferem a
/// interface sem mouse.
///
/// - Sem `--open`: cenário da tela inicial (`inicio-*`).
/// - Com `--open projeto.openframe`: cenário do editor (clipes, inspetor, painéis,
///   zoom, arraste, exportação).
/// - `OPENFRAME_SNAPSHOT_MEDIA=pasta`: cria um projeto na biblioteca, importa as
///   mídias da pasta e roda o cenário do editor sobre ele.
/// - `OPENFRAME_SNAPSHOT_SCENARIO=arraste`: arrastes espelhados na timeline.
class Snapshot : public QObject
{
    Q_OBJECT

public:
    static void runIfRequested(QQmlApplicationEngine *engine, EditorModel *model);

private:
    Snapshot(QQmlApplicationEngine *engine, EditorModel *model, const QString &dir);

    using Step = std::function<void()>;
    /// Agenda `step` depois de `ms` milissegundos, na ordem.
    void then(int ms, Step step);
    void next();
    void finish();

    void homeScenario();
    void mediaScenario(const QString &mediaDir);
    void editorScenario();
    void dragScenario();
    void inspectorTabs(const QString &segment, const QString &prefix);

    void capture(const QString &name);
    /// Recorte do item `objectName` (com `above` px acima, para o título e as abas).
    void captureItem(const QString &objectName, const QString &name, int above = 0);
    void scrollInspector(double fraction);
    QQuickWindow *window() const;
    QQuickItem *findItem(const QString &objectName) const;
    void log(const QString &message) const;

    QQmlApplicationEngine *m_engine;
    EditorModel *m_model;
    QDir m_dir;
    std::deque<std::pair<int, Step>> m_steps;
};

} // namespace of
