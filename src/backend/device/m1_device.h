/*
 * m1_device.h — Main M1 device facade
 *
 * High-level API exposed to QML via Q_PROPERTY. Owns the serial transport
 * and RPC protocol codec, and orchestrates all device communication.
 */

#ifndef M1_DEVICE_H
#define M1_DEVICE_H

#include <QObject>
#include <QImage>
#include <QTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonObject>

#include "device_info.h"
#include "screen_buffer.h"
#include "transport/abstract_transport.h"
#include "transport/serial_transport.h"
#include "transport/tcp_transport.h"
#include "transport/wifi_transport.h"
#include "transport/device_discovery.h"
#include "transport/mdns_discovery.h"
#include "protocol/rpc_frame.h"
#include "protocol/rpc_protocol.h"

class M1Device : public QObject {
    Q_OBJECT

    /* Properties exposed to QML */
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectionChanged)
    Q_PROPERTY(QString portName READ portName NOTIFY connectionChanged)
    Q_PROPERTY(QString connectionType READ connectionType NOTIFY connectionChanged)
    Q_PROPERTY(QString firmwareVersion READ firmwareVersion NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY deviceInfoUpdated)
    Q_PROPERTY(bool batteryCharging READ batteryCharging NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int batteryVoltage READ batteryVoltage NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int batteryCurrent READ batteryCurrent NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int batteryTemp READ batteryTemp NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int batteryHealth READ batteryHealth NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int chargeState READ chargeState NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int chargeFault READ chargeFault NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int fwMajor READ fwMajor NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int fwMinor READ fwMinor NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int fwBuild READ fwBuild NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int fwRC READ fwRC NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int c3Revision READ c3Revision NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int fwVariant READ fwVariant NOTIFY deviceInfoUpdated)
    Q_PROPERTY(bool mobileLinkActive READ mobileLinkActive NOTIFY deviceInfoUpdated)
    Q_PROPERTY(bool isRestoreHost READ isRestoreHost NOTIFY deviceInfoUpdated)
    Q_PROPERTY(bool hasDeviceInfo READ hasDeviceInfo NOTIFY deviceInfoUpdated)
    Q_PROPERTY(int activeBank READ activeBank NOTIFY deviceInfoUpdated)
    Q_PROPERTY(bool sdCardPresent READ sdCardPresent NOTIFY deviceInfoUpdated)
    Q_PROPERTY(QString sdCapacity READ sdCapacity NOTIFY deviceInfoUpdated)
    Q_PROPERTY(bool esp32Ready READ esp32Ready NOTIFY deviceInfoUpdated)
    Q_PROPERTY(QString esp32Version READ esp32Version NOTIFY deviceInfoUpdated)
    Q_PROPERTY(bool sdMounted READ isSdMounted NOTIFY sdMountChanged)
    Q_PROPERTY(bool screenStreaming READ isScreenStreaming NOTIFY screenStreamingChanged)
    Q_PROPERTY(QImage screenImage READ screenImage NOTIFY screenFrameReceived)
    Q_PROPERTY(int screenFrameCount READ screenFrameCount NOTIFY screenFrameReceived)
    Q_PROPERTY(bool logToFile READ logToFile WRITE setLogToFile NOTIFY logToFileChanged)
    Q_PROPERTY(QString logFilePath READ logFilePath WRITE setLogFilePath NOTIFY logFilePathChanged)
    Q_PROPERTY(bool deviceLogVerbose READ deviceLogVerbose WRITE setDeviceLogVerbose NOTIFY deviceLogVerboseChanged)
    Q_PROPERTY(bool legacyCompatMode READ legacyCompatMode NOTIFY legacyCompatModeChanged)

