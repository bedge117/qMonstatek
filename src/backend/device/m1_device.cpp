/*
 * m1_device.cpp — Main M1 device facade implementation
 */

#include "m1_device.h"
#include "protocol/rpc_protocol.h"
#include "protocol/crc16.h"

#include <QDebug>
#include <QCoreApplication>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonObject>
#include <QCryptographicHash>
#include <QUrl>
#include <QSettings>
#include <cstring>

// Max consecutive WiFi TCP auto-reconnect attempts before giving up (§7).
static constexpr int WIFI_RECONNECT_MAX = 8;

M1Device::M1Device(QObject *parent)
    : QObject(parent)
{
    // Default transport is serial (USB)
    setTransport(&m_serialTransport);

    // Default log-to-file path (next to the exe — the previous always-on location).
    // Logging is OFF by default now; the user opts in via the Debug Terminal toggle.
    m_logFilePath = QCoreApplication::applicationDirPath() + "/m1_uart.log";

    // Restore the log-to-file preference (path + on/off) from a previous session.
    {
        QSettings s;
        m_logFilePath = s.value(QStringLiteral("logging/filePath"), m_logFilePath).toString();
        if (s.value(QStringLiteral("logging/enabled"), false).toBool())
            setLogToFile(true);   // reopens the file so capture resumes at launch
        m_deviceLogVerbose = s.value(QStringLiteral("logging/deviceVerbose"), false).toBool();
    }

    // Wire codec → frame handler
    connect(&m_codec, &rpc::FrameCodec::frameReady,
            this, &M1Device::onFrameReceived);

    // Wire device discovery
    connect(&m_discovery, &DeviceDiscovery::deviceFound,
            this, &M1Device::onDeviceFound);
    connect(&m_discovery, &DeviceDiscovery::deviceLost,
            this, &M1Device::onDeviceLost);

    // Periodic ping for connection health (COMMS_REBUILD_SPEC §3):
    //   ping every 3s; declare the WiFi link dead ONLY when there have been no
    //   inbound bytes for 20s OR 6 consecutive missed PONGs.
    connect(&m_pingTimer, &QTimer::timeout, this, [this]() {
        if (!isConnected())
            return;

        const bool wifi = m_transport && m_transport->transportName() == "WiFi";
        if (wifi) {
            m_missedPongs++;
            const qint64 idle = QDateTime::currentMSecsSinceEpoch() - m_lastInboundMs;
            if (m_missedPongs >= 6 || idle > 20000) {
                qWarning() << "WiFi link dead (missedPongs=" << m_missedPongs
                           << " idleMs=" << idle << ") — disconnecting";
                if (m_screenStreaming)
                    stopScreenStream();
                // Clean TCP close sends FIN → ESP32 sends CLOSED → M1 clears s_route_tcp
                m_transport->close();
                return;
            }
        }
        // CRC-dialect discovery: until a validated reply latches the device's
        // dialect, alternate TX each ping so we find whether it speaks the
        // correct or the legacy (old-firmware) CRC. No-ops once latched.
        if (!rpc::crcDialectLocked()) {
            rpc::setTxCrcDialect(rpc::txCrcDialect() == rpc::CrcDialect::Correct
                                     ? rpc::CrcDialect::Legacy
                                     : rpc::CrcDialect::Correct);
        }
        m_lastPingTime = QDateTime::currentMSecsSinceEpoch();
        sendCommand(rpc::CMD_PING);
    });

    // WiFi TCP auto-reconnect/backoff (COMMS_REBUILD_SPEC §7).
    m_wifiReconnectTimer.setSingleShot(true);
    connect(&m_wifiReconnectTimer, &QTimer::timeout,
            this, &M1Device::tryWifiReconnect);

    // FW update timeout (15s for START which includes bank erase, 10s for data/finish)
    m_fwUpdateTimeout.setSingleShot(true);
    connect(&m_fwUpdateTimeout, &QTimer::timeout, this, [this]() {
        if (m_fwUpdateState != FwUpdateState::Idle) {
            QString state;
            switch (m_fwUpdateState) {
            case FwUpdateState::WaitingStartAck: state = "erase/start"; break;
            case FwUpdateState::SendingData:     state = "data transfer"; break;
            case FwUpdateState::WaitingFinishAck: state = "finish"; break;
            default: state = "unknown"; break;
            }
            qWarning() << "FW update timeout during" << state;
            m_fwUpdateState = FwUpdateState::Idle;
            m_fwUpdateData.clear();

            // If we never got valid device info, the firmware likely doesn't
            // support RPC (e.g. stock Monstatek firmware).
            if (m_deviceInfo.fwMajor == 0 && m_deviceInfo.fwMinor == 0 &&
                m_deviceInfo.c3Revision == 0) {
                emit fwUpdateError(
                    "The device firmware does not support over-the-air updates.\n\n"
                    "Use the DFU Flash page to install compatible firmware via USB DFU mode.");
            } else {
                emit fwUpdateError(
                    "Timeout waiting for device response during " + state +
                    ".\nRestart the device and try again.");
            }
        }
    });

    // ESP32 update timeout
    m_espUpdateTimeout.setSingleShot(true);
    connect(&m_espUpdateTimeout, &QTimer::timeout, this, [this]() {
        if (m_espUpdateState != EspUpdateState::Idle) {
            QString state;
            switch (m_espUpdateState) {
            case EspUpdateState::WaitingStartAck: state = "start"; break;
            case EspUpdateState::SendingData:     state = "data transfer"; break;
            case EspUpdateState::WaitingFinishAck: state = "finish"; break;
            default: state = "unknown"; break;
            }
            qWarning() << "ESP32 update timeout during" << state;
            // Tell M1 to clean up (restore GPIO, reset ESP32, etc.)
            // even though the flash failed — prevents M1 getting stuck.
            sendCommand(rpc::CMD_ESP_UPDATE_FINISH);
            m_espUpdateState = EspUpdateState::Idle;
            m_espUpdateData.clear();
            m_espUpdateStaleNack = true;  // M1 may still send a late NACK/ACK — absorb it
            m_pingTimer.start(3000);

            emit espUpdateError("Timeout waiting for device response during " + state +
                                ".\nClose qMonstatek, reboot the M1, then reopen qMonstatek and try again.");
        }
    });

    // File upload timeout
    m_fileUploadTimeout.setSingleShot(true);
    connect(&m_fileUploadTimeout, &QTimer::timeout, this, [this]() {
        if (m_fileUploadState != FileUploadState::Idle) {
            qWarning() << "File upload timeout";
            m_fileUploadState = FileUploadState::Idle;
            m_fileUploadData.clear();
            emit fileOperationError("Upload timed out waiting for device response");
        }
    });

    // Start device scanning
    m_discovery.startScanning();
}

/* ──────────── Connection ──────────── */

bool M1Device::connectToDevice(const QString &portName)
{
    // Ensure serial transport is active
    if (m_transport != &m_serialTransport)
        setTransport(&m_serialTransport);

    if (!m_transport->open(portName)) {
        return false;
    }

    startSession();
    return true;
}

bool M1Device::connectToDeviceWifi(const QString &hostPort)
{
    // Create the threaded WiFi transport (or reuse existing)
    if (!m_wifiTransport) {
        m_wifiTransport = new WifiTransport(this);
    }
    setTransport(m_wifiTransport);

    // Wire the WiFi-specific channels (control frames, decoded screen frames,
    // inbound-activity liveness ticks). setTransport() has just cleared any
    // previous connections from this transport to us, so UniqueConnection keeps
    // things idempotent across reconnects.
    connect(m_wifiTransport, &WifiTransport::controlFrame,
            this, &M1Device::onFrameReceived, Qt::UniqueConnection);
    connect(m_wifiTransport, &WifiTransport::screenFrame,
            this, &M1Device::onWifiScreenFrame, Qt::UniqueConnection);
    connect(m_wifiTransport, &WifiTransport::inboundActivity,
            this, &M1Device::onInboundActivity, Qt::UniqueConnection);

    m_wifiTarget = hostPort;
    m_userDisconnecting = false;
    m_pendingSessionStart = true;

    // Non-blocking open: the connection result arrives via onTransportConnected().
    if (!m_transport->open(hostPort)) {
        setTransport(&m_serialTransport);
        m_pendingSessionStart = false;
        return false;
    }
    // startSession() runs once the socket reports connected (async).
    return true;
}

