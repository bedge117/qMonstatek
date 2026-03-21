/*
 * self_updater.cpp — qMonstatek self-update helper
 */

#include "self_updater.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QDebug>

SelfUpdater::SelfUpdater(QObject *parent)
    : QObject(parent)
{
}

QString SelfUpdater::tempDir() const
{
    return QDir::tempPath();
}

bool SelfUpdater::launchInstallerAndQuit(const QString &installerPath)
{
    QFileInfo fi(installerPath);
    if (!fi.exists() || !fi.isFile()) {
        emit updateError("Installer not found: " + installerPath);
        return false;
    }

    qInfo() << "SelfUpdater: launching installer" << installerPath;

    // Start the installer detached so it survives our exit.
    // No /SILENT flag — let the user see the installer wizard.
    bool ok = QProcess::startDetached(installerPath, {});
    if (!ok) {
        emit updateError("Failed to launch installer. Try running it manually from: "
                         + installerPath);
        return false;
    }

    // Quit so the installer can replace our exe
    QCoreApplication::quit();
    return true;
}
