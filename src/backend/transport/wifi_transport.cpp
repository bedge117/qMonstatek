/*
 * wifi_transport.cpp — GUI-thread facade for the threaded WiFi transport
 */

#include "wifi_transport.h"
#include <QDebug>

WifiTransport::WifiTransport(QObject *parent)
    : AbstractTransport(parent)
{
    m_worker = new NetworkWorker;          // no parent — owned by the worker thread
    m_worker->moveToThread(&m_thread);

    // worker → facade (queued across threads)
    connect(m_worker, &NetworkWorker::connected,       this, &WifiTransport::onWorkerConnected);
    connect(m_worker, &NetworkWorker::disconnected,    this, &WifiTransport::onWorkerDisconnected);
    connect(m_worker, &NetworkWorker::socketError,     this, &WifiTransport::onWorkerError);
    connect(m_worker, &NetworkWorker::screenPortReady, this, &WifiTransport::onScreenPortReady);
    connect(m_worker, &NetworkWorker::controlFrame,    this, &WifiTransport::controlFrame);
    connect(m_worker, &NetworkWorker::screenFrame,     this, &WifiTransport::screenFrame);
    connect(m_worker, &NetworkWorker::inboundActivity, this, &WifiTransport::inboundActivity);

    // facade → worker (queued across threads)
    connect(this, &WifiTransport::requestConnect,    m_worker, &NetworkWorker::connectToHost);
    connect(this, &WifiTransport::requestDisconnect, m_worker, &NetworkWorker::disconnectFromHost);
    connect(this, &WifiTransport::requestWrite,      m_worker, &NetworkWorker::writeData);
    connect(this, &WifiTransport::requestArm,        m_worker, &NetworkWorker::armScreen);
    connect(this, &WifiTransport::requestDisarm,     m_worker, &NetworkWorker::disarmScreen);

    m_thread.start();
}

WifiTransport::~WifiTransport()
{
    m_thread.quit();
    m_thread.wait();
    delete m_worker;   // thread has stopped — safe to delete here
    m_worker = nullptr;
}

bool WifiTransport::open(const QString &target)
{
    // Parse "host:port"
    int colonIdx = target.lastIndexOf(':');
    if (colonIdx <= 0) {
        emit errorOccurred("Invalid target format. Use host:port (e.g., 192.168.1.50:3333)");
        return false;
    }
    QString host = target.left(colonIdx);
    bool ok = false;
    quint16 port = target.mid(colonIdx + 1).toUShort(&ok);
    if (!ok || port == 0) {
        emit errorOccurred("Invalid port number");
        return false;
    }

    m_target = target;
    qInfo() << "WiFi: connecting (async) to" << host << ":" << port;
    emit requestConnect(host, port);   // non-blocking; result via connectionChanged()
    return true;
}

void WifiTransport::close()
{
    emit requestDisconnect();
}

qint64 WifiTransport::send(const QByteArray &data)
{
    emit requestWrite(data);
    return data.size();   // optimistic — the actual write happens on the worker
}

void WifiTransport::armScreen()    { emit requestArm(); }
void WifiTransport::disarmScreen() { emit requestDisarm(); }

void WifiTransport::onWorkerConnected()
{
    m_connected = true;
    qInfo() << "WiFi: connected to" << m_target;
    emit connectionChanged(true);
}

void WifiTransport::onWorkerDisconnected()
{
    if (m_connected) {
        m_connected = false;
        qInfo() << "WiFi: disconnected from" << m_target;
        emit connectionChanged(false);
    }
}

void WifiTransport::onWorkerError(const QString &msg)
{
    qWarning() << "WiFi socket error:" << msg;
    emit errorOccurred(QString("WiFi error: %1").arg(msg));
}

void WifiTransport::onScreenPortReady(quint16 port)
{
    m_udpPort = port;
}