public:
    explicit M1Device(QObject *parent = nullptr);

    /* Connection */
    Q_INVOKABLE bool connectToDevice(const QString &portName);
    Q_INVOKABLE bool connectToDeviceWifi(const QString &hostPort);
    Q_INVOKABLE void disconnect();
    bool isConnected() const;
    QString portName() const;
    QString connectionType() const;

    /* Debug log capture to file (opt-in; OFF by default). When enabled, raw M1
     * log bytes are appended to logFilePath. setLogFilePath accepts a plain path
     * or a file:// URL (from a QML FileDialog). */
    bool logToFile() const { return m_logToFile; }
    QString logFilePath() const { return m_logFilePath; }
    Q_INVOKABLE void setLogToFile(bool enabled);
    Q_INVOKABLE void setLogFilePath(const QString &path);

    /* Device-side UART log verbosity. OFF (default) keeps the M1 at WARN so its
     * UART isn't flooded with m1link/RPC INFO traces; ON raises it to INFO for a
     * capture. Persisted, and re-sent to the device on each (re)connect. */
    bool deviceLogVerbose() const { return m_deviceLogVerbose; }
    Q_INVOKABLE void setDeviceLogVerbose(bool on);

    /* True when the connected device speaks the legacy (pre-fix) CRC — i.e. its
     * firmware predates the CRC-table fix. qMonstatek talks to it in a
     * compatibility mode so the user can push the fixing update without DFU. */
    bool legacyCompatMode() const { return m_legacyCompatMode; }

    /* Device info */
    Q_INVOKABLE void requestDeviceInfo();
    const DeviceInfo& deviceInfo() const { return m_deviceInfo; }
    QString firmwareVersion() const { return m_deviceInfo.fwVersionString(); }
    int batteryLevel() const { return m_deviceInfo.batteryLevel; }
    bool batteryCharging() const { return m_deviceInfo.batteryCharging; }
    int batteryVoltage() const { return m_deviceInfo.batteryVoltageMv; }
    int batteryCurrent() const { return m_deviceInfo.batteryCurrentMa; }
    int batteryTemp() const { return m_deviceInfo.batteryTempC; }
    int batteryHealth() const { return m_deviceInfo.batteryHealth; }
    int chargeState() const { return m_deviceInfo.chargeState; }
    int chargeFault() const { return m_deviceInfo.chargeFault; }
    int fwMajor() const { return m_deviceInfo.fwMajor; }
    int fwMinor() const { return m_deviceInfo.fwMinor; }
    int fwBuild() const { return m_deviceInfo.fwBuild; }
    int fwRC() const { return m_deviceInfo.fwRC; }
    int c3Revision() const { return m_deviceInfo.c3Revision; }
    int fwVariant() const { return m_deviceInfo.fwVariant; }
    bool isRestoreHost() const { return m_deviceInfo.fwVariant == 2; }
    bool mobileLinkActive() const { return m_deviceInfo.linkActive; }
    bool hasDeviceInfo() const { return m_deviceInfo.hasDeviceInfo(); }
    int activeBank() const { return m_deviceInfo.bankNumber(); }
    bool sdCardPresent() const { return m_deviceInfo.sdCardPresent; }
    QString sdCapacity() const { return m_deviceInfo.sdCapacityString(); }
    bool esp32Ready() const { return m_deviceInfo.esp32Ready; }
    QString esp32Version() const { return m_deviceInfo.esp32Version; }

    /* Screen mirror */
    Q_INVOKABLE void startScreenStream(int fps = 10);
    Q_INVOKABLE void stopScreenStream();
    Q_INVOKABLE void captureScreen();
    Q_INVOKABLE bool saveScreenshot(const QString &filePath);
    bool isScreenStreaming() const { return m_screenStreaming; }
    QImage screenImage() const { return m_lastScreenImage; }
    int screenFrameCount() const { return m_screenFrameCount; }

    /* Remote control */
    Q_INVOKABLE void buttonPress(int buttonId);
    Q_INVOKABLE void buttonRelease(int buttonId);
    Q_INVOKABLE void buttonClick(int buttonId);

    /* File operations */
    Q_INVOKABLE void requestFileList(const QString &path);
    Q_INVOKABLE void downloadFile(const QString &remotePath, const QString &localPath);
    Q_INVOKABLE void uploadFile(const QString &localPath, const QString &remotePath);
    Q_INVOKABLE void uploadFiles(const QVariantList &fileUrls, const QString &remotePath);
    Q_INVOKABLE void uploadFolder(const QString &localFolderUrl, const QString &remotePath);
    Q_INVOKABLE void deleteFile(const QString &remotePath);
    Q_INVOKABLE void deleteTree(const QString &remotePath);    // recursive (folder + contents)
    Q_INVOKABLE void renameFile(const QString &oldPath, const QString &newPath); // rename or move
    Q_INVOKABLE void makeDirectory(const QString &remotePath);

    /* SD card mount/unmount */
    Q_INVOKABLE void mountSdCard();
    Q_INVOKABLE void unmountSdCard();
    bool isSdMounted() const { return m_sdMounted; }

    /* Firmware update */
    Q_INVOKABLE void requestFwInfo();
    Q_INVOKABLE void startFwUpdate(const QString &binFilePath);
    Q_INVOKABLE void swapBanks();
    Q_INVOKABLE void eraseInactiveBank();
    Q_INVOKABLE void enterDfu();
    Q_INVOKABLE void reboot();
    Q_INVOKABLE void shutdown();

    /* ESP32 update */
    Q_INVOKABLE void requestEspInfo();
    Q_INVOKABLE void initEsp32();
    Q_INVOKABLE void rebootEsp32();
    Q_INVOKABLE void startEspUpdate(const QString &binFilePath, uint32_t flashAddr, bool force = false);

    /* Debug / CLI terminal */
    Q_INVOKABLE void sendCliCommand(const QString &command);
    Q_INVOKABLE void sendEspUartSnoop();

    /* Device discovery */
    DeviceDiscovery* discovery() { return &m_discovery; }

    /* mDNS browser used to re-resolve the WiFi target on auto-reconnect.
     * Wired from main.cpp (not owned). */
    void setMdnsDiscovery(MdnsDiscovery *mdns);

