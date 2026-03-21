/*
 * self_updater.h — qMonstatek self-update helper
 *
 * Provides a method to launch a downloaded installer and quit
 * the running application so the installer can replace files.
 */

#ifndef SELF_UPDATER_H
#define SELF_UPDATER_H

#include <QObject>
#include <QString>

class SelfUpdater : public QObject {
    Q_OBJECT

public:
    explicit SelfUpdater(QObject *parent = nullptr);

    /**
     * Return the system temp directory for storing the downloaded installer.
     */
    Q_INVOKABLE QString tempDir() const;

    /**
     * Launch the downloaded installer and quit qMonstatek.
     * The Inno Setup installer will kill any remaining instance
     * via taskkill, upgrade in place, and optionally relaunch.
     */
    Q_INVOKABLE bool launchInstallerAndQuit(const QString &installerPath);

signals:
    void updateError(const QString &message);
};

#endif // SELF_UPDATER_H
