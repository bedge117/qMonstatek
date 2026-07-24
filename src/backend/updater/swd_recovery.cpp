/*
 * swd_recovery.cpp — SWD recovery tools via OpenOCD
 *
 * Locates OpenOCD (bundled with STM32CubeIDE or standalone), builds
 * command strings for each operation, and runs them via QProcess.
 * Output is captured and parsed for progress/status reporting.
 *
 * Path resolution ensures the OpenOCD binary and TCL scripts always
 * come from the same installation to avoid version mismatches.
 * Supports STM32CubeIDE 2.1.0, 2.1.1, and future versions.
 */

#include "swd_recovery.h"
#include "tool_paths.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QDebug>

static constexpr int FLASH_BANK_SIZE = 0x100000;  // 1 MB

SwdRecovery::SwdRecovery(QObject *parent)
    : QObject(parent)
{
    resolveOpenOcdPaths();
}

SwdRecovery::~SwdRecovery()
{
    cancel();
}

// ── Path resolution ──────────────────────────────────────────────

/*
 * Find the OpenOCD binary AND scripts together using the shared
 * ToolPaths utility for cross-platform path resolution.
 */
void SwdRecovery::resolveOpenOcdPaths()
{
    if (m_pathsResolved)
        return;
    m_pathsResolved = true;

    m_ocdPath = ToolPaths::findOpenOcd();
    if (!m_ocdPath.isEmpty()) {
        m_scriptsPath = ToolPaths::findOpenOcdScripts(m_ocdPath);
        if (!m_scriptsPath.isEmpty()) {
            probeVersion();
            return;
        }
        // Binary found but no scripts — clear it
        qWarning() << "SWD: Found OpenOCD at" << m_ocdPath << "but no scripts.";
        m_ocdPath.clear();
    }

    qWarning() << "SWD: Could not find OpenOCD binary + scripts pair.";
}

/*
 * Run `openocd --version` to capture the version string for diagnostics.
 * Non-blocking — runs synchronously with a short timeout since --version
 * returns instantly.
 */
void SwdRecovery::probeVersion()
{
    QProcess proc;
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start(m_ocdPath, QStringList() << "--version");
    if (proc.waitForFinished(3000)) {
        QString output = QString::fromUtf8(proc.readAll()).trimmed();
        // First line is typically "Open On-Chip Debugger 0.12.0 ..." or similar
        QStringList lines = output.split('\n', Qt::SkipEmptyParts);
        if (!lines.isEmpty())
            m_ocdVersion = lines.first().trimmed();
    }
    if (m_ocdVersion.isEmpty())
        m_ocdVersion = "unknown";

    qInfo() << "SWD: OpenOCD =" << m_ocdPath;
    qInfo() << "SWD: Scripts =" << m_scriptsPath;
    qInfo() << "SWD: Version =" << m_ocdVersion;
}

/*
 * Find STM32_Programmer_CLI using the shared ToolPaths utility
 * for cross-platform path resolution.
 */
void SwdRecovery::resolveCubeProgrammerPath()
{
    if (m_cubeProgResolved)
        return;
    m_cubeProgResolved = true;

    m_cubeProgrammerPath = ToolPaths::findCubeProgrammerCli();
    if (!m_cubeProgrammerPath.isEmpty())
        qInfo() << "SWD: CubeProgrammer =" << m_cubeProgrammerPath;
    else
        qWarning() << "SWD: STM32_Programmer_CLI not found.";
}

QString SwdRecovery::interfaceConfig() const
{
    // ST-Link uses STM32_Programmer_CLI (not OpenOCD), so this is only
    // called for Pico CMSIS-DAP.
    return QStringLiteral("interface/cmsis-dap.cfg");
}

/*
 * Pre-flight check: verify that all required config files exist in the
 * resolved scripts directory before launching OpenOCD.
 */