void M1Device::disconnect()
{
    m_pingTimer.stop();
    m_wifiReconnectTimer.stop();
    m_wifiWasConnected = false;
    m_wifiReconnectAttempts = 0;
    if (m_screenStreaming) {
        stopScreenStream();
    }
    m_userDisconnecting = true;
    m_transport->close();
    m_codec.reset();
}

bool M1Device::isConnected() const
{
    return m_transport && m_transport->isConnected();
}

QString M1Device::portName() const
{
    return m_transport ? m_transport->targetName() : QString();
}

QString M1Device::connectionType() const
{
    return m_transport ? m_transport->transportName() : QStringLiteral("None");
}

void M1Device::setLogToFile(bool enabled)
{
    if (enabled == m_logToFile)
        return;
    m_logToFile = enabled;

    if (enabled) {
        m_logFile.setFileName(m_logFilePath);
        if (m_logFile.open(QIODevice::WriteOnly | QIODevice::Append
                           | QIODevice::Unbuffered)) {
            const QByteArray hdr =
                QStringLiteral("\n===== session %1 =====\n")
                    .arg(QDateTime::currentDateTime().toString(Qt::ISODate))
                    .toUtf8();
            m_logFile.write(hdr);
            m_logFile.flush();
        } else {
            qWarning() << "Log-to-file: cannot open" << m_logFilePath
                       << ":" << m_logFile.errorString();
            m_logToFile = false;   // couldn't open — stay off
            emit errorOccurred(QStringLiteral("Cannot open log file: ")
                               + m_logFile.errorString());
        }
    } else if (m_logFile.isOpen()) {
        m_logFile.flush();
        m_logFile.close();
    }

    QSettings().setValue(QStringLiteral("logging/enabled"), m_logToFile);
    emit logToFileChanged(m_logToFile);
}

void M1Device::setLogFilePath(const QString &path)
{
    // Accept a plain path or a file:// URL (from a QML FileDialog).
    QString local = path.startsWith(QStringLiteral("file:"))
                        ? QUrl(path).toLocalFile()
                        : path;
    if (local.isEmpty() || local == m_logFilePath)
        return;
    m_logFilePath = local;
    QSettings().setValue(QStringLiteral("logging/filePath"), m_logFilePath);

    // If we're actively logging, reopen at the new location.
    if (m_logToFile) {
        setLogToFile(false);
        setLogToFile(true);
    }
    emit logFilePathChanged(m_logFilePath);
}

void M1Device::setDeviceLogVerbose(bool on)
{
    m_deviceLogVerbose = on;
    QSettings().setValue(QStringLiteral("logging/deviceVerbose"), on);

    // S_M1_LogDebugLevel_t: WARN = 2 (quiet default), INFO = 3 (verbose capture).
    if (isConnected()) {
        QByteArray p(1, static_cast<char>(on ? 3 : 2));
        sendCommand(rpc::CMD_SET_LOG_LEVEL, p);
    }
    emit deviceLogVerboseChanged(on);
}

void M1Device::setTransport(AbstractTransport *transport)
{
    // Disconnect old transport signals
    if (m_transport) {
        QObject::disconnect(m_transport, nullptr, this, nullptr);
    }

    m_transport = transport;

    // Wire new transport signals
    connect(m_transport, &AbstractTransport::dataReceived,
            this, &M1Device::onTransportData);
    connect(m_transport, &AbstractTransport::connectionChanged,
            this, &M1Device::onTransportConnected);
    connect(m_transport, &AbstractTransport::errorOccurred,
            this, &M1Device::errorOccurred);
}

void M1Device::startSession()
{
    m_codec.reset();
    m_missedPongs = 0;
    m_lastInboundMs = QDateTime::currentMSecsSinceEpoch();
    // Fresh CRC-dialect handshake: assume correct until a validated reply proves
    // otherwise. The ping loop probes the legacy dialect if this device is old.
    rpc::resetCrcDialect();
    m_dialectResolved = false;
    sendCommand(rpc::CMD_PING);
    // The device boots at WARN; if the user wants verbose UART, re-assert it now
    // so a reconnect/reboot doesn't silently revert the toggle.
    if (m_deviceLogVerbose) {
        QByteArray p(1, static_cast<char>(3));   // INFO
        sendCommand(rpc::CMD_SET_LOG_LEVEL, p);
    }
    QTimer::singleShot(100, this, &M1Device::requestDeviceInfo);
    m_pingTimer.start(3000);
}

/* ──────────── Device Info ──────────── */

void M1Device::requestDeviceInfo()
{
    sendCommand(rpc::CMD_GET_DEVICE_INFO);
}

/* ──────────── Screen Mirror ──────────── */

void M1Device::startScreenStream(int fps)
{
    if (fps < 1) fps = 1;
    if (fps > 15) fps = 15;

    // Screen now travels over a dedicated UDP channel (COMMS_REBUILD_SPEC §2),
    // decoupled from the control link — the old WiFi FPS cap is no longer needed.
    QByteArray payload;
    payload.append(static_cast<char>(fps));

    // WiFi: extend SCREEN_START to [fps:u8][udp_port:u16 LE] and arm the UDP
    // receiver (resets the epoch/frame_seq latch for a fresh stream).
    if (m_wifiTransport && m_transport == m_wifiTransport) {
        const quint16 port = m_wifiTransport->udpScreenPort();
        payload.append(static_cast<char>(port & 0xFF));
        payload.append(static_cast<char>((port >> 8) & 0xFF));
        m_wifiTransport->armScreen();
    }

    sendCommand(rpc::CMD_SCREEN_START, payload);
    m_screenStreaming = true;
    m_screenWanted    = true;    // remember intent so a WiFi reconnect re-arms the UDP stream
    m_screenFps       = fps;
    emit screenStreamingChanged(true);
}

void M1Device::stopScreenStream()
{
    if (m_wifiTransport && m_transport == m_wifiTransport)
        m_wifiTransport->disarmScreen();
    sendCommand(rpc::CMD_SCREEN_STOP);
    m_screenStreaming = false;
    m_screenWanted    = false;   // user stopped it — don't re-arm on future reconnects
    emit screenStreamingChanged(false);
}

void M1Device::captureScreen()
{
    sendCommand(rpc::CMD_SCREEN_CAPTURE);
}

bool M1Device::saveScreenshot(const QString &filePath)
{
    if (m_lastScreenImage.isNull())
        return false;
    return m_lastScreenImage.save(filePath, "PNG");
}

/* ──────────── Remote Control ──────────── */

void M1Device::buttonPress(int buttonId)
{
    QByteArray payload;
    payload.append(static_cast<char>(buttonId & 0xFF));
    sendCommand(rpc::CMD_BUTTON_PRESS, payload);
}

void M1Device::buttonRelease(int buttonId)
{
    QByteArray payload;
    payload.append(static_cast<char>(buttonId & 0xFF));
    sendCommand(rpc::CMD_BUTTON_RELEASE, payload);
}

void M1Device::buttonClick(int buttonId)
{
    qDebug() << "buttonClick(" << buttonId << ")";
    QByteArray payload;
    payload.append(static_cast<char>(buttonId & 0xFF));
    sendCommand(rpc::CMD_BUTTON_CLICK, payload);
}

/* ──────────── Debug / CLI Terminal ──────────── */

void M1Device::sendCliCommand(const QString &command)
{
    qDebug() << "CLI exec:" << command;
    QByteArray payload = command.toUtf8();
    payload.append('\0');
    sendCommand(rpc::CMD_CLI_EXEC, payload);
}

void M1Device::sendEspUartSnoop()
{
    qDebug() << "ESP UART snoop: requesting boot capture";
    sendCommand(rpc::CMD_ESP_UART_SNOOP);
}

/* ──────────── File Operations ──────────── */

void M1Device::requestFileList(const QString &path)
{
    QByteArray payload = path.toUtf8();
    payload.append('\0');  // null-terminate
    sendCommand(rpc::CMD_FILE_LIST, payload);
}

void M1Device::downloadFile(const QString &remotePath, const QString &localPath)
{
    m_fileDownloadBuf.clear();
    m_fileDownloadDest = localPath;

    QByteArray payload = remotePath.toUtf8();
    payload.append('\0');
    sendCommand(rpc::CMD_FILE_READ, payload);
}