signals:
    void connectionChanged(bool connected);
    void deviceInfoUpdated();
    void screenFrameReceived();
    void screenImageReady(QImage image);   // push: finished, upscaled screen frame
    void screenStreamingChanged(bool streaming);
    void pongReceived(int latencyMs);
    void logToFileChanged(bool enabled);
    void logFilePathChanged(QString path);
    void deviceLogVerboseChanged(bool on);
    void legacyCompatModeChanged(bool legacy);
    void legacyFirmwareDetected();   // one-shot: old firmware seen, prompt to update

    /* File signals */
    void fileListReceived(const QString &path, const QJsonArray &entries);
    void fileDownloadProgress(int percent);
    void fileDownloadComplete(const QString &localPath);
    void fileUploadProgress(int percent);
    void fileUploadComplete();
    void fileDeleteComplete();
    void fileRenameComplete();
    void fileMkdirComplete();
    void fileOperationError(const QString &message);
    void multiUploadProgress(int fileIndex, int totalFiles, const QString &fileName);
    void multiUploadComplete(int totalFiles);
    void sdMountChanged(bool mounted);

    /* Firmware signals */
    void fwInfoReceived(const QJsonObject &info);
    void fwUpdateProgress(int percent);
    void fwUpdateComplete();
    void fwUpdateError(const QString &message);
    void bankSwapStarted();       // ACK received — device is about to reboot
    void bankSwapError(const QString &message);  // NACK received — swap refused
    void bankEraseComplete();
    void bankEraseError(const QString &message);

    /* ESP32 signals */
    void espInfoReceived(const QString &version);
    void espUpdateProgress(int percent);
    void espUpdateStatus(const QString &status);
    void espUpdateComplete();
    void espUpdateError(const QString &message);

    /* Debug / CLI */
    void cliResponseReceived(const QString &response);
    void espUartSnoopReceived(const QString &output);
    void m1LogReceived(const QString &line);

    /* General */
    void errorOccurred(const QString &message);

private slots:
    void onFrameReceived(rpc::Frame frame);
    void onTransportData(const QByteArray &data);
    void onTransportConnected(bool connected);
    void onDeviceFound(const QString &portName);
    void onDeviceLost(const QString &portName);
    void onWifiScreenFrame(const QImage &image);   // pushed from the worker thread
    void onInboundActivity();                       // any inbound WiFi byte (liveness)
    void tryWifiReconnect();