bool SwdRecovery::validateSetup(QString &error) const
{
    if (m_probeType == StLinkV2) {
        // ST-Link uses STM32_Programmer_CLI
        if (m_cubeProgrammerPath.isEmpty()) {
            error = "STM32_Programmer_CLI not found. Install STM32CubeProgrammer "
                    "or STM32CubeIDE.";
            return false;
        }
        return true;
    }

    // Pico CMSIS-DAP uses OpenOCD
    if (m_ocdPath.isEmpty() || m_scriptsPath.isEmpty()) {
#ifdef _WIN32
        error = "OpenOCD not found. Install STM32CubeIDE or place OpenOCD "
                "in the openocd/ folder next to qmonstatek.exe.";
#elif defined(__APPLE__)
        error = "OpenOCD not found. Install STM32CubeIDE or run: brew install openocd";
#else
        error = "OpenOCD not found. Install STM32CubeIDE or run: sudo apt install openocd";
#endif
        return false;
    }

    // Check interface config
    QString ifacePath = QDir(m_scriptsPath).filePath(interfaceConfig());
    if (!QFile::exists(ifacePath)) {
        error = QString("Interface config not found: %1\n"
                        "Scripts directory: %2\n"
                        "Try reinstalling STM32CubeIDE or using a bundled OpenOCD.")
                    .arg(interfaceConfig(), m_scriptsPath);
        return false;
    }

    // Check target config
    QString targetPath = QDir(m_scriptsPath).filePath("target/stm32h5x.cfg");
    if (!QFile::exists(targetPath)) {
        error = QString("Target config not found: target/stm32h5x.cfg\n"
                        "Scripts directory: %1\n"
                        "Your OpenOCD installation may not support STM32H5. "
                        "STM32CubeIDE 2.1.0 or newer is required.")
                    .arg(m_scriptsPath);
        return false;
    }

    return true;
}

bool SwdRecovery::isOpenOcdAvailable()
{
    resolveOpenOcdPaths();
    resolveCubeProgrammerPath();
    if (m_probeType == StLinkV2)
        return !m_cubeProgrammerPath.isEmpty();
    return !m_ocdPath.isEmpty() && !m_scriptsPath.isEmpty();
}

QString SwdRecovery::openOcdLocation()
{
    if (m_probeType == StLinkV2)
        return m_cubeProgrammerPath;
    return m_ocdPath;
}

void SwdRecovery::setProbeType(int type)
{
    if (m_probeType != type) {
        m_probeType = type;
        emit probeTypeChanged(type);
    }
}

// ── Operations ───────────────────────────────────────────────────

void SwdRecovery::recoveryFlash(const QString &binFilePath)
{
    if (m_running) {
        emit operationError("An operation is already in progress.");
        return;
    }

    QFileInfo fi(binFilePath);
    if (!fi.exists()) {
        emit operationError("Firmware file not found: " + binFilePath);
        return;
    }
    if (fi.size() > FLASH_BANK_SIZE + 4) {
        emit operationError(QString("Firmware file is too large (%1 KB). "
                                    "The M1 flash bank is 1 MB.").arg(fi.size() / 1024));
        return;
    }

    if (m_probeType == StLinkV2) {
        // ST-Link: use STM32_Programmer_CLI
        // Writes to 0x08000000 (boot address regardless of SWAP_BANK),
        // auto-erases needed sectors, verifies, and resets.
        QString path = fi.absoluteFilePath().replace('\\', '/');
        QStringList args;
        args << "-c" << "port=SWD" << "mode=UR" << "reset=HWrst"
             << "-e" << "all"
             << "-w" << path << "0x08000000"
             << "-v"
             << "-rst";
        runCubeProgrammer(args, "Recovery Flash");
        return;
    }

    // Pico CMSIS-DAP: use OpenOCD
    // Use forward slashes — OpenOCD's Tcl parser treats \ as escape chars
    QString path = fi.absoluteFilePath().replace('\\', '/');

    // Clear SWAP_BANK first so 0x08000000 always = physical bank 1,
    // then erase and program bank 1. This ensures recovery works
    // regardless of which bank was previously active.
    //
    // STM32H573 flash registers (non-secure base 0x40022000):
    //   NSKEYR     = 0x40022008  (flash unlock keys)
    //   OPTKEYR    = 0x4002200C  (option byte unlock keys)
    //   OPTCR      = 0x4002201C  (OPTSTRT = bit 1)
    //   OPTSR_CUR  = 0x40022050  (SWAP_BANK = bit 31)
    //   OPTSR_PRG  = 0x40022054
    QString cmds = QString(
        "adapter speed 2000; "
        "init; "
        "halt; "
        "mww 0x40022008 0x45670123; "        // NSKEYR unlock key 1
        "mww 0x40022008 0xCDEF89AB; "        // NSKEYR unlock key 2
        "mww 0x4002200C 0x08192A3B; "        // OPTKEYR unlock key 1
        "mww 0x4002200C 0x4C5D6E7F; "        // OPTKEYR unlock key 2
        "set optr [mrw 0x40022050]; "         // read OPTSR_CUR
        "set cleared [expr {$optr & 0x7FFFFFFF}]; " // clear SWAP_BANK bit
        "mww 0x40022054 $cleared; "           // write OPTSR_PRG
        "mww 0x4002201C 0x00000002; "         // OPTCR = OPTSTRT (bit 1)
        "sleep 500; "                         // wait for OBL reset
        "halt; "                              // re-halt after reset
        "stm32h5x mass_erase 0; "
        "program {%1} 0x08000000 verify reset exit"
    ).arg(path);

    runOpenOcd(cmds, "Recovery Flash");
}