void M1Device::uploadFile(const QString &localPath, const QString &remotePath)
{
    if (m_fileUploadState != FileUploadState::Idle) {
        emit fileOperationError("Upload already in progress");
        return;
    }

    QFile file(localPath);
    if (!file.open(QIODevice::ReadOnly)) {
        emit fileOperationError("Cannot open local file: " + localPath);
        return;
    }

    m_fileUploadData = file.readAll();
    file.close();

    m_fileUploadSize = static_cast<uint32_t>(m_fileUploadData.size());
    m_fileUploadOffset = 0;

    if (m_fileUploadSize == 0) {
        emit fileOperationError("File is empty");
        m_fileUploadData.clear();
        return;
    }

    // Send WRITE_START: size(4 LE) + path
    QByteArray payload;
    payload.append(static_cast<char>(m_fileUploadSize & 0xFF));
    payload.append(static_cast<char>((m_fileUploadSize >> 8) & 0xFF));
    payload.append(static_cast<char>((m_fileUploadSize >> 16) & 0xFF));
    payload.append(static_cast<char>((m_fileUploadSize >> 24) & 0xFF));
    payload.append(remotePath.toUtf8());
    payload.append('\0');

    m_fileUploadState = FileUploadState::WaitingStartAck;
    m_fileUploadTimeout.start(10000);
    sendCommand(rpc::CMD_FILE_WRITE_START, payload);

    qDebug() << "File upload: starting, size =" << m_fileUploadSize
             << "bytes, remote =" << remotePath;
}

void M1Device::fileUploadSendNextChunk()
{
    if (m_fileUploadOffset >= m_fileUploadSize) {
        // All data sent — send FINISH
        m_fileUploadState = FileUploadState::WaitingFinishAck;
        m_fileUploadTimeout.start(10000);
        sendCommand(rpc::CMD_FILE_WRITE_FINISH);
        return;
    }

    constexpr int CHUNK_SIZE = 512;
    int chunkLen = qMin(CHUNK_SIZE,
                        static_cast<int>(m_fileUploadSize - m_fileUploadOffset));

    QByteArray chunkPayload;
    chunkPayload.append(static_cast<char>(m_fileUploadOffset & 0xFF));
    chunkPayload.append(static_cast<char>((m_fileUploadOffset >> 8) & 0xFF));
    chunkPayload.append(static_cast<char>((m_fileUploadOffset >> 16) & 0xFF));
    chunkPayload.append(static_cast<char>((m_fileUploadOffset >> 24) & 0xFF));
    chunkPayload.append(m_fileUploadData.mid(
        static_cast<int>(m_fileUploadOffset), chunkLen));

    sendCommand(rpc::CMD_FILE_WRITE_DATA, chunkPayload);

    m_fileUploadOffset += chunkLen;
    int pct = static_cast<int>(m_fileUploadOffset * 100 / m_fileUploadSize);
    emit fileUploadProgress(pct);
}

void M1Device::deleteFile(const QString &remotePath)
{
    m_pendingFileCmd = rpc::CMD_FILE_DELETE;
    QByteArray payload = remotePath.toUtf8();
    payload.append('\0');
    sendCommand(rpc::CMD_FILE_DELETE, payload);
}

void M1Device::deleteTree(const QString &remotePath)
{
    m_pendingFileCmd = rpc::CMD_FILE_DELETE_TREE;
    QByteArray payload = remotePath.toUtf8();
    payload.append('\0');
    sendCommand(rpc::CMD_FILE_DELETE_TREE, payload);
}

void M1Device::renameFile(const QString &oldPath, const QString &newPath)
{
    m_pendingFileCmd = rpc::CMD_FILE_RENAME;
    QByteArray payload = oldPath.toUtf8();
    payload.append('\0');                 // separator between old and new path
    payload.append(newPath.toUtf8());
    sendCommand(rpc::CMD_FILE_RENAME, payload);
}

void M1Device::makeDirectory(const QString &remotePath)
{
    m_pendingFileCmd = rpc::CMD_FILE_MKDIR;
    QByteArray payload = remotePath.toUtf8();
    payload.append('\0');
    sendCommand(rpc::CMD_FILE_MKDIR, payload);
}

/* ──────────── Multi-File / Folder Upload ──────────── */

void M1Device::uploadFiles(const QVariantList &fileUrls, const QString &remotePath)
{
    if (m_uploadQueueIndex >= 0 || m_fileUploadState != FileUploadState::Idle) {
        emit fileOperationError("Upload already in progress");
        return;
    }

    m_uploadQueue.clear();
    m_mkdirQueue.clear();
    m_mkdirQueueIndex = -1;

    for (const QVariant &v : fileUrls) {
        QString localPath = QUrl(v.toString()).toLocalFile();
        if (localPath.isEmpty()) localPath = v.toString();
        QString fileName = QFileInfo(localPath).fileName();
        QString rp = remotePath;
        if (!rp.endsWith("/")) rp += "/";
        m_uploadQueue.append({localPath, rp + fileName});
    }

    if (m_uploadQueue.isEmpty()) {
        emit fileOperationError("No files selected");
        return;
    }

    qDebug() << "Multi-upload: queued" << m_uploadQueue.size() << "files";
    startUploadQueue();
}

void M1Device::uploadFolder(const QString &localFolderUrl, const QString &remotePath)
{
    if (m_uploadQueueIndex >= 0 || m_fileUploadState != FileUploadState::Idle) {
        emit fileOperationError("Upload already in progress");
        return;
    }

    QString localFolder = QUrl(localFolderUrl).toLocalFile();
    if (localFolder.isEmpty()) localFolder = localFolderUrl;

    QDir baseDir(localFolder);
    if (!baseDir.exists()) {
        emit fileOperationError("Local folder not found: " + localFolder);
        return;
    }

    QString baseName = baseDir.dirName();
    QString remoteBase = remotePath;
    if (!remoteBase.endsWith("/")) remoteBase += "/";
    remoteBase += baseName;

    QStringList dirs;
    QList<UploadQueueItem> files;

    dirs.append(remoteBase);

    QDirIterator it(localFolder, QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        QString relPath = baseDir.relativeFilePath(it.filePath());
        QString remoteFull = remoteBase + "/" + relPath.replace("\\", "/");

        if (it.fileInfo().isDir()) {
            dirs.append(remoteFull);
        } else {
            files.append({it.filePath(), remoteFull});
        }
    }

    // Sort dirs by path length so parents are created before children
    std::sort(dirs.begin(), dirs.end(), [](const QString &a, const QString &b) {
        return a.length() < b.length();
    });

    m_uploadQueue = files;
    m_mkdirQueue = dirs;

    if (dirs.isEmpty() && files.isEmpty()) {
        emit fileOperationError("Folder is empty");
        return;
    }

    qDebug() << "Folder upload:" << dirs.size() << "dirs," << files.size() << "files";

    // Start creating directories first
    if (!dirs.isEmpty()) {
        m_mkdirQueueIndex = 0;
        emit multiUploadProgress(0, files.size(), "Creating directories...");
        m_pendingFileCmd = rpc::CMD_FILE_MKDIR;
        QByteArray payload = dirs[0].toUtf8();
        payload.append('\0');
        sendCommand(rpc::CMD_FILE_MKDIR, payload);
    } else {
        startUploadQueue();
    }
}

void M1Device::startUploadQueue()
{
    if (m_uploadQueue.isEmpty()) {
        emit multiUploadComplete(0);
        return;
    }
    m_uploadQueueIndex = 0;
    auto &item = m_uploadQueue[0];
    emit multiUploadProgress(1, m_uploadQueue.size(), QFileInfo(item.localPath).fileName());
    uploadFile(item.localPath, item.remotePath);
}

void M1Device::advanceUploadQueue()
{
    m_uploadQueueIndex++;
    if (m_uploadQueueIndex >= m_uploadQueue.size()) {
        int total = m_uploadQueue.size();
        m_uploadQueue.clear();
        m_uploadQueueIndex = -1;
        emit multiUploadComplete(total);
        return;
    }
    auto &item = m_uploadQueue[m_uploadQueueIndex];
    emit multiUploadProgress(m_uploadQueueIndex + 1, m_uploadQueue.size(),
                             QFileInfo(item.localPath).fileName());
    uploadFile(item.localPath, item.remotePath);
}

