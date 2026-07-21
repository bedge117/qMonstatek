/*
 * network_worker.cpp — WiFi socket worker (runs on a dedicated QThread)
 */

#include "network_worker.h"
#include "protocol/rpc_protocol.h"   // rpc::CMD_SCREEN_FRAME

#include <QTcpSocket>
#include <QUdpSocket>
#include <QHostAddress>
#include <QDebug>

/* UDP screen datagram (COMMS_REBUILD_SPEC §2, little-endian):
 *   [0x53 0x43]        magic "SC" (2)
 *   [frame_seq:u16 LE] (2)
 *   [epoch:u32 LE]     (4)
 *   [fb:1024 bytes]
 * Total 1032 bytes. */
static constexpr int      SCREEN_DGRAM_SIZE = 1032;
static constexpr uint8_t  SCREEN_MAGIC0     = 0x53;  // 'S'
static constexpr uint8_t  SCREEN_MAGIC1     = 0x43;  // 'C'
static constexpr int      SCREEN_FB_OFFSET  = 8;
static constexpr int      SCREEN_FB_LEN     = 1024;

NetworkWorker::NetworkWorker(QObject *parent)
    : QObject(parent)
{
    // Sockets + codec are created here (parented to this) so moveToThread()
    // carries them onto the worker thread along with us.
    m_tcp   = new QTcpSocket(this);
    m_udp   = new QUdpSocket(this);
    m_codec = new rpc::FrameCodec(this);

    connect(m_tcp, &QTcpSocket::connected,    this, &NetworkWorker::onTcpConnected);
    connect(m_tcp, &QTcpSocket::disconnected, this, &NetworkWorker::onTcpDisconnected);
    connect(m_tcp, &QTcpSocket::readyRead,    this, &NetworkWorker::onTcpReadyRead);
    connect(m_tcp, &QTcpSocket::errorOccurred, this, &NetworkWorker::onTcpError);

    connect(m_udp, &QUdpSocket::readyRead, this, &NetworkWorker::onUdpReadyRead);

    connect(m_codec, &rpc::FrameCodec::frameReady, this, &NetworkWorker::onFrameReady);
}

NetworkWorker::~NetworkWorker() = default;

void NetworkWorker::connectToHost(const QString &host, quint16 port)
{
    if (m_tcp->state() != QAbstractSocket::UnconnectedState)
        m_tcp->abort();

    // Bind the UDP screen socket to an OS-assigned ephemeral port once; the
    // port is sent to the ESP in the extended SCREEN_START payload.
    if (m_udpPort == 0) {
        if (m_udp->bind(QHostAddress::AnyIPv4, 0)) {
            m_udpPort = m_udp->localPort();
            qInfo() << "NetworkWorker: UDP screen socket bound to port" << m_udpPort;
        } else {
            qWarning() << "NetworkWorker: UDP bind failed:" << m_udp->errorString();
        }
    }
    emit screenPortReady(m_udpPort);

    qInfo() << "NetworkWorker: TCP connecting to" << host << ":" << port;
    m_tcp->connectToHost(host, port);
}

void NetworkWorker::disconnectFromHost()
{
    m_pendingTx.clear();     // user-initiated close: don't replay stale commands
    m_screenActive = false;
    if (m_tcp->state() != QAbstractSocket::UnconnectedState) {
        // Graceful FIN so the ESP/M1 tear down the route cleanly.
        m_tcp->disconnectFromHost();
    }
}

void NetworkWorker::writeData(const QByteArray &data)
{
    const int cmd = (data.size() >= 2) ? static_cast<uint8_t>(data.at(1)) : -1;
    if (m_tcp->state() != QAbstractSocket::ConnectedState) {
        // Not connected (typically a brief WiFi auto-reconnect window). Buffer
        // the frame instead of dropping it — a button/nav burst pressed during
        // the gap would otherwise vanish while the every-3s ping recovers.
        if (m_pendingTx.size() < kMaxPendingTx) {
            m_pendingTx.append(data);
            qWarning() << "NetworkWorker: write QUEUED cmd=0x" << Qt::hex << cmd
                       << Qt::dec << "(reconnecting, pending=" << m_pendingTx.size() << ")";
        } else {
            qWarning() << "NetworkWorker: write DROPPED cmd=0x" << Qt::hex << cmd
                       << Qt::dec << "(pending buffer full)";
        }
        return;
    }
    m_tcp->write(data);
}