void SwdRecovery::swapBank()
{
    if (m_running) {
        emit operationError("An operation is already in progress.");
        return;
    }

    if (m_probeType == StLinkV2) {
        // ST-Link: read current SWAP_BANK and toggle it.
        // CubeProgrammer reads current value and we toggle.
        // Since we can't read-then-toggle atomically, we use two steps:
        // For simplicity, just set SWAP_BANK=1. If already 1, set to 0.
        // TODO: read current state first. For now, prompt user or just toggle.
        // Using -ob with a value always sets it.
        // We'll read status first via a separate call, but for now just
        // offer a simple toggle: try setting SWAP_BANK=1, if it was already 1
        // the OBL launch will still reset.
        emit operationError("Swap Bank with ST-Link: use Read Status to check current "
                            "bank, then use STM32CubeProgrammer to set SWAP_BANK.");
        return;
    }

    // Pico CMSIS-DAP: use OpenOCD
    // Unlock flash + option bytes, read OPTR, toggle SWAP_BANK (bit 31), launch, reset
    QString cmds =
        "adapter speed 2000; init; "
        "halt; "
        "mww 0x40022008 0x45670123; "        // NSKEYR unlock key 1
        "mww 0x40022008 0xCDEF89AB; "        // NSKEYR unlock key 2
        "mww 0x4002200C 0x08192A3B; "        // OPTKEYR unlock key 1
        "mww 0x4002200C 0x4C5D6E7F; "        // OPTKEYR unlock key 2
        "set val [mrw 0x40022050]; "          // read OPTSR_CUR
        "set new [expr {$val ^ 0x80000000}]; " // toggle bit 31
        "mww 0x40022054 $new; "               // write OPTSR_PRG
        "mww 0x4002201C 0x00000002; "         // OPTCR = OPTSTRT (bit 1)
        "sleep 500; exit";

    runOpenOcd(cmds, "Swap Bank");
}

void SwdRecovery::verifyBank1(const QString &binFilePath)
{
    if (m_running) {
        emit operationError("An operation is already in progress.");
        return;
    }

    QFileInfo fi(binFilePath);
    if (!fi.exists()) {
        emit operationError("Firmware file not found: " + binFilePath);
        return;
    }

    QString path = fi.absoluteFilePath().replace('\\', '/');

    // Check SWAP_BANK to find physical bank 1's address:
    //   SWAP_BANK=0: bank 1 at 0x08000000
    //   SWAP_BANK=1: bank 1 at 0x08100000 (swapped)
    QString cmds = QString(
        "adapter speed 2000; init; "
        "halt; "
        "set optr [mrw 0x40022050]; "
        "if {$optr & 0x80000000} {"
        "  verify_image {%1} 0x08100000"
        "} else {"
        "  verify_image {%1} 0x08000000"
        "}; "
        "exit"
    ).arg(path);

    runOpenOcd(cmds, "Verify Bank 1");
}