void M1Device::advanceMkdirQueue()
{
    m_mkdirQueueIndex++;
    if (m_mkdirQueueIndex >= m_mkdirQueue.size()) {
        m_mkdirQueue.clear();
        m_mkdirQueueIndex = -1;
        // All dirs created — start file uploads
        if (!m_uploadQueue.isEmpty()) {
            startUploadQueue();
        } else {
            emit multiUploadComplete(0);
        }
        return;
    }
    m_pendingFileCmd = rpc::CMD_FILE_MKDIR;
    QByteArray payload = m_mkdirQueue[m_mkdirQueueIndex].toUtf8();
    payload.append('\0');
    sendCommand(rpc::CMD_FILE_MKDIR, payload);
}

/* ──────────── SD Card Mount/Unmount ──────────── */

void M1Device::mountSdCard()
{
    m_pendingFileCmd = rpc::CMD_SD_MOUNT;
    sendCommand(rpc::CMD_SD_MOUNT);
}

void M1Device::unmountSdCard()
{
    m_pendingFileCmd = rpc::CMD_SD_UNMOUNT;
    sendCommand(rpc::CMD_SD_UNMOUNT);
}

/* ──────────── Firmware Update ──────────── */

void M1Device::requestFwInfo()
{
    sendCommand(rpc::CMD_FW_INFO);
}

void M1Device::startFwUpdate(const QString &binFilePath)
{
    if (m_fwUpdateState != FwUpdateState::Idle) {
        emit fwUpdateError("Firmware update already in progress");
        return;
    }

    QFile file(binFilePath);
    if (!file.open(QIODevice::ReadOnly)) {
        emit fwUpdateError("Cannot open firmware file: " + binFilePath);
        return;
    }

    m_fwUpdateData = file.readAll();
    file.close();

    m_fwUpdateSize = static_cast<uint32_t>(m_fwUpdateData.size());

    if (m_fwUpdateSize == 0 || m_fwUpdateSize % 4 != 0) {
        emit fwUpdateError("Invalid firmware file: size must be non-zero and 4-byte aligned");
        return;
    }

    if (m_fwUpdateSize > 0x100000) {  // 1MB max
        emit fwUpdateError("Firmware file too large (max 1MB)");
        return;
    }

    // Send FW_UPDATE_START: size(4) + crc32(4)
    // CRC-32 is 0 — firmware skips CRC check when 0
    uint32_t crc32 = 0;
    QByteArray payload;
    payload.append(reinterpret_cast<const char*>(&m_fwUpdateSize), 4);
    payload.append(reinterpret_cast<const char*>(&crc32), 4);

    m_fwUpdateOffset = 0;
    m_fwUpdateState = FwUpdateState::WaitingStartAck;
    m_fwUpdateTimeout.start(15000);  // 15s for bank erase

    qDebug() << "FW update: starting, size =" << m_fwUpdateSize << "bytes";
    sendCommand(rpc::CMD_FW_UPDATE_START, payload);
    emit fwUpdateProgress(0);
}

void M1Device::fwUpdateSendNextChunk()
{
    constexpr int CHUNK_SIZE = 1024;

    if (m_fwUpdateOffset >= m_fwUpdateSize) {
        // All data sent, send FINISH
        qDebug() << "FW update: all chunks sent, sending FINISH";
        m_fwUpdateState = FwUpdateState::WaitingFinishAck;
        m_fwUpdateTimeout.start(15000);  // 15s for CRC verification
        sendCommand(rpc::CMD_FW_UPDATE_FINISH);
        return;
    }

    int chunkLen = qMin(CHUNK_SIZE,
                        static_cast<int>(m_fwUpdateSize - m_fwUpdateOffset));

    QByteArray chunkPayload;
    chunkPayload.append(reinterpret_cast<const char*>(&m_fwUpdateOffset), 4);
    chunkPayload.append(m_fwUpdateData.mid(
        static_cast<int>(m_fwUpdateOffset), chunkLen));

    sendCommand(rpc::CMD_FW_UPDATE_DATA, chunkPayload);

    m_fwUpdateOffset += chunkLen;
    int pct = static_cast<int>(m_fwUpdateOffset * 100 / m_fwUpdateSize);
    emit fwUpdateProgress(pct);
}

void M1Device::swapBanks()
{
    m_bankSwapPending = true;
    sendCommand(rpc::CMD_FW_BANK_SWAP);
}

void M1Device::eraseInactiveBank()
{
    m_bankErasePending = true;
    m_pingTimer.stop();  // Erase takes ~5s; suspend pings so we don't timeout
    sendCommand(rpc::CMD_FW_BANK_ERASE);
}

void M1Device::enterDfu()
{
    sendCommand(rpc::CMD_FW_DFU_ENTER);
}

void M1Device::reboot()
{
    sendCommand(rpc::CMD_REBOOT);
    // Proactively close so auto-reconnect does a clean full reinit.
    // Without this, a fast reboot may not trigger a serial ResourceError,
    // leaving stale state (no fresh deviceInfo, locked update paths).
    QTimer::singleShot(500, this, [this]() {
        if (isConnected()) {
            qInfo() << "Reboot: closing connection for clean reconnect";
            m_transport->close();
        }
    });
}

void M1Device::shutdown()
{
    sendCommand(rpc::CMD_POWER_OFF);
}

/* ──────────── ESP32 Update ──────────── */

void M1Device::requestEspInfo()
{
    sendCommand(rpc::CMD_ESP_INFO);
}

void M1Device::initEsp32()
{
    sendCliCommand("mtest 70 0");
    // Refresh device info after delay to pick up esp32Ready status
    QTimer::singleShot(2000, this, &M1Device::requestDeviceInfo);
}

void M1Device::rebootEsp32()
{
    // ESP-only reboot (mtest 78 -> m1_esp32_reboot on the M1): cold-resets the
    // ESP without rebooting the M1. Refresh device info after it boots + relinks.
    sendCliCommand("mtest 78 0");
    QTimer::singleShot(2500, this, &M1Device::requestDeviceInfo);
}

void M1Device::startEspUpdate(const QString &binFilePath, uint32_t flashAddr)
{
    if (m_espUpdateState != EspUpdateState::Idle) {
        emit espUpdateError("ESP32 update already in progress");
        return;
    }

    QFile file(binFilePath);
    if (!file.open(QIODevice::ReadOnly)) {
        emit espUpdateError("Cannot open ESP32 firmware file: " + binFilePath);
        return;
    }

    m_espUpdateData = file.readAll();
    file.close();

    m_espUpdateSize = static_cast<uint32_t>(m_espUpdateData.size());
    m_espUpdateFlashAddr = flashAddr;

    if (m_espUpdateSize == 0) {
        emit espUpdateError("Firmware file is empty");
        m_espUpdateData.clear();
        return;
    }

    // Size validation based on flash type
    constexpr uint32_t APP_MAX_SIZE     = 1600 * 1024;  // 1600 KB
    constexpr uint32_t FACTORY_MIN_SIZE = 4000 * 1024;  // 4000 KB

    if (flashAddr == 0x60000) {
        // App-only: must be under 1600 KB (app partition starts at 0x60000)
        if (m_espUpdateSize > APP_MAX_SIZE) {
            emit espUpdateError(
                QString("File too large for app-only flash (%1 KB). "
                        "App-only images must be under 1600 KB. "
                        "This looks like a factory image — select Factory Image instead.")
                    .arg(m_espUpdateSize / 1024));
            m_espUpdateData.clear();
            return;
        }
    } else if (flashAddr == 0x00000) {
        // Factory: must be over 4000 KB
        if (m_espUpdateSize < FACTORY_MIN_SIZE) {
            emit espUpdateError(
                QString("File too small for factory flash (%1 KB). "
                        "Factory images are typically over 4000 KB. "
                        "This looks like an app-only image — select App-Only instead.")
                    .arg(m_espUpdateSize / 1024));
            m_espUpdateData.clear();
            return;
        }
    }

    // Send ESP_UPDATE_START: size(4) + addr(4)
    QByteArray payload;
    payload.append(reinterpret_cast<const char*>(&m_espUpdateSize), 4);
    payload.append(reinterpret_cast<const char*>(&m_espUpdateFlashAddr), 4);

    m_espUpdateOffset = 0;
    m_espUpdateState = EspUpdateState::WaitingStartAck;
    m_pingTimer.stop();  // user-requested: suspend pings during ESP flash
    m_espUpdateTimeout.start(120000);  // 120s — 4MB factory erase can take 60-80s on ESP32

    // Log file MD5 for correlation with M1's local hash — verifies USB transfer integrity
    QByteArray fileMd5 = QCryptographicHash::hash(m_espUpdateData, QCryptographicHash::Md5).toHex();
    qDebug() << "ESP32 update: starting, size =" << m_espUpdateSize
             << "bytes, addr = 0x" << Qt::hex << flashAddr
             << "file MD5 =" << fileMd5;
    sendCommand(rpc::CMD_ESP_UPDATE_START, payload);
    emit espUpdateProgress(0);
    emit espUpdateStatus("Connecting to ESP32 and erasing flash... (this takes 60-80s for 4MB)");
}

