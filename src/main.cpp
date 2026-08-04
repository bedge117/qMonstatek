/*
 * main.cpp — qMonstatek application entry point
 */

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QIcon>
#include <QDebug>
#include <cstdio>
#include <QStandardPaths>
#include <QDir>
#include <QCommandLineParser>
#include <QtQml>

#include "device/m1_device.h"
#include "device/screen_canvas.h"
#include "protocol/rpc_frame.h"
#include "device/log_model.h"
#include "ui_settings.h"
#include "transport/mdns_discovery.h"
#include "updater/github_checker.h"
#include "updater/self_updater.h"
#include "updater/dfu_flasher.h"
#include "updater/swd_recovery.h"
#include "updater/app_switcher.h"

static FILE *s_logFile = nullptr;

static void msgHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    Q_UNUSED(ctx);
    const char *tag = "";
    switch (type) {
    case QtDebugMsg:    tag = "DBG"; break;
    case QtInfoMsg:     tag = "INF"; break;
    case QtWarningMsg:  tag = "WRN"; break;
    case QtCriticalMsg: tag = "ERR"; break;
    case QtFatalMsg:    tag = "FTL"; break;
    }

    // Write to log file
    if (s_logFile) {
        fprintf(s_logFile, "[%s] %s\n", tag, msg.toUtf8().constData());
        fflush(s_logFile);
    }

    // Feed the in-app log model
    LogModel *lm = globalLogModel();
    if (lm) {
        lm->append(QStringLiteral("[%1] %2").arg(tag, msg));
    }
}

int main(int argc, char *argv[])
{
#ifdef Q_OS_LINUX
    /* Force Qt's built-in file dialog on Linux to avoid crashes when the
     * native freedesktop.org D-Bus file chooser is unavailable (common in
     * AppImage environments). */
    qputenv("QT_QPA_NO_NATIVE_FILE_DIALOG", "1");
#endif

    QApplication app(argc, argv);
    app.setApplicationName("qMonstatek");
    app.setOrganizationName("Monstatek");
    app.setApplicationVersion("2.10.2");

    QCommandLineParser commandLine;
    commandLine.setApplicationDescription("qMonstatek desktop companion");
    commandLine.addHelpOption();
    const QCommandLineOption portOption(
        "port", "Connect to this serial port instead of auto-selecting a device.", "port");
    commandLine.addOption(portOption);
    commandLine.process(app);
    const QString requestedPort = commandLine.value(portOption).trimmed();

    // Open log file in temp directory (avoids write permission issues in Program Files)
    QString logPath = QDir::tempPath() + "/qmonstatek.log";
    s_logFile = fopen(logPath.toLocal8Bit().constData(), "w");

    qInstallMessageHandler(msgHandler);
    if (s_logFile) {
        fprintf(s_logFile, "qMonstatek: starting... (log file active)\n");
        fflush(s_logFile);
    }
    app.setWindowIcon(QIcon(":/icons/app_icon.png"));

    QQuickStyle::setStyle("Material");

    // Allow rpc::Frame + QImage to cross the worker→GUI thread boundary via
    // queued signal/slot connections (COMMS_REBUILD_SPEC §7).
    qRegisterMetaType<rpc::Frame>("rpc::Frame");

    // Push-render item for the screen mirror (replaces the image-provider pull).
    qmlRegisterType<ScreenCanvas>("Monstatek.Backend", 1, 0, "ScreenCanvas");

    // Create backend objects
    M1Device device;
    device.setPreferredSerialPort(requestedPort);
    GithubChecker githubChecker;
    githubChecker.setPersistKey("firmware/repoUrl");
    GithubChecker appUpdateChecker;
    appUpdateChecker.setRepoUrl("bedge117/qMonstatek");
    GithubChecker studioAppChecker;                          // for the "Get Studio" download
    studioAppChecker.setRepoUrl("bedge117/qmonstatek-studio");
    AppSwitcher appSwitcher;                                  // hand off to Studio (M1OS)
    GithubChecker esp32Checker;
    esp32Checker.setRepoUrl("bedge117/m1-esp32-brain");   // default before persist load
    esp32Checker.setPersistKey("firmware/espRepoUrl");    // user-selectable in Settings
    SelfUpdater selfUpdater;
    DfuFlasher dfuFlasher;
    SwdRecovery swdRecovery;
    MdnsDiscovery mdnsDiscovery;
    device.setMdnsDiscovery(&mdnsDiscovery);   // WiFi auto-reconnect re-resolve
    LogModel logModel;
    setGlobalLogModel(&logModel);
    UiSettings uiSettings;

    // Set up QML engine
    QQmlApplicationEngine engine;

    // Expose backend to QML
    engine.rootContext()->setContextProperty("m1device", &device);
    engine.rootContext()->setContextProperty("githubChecker", &githubChecker);
    engine.rootContext()->setContextProperty("appUpdateChecker", &appUpdateChecker);
    engine.rootContext()->setContextProperty("studioAppChecker", &studioAppChecker);
    engine.rootContext()->setContextProperty("appSwitcher", &appSwitcher);
    engine.rootContext()->setContextProperty("esp32Checker", &esp32Checker);
    engine.rootContext()->setContextProperty("selfUpdater", &selfUpdater);
    engine.rootContext()->setContextProperty("dfuFlasher", &dfuFlasher);
    engine.rootContext()->setContextProperty("swdRecovery", &swdRecovery);
    engine.rootContext()->setContextProperty("deviceDiscovery", device.discovery());
    engine.rootContext()->setContextProperty("mdnsDiscovery", &mdnsDiscovery);
    engine.rootContext()->setContextProperty("appLog", &logModel);
    engine.rootContext()->setContextProperty("uiSettings", &uiSettings);

    // Load main QML
    const QUrl url(QStringLiteral("qrc:/QMonstatek/qml/main.qml"));

    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() {
            QCoreApplication::exit(-1);
        },
        Qt::QueuedConnection);
    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        return -1;
    }

    return app.exec();
}