void SwdRecovery::verifyBank2(const QString &binFilePath)
{
    if (m_running) {
        emit operationError("An operation is already in progress.");
        return;
    }

    QFileInfo fi(binFilePath);
    if (!fi.exists()) {
        emit operationError("Firmware file not found: " + binFilePath);
        return;
    }

    QString path = fi.absoluteFilePath().replace('\\', '/');

    // Check SWAP_BANK to find physical bank 2's address:
    //   SWAP_BANK=0: bank 2 at 0x08100000
    //   SWAP_BANK=1: bank 2 at 0x08000000 (swapped)
    QString cmds = QString(
        "adapter speed 2000; init; "
        "halt; "
        "set optr [mrw 0x40022050]; "
        "if {$optr & 0x80000000} {"
        "  verify_image {%1} 0x08000000"
        "} else {"
        "  verify_image {%1} 0x08100000"
        "}; "
        "exit"
    ).arg(path);

    runOpenOcd(cmds, "Verify Bank 2");
}

void SwdRecovery::cloneBank1ToBank2()
{
    if (m_running) {
        emit operationError("An operation is already in progress.");
        return;
    }

    QString tempFile = QString(QDir::tempPath() + "/m1_swd_bank1_backup.bin")
                           .replace('\\', '/');

    // Check SWAP_BANK to find correct addresses:
    //   SWAP_BANK=0: bank 1 at 0x08000000, bank 2 at 0x08100000
    //   SWAP_BANK=1: bank 1 at 0x08100000, bank 2 at 0x08000000
    // Use reset halt (not just halt) to ensure all peripherals/DMA are
    // stopped before the 1MB flash read — prevents bus access conflicts.
    QString cmds = QString(
        "adapter speed 2000; init; "
        "reset halt; "
        "set optr [mrw 0x40022050]; "
        "if {$optr & 0x80000000} {"
        "  set bank1 0x08100000; set bank2 0x08000000"
        "} else {"
        "  set bank1 0x08000000; set bank2 0x08100000"
        "}; "
        "dump_image {%1} $bank1 0x100000; "
        "program {%1} $bank2 verify; "
        "reset; exit"
    ).arg(tempFile);

    runOpenOcd(cmds, "Clone Bank 1 to Bank 2");
}

void SwdRecovery::readStatus()
{
    if (m_running) {
        emit operationError("An operation is already in progress.");
        return;
    }

    if (m_probeType == StLinkV2) {
        // ST-Link: use CubeProgrammer to display option bytes
        QStringList args;
        args << "-c" << "port=SWD" << "mode=UR" << "reset=HWrst"
             << "-ob" << "displ";
        runCubeProgrammer(args, "Read Status");
        return;
    }

    // Pico CMSIS-DAP: use OpenOCD
    runOpenOcd("adapter speed 2000; init; "
               "halt; "
               "mdw 0x40022050; exit",  // OPTSR_CUR at 0x40022050
               "Read Status");
}

// ── Process management ───────────────────────────────────────────