void M1Device::espUpdateSendNextChunk()
{
    constexpr int CHUNK_SIZE = 1024;

    if (m_espUpdateOffset >= m_espUpdateSize) {
        qDebug() << "ESP32 update: all chunks sent, sending FINISH";
        m_espUpdateState = EspUpdateState::WaitingFinishAck;
        // MD5 verify reads entire flash region — scale timeout with image size
        // ~30s/MB for MD5 computation + 10s buffer
        int finishTimeout = static_cast<int>(m_espUpdateSize / (1024.0 * 1024.0) * 30000) + 10000;
        m_espUpdateTimeout.start(finishTimeout);
        emit espUpdateStatus("Verifying flash (MD5)...");
        sendCommand(rpc::CMD_ESP_UPDATE_FINISH);
        return;
    }

    int chunkLen = qMin(CHUNK_SIZE,
                        static_cast<int>(m_espUpdateSize - m_espUpdateOffset));

    QByteArray chunkPayload;
    chunkPayload.append(reinterpret_cast<const char*>(&m_espUpdateOffset), 4);
    chunkPayload.append(m_espUpdateData.mid(
        static_cast<int>(m_espUpdateOffset), chunkLen));

    sendCommand(rpc::CMD_ESP_UPDATE_DATA, chunkPayload);

    m_espUpdateOffset += chunkLen;
    int pct = static_cast<int>(m_espUpdateOffset * 100 / m_espUpdateSize);
    emit espUpdateProgress(pct);
}

/* ──────────── Internal ──────────── */

void M1Device::sendCommand(uint8_t cmd, const QByteArray &payload)
{
    uint8_t seq = m_codec.nextSeq();
    QByteArray frame = rpc::FrameCodec::buildFrame(cmd, seq, payload);
    m_transport->send(frame);
}

void M1Device::onTransportData(const QByteArray &data)
{
    m_codec.feed(data);
}

void M1Device::onFrameReceived(rpc::Frame frame)
{
    // Any complete inbound frame counts as link liveness (§3).
    m_lastInboundMs = QDateTime::currentMSecsSinceEpoch();

    // First validated frame latches the device's CRC dialect (see crc16.*).
    // Surface legacy/compat mode once, and re-request device info in case the
    // initial request went out under the wrong dialect and was dropped.
    if (!m_dialectResolved && rpc::crcDialectLocked()) {
        m_dialectResolved = true;
        m_legacyCompatMode = (rpc::txCrcDialect() == rpc::CrcDialect::Legacy);
        if (m_legacyCompatMode) {
            qWarning() << "CRC compat: device uses the LEGACY (pre-fix) CRC — old "
                          "firmware. Compatibility mode enabled; update recommended.";
            emit legacyFirmwareDetected();
        }
        emit legacyCompatModeChanged(m_legacyCompatMode);
        requestDeviceInfo();
    }

    switch (frame.cmd) {
    case rpc::CMD_PONG: {
        m_missedPongs = 0;
        qint64 now = QDateTime::currentMSecsSinceEpoch();
        int latency = static_cast<int>(now - m_lastPingTime);
        emit pongReceived(latency);
        break;
    }
    case rpc::CMD_DEVICE_INFO_RESP:
        handleDeviceInfoResp(frame);
        break;
    case rpc::CMD_SCREEN_FRAME:
        handleScreenFrame(frame);
        break;
    case rpc::CMD_FW_INFO_RESP:
        handleFwInfoResp(frame);
        break;
    case rpc::CMD_FILE_LIST_RESP:
        handleFileListResp(frame);
        break;
    case rpc::CMD_FILE_READ_DATA:
        handleFileReadData(frame);
        break;
    case rpc::CMD_ACK:
        handleAck(frame);
        break;
    case rpc::CMD_NACK:
        handleNack(frame);
        break;
    case rpc::CMD_ESP_INFO_RESP:
        if (frame.payload.size() > 0) {
            QString ver = QString::fromUtf8(frame.payload);
            emit espInfoReceived(ver);
        }
        break;
    case rpc::CMD_CLI_RESP:
        if (frame.payload.size() > 0) {
            QString resp = QString::fromUtf8(frame.payload.constData(),
                                             frame.payload.size());
            emit cliResponseReceived(resp);
        }
        break;
    case rpc::CMD_ESP_UART_SNOOP_RESP: {
        int sz = frame.payload.size();
        qDebug() << "ESP UART snoop: received" << sz << "bytes";

        // Build both text and hex dump views
        QString text;
        // Printable text (replace non-printable with '.')
        QString printable;
        for (int i = 0; i < sz; i++) {
            char c = frame.payload.at(i);
            if (c == '\n' || c == '\r')
                printable += c;
            else if (c >= 0x20 && c < 0x7F)
                printable += c;
            else
                printable += '.';
        }

        // Full hex dump
        QString hexDump;
        for (int i = 0; i < sz; i++) {
            if (i > 0 && i % 16 == 0)
                hexDump += '\n';
            else if (i > 0)
                hexDump += ' ';
            hexDump += QString("%1").arg(
                static_cast<uint8_t>(frame.payload.at(i)), 2, 16, QChar('0'));
        }

        text = printable + "\n\n--- HEX DUMP ---\n" + hexDump;
        emit espUartSnoopReceived(text);
        break;
    }
    case rpc::CMD_LOG_MESSAGE:
        if (frame.payload.size() > 0) {
            // Optional crash-proof capture: when the user has enabled log-to-file,
            // append the RAW log bytes and flush to the OS immediately. Writing raw
            // (not just completed lines) means a fast M1 crash can't lose the final
            // partial line — usually the one that names the fault. OFF by default so
            // it doesn't grow an unbounded file every session (see setLogToFile).
            if (m_logToFile && m_logFile.isOpen()) {
                m_logFile.write(frame.payload);
                m_logFile.flush();
            }
            m_m1LogBuf.append(frame.payload);
            int start = 0;
            for (int i = 0; i < m_m1LogBuf.size(); ++i) {
                if (m_m1LogBuf.at(i) == '\n') {
                    QByteArray lineBytes = m_m1LogBuf.mid(start, i - start);
                    if (lineBytes.endsWith('\r'))
                        lineBytes.chop(1);
                    if (!lineBytes.isEmpty())
                        emit m1LogReceived(QString::fromUtf8(lineBytes));
                    start = i + 1;
                }
            }
            m_m1LogBuf = m_m1LogBuf.mid(start);
        }
        break;
    default:
        qDebug() << "Unhandled RPC command:" << Qt::hex << frame.cmd;
        break;
    }
}

void M1Device::handleDeviceInfoResp(const rpc::Frame &frame)
{
    if (frame.payload.size() < rpc::DEVICE_INFO_BASE_SIZE) {
        qWarning() << "Device info response too short:"
                   << frame.payload.size() << "bytes (need"
                   << rpc::DEVICE_INFO_BASE_SIZE << ")";
        return;
    }

    const auto *info = reinterpret_cast<const rpc::DeviceInfoPayload*>(
        frame.payload.constData());

    if (info->magic != rpc::DEVICE_INFO_MAGIC) {
        qWarning() << "Device info bad magic:" << Qt::hex << info->magic;
        return;
    }

    m_deviceInfo.fwMajor = info->fw_version_major;
    m_deviceInfo.fwMinor = info->fw_version_minor;
    m_deviceInfo.fwBuild = info->fw_version_build;
    m_deviceInfo.fwRC    = info->fw_version_rc;

    m_deviceInfo.activeBank = info->active_bank;
    m_deviceInfo.batteryLevel = info->battery_level;
    m_deviceInfo.batteryCharging = info->battery_charging;
    m_deviceInfo.sdCardPresent = info->sd_card_present;
    m_deviceInfo.sdTotalKB = info->sd_total_kb;
    m_deviceInfo.sdFreeKB = info->sd_free_kb;
    m_deviceInfo.esp32Ready = info->esp32_ready;
    m_deviceInfo.esp32Version = QString::fromLatin1(info->esp32_version,
        static_cast<int>(strnlen(info->esp32_version, 32)));
    m_deviceInfo.ismBandRegion = info->ism_band_region;
    m_deviceInfo.opMode = info->op_mode;
    m_deviceInfo.southpawMode = info->southpaw_mode;
    m_deviceInfo.c3Revision = info->c3_revision;

    // Extended battery detail (check offset of charge_fault + 1 = 67 bytes)
    constexpr int EXTENDED_BATT_SIZE = offsetof(rpc::DeviceInfoPayload, charge_fault) + 1;
    if (frame.payload.size() >= EXTENDED_BATT_SIZE) {
        m_deviceInfo.batteryVoltageMv = info->batt_voltage_mv;
        m_deviceInfo.batteryCurrentMa = info->batt_current_ma;
        m_deviceInfo.batteryTempC     = info->batt_temp_c;
        m_deviceInfo.batteryHealth    = info->batt_health;
        m_deviceInfo.chargeState      = info->charge_state;
        m_deviceInfo.chargeFault      = info->charge_fault;
    }

    emit deviceInfoUpdated();
}

