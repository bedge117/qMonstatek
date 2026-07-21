/*
 * wifi_transport.h — GUI-thread facade for the threaded WiFi transport
 *
 * Presents the usual AbstractTransport API (open/close/send/isConnected) while
 * all socket I/O, frame parsing and screen decode run on a worker QThread
 * (NetworkWorker). Control frames, decoded screen frames and inbound-activity
 * ticks are surfaced as queued signals for M1Device to consume on the GUI
 * thread (COMMS_REBUILD_SPEC §7).
 *
 * open() is non-blocking: it starts the connection attempt and returns; the
 * result arrives later via connectionChanged()/errorOccurred().
 */

#ifndef WIFI_TRANSPORT_H
#define WIFI_TRANSPORT_H

#include "abstract_transport.h"
#include "network_worker.h"

#include <QThread>
#include <QImage>
#include <QString>

class WifiTransport : public AbstractTransport {
    Q_OBJECT

public:
    explicit WifiTransport(QObject *parent = nullptr);
    ~WifiTransport() override;

    bool open(const QString &target) override;    // async; true = attempt started
    void close() override;
    qint64 send(const QByteArray &data) override;
    bool isConnected() const override { return m_connected; }
    QString transportName() const override { return QStringLiteral("WiFi"); }
    QString targetName() const override { return m_target; }

    /* Local UDP port bound for screen RX (sent in the extended SCREEN_START). */
    quint16 udpScreenPort() const { return m_udpPort; }

    /* Screen stream lifecycle (arms/disarms UDP acceptance + epoch latch). */
    void armScreen();
    void disarmScreen();

signals:
    /* Surfaced to M1Device (in addition to the AbstractTransport signals). */
    void controlFrame(rpc::Frame frame);
    void screenFrame(QImage image);
    void inboundActivity();

    /* Internal: GUI thread → worker thread (queued). */
    void requestConnect(const QString &host, quint16 port);
    void requestDisconnect();
    void requestWrite(const QByteArray &data);
    void requestArm();
    void requestDisarm();

private slots:
    void onWorkerConnected();
    void onWorkerDisconnected();
    void onWorkerError(const QString &msg);
    void onScreenPortReady(quint16 port);

private:
    QThread        m_thread;
    NetworkWorker *m_worker = nullptr;
    QString        m_target;
    bool           m_connected = false;
    quint16        m_udpPort = 0;
};

#endif // WIFI_TRANSPORT_H