void SwdRecovery::runOpenOcd(const QString &commands, const QString &opName)
{
    // Pre-flight validation
    QString setupError;
    if (!validateSetup(setupError)) {
        emit operationError(setupError);
        return;
    }

    clearLog();
    m_currentOp    = opName;
    m_running      = true;
    m_progress     = 0;
    m_usingCubeProg = false;
    emit runningChanged(true);
    emit progressChanged(0);
    setStatus(opName + "...");

    // Diagnostic header
    appendLog("=== " + opName + " ===\n");
    appendLog("Probe:   Pico CMSIS-DAP\n");
    appendLog("OpenOCD: " + m_ocdPath + "\n");
    appendLog("Scripts: " + m_scriptsPath + "\n");
    appendLog("Version: " + m_ocdVersion + "\n");
    appendLog("Config:  " + interfaceConfig() + "\n\n");

    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::MergedChannels);

    // Run OpenOCD from its own bin directory so it finds libusb DLLs
    m_process->setWorkingDirectory(QFileInfo(m_ocdPath).absolutePath());

    connect(m_process, &QProcess::readyRead,
            this, &SwdRecovery::onProcessOutput);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &SwdRecovery::onProcessFinished);
    connect(m_process, &QProcess::errorOccurred,
            this, [this](QProcess::ProcessError err) {
        QString msg;
        switch (err) {
        case QProcess::FailedToStart:
#ifdef _WIN32
            msg = "OpenOCD failed to start. Check that the executable exists and "
                  "required DLLs (libusb-1.0.dll) are present.";
#else
            msg = "OpenOCD failed to start. Check that the executable exists and "
                  "libusb is installed (brew install libusb / apt install libusb-1.0-0).";
#endif
            break;
        case QProcess::Timedout:
            msg = "OpenOCD timed out.";
            break;
        default:
            msg = "OpenOCD process error: " + QString::number(err);
            break;
        }
        appendLog("\nERROR: " + msg + "\n");
        if (m_running) {
            m_running = false;
            emit runningChanged(false);
            setStatus(m_currentOp + " -- " + msg);
            emit operationError(msg);
        }
    });

    // Use forward slashes — OpenOCD's Tcl parser treats \ as escape
    QString scriptsPathFwd = QString(m_scriptsPath).replace('\\', '/');

    QStringList args;
    args << "-s" << scriptsPathFwd
         << "-f" << interfaceConfig()
         << "-f" << "target/stm32h5x.cfg"
         << "-c" << commands;

    // Log the full command for debugging
    appendLog("Command: " + m_ocdPath + "\n");
    for (const QString &arg : args)
        appendLog("  " + arg + "\n");
    appendLog("\n");

    qInfo() << "SWD:" << m_ocdPath << args;
    m_process->start(m_ocdPath, args);
}

void SwdRecovery::runCubeProgrammer(const QStringList &cubeArgs, const QString &opName)
{
    resolveCubeProgrammerPath();

    // Pre-flight validation
    QString setupError;
    if (!validateSetup(setupError)) {
        emit operationError(setupError);
        return;
    }

    clearLog();
    m_currentOp     = opName;
    m_running       = true;
    m_progress      = 0;
    m_usingCubeProg = true;
    emit runningChanged(true);
    emit progressChanged(0);
    setStatus(opName + "...");

    // Diagnostic header
    appendLog("=== " + opName + " ===\n");
    appendLog("Probe:   ST-Link\n");
    appendLog("Tool:    " + m_cubeProgrammerPath + "\n\n");

    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    m_process->setWorkingDirectory(QFileInfo(m_cubeProgrammerPath).absolutePath());

    connect(m_process, &QProcess::readyRead,
            this, &SwdRecovery::onProcessOutput);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &SwdRecovery::onProcessFinished);
    connect(m_process, &QProcess::errorOccurred,
            this, [this](QProcess::ProcessError err) {
        QString msg;
        switch (err) {
        case QProcess::FailedToStart:
            msg = "STM32_Programmer_CLI failed to start.";
            break;
        default:
            msg = "STM32_Programmer_CLI process error: " + QString::number(err);
            break;
        }
        appendLog("\nERROR: " + msg + "\n");
        if (m_running) {
            m_running = false;
            emit runningChanged(false);
            setStatus(m_currentOp + " -- " + msg);
            emit operationError(msg);
        }
    });

    // Log command
    appendLog("Command: " + m_cubeProgrammerPath + "\n");
    for (const QString &arg : cubeArgs)
        appendLog("  " + arg + "\n");
    appendLog("\n");

    qInfo() << "SWD:" << m_cubeProgrammerPath << cubeArgs;
    m_process->start(m_cubeProgrammerPath, cubeArgs);
}

