/*
 * network_worker.h — WiFi socket worker (runs on a dedicated QThread)
 *
 * Owns the TCP control socket, the UDP screen socket, the RPC frame codec
 * (RX) and the screen framebuffer decoder. Keeps ALL socket I/O, frame
 * parsing and image conversion off the GUI thread (COMMS_REBUILD_SPEC §7).
 *
 * The GUI-thread facade is WifiTransport, which owns the thread and marshals
 * requests/results across it via queued signals.
 */

#ifndef NETWORK_WORKER_H
#define NETWORK_WORKER_H

#include <QObject>
#include <QImage>
#include <QByteArray>
#include <QString>

#include "protocol/rpc_frame.h"
#include "device/screen_buffer.h"

class QTcpSocket;
class QUdpSocket;

class NetworkWorker : public QObject {
    Q_OBJECT

public:
    explicit NetworkWorker(QObject *parent = nullptr);
    ~NetworkWorker() override;

public slots:
    /* All invoked via queued signals from WifiTransport (GUI thread). */
    void connectToHost(const QString &host, quint16 port);
    void disconnectFromHost();
    void writeData(const QByteArray &data);
    void armScreen();     // reset epoch/seq latch; accept a fresh UDP stream
    void disarmScreen();  // stop accepting screen datagrams

signals:
    void connected();
    void disconnected();
    void socketError(const QString &message);
    void screenPortReady(quint16 udpPort);   // local UDP port bound for screen RX
    void controlFrame(rpc::Frame frame);     // a parsed control frame (queued to GUI)
    void screenFrame(QImage image);          // decoded, upscaled screen frame
    void inboundActivity();                  // any inbound TCP bytes (liveness)

private slots:
    void onTcpConnected();
    void onTcpDisconnected();
    void onTcpReadyRead();
    void onTcpError();
    void onUdpReadyRead();
    void onFrameReady(rpc::Frame frame);

private:
    QTcpSocket      *m_tcp   = nullptr;
    QUdpSocket      *m_udp   = nullptr;
    rpc::FrameCodec *m_codec = nullptr;
    ScreenBuffer     m_screen;

    quint16  m_udpPort      = 0;
    bool     m_screenActive = false;
    bool     m_epochKnown   = false;
    quint32  m_epoch        = 0;
    int      m_lastSeq      = -1;   // -1 = no frame yet

    // Outbound control frames written while the socket is briefly between
    // connections (WiFi auto-reconnect). Buffered here and flushed on
    // (re)connect so a burst of button/nav commands isn't silently lost.
    QList<QByteArray> m_pendingTx;
    static constexpr int kMaxPendingTx = 64;
};

#endif // NETWORK_WORKER_H
