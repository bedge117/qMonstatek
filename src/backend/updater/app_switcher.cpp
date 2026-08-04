/* app_switcher.cpp — qMonstatek Studio handoff helper. */

#include "app_switcher.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QSettings>
#include <QSet>

namespace {

QString validCandidate(const QString &path)
{
    const QFileInfo candidate(path);
    if (!candidate.exists() || !candidate.isFile())
        return {};

    // Studio ships as qmstudio.exe and this app as qmonstatek.exe, so the names
    // differ — but keep this guard anyway so a renamed/portable copy of this app
    // can never be mistaken for Studio.
    const QFileInfo self(QCoreApplication::applicationFilePath());
    if (candidate.canonicalFilePath() == self.canonicalFilePath())
        return {};

    return candidate.absoluteFilePath();
}

void addInstallCandidate(QStringList &paths, const QString &base)
{
    if (!base.isEmpty())
        paths.append(QDir(base).filePath("qmstudio.exe"));
}

} // namespace

AppSwitcher::AppSwitcher(QObject *parent)
    : QObject(parent)
{
}

QString AppSwitcher::locateStudio() const
{
    QStringList candidates;

    // Useful for portable/developer setups and harmless for installed builds.
    const QString overridePath = qEnvironmentVariable("QM_STUDIO_PATH");
    if (!overridePath.isEmpty())
        candidates.append(overridePath);

    // A side-by-side portable layout is convenient for development and release
    // zips: .../qMonstatek/qmonstatek.exe -> ../qMonstatek Studio/qmstudio.exe.
    const QDir appDir(QCoreApplication::applicationDirPath());
    addInstallCandidate(candidates, appDir.absoluteFilePath("../qMonstatek Studio"));
    // Local build/deploy layouts keep the products in sibling repositories.
    // These are fallbacks only; an installed Studio found in the registry
    // below always wins.
    addInstallCandidate(candidates, appDir.absoluteFilePath("../../qmonstatek-studio/deploy"));
    addInstallCandidate(candidates, appDir.absoluteFilePath("../../../qmonstatek-studio/build/src"));

#ifdef Q_OS_WIN
    // Studio has a stable, distinct Inno Setup AppId. Use the installed location
    // after nearby portable/build copies, so a qMonstatek deploy test does not
    // silently start an older Program Files Studio.
    const QString uninstallKey =
        "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
        "\\{B5B3D5FE-A6FA-4481-848E-BDAD383A3973}_is1";
    const QSettings uninstall(uninstallKey, QSettings::NativeFormat);
    addInstallCandidate(candidates, uninstall.value("InstallLocation").toString());

    // Fallback for a normal Inno default install, including 32-bit installs on
    // a 64-bit host. Duplicates are removed below.
    addInstallCandidate(candidates, qEnvironmentVariable("ProgramW6432") + "/qMonstatek Studio");
    addInstallCandidate(candidates, qEnvironmentVariable("ProgramFiles") + "/qMonstatek Studio");
    addInstallCandidate(candidates, qEnvironmentVariable("ProgramFiles(x86)") + "/qMonstatek Studio");
#endif

    QSet<QString> seen;
    for (const QString &candidate : candidates) {
        const QString normalized = QDir::cleanPath(candidate);
        if (seen.contains(normalized))
            continue;
        seen.insert(normalized);
        const QString valid = validCandidate(normalized);
        if (!valid.isEmpty())
            return valid;
    }

    return {};
}

bool AppSwitcher::studioInstalled() const
{
    return !locateStudio().isEmpty();
}

QString AppSwitcher::studioExecutable() const
{
    return locateStudio();
}

bool AppSwitcher::launchStudioAndQuit(const QString &portName)
{
    const QString executable = locateStudio();
    if (executable.isEmpty()) {
        emit launchError("qMonstatek Studio is not installed. Download it to manage M1OS.");
        return false;
    }

    QStringList arguments;
    if (!portName.trimmed().isEmpty())
        arguments << "--port" << portName.trimmed();

    if (!QProcess::startDetached(executable, arguments,
                                 QFileInfo(executable).absolutePath())) {
        emit launchError("Could not start qMonstatek Studio.");
        return false;
    }

    QCoreApplication::quit();
    return true;
}