void SwdRecovery::onProcessOutput()
{
    if (!m_process)
        return;

    QString text = QString::fromUtf8(m_process->readAll());
    appendLog(text);

    for (const QString &part : text.split('\n', Qt::SkipEmptyParts)) {
        QString line = part.trimmed();

        if (m_usingCubeProg) {
            // ── STM32_Programmer_CLI output parsing ──
            if (line.contains("Mass erase command correctly executed") ||
                line.contains("Full chip erase")) {
                m_progress = 20;
                emit progressChanged(m_progress);
                setStatus(m_currentOp + " -- erased, programming...");
            } else if (line.contains("Download in Progress")) {
                m_progress = 30;
                emit progressChanged(m_progress);
                setStatus(m_currentOp + " -- programming...");
            } else if (line.contains("File download complete")) {
                m_progress = 60;
                emit progressChanged(m_progress);
                setStatus(m_currentOp + " -- verifying...");
            } else if (line.contains("Verification") && line.contains("OK")) {
                m_progress = 90;
                emit progressChanged(m_progress);
                setStatus(m_currentOp + " -- verified OK");
            } else if (line.contains("MCU Reset")) {
                m_progress = 95;
                emit progressChanged(m_progress);
            }

            // Parse percentage from download progress (e.g. "  45%")
            static QRegularExpression pctRe("^\\s*(\\d+)%");
            auto pctMatch = pctRe.match(line);
            if (pctMatch.hasMatch()) {
                int pct = pctMatch.captured(1).toInt();
                // Map download 0-100% to our 30-60% range
                m_progress = 30 + (pct * 30) / 100;
                emit progressChanged(m_progress);
            }

            // Parse SWAP_BANK from option bytes display
            if (m_currentOp == "Read Status" && line.contains("SWAP_BANK")) {
                static QRegularExpression sbRe("SWAP_BANK\\s*[:=]\\s*(0x[0-9a-fA-F]+|\\d+)");
                auto sbMatch = sbRe.match(line);
                if (sbMatch.hasMatch()) {
                    bool ok;
                    int val = sbMatch.captured(1).toInt(&ok, 0);
                    if (ok) {
                        QString bankInfo = val
                            ? "SWAP_BANK = 1 : Bank 2 is active (mapped to 0x08000000)"
                            : "SWAP_BANK = 0 : Bank 1 is active (mapped to 0x08000000)";
                        appendLog("\n" + bankInfo + "\n");
                        setStatus(bankInfo);
                    }
                }
            }
        } else {
            // ── OpenOCD output parsing ──
            if (line.contains("Programming Started")) {
                m_progress = 25;
                emit progressChanged(m_progress);
                setStatus(m_currentOp + " -- programming...");
            } else if (line.contains("Programming Finished")) {
                m_progress = 50;
                emit progressChanged(m_progress);
                setStatus(m_currentOp + " -- verifying...");
            } else if (line.contains("Verify Started")) {
                m_progress = 60;
                emit progressChanged(m_progress);
            } else if (line.contains("Verified OK") || line.contains("verified")) {
                m_progress = 90;
                emit progressChanged(m_progress);
                setStatus(m_currentOp + " -- verified OK");
            } else if (line.contains("Resetting Target")) {
                m_progress = 95;
                emit progressChanged(m_progress);
            } else if (line.contains("dumped")) {
                m_progress = 40;
                emit progressChanged(m_progress);
                setStatus(m_currentOp + " -- bank 1 dumped, programming bank 2...");
            }

            // Parse OPTSR_CUR register value for Read Status
            if (m_currentOp == "Read Status" && line.contains("0x40022050")) {
                static QRegularExpression re("0x40022050\\s*:?\\s*([0-9a-fA-F]{8})");
                auto match = re.match(line);
                if (match.hasMatch()) {
                    bool ok;
                    quint32 optr = match.captured(1).toUInt(&ok, 16);
                    if (ok) {
                        bool swapBankSet = (optr & 0x80000000) != 0;
                        QString bankInfo = swapBankSet
                            ? "SWAP_BANK = 1 : Bank 2 is active (mapped to 0x08000000)"
                            : "SWAP_BANK = 0 : Bank 1 is active (mapped to 0x08000000)";
                        appendLog("\n" + bankInfo + "\n");
                        setStatus(bankInfo);
                    }
                }
            }
        }
    }
}