void NetworkWorker::armScreen()
{
    m_screenActive = true;
    m_epochKnown   = false;
    m_lastSeq      = -1;
}

void NetworkWorker::disarmScreen()
{
    m_screenActive = false;
}

void NetworkWorker::onTcpConnected()
{
    m_tcp->setSocketOption(QAbstractSocket::LowDelayOption, 1);
    m_codec->reset();
    qInfo() << "NetworkWorker: TCP connected"
            << "local=" << m_tcp->localAddress().toString() << ":" << m_tcp->localPort()
            << "peer="  << m_tcp->peerAddress().toString()  << ":" << m_tcp->peerPort();

    // Flush any control frames buffered during the reconnect gap.
    if (!m_pendingTx.isEmpty()) {
        qInfo() << "NetworkWorker: flushing" << m_pendingTx.size() << "buffered TX frames";
        for (const QByteArray &f : m_pendingTx)
            m_tcp->write(f);
        m_pendingTx.clear();
    }

    emit connected();
}

void NetworkWorker::onTcpDisconnected()
{
    m_screenActive = false;
    m_epochKnown   = false;
    m_lastSeq      = -1;
    qInfo() << "NetworkWorker: TCP disconnected";
    emit disconnected();
}

void NetworkWorker::onTcpReadyRead()
{
    QByteArray data = m_tcp->readAll();
    if (data.isEmpty())
        return;
    emit inboundActivity();      // any inbound byte keeps the link alive (§3)
    m_codec->feed(data);
}

void NetworkWorker::onTcpError()
{
    emit socketError(m_tcp->errorString());
    // Hard errors (refused/reset/timeout) may not raise disconnected() on their
    // own — surface it once the socket has actually fallen unconnected.
    if (m_tcp->state() == QAbstractSocket::UnconnectedState)
        emit disconnected();
}

void NetworkWorker::onFrameReady(rpc::Frame frame)
{
    // Screen rides the separate UDP channel (onUdpReadyRead); control frames pass
    // through to the GUI thread here.
    emit controlFrame(frame);
}

void NetworkWorker::onUdpReadyRead()
{
    while (m_udp->hasPendingDatagrams()) {
        const qint64 sz = m_udp->pendingDatagramSize();
        QByteArray buf;
        buf.resize(static_cast<int>(sz));
        m_udp->readDatagram(buf.data(), sz);

        if (!m_screenActive)                 continue;
        if (buf.size() != SCREEN_DGRAM_SIZE) continue;

        const uint8_t *p = reinterpret_cast<const uint8_t *>(buf.constData());
        if (p[0] != SCREEN_MAGIC0 || p[1] != SCREEN_MAGIC1)
            continue;   // wrong magic

        const quint16 seq = static_cast<quint16>(p[2] | (p[3] << 8));
        const quint32 epoch = static_cast<quint32>(p[4])
                            | (static_cast<quint32>(p[5]) << 8)
                            | (static_cast<quint32>(p[6]) << 16)
                            | (static_cast<quint32>(p[7]) << 24);

        // Latch the epoch of the stream we started; drop anything else (stale).
        if (!m_epochKnown) {
            m_epoch = epoch;
            m_epochKnown = true;
        } else if (epoch != m_epoch) {
            continue;
        }

        // frame_seq drops duplicates / out-of-order (u16 wrap-aware).
        if (m_lastSeq >= 0) {
            const quint16 delta =
                static_cast<quint16>(seq - static_cast<quint16>(m_lastSeq));
            if (delta == 0 || delta > 0x7FFF)
                continue;
        }
        m_lastSeq = seq;

        if (m_screen.update(buf.mid(SCREEN_FB_OFFSET, SCREEN_FB_LEN)))
            emit screenFrame(m_screen.toImage());   // decode on the worker thread
    }
}
