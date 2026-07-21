/*
 * tcp_transport.cpp — TCP socket transport for WiFi M1 communication
 */

#include "tcp_transport.h"
#include <QDebug>

TcpTransport::TcpTransport(QObject *parent)
    : AbstractTransport(parent)
{
    connect(&m_socket, &QTcpSocket::connected,
            this, &TcpTransport::onConnected);
    connect(&m_socket, &QTcpSocket::disconnected,
            this, &TcpTransport::onDisconnected);
    connect(&m_socket, &QTcpSocket::readyRead,
            this, &TcpTransport::onReadyRead);
    connect(&m_socket, &QTcpSocket::errorOccurred,
            this, &TcpTransport::onError);
}

TcpTransport::~TcpTransport()
{
    close();
}

bool TcpTransport::open(const QString &target)
{
    if (m_connected) {
        close();
    }

    // Parse "host:port"
    int colonIdx = target.lastIndexOf(':');
    if (colonIdx <= 0) {
        emit errorOccurred("Invalid target format. Use host:port (e.g., 192.168.1.50:3333)");
        return false;
    }

    QString host = target.left(colonIdx);
    bool ok;
    quint16 port = target.mid(colonIdx + 1).toUShort(&ok);
    if (!ok || port == 0) {
        emit errorOccurred("Invalid port number");
        return false;
    }

    m_target = target;
    qInfo() << "TCP connecting to" << host << ":" << port;

    m_socket.connectToHost(host, port);

    // Wait for connection with timeout
    if (!m_socket.waitForConnected(3000)) {
        QString err = QString("TCP connection to %1 failed: %2")
                          .arg(target, m_socket.errorString());
        qWarning() << err;
        emit errorOccurred(err);
        return false;
    }

    return true;
}

void TcpTransport::close()
{
    if (m_socket.state() != QAbstractSocket::UnconnectedState) {
        QString target = m_target;
        m_socket.disconnectFromHost();
        if (m_socket.state() != QAbstractSocket::UnconnectedState) {
            m_socket.waitForDisconnected(1000);
        }
        if (m_connected) {
            m_connected = false;
            qInfo() << "TCP disconnected from" << target;
            emit connectionChanged(false);
        }
    }
}

qint64 TcpTransport::send(const QByteArray &data)
{
    if (!m_connected) {
        qWarning() << "TCP send: not connected, dropping" << data.size() << "bytes";
        return -1;
    }
    qint64 written = m_socket.write(data);
    qInfo() << "TCP TX:" << written << "bytes" << data.toHex(' ').left(80);
    return written;
}

bool TcpTransport::isConnected() const
{
    return m_connected;
}

void TcpTransport::onConnected()
{
    m_connected = true;
    m_socket.setSocketOption(QAbstractSocket::LowDelayOption, 1);
    qInfo() << "TCP connected to" << m_target
            << "local=" << m_socket.localAddress().toString() << ":" << m_socket.localPort()
            << "peer=" << m_socket.peerAddress().toString() << ":" << m_socket.peerPort()
            << "state=" << m_socket.state();

    // Periodic socket health check
    if (!m_rxCheckTimer) {
        m_rxCheckTimer = new QTimer(this);
        m_rxCheckTimer->setInterval(3000);
        connect(m_rxCheckTimer, &QTimer::timeout, this, [this]() {
            qInfo() << "TCP socket health: state=" << m_socket.state()
                    << "bytesAvail=" << m_socket.bytesAvailable()
                    << "connected=" << m_connected;
            if (m_socket.bytesAvailable() > 0) {
                qWarning() << "TCP: bytes available but readyRead not firing! Forcing read.";
                onReadyRead();
            }
        });
    }
    m_rxCheckTimer->start();

    emit connectionChanged(true);
}

void TcpTransport::onDisconnected()
{
    if (m_rxCheckTimer) m_rxCheckTimer->stop();
    if (m_connected) {
        m_connected = false;
        qInfo() << "TCP disconnected from" << m_target;
        emit connectionChanged(false);
    }
}

void TcpTransport::onReadyRead()
{
    QByteArray data = m_socket.readAll();
    if (!data.isEmpty()) {
        qInfo() << "TCP RX:" << data.size() << "bytes" << data.toHex(' ').left(80);
        emit dataReceived(data);
    }
}

void TcpTransport::onError(QAbstractSocket::SocketError error)
{
    Q_UNUSED(error);

    // Connection refused or reset typically means device went away
    if (error == QAbstractSocket::RemoteHostClosedError ||
        error == QAbstractSocket::ConnectionRefusedError ||
        error == QAbstractSocket::NetworkError) {
        qWarning() << "TCP socket error (device disconnected?):" << m_socket.errorString();
        if (m_connected) {
            m_connected = false;
            m_socket.abort();
            emit connectionChanged(false);
        }
        return;
    }

    QString msg = QString("TCP error (%1): %2")
                      .arg(static_cast<int>(error))
                      .arg(m_socket.errorString());
    qWarning() << msg;
    emit errorOccurred(msg);
}