void SwdRecovery::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    // Read any remaining output and release OS handles immediately
    if (m_process) {
        QString remaining = QString::fromUtf8(m_process->readAll());
        if (!remaining.isEmpty())
            appendLog(remaining);
        m_process->close();          // release handles NOW (not deferred)
        m_process->deleteLater();
        m_process = nullptr;
    }

    m_running = false;
    emit runningChanged(false);

    QString toolName = m_usingCubeProg ? "STM32_Programmer_CLI" : "OpenOCD";

    if (exitStatus == QProcess::CrashExit) {
        setStatus(m_currentOp + " -- " + toolName + " crashed.");
        emit operationError(toolName + " crashed. Check probe connection and try again.");
        return;
    }

    if (exitCode == 0) {
        m_progress = 100;
        emit progressChanged(100);
        QString msg = m_currentOp + " -- complete.";
        setStatus(msg);
        appendLog("\n" + msg + "\n");
        emit operationComplete(msg);
    } else {
        QString msg = m_currentOp + " failed (exit code " + QString::number(exitCode) + ").";

        if (m_usingCubeProg) {
            // STM32_Programmer_CLI error hints
            if (m_outputLog.contains("No STM32 target found") ||
                m_outputLog.contains("ST-LINK error") ||
                m_outputLog.contains("No debug probe detected")) {
                msg += "\nST-Link not detected or M1 not connected. Verify:\n"
                       "  1. ST-Link is plugged into USB\n"
                       "  2. SWD wires: SWCLK, SWDIO, GND connected to M1\n"
                       "  3. M1 is powered (USB-C or battery)";
            }
            if (m_outputLog.contains("Error: Erase") ||
                m_outputLog.contains("Mass erase failed")) {
                msg += "\nFlash erase failed. The device may be read-protected.";
            }
        } else {
            // OpenOCD error hints
            if (m_outputLog.contains("unable to find") ||
                m_outputLog.contains("Error connecting DP")) {
                msg += "\nCheck that the probe is connected and the M1 is powered.";
            }
            if (m_outputLog.contains("No CMSIS-DAP") ||
                m_outputLog.contains("no device found")) {
                msg += "\nNo debug probe detected. Verify USB connection.";
            }
            if (m_outputLog.contains("LIBUSB_ERROR")) {
                msg += "\nUSB driver issue. Try reinstalling the probe driver.";
            }
        }

        setStatus(msg);
        appendLog("\n" + msg + "\n");
        emit operationError(msg);
    }
}

// ── Cancel ───────────────────────────────────────────────────────

void SwdRecovery::cancel()
{
    if (m_process) {
        m_process->kill();
        m_process->waitForFinished(2000);
        m_process->deleteLater();
        m_process = nullptr;
    }

    if (m_running) {
        m_running  = false;
        m_progress = 0;
        emit runningChanged(false);
        emit progressChanged(0);
        setStatus("Operation cancelled.");
        appendLog("\nOperation cancelled.\n");
    }
}

// ── Helpers ──────────────────────────────────────────────────────

void SwdRecovery::setStatus(const QString &msg)
{
    if (m_statusMessage != msg) {
        m_statusMessage = msg;
        emit statusMessageChanged(msg);
    }
}

void SwdRecovery::appendLog(const QString &text)
{
    m_outputLog += text;
    emit outputLogChanged();
}

void SwdRecovery::clearLog()
{
    m_outputLog.clear();
    emit outputLogChanged();
}
