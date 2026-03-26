/*
 * github_checker.cpp — GitHub Releases API client
 */

#include "github_checker.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDir>
#include <QFile>
#include <QDebug>
#include <QCoreApplication>
#include <QRegularExpression>
#include <QSettings>
#include <QCryptographicHash>
#include <QSslSocket>

GithubChecker::GithubChecker(QObject *parent)
    : QObject(parent)
{
}

void GithubChecker::setPersistKey(const QString &key)
{
    m_persistKey = key;
    if (!key.isEmpty()) {
        QSettings settings;
        QString saved = settings.value(key).toString();
        if (!saved.isEmpty()) {
            m_repoUrl = saved;
            emit repoUrlChanged();
        }
    }
}

void GithubChecker::setRepoUrl(const QString &url)
{
    if (m_repoUrl != url) {
        m_repoUrl = url;
        if (!m_persistKey.isEmpty()) {
            QSettings settings;
            settings.setValue(m_persistKey, url);
        }
        emit repoUrlChanged();
    }
}

/* Parse "v0.8.0.0-C3.1", "v0.8.0.0", or "v1.1.0" into components */
bool GithubChecker::parseVersionTag(const QString &tag,
                                    int &major, int &minor, int &build, int &rc,
                                    int &c3Rev)
{
    // Try 4-component first: v0.8.0.0 or v0.8.0.0-C3.1
    static QRegularExpression re4(
        R"(v?(\d+)\.(\d+)\.(\d+)\.(\d+)(?:-C3\.(\d+))?)",
        QRegularExpression::CaseInsensitiveOption);

    QRegularExpressionMatch m = re4.match(tag);
    if (m.hasMatch()) {
        major = m.captured(1).toInt();
        minor = m.captured(2).toInt();
        build = m.captured(3).toInt();
        rc    = m.captured(4).toInt();
        c3Rev = m.captured(5).isEmpty() ? 0 : m.captured(5).toInt();
        return true;
    }

    // Try C3-only tag: C3.4, C3.1, etc.
    static QRegularExpression reC3(
        R"(C3\.(\d+))",
        QRegularExpression::CaseInsensitiveOption);

    m = reC3.match(tag);
    if (m.hasMatch()) {
        major = 0; minor = 8; build = 0; rc = 0;
        c3Rev = m.captured(1).toInt();
        return true;
    }

    // Try 3-component semver: v1.1.0
    static QRegularExpression re3(
        R"(v?(\d+)\.(\d+)\.(\d+))",
        QRegularExpression::CaseInsensitiveOption);

    m = re3.match(tag);
    if (m.hasMatch()) {
        major = m.captured(1).toInt();
        minor = m.captured(2).toInt();
        build = m.captured(3).toInt();
        rc    = 0;
        c3Rev = 0;
        return true;
    }

    return false;
}

void GithubChecker::checkForUpdates(int fwMajor, int fwMinor,
                                    int fwBuild, int fwRC,
                                    int c3Revision)
{
    if (m_checking) return;

    m_curMajor = fwMajor;
    m_curMinor = fwMinor;
    m_curBuild = fwBuild;
    m_curRC    = fwRC;
    m_curC3Rev = c3Revision;

    m_checking = true;
    emit checkingChanged();

    QString apiUrl = QString("https://api.github.com/repos/%1/releases/latest")
                         .arg(m_repoUrl);

    qDebug() << "[UpdateCheck] Checking" << apiUrl
             << "current:" << fwMajor << fwMinor << fwBuild << fwRC
             << "C3." << c3Revision;

    if (!QSslSocket::supportsSsl()) {
        qWarning() << "[UpdateCheck] TLS/SSL not available."
                    << "Build:" << QSslSocket::sslLibraryBuildVersionString()
                    << "Runtime:" << QSslSocket::sslLibraryVersionString();
#ifdef Q_OS_LINUX
        emit checkError("TLS not available. Install OpenSSL:\n"
                        "  sudo pacman -S openssl   (Arch/EndeavourOS)\n"
                        "  sudo apt install libssl-dev   (Debian/Ubuntu)\n"
                        "Then restart the application.");
#else
        emit checkError("TLS initialization failed. OpenSSL libraries not found.");
#endif
        m_checking = false;
        emit checkingChanged();
        return;
    }

    QNetworkRequest req{QUrl(apiUrl)};
    req.setHeader(QNetworkRequest::UserAgentHeader, "qMonstatek/1.0");
    req.setRawHeader("Accept", "application/vnd.github.v3+json");

    QNetworkReply *reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onReleaseReply(reply);
    });
}

