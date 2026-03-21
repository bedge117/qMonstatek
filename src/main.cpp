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

#include "device/m1_device.h"
#include "device/screen_image_provider.h"
#include "device/log_model.h"
#include "updater/github_checker.h"
#include "updater/self_updater.h"
#include "updater/dfu_flasher.h"
#include "updater/swd_recovery.h"

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
    QApplication app(argc, argv);
    app.setApplicationName("qMonstatek");
    app.setOrganizationName("Monstatek");
    app.setApplicationVersion("2.0.0");

    // Open log file next to the executable
    QString logPath = QCoreApplication::applicationDirPath() + "/qmonstatek.log";
    s_logFile = fopen(logPath.toLocal8Bit().constData(), "w");

    qInstallMessageHandler(msgHandler);
    if (s_logFile) {
        fprintf(s_logFile, "qMonstatek: starting... (log file active)\n");
        fflush(s_logFile);
    }
    app.setWindowIcon(QIcon(":/icons/app_icon.png"));

    QQuickStyle::setStyle("Material");

    // Create backend objects
    M1Device device;
    GithubChecker githubChecker;
    githubChecker.setPersistKey("firmware/repoUrl");
    GithubChecker appUpdateChecker;
    appUpdateChecker.setRepoUrl("bedge117/qMonstatek");
    GithubChecker esp32Checker;
    esp32Checker.setRepoUrl("bedge117/esp32-at-monstatek-m1");
    SelfUpdater selfUpdater;
    DfuFlasher dfuFlasher;
    SwdRecovery swdRecovery;
    LogModel logModel;
    setGlobalLogModel(&logModel);

    // Set up QML engine
    QQmlApplicationEngine engine;

    // Register screen image provider (engine takes ownership)
    auto *screenProvider = new ScreenImageProvider;
    screenProvider->setDevice(&device);
    engine.addImageProvider("screen", screenProvider);

    // Expose backend to QML
    engine.rootContext()->setContextProperty("m1device", &device);
    engine.rootContext()->setContextProperty("githubChecker", &githubChecker);
    engine.rootContext()->setContextProperty("appUpdateChecker", &appUpdateChecker);
    engine.rootContext()->setContextProperty("esp32Checker", &esp32Checker);
    engine.rootContext()->setContextProperty("selfUpdater", &selfUpdater);
    engine.rootContext()->setContextProperty("dfuFlasher", &dfuFlasher);
    engine.rootContext()->setContextProperty("swdRecovery", &swdRecovery);
    engine.rootContext()->setContextProperty("deviceDiscovery", device.discovery());
    engine.rootContext()->setContextProperty("appLog", &logModel);

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
