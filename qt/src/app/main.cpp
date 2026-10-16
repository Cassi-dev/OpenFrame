#include "EditorModel.h"
#include "FilterPreviews.h"
#include "Snapshot.h"

#include <QCommandLineParser>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QScreen>
#include <QStandardPaths>
#include <QStyleHints>

static QString g_nativeLogPath;

static void openframeMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    const char *typeStr = "DEBUG";
    switch (type) {
    case QtDebugMsg: typeStr = "DEBUG"; break;
    case QtInfoMsg: typeStr = "INFO"; break;
    case QtWarningMsg: typeStr = "WARN"; break;
    case QtCriticalMsg: typeStr = "CRIT"; break;
    case QtFatalMsg: typeStr = "FATAL"; break;
    }

    const QString line = QStringLiteral("[%1] %2 (%3:%4): %5\n")
                             .arg(QLatin1String(typeStr),
                                  QDateTime::currentDateTime().toString(Qt::ISODate),
                                  context.file ? QString::fromUtf8(context.file) : QStringLiteral("?"),
                                  QString::number(context.line),
                                  msg);

    fprintf(stderr, "%s", line.toLocal8Bit().constData());

    if (!g_nativeLogPath.isEmpty()) {
        QFile file(g_nativeLogPath);
        if (file.open(QIODevice::Append | QIODevice::Text)) {
            file.write(line.toUtf8());
        }
    }
}

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    // Configura log nativo em disco para diagnóstico
    g_nativeLogPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/openframe_native.log");
    QDir().mkpath(QFileInfo(g_nativeLogPath).absolutePath());
    qInstallMessageHandler(openframeMessageHandler);
    qInfo() << "=== OpenFrame iniciando versão" << OPENFRAME_VERSION << "===";
    qInfo() << "Platform:" << QGuiApplication::platformName() << "Arguments:" << app.arguments();

    QGuiApplication::setOrganizationName(QStringLiteral("OpenFrame"));
    QGuiApplication::setOrganizationDomain(QStringLiteral("openframe.app"));
    QGuiApplication::setApplicationName(QStringLiteral("OpenFrame"));
    QGuiApplication::setApplicationVersion(QStringLiteral(OPENFRAME_VERSION));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/qt/qml/OpenFrame/icons/openframe-256.png")));

    // Sem GPU (modo de captura offscreen e algumas máquinas virtuais), o Qt Quick
    // desenha por software; todos os itens do app funcionam assim.
    if (QGuiApplication::platformName() == QLatin1String("offscreen") || qEnvironmentVariableIsSet("OPENFRAME_SOFTWARE"))
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);

#if !defined(Q_OS_ANDROID)
    QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);
#endif
    QGuiApplication::styleHints()->setColorScheme(Qt::ColorScheme::Dark);
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    // Inter (pesos 200 a 500) e os ícones Lucide vêm no próprio executável.
    QDirIterator fonts(QStringLiteral(":/qt/qml/OpenFrame/fonts"), {QStringLiteral("*.ttf")});
    while (fonts.hasNext())
        QFontDatabase::addApplicationFont(fonts.next());
    QFont font(QStringLiteral("Inter"));
    font.setPixelSize(12);
    QGuiApplication::setFont(font);

    of::EditorModel model;

#if !defined(Q_OS_ANDROID)
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

    if (parser.isSet(openOption))
        model.openExternal(parser.value(openOption));
    else if (!parser.positionalArguments().isEmpty())
        model.openProjectFile(QUrl::fromLocalFile(parser.positionalArguments().first()));
#endif

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("filters"), new of::FilterPreviews);
    
    QString qmlErrorString;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [&qmlErrorString](const QUrl &url) {
                         qmlErrorString = QStringLiteral("Falha ao instanciar objeto QML: ") + url.toString();
                         qCritical() << qmlErrorString;
                     }, Qt::DirectConnection);

    qInfo() << "Carregando módulo OpenFrame/Main...";
    engine.loadFromModule("OpenFrame", "Main");
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "ERRO FATAL: Falha ao carregar OpenFrame/Main.qml!";

        // Em vez de fechar silenciosamente, carrega uma janela com diagnóstico na tela
        const QString fallbackQml = QStringLiteral(R"(
            import QtQuick
            import QtQuick.Window
            import QtQuick.Controls

            Window {
                visible: true
                width: Screen.width > 0 ? Screen.width : 400
                height: Screen.height > 0 ? Screen.height : 800
                color: "#0B0B0B"
                title: "OpenFrame - Falha de Inicialização"

                Column {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 32, 480)
                    spacing: 16

                    Text {
                        text: "OpenFrame"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#00C2CC"
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }

                    Text {
                        text: "Falha ao carregar a interface (QML)."
                        font.pixelSize: 16
                        color: "#FFFFFF"
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                    }

                    Rectangle {
                        width: parent.width
                        height: 180
                        color: "#18181b"
                        radius: 8
                        clip: true

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 8
                            contentWidth: width
                            contentHeight: errText.paintedHeight

                            Text {
                                id: errText
                                width: parent.width
                                text: "Consulte o arquivo openframe_native.log em:\n" + 
                                      Qt.application.name + " AppDataLocation"
                                font.pixelSize: 11
                                font.family: "monospace"
                                color: "#f87171"
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    Button {
                        text: "Fechar"
                        anchors.horizontalCenter: parent.horizontalCenter
                        onClicked: Qt.quit()
                    }
                }
            }
        )");

        engine.loadData(fallbackQml.toUtf8());
        if (!engine.rootObjects().isEmpty()) {
            return app.exec();
        }
        return 1;
    }

    qInfo() << "OpenFrame QML carregado com sucesso. Executando loop de eventos.";
    of::Snapshot::runIfRequested(&engine, &model);
    return app.exec();
}
