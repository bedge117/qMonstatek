/*
 * self_updater.h — qMonstatek self-update helper
 *
 * Provides methods to extract a downloaded installer zip and
 * launch it, then quit the running application so the installer
 * can replace files.
 */

#ifndef SELF_UPDATER_H
#define SELF_UPDATER_H

#include <QObject>
#include <QString>

class SelfUpdater : public QObject {
    Q_OBJECT

public:
    explicit SelfUpdater(QObject *parent = nullptr);

    Q_INVOKABLE QString tempDir() const;

    /* Firmware bundled inside the app for fully-offline recovery.
     * bundledFirmwarePath() extracts it to a temp file (once) and returns the
     * local path, or "" if this build has no bundled image. */
    Q_INVOKABLE QString bundledFirmwareName() const;
    Q_INVOKABLE QString bundledFirmwarePath();

    /**
     * Launch installer from a downloaded file.
     * If the file is a .zip, extracts the .exe first.
     * Quits qMonstatek so the installer can replace files.
     */
    Q_INVOKABLE bool launchInstallerAndQuit(const QString &path);

signals:
    void updateError(const QString &message);

private:
    QString extractZip(const QString &zipPath);
    void    cleanupOldDownloads();
};

#endif // SELF_UPDATER_H