private:
    void trySerialReconnect();
    void sendCommand(uint8_t cmd, const QByteArray &payload = {});
    void handleDeviceInfoResp(const rpc::Frame &frame);
    void handleScreenFrame(const rpc::Frame &frame);
    void handleFwInfoResp(const rpc::Frame &frame);
    void handleFileListResp(const rpc::Frame &frame);
    void handleFileReadData(const rpc::Frame &frame);
    void handleAck(const rpc::Frame &frame);
    void handleNack(const rpc::Frame &frame);
    void fwUpdateSendNextChunk();

    /** Switch active transport, rewiring signals. */
    void setTransport(AbstractTransport *transport);

    /** Post-connect handshake (ping, device info, keepalive). */
    void startSession();
    /** Keep PING traffic out of an exclusive file/firmware transaction. */
    void suspendKeepalive();
    void resumeKeepaliveIfIdle();
    /** Retry an open CDC port after a device-side liveness failure. */
    void scheduleSerialReconnect(const QString &portName, int delayMs);

    /* Transports — serial is always available, WiFi created on demand */
    AbstractTransport *m_transport = nullptr;
    SerialTransport    m_serialTransport;
    WifiTransport     *m_wifiTransport = nullptr;

    rpc::FrameCodec m_codec;
    DeviceDiscovery m_discovery;
    DeviceInfo      m_deviceInfo;
    ScreenBuffer    m_screenBuffer;

    /* M1 firmware log line buffer (for assembling partial lines) */
    QByteArray m_m1LogBuf;

    /* Debug log-to-file (opt-in) */
    bool    m_logToFile = false;
    QString m_logFilePath;
    QFile   m_logFile;
    bool    m_deviceLogVerbose = false;

    /* CRC-dialect handshake state (see crc16.*). */
    bool    m_dialectResolved  = false;   // latched the device's dialect this session
    bool    m_legacyCompatMode = false;   // device uses the pre-fix (legacy) CRC

    bool     m_screenStreaming = false;
    bool     m_screenWanted    = false;   // user intent: re-arm the UDP stream on reconnect
    int      m_screenFps       = 5;
    int      m_screenFrameCount = 0;
    bool     m_autoConnect = true;
    bool     m_userDisconnecting = false;
    QTimer   m_pingTimer;
    bool     m_keepaliveSuspended = false;
    qint64   m_lastPingTime = 0;
    int      m_missedPongs = 0;
    qint64   m_lastInboundMs = 0;   // last inbound byte/frame time (liveness, §3)

    QTimer   m_serialReconnectTimer;
    QString  m_serialReconnectPort;
    int      m_serialReconnectAttempts = 0;

    /* Latest finished (upscaled) screen frame — pushed to QML and used by
     * screenshot save. Decoded on the worker thread for WiFi, on the GUI
     * thread for serial. */
    QImage   m_lastScreenImage;

    /* WiFi async connect + auto-reconnect state */
    QString  m_wifiTarget;                 // last WiFi host:port
    bool     m_pendingSessionStart = false;
    bool     m_wifiWasConnected = false;   // gate auto-reconnect to real drops
    QTimer   m_wifiReconnectTimer;
    int      m_wifiReconnectAttempts = 0;
    MdnsDiscovery *m_mdns = nullptr;        // not owned

    /* File transfer state */
    QByteArray m_fileDownloadBuf;
    QString    m_fileDownloadDest;
    uint32_t   m_fileExpectedSize = 0;
    uint8_t    m_pendingFileCmd = 0;   // tracks last file op for ACK routing
    bool       m_bankSwapPending = false;
    bool       m_bankErasePending = false;

    /* File upload state machine */
    enum class FileUploadState {
        Idle,
        WaitingStartAck,
        SendingData,
        WaitingFinishAck
    };
    FileUploadState m_fileUploadState = FileUploadState::Idle;
    QByteArray      m_fileUploadData;
    uint32_t        m_fileUploadOffset = 0;
    uint32_t        m_fileUploadSize = 0;
    QTimer          m_fileUploadTimeout;
    void            fileUploadSendNextChunk();

    /* Multi-file upload queue */
    struct UploadQueueItem {
        QString localPath;
        QString remotePath;
    };
    QList<UploadQueueItem> m_uploadQueue;
    int m_uploadQueueIndex = -1;   // -1 = queue inactive
    QStringList m_mkdirQueue;
    int m_mkdirQueueIndex = -1;
    void startUploadQueue();
    void advanceUploadQueue();
    void advanceMkdirQueue();

    /* SD mount state */
    bool m_sdMounted = true;

    /* FW update state machine */
    enum class FwUpdateState {
        Idle,
        WaitingStartAck,
        SendingData,
        WaitingFinishAck
    };
    FwUpdateState m_fwUpdateState = FwUpdateState::Idle;
    QByteArray    m_fwUpdateData;
    uint32_t      m_fwUpdateOffset = 0;
    uint32_t      m_fwUpdateSize = 0;
    QTimer        m_fwUpdateTimeout;

    /* ESP32 update state machine */
    enum class EspUpdateState {
        Idle,
        WaitingStartAck,
        SendingData,
        WaitingFinishAck
    };
    EspUpdateState m_espUpdateState = EspUpdateState::Idle;
    QByteArray     m_espUpdateData;
    uint32_t       m_espUpdateOffset = 0;
    uint32_t       m_espUpdateSize = 0;
    uint32_t       m_espUpdateFlashAddr = 0;
    QTimer         m_espUpdateTimeout;
    bool           m_espUpdateStaleNack = false;  // true after timeout, consumes late NACK
    void           espUpdateSendNextChunk();
};

#endif // M1_DEVICE_H