void GithubChecker::onReleaseReply(QNetworkReply *reply)
{
    m_checking = false;
    emit checkingChanged();

    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        if (reply->error() == QNetworkReply::ContentNotFoundError) {
            emit noUpdateAvailable("No releases published on " + m_repoUrl);
        } else {
            emit checkError(QString("GitHub API error: %1").arg(reply->errorString()));
        }
        return;
    }

    QByteArray data = reply->readAll();
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) {
        emit checkError("Invalid JSON response from GitHub");
        return;
    }

    QJsonObject root = doc.object();
    QString tagName = root["tag_name"].toString();

    // Parse the release version
    int relMajor = 0, relMinor = 0, relBuild = 0, relRC = 0, relC3 = 0;
    if (!parseVersionTag(tagName, relMajor, relMinor, relBuild, relRC, relC3)) {
        qWarning() << "[UpdateCheck] Cannot parse release tag:" << tagName;
        emit checkError("Cannot parse release version tag: " + tagName);
        return;
    }

    qDebug() << "[UpdateCheck] Release:" << relMajor << relMinor << relBuild << relRC
             << "C3." << relC3;

    // Hierarchical comparison: base version first, then C3 revision
    bool isNewer = false;
    auto baseCompare = [](int a1, int a2, int a3, int a4,
                          int b1, int b2, int b3, int b4) -> int {
        if (a1 != b1) return a1 - b1;
        if (a2 != b2) return a2 - b2;
        if (a3 != b3) return a3 - b3;
        return a4 - b4;
    };

    int baseCmp = baseCompare(relMajor, relMinor, relBuild, relRC,
                              m_curMajor, m_curMinor, m_curBuild, m_curRC);
    if (baseCmp > 0) {
        isNewer = true;     // higher base version
    } else if (baseCmp == 0 && relC3 > m_curC3Rev) {
        isNewer = true;     // same base, higher C3 revision
    }

    // Build the info object
    QJsonObject info;
    info["version"]     = tagName;
    info["name"]        = root["name"].toString();
    info["body"]        = root["body"].toString();
    info["publishedAt"] = root["published_at"].toString();
    info["htmlUrl"]     = root["html_url"].toString();
    info["prerelease"]  = root["prerelease"].toBool();
    info["isNewer"]     = isNewer;

    // Use the tag name directly as the display version (preserves original format)
    info["versionFormatted"] = tagName;

    // Build current version string from app version (e.g. "v2.1.2")
    info["currentVersion"] = "v" + QCoreApplication::applicationVersion();

    // Parse assets
    QJsonArray assets;
    QJsonArray assetsArr = root["assets"].toArray();
    for (const auto &assetVal : assetsArr) {
        QJsonObject asset = assetVal.toObject();
        QJsonObject a;
        a["name"]        = asset["name"].toString();
        a["size"]        = asset["size"].toInt();
        a["downloadUrl"] = asset["browser_download_url"].toString();
        a["contentType"] = asset["content_type"].toString();
        assets.append(a);
    }
    info["assets"] = assets;

    if (isNewer) {
        emit releaseFound(info);
    } else {
        QString msg = QString("You're up to date (%1). Latest release: %2")
                          .arg(info["currentVersion"].toString(),
                               info["versionFormatted"].toString());
        emit noUpdateAvailable(msg);
    }
}

bool GithubChecker::saveFileTo(const QString &src, const QString &dest)
{
    if (QFile::exists(dest))
        QFile::remove(dest);
    return QFile::copy(src, dest);
}

void GithubChecker::downloadAsset(const QUrl &url, const QString &destPath)
{
    // If destPath is just a filename (no directory separator), put it in
    // the system temp directory so we don't need write access to Program Files.
    if (!destPath.contains('/') && !destPath.contains('\\')) {
        m_downloadDest = QDir(QDir::tempPath()).filePath(destPath);
    } else {
        m_downloadDest = destPath;
    }

    QNetworkRequest req{url};
    req.setHeader(QNetworkRequest::UserAgentHeader, "qMonstatek/1.0");

    QNetworkReply *reply = m_nam.get(req);

    connect(reply, &QNetworkReply::downloadProgress,
            this, [this](qint64 received, qint64 total) {
        if (total > 0) {
            emit downloadProgress(static_cast<int>(received * 100 / total));
        }
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onDownloadReply(reply);
    });
}

void GithubChecker::onDownloadReply(QNetworkReply *reply)
{
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        emit downloadError(reply->errorString());
        return;
    }

    // Handle redirect
    QUrl redirect = reply->attribute(
        QNetworkRequest::RedirectionTargetAttribute).toUrl();
    if (redirect.isValid()) {
        downloadAsset(redirect, m_downloadDest);
        return;
    }

    QByteArray data = reply->readAll();

    // Clean up any previous firmware downloads in temp
    QFileInfo destInfo(m_downloadDest);
    if (destInfo.absolutePath() == QDir::tempPath()) {
        QDir tmp(QDir::tempPath());
        QString suffix = destInfo.suffix();  // e.g. "bin"
        if (!suffix.isEmpty()) {
            QStringList filters;
            filters << "M1_v*." + suffix << "factory_ESP32*." + suffix;
            for (const QString &old : tmp.entryList(filters, QDir::Files)) {
                if (old != destInfo.fileName())
                    QFile::remove(tmp.filePath(old));
            }
        }
    }

    QFile outFile(m_downloadDest);
    if (!outFile.open(QIODevice::WriteOnly)) {
        emit downloadError("Cannot write to: " + m_downloadDest);
        return;
    }
    outFile.write(data);
    outFile.close();

    emit downloadComplete(m_downloadDest);
}

QJsonObject GithubChecker::verifyFileMd5(const QString &binPath, const QString &md5Path)
{
    QJsonObject result;

    QFile binFile(binPath);
    if (!binFile.open(QIODevice::ReadOnly)) {
        result["error"] = "Cannot open binary file: " + binPath;
        return result;
    }
    QByteArray computed = QCryptographicHash::hash(binFile.readAll(),
                                                   QCryptographicHash::Md5).toHex();
    binFile.close();

    QFile md5File(md5Path);
    if (!md5File.open(QIODevice::ReadOnly | QIODevice::Text)) {
        result["error"] = "Cannot open MD5 file: " + md5Path;
        return result;
    }
    QString content = QString::fromUtf8(md5File.readAll()).trimmed();
    md5File.close();

    // Parse standard .md5 format: "hash  filename" or just "hash"
    QString expected = content.split(QRegularExpression("\\s+")).first().toLower();

    result["computed"] = QString(computed);
    result["expected"] = expected;
    result["match"]    = (QString(computed) == expected);

    return result;
}

qint64 GithubChecker::fileSize(const QString &path)
{
    QFileInfo fi(path);
    return fi.exists() ? fi.size() : -1;
}