void M1Device::handleScreenFrame(const rpc::Frame &frame)
{
    // Serial (USB) screen path: frames still arrive as CMD_SCREEN_FRAME over the
    // control link. Decode here on the GUI thread (cheap, serial-only) and push
    // the finished image the same way the WiFi worker does. (WiFi screen frames
    // never come through here — they arrive over UDP via onWifiScreenFrame().)
    if (m_screenBuffer.update(frame.payload)) {
        m_lastScreenImage = m_screenBuffer.toImage();
        m_screenFrameCount++;
        emit screenImageReady(m_lastScreenImage);
        emit screenFrameReceived();
    } else {
        qWarning() << "SCREEN: rejected frame, payload=" << frame.payload.size()
                   << "(expected" << rpc::SCREEN_FB_SIZE << ")";
    }
}

void M1Device::handleFwInfoResp(const rpc::Frame &frame)
{
    // Minimum size: active_bank(2) + 2 * old BankInfo(13) = 28 bytes
    constexpr int MIN_FW_INFO_SIZE = 28;
    qDebug() << "FW_INFO_RESP payload:" << frame.payload.size()
             << "bytes, need:" << sizeof(rpc::FwInfoPayload)
             << "(min:" << MIN_FW_INFO_SIZE << ")";
    if (frame.payload.size() < MIN_FW_INFO_SIZE) {
        qWarning() << "FW_INFO_RESP too short, dropping";
        return;
    }

    // Old firmware sends 28 bytes (2 + 13*2), new sends 70 (2 + 34*2).
    // A flat memcpy would misalign bank2 data into bank1's new fields.
    // Parse each bank at its correct offset based on per-bank size.
    rpc::FwInfoPayload local;
    memset(&local, 0, sizeof(local));

    const uint8_t *raw = reinterpret_cast<const uint8_t*>(frame.payload.constData());
    int payloadSize = frame.payload.size();

    // active_bank is always first 2 bytes
    memcpy(&local.active_bank, raw, 2);

    // Determine per-bank size from payload
    int perBankSize = (payloadSize - 2) / 2;
    int copyBank = qMin(perBankSize, static_cast<int>(sizeof(rpc::FwBankInfo)));
    if (perBankSize > 0) {
        memcpy(&local.bank1, raw + 2, copyBank);
        memcpy(&local.bank2, raw + 2 + perBankSize, copyBank);
    }
    const auto *fw = &local;

    QJsonObject info;
    info["activeBank"] = static_cast<int>(fw->active_bank);

    auto bankToJson = [](const rpc::FwBankInfo &b) {
        QJsonObject obj;
        obj["major"] = b.fw_version_major;
        obj["minor"] = b.fw_version_minor;
        obj["build"] = b.fw_version_build;
        obj["rc"]    = b.fw_version_rc;
        obj["crcValid"] = b.crc_valid != 0;
        obj["imageSize"] = static_cast<int>(b.image_size);
        obj["c3Revision"] = b.c3_revision;
        // Build date is a fixed 20-byte null-terminated string
        obj["buildDate"] = QString::fromLatin1(b.build_date, 19).trimmed();
        return obj;
    };
    info["bank1"] = bankToJson(fw->bank1);
    info["bank2"] = bankToJson(fw->bank2);

    qDebug() << "FW_INFO: payload" << frame.payload.size() << "bytes, perBankSize" << perBankSize;
    qDebug() << "FW_INFO: bank1 v" << fw->bank1.fw_version_major
             << "." << fw->bank1.fw_version_minor
             << "." << fw->bank1.fw_version_build
             << "c3rev=" << fw->bank1.c3_revision
             << "date=" << QString::fromLatin1(fw->bank1.build_date, 19);
    qDebug() << "FW_INFO: bank2 v" << fw->bank2.fw_version_major
             << "." << fw->bank2.fw_version_minor
             << "." << fw->bank2.fw_version_build
             << "c3rev=" << fw->bank2.c3_revision
             << "date=" << QString::fromLatin1(fw->bank2.build_date, 19);
    qDebug() << "FW_INFO: activeBank=" << fw->active_bank;
    emit fwInfoReceived(info);
}

void M1Device::handleFileListResp(const rpc::Frame &frame)
{
    // Parse file entries from payload
    QJsonArray entries;
    const uint8_t *data = reinterpret_cast<const uint8_t*>(frame.payload.constData());
    int remaining = frame.payload.size();
    int offset = 0;

    qDebug() << "FILE_LIST_RESP: payload" << remaining << "bytes";

    // First bytes: path string (null-terminated)
    if (remaining < 1) {
        qWarning() << "FILE_LIST_RESP: empty payload";
        return;
    }
    QString path = QString::fromUtf8(frame.payload.constData());
    offset = static_cast<int>(path.toUtf8().size()) + 1;  // skip null terminator

    qDebug() << "FILE_LIST_RESP: path =" << path << ", data offset =" << offset
             << ", remaining =" << (remaining - offset);

    // Remaining: repeated FileEntry structures
    while (offset + 9 < remaining) {  // minimum: is_dir(1) + size(4) + date(2) + time(2) + name(1)
        QJsonObject entry;
        entry["isDir"] = data[offset] != 0;
        uint32_t fsize = data[offset+1] | (data[offset+2]<<8) |
                         (data[offset+3]<<16) | (data[offset+4]<<24);
        entry["size"] = static_cast<int>(fsize);
        offset += 9;  // skip is_dir + size + date + time

        // Read null-terminated name
        int nameStart = offset;
        while (offset < remaining && data[offset] != 0) offset++;
        entry["name"] = QString::fromUtf8(
            reinterpret_cast<const char*>(data + nameStart), offset - nameStart);
        offset++;  // skip null

        qDebug() << "  entry:" << entry["name"].toString()
                 << (entry["isDir"].toBool() ? "[DIR]" : "")
                 << entry["size"].toInt() << "bytes";

        entries.append(entry);
    }

    qDebug() << "FILE_LIST_RESP: parsed" << entries.size() << "entries";
    emit fileListReceived(path, entries);
}

void M1Device::handleFileReadData(const rpc::Frame &frame)
{
    if (frame.payload.size() < 4) return;

    // First 4 bytes = offset, rest = data
    m_fileDownloadBuf.append(frame.payload.mid(4));

    // Simple heuristic: if chunk is less than 512 bytes, it's the last chunk
    if (frame.payload.size() - 4 < 512) {
        // Write to local file
        QFile outFile(m_fileDownloadDest);
        if (outFile.open(QIODevice::WriteOnly)) {
            outFile.write(m_fileDownloadBuf);
            outFile.close();
            emit fileDownloadComplete(m_fileDownloadDest);
        } else {
            emit fileOperationError("Cannot write to: " + m_fileDownloadDest);
        }
        m_fileDownloadBuf.clear();
    }
}

