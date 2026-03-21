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

QString SelfUpdater::extractSetupExe(const QString &zipPath)
{
    // Extract to a temp folder next to the zip
    QString extractDir = QFileInfo(zipPath).absolutePath() + "/qmonstatek_update";
    QDir().mkpath(extractDir);

    // Use PowerShell to extract (available on all Windows 10+)
    QProcess ps;
    ps.setProcessChannelMode(QProcess::MergedChannels);
    QStringList args;
    args << "-NoProfile" << "-Command"
         << QString("Expand-Archive -Path '%1' -DestinationPath '%2' -Force")
                .arg(zipPath, extractDir);
    ps.start("powershell.exe", args);

    if (!ps.waitForFinished(30000)) {
        qWarning() << "SelfUpdater: PowerShell extract timed out";
        return {};
    }

    if (ps.exitCode() != 0) {
        qWarning() << "SelfUpdater: extract failed:" << ps.readAll();
        return {};
    }

    // Find the _setup.exe inside
    QDir dir(extractDir);
    QStringList exes = dir.entryList(QStringList() << "*_setup.exe", QDir::Files);
    if (exes.isEmpty()) {
        qWarning() << "SelfUpdater: no _setup.exe found in zip";
        return {};
    }

    return dir.absoluteFilePath(exes.first());
}

bool SelfUpdater::launchInstallerAndQuit(const QString &path)
{
    QFileInfo fi(path);
    if (!fi.exists() || !fi.isFile()) {
        emit updateError("Installer not found: " + path);
        return false;
    }

    QString exePath = path;

    // If it's a zip, extract the setup exe first
    if (fi.suffix().toLower() == "zip") {
        exePath = extractSetupExe(path);
        if (exePath.isEmpty()) {
            emit updateError("Failed to extract installer from zip.");
            return false;
        }
    }

    qInfo() << "SelfUpdater: launching installer" << exePath;

    bool ok = QProcess::startDetached(exePath, {});
    if (!ok) {
        emit updateError("Failed to launch installer. Try running it manually from: "
                         + exePath);
        return false;
    }

    QCoreApplication::quit();
    return true;
}
