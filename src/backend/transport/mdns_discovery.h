/*
 * mdns_discovery.h — mDNS service browser for M1 WiFi discovery
 *
 * Sends mDNS queries for _m1rpc._tcp.local and parses responses
 * to discover M1 devices on the local network.
 */

#ifndef MDNS_DISCOVERY_H
#define MDNS_DISCOVERY_H

#include <QObject>
#include <QUdpSocket>
#include <QTimer>
#include <QVariantList>
#include <QHostAddress>

struct MdnsService {
    QString name;       // e.g., "m1-device"
    QString host;       // e.g., "m1-device.local"
    QHostAddress ip;    // resolved IP address
    quint16 port;       // e.g., 3333
};

class MdnsDiscovery : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList services READ servicesAsVariant NOTIFY servicesChanged)
    Q_PROPERTY(bool scanning READ isScanning NOTIFY scanningChanged)

public:
    explicit MdnsDiscovery(QObject *parent = nullptr);
    ~MdnsDiscovery() override;

    Q_INVOKABLE void startScan();
    Q_INVOKABLE void stopScan();
    bool isScanning() const { return m_scanning; }
    QVariantList servicesAsVariant() const;

signals:
    void servicesChanged();
    void scanningChanged(bool scanning);
    void serviceFound(const QString &name, const QString &address, int port);

private slots:
    void onReadyRead();
    void sendQuery();

private:
    void parseMdnsResponse(const QByteArray &data, const QHostAddress &sender);
    QByteArray buildMdnsQuery(const QString &service);
    QString readDnsName(const QByteArray &data, int &offset);

    QUdpSocket m_socket;
    QTimer m_queryTimer;
    QList<MdnsService> m_services;
    bool m_scanning = false;

    static const QHostAddress MDNS_ADDR;
    static const quint16 MDNS_PORT = 5353;
};

#endif // MDNS_DISCOVERY_H