void M1Device::handleAck(const rpc::Frame & /*frame*/)
{
    qDebug() << "RPC ACK received";

    // Bank erase ACK — inactive bank has been wiped
    if (m_bankErasePending) {
        m_bankErasePending = false;
        m_pingTimer.start(3000);
        qDebug() << "Bank erase: ACK received, inactive bank wiped";
        emit bankEraseComplete();
        return;
    }

    // Bank swap ACK — device accepted swap and is about to reboot
    if (m_bankSwapPending) {
        m_bankSwapPending = false;
        qDebug() << "Bank swap: ACK received, device will reboot";
        emit bankSwapStarted();
        // Proactively close so auto-reconnect does a clean full reinit.
        // Without this, a fast reboot may not trigger a serial ResourceError,
        // leaving stale state (no fresh deviceInfo, locked update paths).
        QTimer::singleShot(500, this, [this]() {
            if (isConnected()) {
                qInfo() << "Bank swap: closing connection for clean reconnect";
                m_transport->close();
            }
        });
        return;
    }

    // FW update state machine takes priority
    if (m_fwUpdateState != FwUpdateState::Idle) {
        switch (m_fwUpdateState) {
        case FwUpdateState::WaitingStartAck:
            qDebug() << "FW update: START ACK'd, sending data...";
            m_fwUpdateState = FwUpdateState::SendingData;
            m_fwUpdateTimeout.start(10000);  // 10s per chunk
            fwUpdateSendNextChunk();
            return;
        case FwUpdateState::SendingData:
            m_fwUpdateTimeout.start(10000);  // reset for next chunk
            fwUpdateSendNextChunk();
            return;
        case FwUpdateState::WaitingFinishAck:
            qDebug() << "FW update: FINISH ACK'd, update complete!";
            m_fwUpdateTimeout.stop();
            m_fwUpdateState = FwUpdateState::Idle;
            m_fwUpdateData.clear();
            emit fwUpdateComplete();
            return;
        default:
            break;
        }
    }

    // ESP32 update state machine
    if (m_espUpdateState != EspUpdateState::Idle) {
        switch (m_espUpdateState) {
        case EspUpdateState::WaitingStartAck:
            qDebug() << "ESP32 update: START ACK'd, sending data...";
            m_espUpdateState = EspUpdateState::SendingData;
            m_espUpdateTimeout.start(30000);
            emit espUpdateStatus("Writing firmware...");
            espUpdateSendNextChunk();
            return;
        case EspUpdateState::SendingData:
            m_espUpdateTimeout.start(30000);
            espUpdateSendNextChunk();
            return;
        case EspUpdateState::WaitingFinishAck:
            qDebug() << "ESP32 update: FINISH ACK'd, upload complete!";
            m_espUpdateTimeout.stop();
            m_espUpdateState = EspUpdateState::Idle;
            m_espUpdateData.clear();
            m_pingTimer.start(3000);
            emit espUpdateComplete();
            return;
        default:
            break;
        }
    }

    // File upload state machine
    if (m_fileUploadState != FileUploadState::Idle) {
        switch (m_fileUploadState) {
        case FileUploadState::WaitingStartAck:
            qDebug() << "File upload: START ACK'd, sending data...";
            m_fileUploadState = FileUploadState::SendingData;
            m_fileUploadTimeout.start(10000);
            fileUploadSendNextChunk();
            return;
        case FileUploadState::SendingData:
            m_fileUploadTimeout.start(10000);
            fileUploadSendNextChunk();
            return;
        case FileUploadState::WaitingFinishAck:
            qDebug() << "File upload: FINISH ACK'd, upload complete!";
            m_fileUploadTimeout.stop();
            m_fileUploadState = FileUploadState::Idle;
            m_fileUploadData.clear();
            if (m_uploadQueueIndex >= 0) {
                advanceUploadQueue();
            } else {
                emit fileUploadComplete();
            }
            return;
        default:
            break;
        }
    }

    uint8_t pending = m_pendingFileCmd;
    m_pendingFileCmd = 0;

    switch (pending) {
    case rpc::CMD_FILE_DELETE:
    case rpc::CMD_FILE_DELETE_TREE:
        qDebug() << "File delete confirmed";
        emit fileDeleteComplete();
        break;
    case rpc::CMD_FILE_RENAME:
        qDebug() << "File rename/move confirmed";
        emit fileRenameComplete();
        break;
    case rpc::CMD_FILE_MKDIR:
        qDebug() << "Mkdir confirmed";
        if (m_mkdirQueueIndex >= 0) {
            advanceMkdirQueue();
        } else {
            emit fileMkdirComplete();
        }
        break;
    case rpc::CMD_SD_UNMOUNT:
        qDebug() << "SD unmount confirmed";
        m_sdMounted = false;
        emit sdMountChanged(false);
        break;
    case rpc::CMD_SD_MOUNT:
        qDebug() << "SD mount confirmed";
        m_sdMounted = true;
        emit sdMountChanged(true);
        break;
    default:
        // Absorb stale ACK from a timed-out ESP32 flash attempt — only if
        // no active state machine claimed this ACK (prevents eating ACKs
        // that belong to a subsequent operation).
        if (m_espUpdateStaleNack) {
            m_espUpdateStaleNack = false;
            qDebug() << "Consumed stale ESP32 ACK after timeout";
        }
        break;
    }
}

void M1Device::handleNack(const rpc::Frame &frame)
{
    uint8_t errCode = 0;
    if (!frame.payload.isEmpty()) {
        errCode = static_cast<uint8_t>(frame.payload.at(0));
    }

    QString errMsg;
    switch (errCode) {
    case rpc::ERR_UNKNOWN_CMD:     errMsg = "Unknown command"; break;
    case rpc::ERR_INVALID_PAYLOAD: errMsg = "Invalid payload"; break;
    case rpc::ERR_BUSY:            errMsg = "Device busy"; break;
    case rpc::ERR_SD_NOT_READY:    errMsg = "SD card not ready"; break;
    case rpc::ERR_FILE_NOT_FOUND:  errMsg = "File not found"; break;
    case rpc::ERR_DIR_NOT_EMPTY:   errMsg = "Folder not empty"; break;
    case rpc::ERR_FLASH_ERROR:     errMsg = "Flash error"; break;
    case rpc::ERR_CRC_MISMATCH:    errMsg = "CRC mismatch"; break;
    case rpc::ERR_SIZE_TOO_LARGE:  errMsg = "Size too large"; break;
    case rpc::ERR_BANK_EMPTY:      errMsg = "Inactive bank has no valid firmware — cannot swap"; break;
    case rpc::ERR_ESP_FLASH: {
        // Parse sub-error from 2nd payload byte if present
        uint8_t sub = (frame.payload.size() >= 2)
                      ? static_cast<uint8_t>(frame.payload.at(1)) : 0;
        switch (sub) {
        case rpc::ESP_SUB_CONNECT:
            errMsg = "ESP32 flash failed: cannot connect to ROM bootloader.\n\n"
                     "The M1 could not establish communication with the ESP32.\n"
                     "Restart qMonstatek, reboot the M1, and try again.";
            break;
        case rpc::ESP_SUB_ERASE:
            errMsg = "ESP32 flash failed: flash erase error.\n\n"
                     "The ESP32 flash could not be erased. This may indicate a hardware issue.\n"
                     "Restart qMonstatek, reboot the M1, and try again.";
            break;
        case rpc::ESP_SUB_WRITE:
            errMsg = "ESP32 flash failed: data transfer interrupted.\n\n"
                     "Communication was lost during the flash write.\n"
                     "Restart qMonstatek, reboot the M1, and try again.";
            break;
        case rpc::ESP_SUB_VERIFY: {
            errMsg = "ESP32 flash failed: MD5 verification mismatch.\n\n"
                     "The data written to flash does not match what was sent. "
                     "This can happen due to signal noise during transfer.";
            // Extended diagnostic payload (74 bytes):
            // [2-5] total_hashed LE, [6-9] image_size LE,
            // [10-41] expected MD5 hex, [42-73] actual MD5 hex
            if (frame.payload.size() >= 74) {
                QByteArray expectedMd5 = frame.payload.mid(10, 32);
                QByteArray actualMd5 = frame.payload.mid(42, 32);
                errMsg += QString("\n\n  Expected MD5: %1\n  Actual MD5:   %2")
                          .arg(QString::fromLatin1(expectedMd5))
                          .arg(QString::fromLatin1(actualMd5));
            }
            errMsg += "\n\nRestart qMonstatek, reboot the M1, and try again.\n"
                      "If this error persists, ensure the firmware binary was built correctly.";
            break;
        }
        default:
            errMsg = "ESP32 flash failed: unknown error.\n\n"
                     "Restart qMonstatek, reboot the M1, and try again.";
            break;
        }
        break;
    }
    default:                       errMsg = QString("Error code %1").arg(errCode); break;
    }

    qWarning() << "RPC NACK:" << errMsg;

    // Bank erase NACK — erase failed
    if (m_bankErasePending) {
        m_bankErasePending = false;
        m_pingTimer.start(3000);
        qWarning() << "Bank erase failed:" << errMsg;
        emit bankEraseError(errMsg);
        return;
    }

    // Bank swap NACK — swap was refused
    if (m_bankSwapPending) {
        m_bankSwapPending = false;
        qWarning() << "Bank swap refused:" << errMsg;
        emit bankSwapError(errMsg);
        return;
    }

    // If fw update is in progress, abort it
    if (m_fwUpdateState != FwUpdateState::Idle) {
        qWarning() << "FW update aborted due to NACK";
        m_fwUpdateTimeout.stop();
        m_fwUpdateState = FwUpdateState::Idle;
        m_fwUpdateData.clear();
        emit fwUpdateError(errMsg);
        return;
    }

    // If ESP32 update is in progress, abort it
    if (m_espUpdateState != EspUpdateState::Idle) {
        qWarning() << "ESP32 update failed:" << errMsg;
        m_espUpdateTimeout.stop();
        m_espUpdateState = EspUpdateState::Idle;
        m_espUpdateData.clear();
        m_pingTimer.start(3000);  // Resume polling
        emit espUpdateError(errMsg);
        return;
    }

    // If file upload is in progress, abort it (and the queue)
    if (m_fileUploadState != FileUploadState::Idle) {
        qWarning() << "File upload aborted due to NACK:" << errMsg;
        m_fileUploadTimeout.stop();
        m_fileUploadState = FileUploadState::Idle;
        m_fileUploadData.clear();
        m_uploadQueue.clear();
        m_uploadQueueIndex = -1;
        m_mkdirQueue.clear();
        m_mkdirQueueIndex = -1;
        emit fileOperationError("Upload failed: " + errMsg);
        return;
    }

    // Absorb stale NACK from a timed-out ESP32 flash attempt — only if
    // no active state machine claimed this NACK.
    if (m_espUpdateStaleNack) {
        m_espUpdateStaleNack = false;
        qDebug() << "Consumed stale ESP32 NACK after timeout";
        return;
    }

    m_pendingFileCmd = 0;
    emit errorOccurred(errMsg);
}

