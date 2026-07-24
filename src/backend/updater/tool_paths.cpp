/*
 * tool_paths.cpp — Cross-platform tool discovery for OpenOCD and STM32CubeProgrammer
 */

#include "tool_paths.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QDebug>

#ifdef _WIN32
static const QString EXE_SUFFIX = QStringLiteral(".exe");
#else
static const QString EXE_SUFFIX;
#endif

// ── Helper: search STM32CubeIDE installations for a plugin binary ──

struct IdeSearchResult {
    QString binaryPath;
    QString idePath;     // the IDE install directory where it was found
};

static QStringList ideBaseDirs()
{
    QStringList dirs;
#ifdef _WIN32
    dirs << "C:/ST";
#elif defined(__APPLE__)
    dirs << "/Applications";
    dirs << QDir::homePath() + "/Applications";
#else
    // Linux: ST's default install location
    dirs << "/opt/st";
    dirs << QDir::homePath() + "/STM32CubeIDE";
#endif
    return dirs;
}

static IdeSearchResult findInIdePlugins(const QString &pluginGlob,
                                        const QString &relBinaryPath)
{
    IdeSearchResult result;

    for (const QString &baseDir : ideBaseDirs()) {
        QDir base(baseDir);
        if (!base.exists())
            continue;

#ifdef __APPLE__
        // macOS: STM32CubeIDE.app/Contents/Eclipse/plugins/
        QStringList ideEntries = base.entryList(
            QStringList() << "STM32CubeIDE*.app", QDir::Dirs, QDir::Name | QDir::Reversed);
        for (const QString &ideEntry : ideEntries) {
            QDir pluginsDir(base.filePath(ideEntry) + "/Contents/Eclipse/plugins");
#else
        QStringList ideEntries = base.entryList(
            QStringList() << "STM32CubeIDE*" << "stm32cubeide*",
            QDir::Dirs, QDir::Name | QDir::Reversed);
        for (const QString &ideEntry : ideEntries) {
            // Windows: STM32CubeIDE_X.Y.Z/STM32CubeIDE/plugins/
            // Linux:   stm32cubeide_X.Y.Z/plugins/
            QString idePath = base.filePath(ideEntry);
            QDir pluginsDir(idePath + "/STM32CubeIDE/plugins");
            if (!pluginsDir.exists())
                pluginsDir = QDir(idePath + "/plugins");
#endif
            if (!pluginsDir.exists())
                continue;

            QStringList plugins = pluginsDir.entryList(
                QStringList() << pluginGlob, QDir::Dirs);
            for (const QString &plugin : plugins) {
                QString candidate = pluginsDir.filePath(plugin) + "/" +
                                    relBinaryPath + EXE_SUFFIX;
                if (QFile::exists(candidate)) {
                    result.binaryPath = candidate;
                    result.idePath = pluginsDir.absolutePath();
                    return result;
                }
            }
        }
    }
    return result;
}

// ── OpenOCD ─────────────────────────────────────────────────────────

QString ToolPaths::findOpenOcd()
{
    // 1. App-local bundle
    QString appDir = QCoreApplication::applicationDirPath();
    QString localBin = QDir(appDir).filePath("openocd/bin/openocd" + EXE_SUFFIX);
    if (QFile::exists(localBin))
        return localBin;

    // 2. STM32CubeIDE
    auto ide = findInIdePlugins(
        "com.st.stm32cube.ide.mcu.externaltools.openocd*",
        "tools/bin/openocd");
    if (!ide.binaryPath.isEmpty())
        return ide.binaryPath;

    // 3. System PATH
    QString pathOcd = QStandardPaths::findExecutable("openocd");
    if (!pathOcd.isEmpty())
        return pathOcd;

    return {};
}

QString ToolPaths::findOpenOcdScripts(const QString &ocdBinaryPath)
{
    if (ocdBinaryPath.isEmpty())
        return {};

    QFileInfo fi(ocdBinaryPath);
    QDir binDir = fi.absoluteDir();

    // App-local: <app>/openocd/scripts/
    {
        QDir ocdRoot(binDir);
        ocdRoot.cdUp();  // bin/ -> openocd/ or tools/
        QString scripts = ocdRoot.filePath("scripts");
        if (QDir(scripts).exists())
            return scripts;
    }

    // IDE Layout A: .../tools/resources/openocd/st_scripts/
    {
        QDir toolsDir(binDir);
        toolsDir.cdUp();  // bin/ -> tools/
        QString scripts = toolsDir.filePath("resources/openocd/st_scripts");
        if (QDir(scripts).exists())
            return scripts;
    }

    // IDE Layout B: separate debug plugin has scripts
    // Walk up from tools/bin/ to plugins/, then search debug.openocd plugins
    {
        QDir pluginsDir(binDir);
        // bin/ -> tools/ -> <plugin>/ -> plugins/
        pluginsDir.cdUp(); pluginsDir.cdUp(); pluginsDir.cdUp();
        QStringList debugPlugins = pluginsDir.entryList(
            QStringList() << "com.st.stm32cube.ide.mcu.debug.openocd*",
            QDir::Dirs);
        for (const QString &dp : debugPlugins) {
            QString scripts = pluginsDir.filePath(dp) +
                              "/resources/openocd/st_scripts";
            if (QDir(scripts).exists())
                return scripts;
        }
    }

    // System install: ../share/openocd/scripts/
    {
        QDir parentDir(binDir);
        parentDir.cdUp();  // bin/ -> prefix/
        QString scripts = parentDir.filePath("share/openocd/scripts");
        if (QDir(scripts).exists())
            return scripts;
    }

    return {};
}

// ── STM32_Programmer_CLI ────────────────────────────────────────────

QString ToolPaths::findCubeProgrammerCli()
{
    QString binName = "STM32_Programmer_CLI" + EXE_SUFFIX;

    // 0. App-local bundle — mirrors the Windows stm32prog/ folder so a macOS
    //    .dmg / Linux AppImage can ship its own copy of the CLI.
    {
        const QString appDir = QCoreApplication::applicationDirPath();
        QStringList localCandidates;
        localCandidates << QDir(appDir).filePath("stm32prog/bin/" + binName);
        localCandidates << QDir(appDir).filePath("stm32prog/" + binName);
#ifdef __APPLE__
        // Inside a .app the exe is in Contents/MacOS; the bundle lives under
        // Contents/Resources.
        localCandidates << QDir(appDir).filePath("../Resources/stm32prog/bin/" + binName);
        localCandidates << QDir(appDir).filePath("../Resources/stm32prog/" + binName);
#endif
        for (const QString &c : localCandidates)
            if (QFile::exists(c))
                return QFileInfo(c).absoluteFilePath();
    }

    // 1. Standalone STM32CubeProgrammer install
    QStringList standalonePaths;
#ifdef _WIN32
    standalonePaths << "C:/Program Files/STMicroelectronics/STM32Cube/"
                       "STM32CubeProgrammer/bin/" + binName;
#elif defined(__APPLE__)
    // Default macOS install (STM32CubeProgrammer 2.19+): the CLI lives under
    // the .app's Contents/Resources/bin. Cover /Applications and ~/Applications,
    // plus the api/lib copy and older/symlinked layouts.
    {
        const QStringList appRoots = {
            "/Applications",
            QDir::homePath() + "/Applications"
        };
        for (const QString &root : appRoots) {
            const QString appBase = root +
                "/STMicroelectronics/STM32Cube/STM32CubeProgrammer/"
                "STM32CubeProgrammer.app/Contents";
            standalonePaths << appBase + "/Resources/bin/" + binName;
            standalonePaths << appBase + "/Resources/api/lib/" + binName;
            standalonePaths << appBase + "/MacOs/bin/" + binName;   // legacy layout
        }
    }
    standalonePaths << "/Applications/STM32CubeProgrammer/bin/" + binName;
#else
    standalonePaths << "/opt/st/STM32CubeProgrammer/bin/" + binName;
    standalonePaths << "/usr/local/STMicroelectronics/STM32Cube/"
                       "STM32CubeProgrammer/bin/" + binName;
    standalonePaths << QDir::homePath() + "/STMicroelectronics/STM32Cube/"
                       "STM32CubeProgrammer/bin/" + binName;
    standalonePaths << "/opt/stm32cubeprog/bin/" + binName;
#endif
    for (const QString &path : standalonePaths) {
        if (QFile::exists(path))
            return path;
    }

    // 2. STM32CubeIDE embedded cubeprogrammer plugin
    auto ide = findInIdePlugins(
        "com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer*",
        "tools/bin/STM32_Programmer_CLI");
    if (!ide.binaryPath.isEmpty())
        return ide.binaryPath;

    // 3. System PATH
    QString pathCli = QStandardPaths::findExecutable("STM32_Programmer_CLI");
    if (!pathCli.isEmpty())
        return pathCli;

    return {};
}
