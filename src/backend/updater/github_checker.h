/*
 * github_checker.h — GitHub Releases API client
 *
 * Checks for new firmware releases on a configurable GitHub repository.
 * Default: bedge117/M1
 */

#ifndef GITHUB_CHECKER_H
#define GITHUB_CHECKER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QString>
#include <QUrl>
#include <QJsonObject>

class GithubChecker : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString repoUrl READ repoUrl WRITE setRepoUrl NOTIFY repoUrlChanged)
    Q_PROPERTY(bool checking READ isChecking NOTIFY checkingChanged)

public:
    explicit GithubChecker(QObject *parent = nullptr);

    /**
     * Check for the latest release on the configured repo.
     * Pass the device's current version so we can compare.
     */
    Q_INVOKABLE void checkForUpdates(int fwMajor = 0, int fwMinor = 0,
                                     int fwBuild = 0, int fwRC = 0,
                                     int c3Revision = 0);

    /**
     * Download a firmware asset to a local temp file.
     */
    Q_INVOKABLE void downloadAsset(const QUrl &url, const QString &destPath);

    /**
     * Copy a downloaded file to a user-chosen location.
     */
    Q_INVOKABLE bool saveFileTo(const QString &src, const QString &dest);

    /**
     * Get/set the GitHub repository (format: "owner/repo").
     */
    QString repoUrl() const { return m_repoUrl; }
    void setRepoUrl(const QString &url);

    bool isChecking() const { return m_checking; }

    /**
     * Parse a release tag like "v0.8.0.0-C3.1" into components.
     * Returns true if parsing succeeded.
     */
    static bool parseVersionTag(const QString &tag,
                                int &major, int &minor, int &build, int &rc,
                                int &c3Rev);

signals:
    /**
     * Emitted when a newer release is found.
     * info contains: version, name, body, publishedAt, assets, isNewer
     */
    void releaseFound(const QJsonObject &info);

    /**
     * Emitted when no newer release is available (already up to date,
     * or no releases exist).
     */
    void noUpdateAvailable(const QString &message);

    /**
     * Emitted when check fails.
     */
    void checkError(const QString &message);

    void downloadProgress(int percent);
    void downloadComplete(const QString &filePath);
    void downloadError(const QString &message);

    void repoUrlChanged();
    void checkingChanged();

public:
    /**
     * Enable persistence: loads saved repo on call, auto-saves on setRepoUrl.
     */
    void setPersistKey(const QString &key);

private slots:
    void onReleaseReply(QNetworkReply *reply);
    void onDownloadReply(QNetworkReply *reply);

private:
    QNetworkAccessManager m_nam;
    QString m_repoUrl = "bedge117/M1";
    QString m_persistKey;
    QString m_downloadDest;
    bool    m_checking = false;

    // Current device version (set at check time)
    int m_curMajor = 0;
    int m_curMinor = 0;
    int m_curBuild = 0;
    int m_curRC    = 0;
    int m_curC3Rev = 0;
};

#endif // GITHUB_CHECKER_H