void M1Device::onTransportConnected(bool connected)
{
    if (connected) {
        const bool wifi = m_transport && m_transport->transportName() == "WiFi";
        if (wifi) {
            m_wifiWasConnected = true;
            m_wifiReconnectAttempts = 0;
            m_wifiReconnectTimer.stop();
        }
        // WiFi open() is async — start the session now that we are connected.
        if (m_pendingSessionStart) {
            m_pendingSessionStart = false;
            startSession();
        }
        // Re-arm the UDP screen stream after a WiFi reconnect: the ESP clears its
        // UDP target on every accept, so a fresh SCREEN_START is required or the
        // screen stays black. Delay a little so the relay/session settles first.
        if (wifi && m_screenWanted) {
            QTimer::singleShot(500, this, [this]() {
                if (m_screenWanted && isConnected())
                    startScreenStream(m_screenFps);
            });
        }
        emit connectionChanged(true);
        return;
    }

    {
        QString lastPort = m_transport ? m_transport->targetName() : QString();

        m_pingTimer.stop();
        m_codec.reset();
        m_deviceInfo = DeviceInfo{};
        m_screenStreaming = false;
        m_bankSwapPending = false;
        m_fwUpdateTimeout.stop();
        if (m_fwUpdateState != FwUpdateState::Idle) {
            m_fwUpdateState = FwUpdateState::Idle;
            m_fwUpdateData.clear();
            emit fwUpdateError("Device disconnected during firmware update");
        }
        m_espUpdateTimeout.stop();
        m_espUpdateStaleNack = false;
        if (m_espUpdateState != EspUpdateState::Idle) {
            m_espUpdateState = EspUpdateState::Idle;
            m_espUpdateData.clear();
            emit espUpdateError("Device disconnected during ESP32 update");
        }
        m_fileUploadTimeout.stop();
        if (m_fileUploadState != FileUploadState::Idle) {
            m_fileUploadState = FileUploadState::Idle;
            m_fileUploadData.clear();
            emit fileOperationError("Device disconnected during file upload");
        }
        m_uploadQueue.clear();
        m_uploadQueueIndex = -1;
        m_mkdirQueue.clear();
        m_mkdirQueueIndex = -1;
        m_sdMounted = true;  // reset to default on disconnect
        emit screenStreamingChanged(false);

        const bool wifi = m_transport && m_transport->transportName() == "WiFi";

        if (wifi) {
            // WiFi TCP auto-reconnect/backoff (§7): only for real drops after a
            // successful connect, never on a user-initiated close.
            if (!m_userDisconnecting && m_wifiWasConnected && !m_wifiTarget.isEmpty()
                && m_wifiReconnectAttempts < WIFI_RECONNECT_MAX) {
                const int delay = qMin(10000, 1000 << qMin(m_wifiReconnectAttempts, 3));
                qInfo() << "WiFi: unexpected disconnect — reconnect in" << delay
                        << "ms (attempt" << (m_wifiReconnectAttempts + 1) << ")";
                if (m_mdns)
                    m_mdns->startScan();   // re-resolve the target via mDNS
                m_wifiReconnectTimer.start(delay);
            }
        } else if (!m_userDisconnecting && !lastPort.isEmpty()) {
            // Serial: tell discovery to forget the port so the next scan
            // re-detects it (handles fast reboots where the COM port reappears
            // within the 2-second scan window).
            qInfo() << "Unexpected disconnect on" << lastPort
                    << "— will auto-reconnect when device reappears";
            m_discovery.forgetPort(lastPort);
        }
        m_userDisconnecting = false;
    }
    emit connectionChanged(connected);
}

void M1Device::onDeviceFound(const QString &portName)
{
    if (m_autoConnect && !isConnected()) {
        qInfo() << "Auto-connecting to" << portName;
        connectToDevice(portName);
    }
}

void M1Device::onDeviceLost(const QString &portName)
{
    // Only applies to USB (serial) connections
    if (m_transport == &m_serialTransport &&
        isConnected() && m_serialTransport.portName() == portName) {
        qInfo() << "Device lost:" << portName;
        // Don't call disconnect() — it sets m_userDisconnecting which
        // skips forgetPort() in onTransportConnected(false) and blocks
        // auto-reconnect when the device reappears.
        m_pingTimer.stop();
        m_transport->close();
    }
}

/* ──────────── WiFi worker + reconnect ──────────── */

void M1Device::onWifiScreenFrame(const QImage &image)
{
    // Pushed from the worker thread (already decoded + upscaled). No conversion
    // happens on the GUI thread — we just hold and forward the finished frame.
    m_lastScreenImage = image;
    m_screenFrameCount++;
    emit screenImageReady(image);
    emit screenFrameReceived();
}

void M1Device::onInboundActivity()
{
    // Any inbound TCP byte keeps the link alive (§3), even without a full frame.
    m_lastInboundMs = QDateTime::currentMSecsSinceEpoch();
}

void M1Device::tryWifiReconnect()
{
    if (isConnected())
        return;
    m_wifiReconnectAttempts++;
    qInfo() << "WiFi: reconnect attempt" << m_wifiReconnectAttempts
            << "to" << m_wifiTarget;
    connectToDeviceWifi(m_wifiTarget);
}

void M1Device::setMdnsDiscovery(MdnsDiscovery *mdns)
{
    m_mdns = mdns;
    if (!m_mdns)
        return;

    // While an auto-reconnect is in progress, adopt a freshly resolved address
    // for the M1 (its IP may have changed across the reconnect window).
    connect(m_mdns, &MdnsDiscovery::serviceFound, this,
            [this](const QString &name, const QString &address, int port) {
                Q_UNUSED(name);
                if (isConnected() || !m_wifiWasConnected || m_wifiReconnectAttempts == 0)
                    return;
                const QString t = address + ":" + QString::number(port);
                if (t != m_wifiTarget) {
                    qInfo() << "WiFi: mDNS re-resolved target" << m_wifiTarget
                            << "->" << t;
                    m_wifiTarget = t;
                }
            });
}
