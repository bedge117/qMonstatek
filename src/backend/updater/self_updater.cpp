/*
 * self_updater.cpp — qMonstatek self-update helper
 */

#include "self_updater.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QUrl>
#include <QDebug>

// Minimal Recovery firmware bundled in the app (see src/CMakeLists.txt
// app_resources). Its only job is to un-brick the M1 over SWD and get it
// talking to qMonstatek again, so a real firmware can then be installed —
// this enables that first step with no internet. Keep in sync with the file.
static const char *kBundledFwName     = "M1_Recovery_C3.1.0_wCRC.bin";
static const char *kBundledFwResource = ":/firmware/M1_Recovery_C3.1.0_wCRC.bin";

SelfUpdater::SelfUpdater(QObject *parent)
    : QObject(parent)
{
    cleanupOldDownloads();
}

QString SelfUpdater::tempDir() const
{
    return QDir::tempPath();
}

QString SelfUpdater::bundledFirmwareName() const
{
    return QFile::exists(QString::fromLatin1(kBundledFwResource))
               ? QString::fromLatin1(kBundledFwName)
               : QString();
}

QString SelfUpdater::bundledFirmwarePath()
{
    QFile res(QString::fromLatin1(kBundledFwResource));
    if (!res.open(QIODevice::ReadOnly)) {
        emit updateError("This build has no bundled recovery firmware.");
        return QString();
    }
    const QByteArray data = res.readAll();
    res.close();

    const QString dest = QDir(QDir::tempPath()).filePath(QString::fromLatin1(kBundledFwName));
    QFileInfo fi(dest);
    if (fi.exists() && fi.size() == data.size())
        return dest;                 // already extracted this run

    QFile out(dest);
    if (!out.open(QIODevice::WriteOnly)) {
        emit updateError("Cannot write bundled firmware to the temp folder.");
        return QString();
    }
    out.write(data);
    out.close();
    return dest;
}

void SelfUpdater::cleanupOldDownloads()
{
    QDir tmp(QDir::tempPath());

    // Clean up downloaded installers for all platforms (zipped and raw)
    QStringList filters;
    filters << "qMonstatek_*_setup.zip" << "qMonstatek_*_setup.exe"
            << "qMonstatek_*_macos.zip" << "qMonstatek_*.dmg"
            << "qMonstatek_*_linux.zip" << "qMonstatek_*.AppImage";
    QStringList files = tmp.entryList(filters, QDir::Files);
    for (const QString &f : files) {
        QString path = tmp.absoluteFilePath(f);
        if (QFile::remove(path))
            qInfo() << "SelfUpdater: cleaned up" << f;
    }

    // Delete the extraction folder
    QDir extractDir(tmp.absoluteFilePath("qmonstatek_update"));
    if (extractDir.exists()) {
        if (extractDir.removeRecursively())
            qInfo() << "SelfUpdater: cleaned up qmonstatek_update/";
    }
}

/*
 * Extract a .zip file to the qmonstatek_update temp folder.
 * Uses PowerShell on Windows, unzip on macOS/Linux.
 * Returns the path to the extraction directory, or empty on failure.
 */
QString SelfUpdater::extractZip(const QString &zipPath)
{
    QString extractDir = QFileInfo(zipPath).absolutePath() + "/qmonstatek_update";
    QDir().mkpath(extractDir);

    QProcess ps;
    ps.setProcessChannelMode(QProcess::MergedChannels);

#ifdef _WIN32
    QStringList args;
    args << "-NoProfile" << "-Command"
         << QString("Expand-Archive -Path '%1' -DestinationPath '%2' -Force")
                .arg(zipPath, extractDir);
    ps.start("powershell.exe", args);
#else
    // macOS and Linux: unzip is available by default
    ps.start("unzip", QStringList() << "-o" << zipPath << "-d" << extractDir);
#endif

    if (!ps.waitForFinished(30000)) {
        qWarning() << "SelfUpdater: zip extraction timed out";
        return {};
    }

    if (ps.exitCode() != 0) {
        qWarning() << "SelfUpdater: extract failed:" << ps.readAll();
        return {};
    }

    return extractDir;
}

bool SelfUpdater::launchInstallerAndQuit(const QString &path)
{
    QFileInfo fi(path);
    if (!fi.exists() || !fi.isFile()) {
        emit updateError("Installer not found: " + path);
        return false;
    }

    // If it's a zip, extract first
    QString targetPath = path;
    QString extractDir;
    if (fi.suffix().toLower() == "zip") {
        extractDir = extractZip(path);
        if (extractDir.isEmpty()) {
            emit updateError("Failed to extract update from zip.");
            return false;
        }
    }

#ifdef _WIN32
    // Windows: find and launch the _setup.exe
    if (!extractDir.isEmpty()) {
        QDir dir(extractDir);
        QStringList exes = dir.entryList(QStringList() << "*_setup.exe", QDir::Files);
        if (exes.isEmpty()) {
            emit updateError("No installer found in zip.");
            return false;
        }
        targetPath = dir.absoluteFilePath(exes.first());
    }

    qInfo() << "SelfUpdater: launching installer" << targetPath;
    bool ok = QProcess::startDetached(targetPath, {});
    if (!ok) {
        emit updateError("Failed to launch installer.");
        return false;
    }

#elif defined(__APPLE__)
    // macOS: find .dmg in extracted zip (or use the path directly if not zipped)
    if (!extractDir.isEmpty()) {
        QDir dir(extractDir);
        QStringList dmgs = dir.entryList(QStringList() << "*.dmg", QDir::Files);
        if (!dmgs.isEmpty())
            targetPath = dir.absoluteFilePath(dmgs.first());
    }

    qInfo() << "SelfUpdater: opening" << targetPath;
    QDesktopServices::openUrl(QUrl::fromLocalFile(targetPath));

#else
    // Linux: find .AppImage in extracted zip, make executable, open containing folder
    if (!extractDir.isEmpty()) {
        QDir dir(extractDir);
        QStringList appImages = dir.entryList(QStringList() << "*.AppImage", QDir::Files);
        if (!appImages.isEmpty()) {
            targetPath = dir.absoluteFilePath(appImages.first());
            // Preserve executable bit
            QFile::setPermissions(targetPath,
                QFile::permissions(targetPath) | QFileDevice::ExeUser | QFileDevice::ExeGroup);
        }
    }

    qInfo() << "SelfUpdater: opening download location for" << targetPath;
    QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(targetPath).absolutePath()));
#endif

    QCoreApplication::quit();
    return true;
}
