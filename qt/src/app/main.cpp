#include "EditorModel.h"
#include "FilterPreviews.h"
#include "Snapshot.h"

#include <QCommandLineParser>
#include <QDirIterator>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStyleHints>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName(QStringLiteral("OpenFrame"));
    QGuiApplication::setOrganizationDomain(QStringLiteral("openframe.app"));
    QGuiApplication::setApplicationName(QStringLiteral("OpenFrame"));
    QGuiApplication::setApplicationVersion(QStringLiteral(OPENFRAME_VERSION));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/qt/qml/OpenFrame/icons/openframe-256.png")));

    // Sem GPU (modo de captura offscreen e algumas máquinas virtuais), o Qt Quick
    // desenha por software; todos os itens do app funcionam assim.
    if (QGuiApplication::platformName() == QLatin1String("offscreen") || qEnvironmentVariableIsSet("OPENFRAME_SOFTWARE"))
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
    QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);
    QGuiApplication::styleHints()->setColorScheme(Qt::ColorScheme::Dark);
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    // Inter (pesos 200 a 500) e os ícones Lucide vêm no próprio executável.
    QDirIterator fonts(QStringLiteral(":/qt/qml/OpenFrame/fonts"), {QStringLiteral("*.ttf")});
    while (fonts.hasNext())
        QFontDatabase::addApplicationFont(fonts.next());
    QFont font(QStringLiteral("Inter"));
    font.setPixelSize(12);
    QGuiApplication::setFont(font);

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("OpenFrame, editor de vídeo"));
    parser.addHelpOption();
    parser.addVersionOption();
    QCommandLineOption openOption({QStringLiteral("o"), QStringLiteral("open")},
                                  QStringLiteral("Abre um projeto .openframe direto, fora da biblioteca."),
                                  QStringLiteral("arquivo"));
    parser.addOption(openOption);
    parser.addPositionalArgument(QStringLiteral("projeto"), QStringLiteral("Projeto .openframe a importar e abrir."));
    parser.process(app);

    of::EditorModel model;
    if (parser.isSet(openOption))
        model.openExternal(parser.value(openOption));
    else if (!parser.positionalArguments().isEmpty())
        model.openProjectFile(QUrl::fromLocalFile(parser.positionalArguments().first()));

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("filters"), new of::FilterPreviews);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("OpenFrame", "Main");
    if (engine.rootObjects().isEmpty())
        return 1;

    of::Snapshot::runIfRequested(&engine, &model);
    return app.exec();
}
