/*
 * mdns_discovery.cpp — mDNS service browser for M1 WiFi discovery
 *
 * Sends DNS-SD PTR queries for _m1rpc._tcp.local on multicast 224.0.0.251:5353
 * and parses responses to discover M1 devices.
 */

#include "mdns_discovery.h"
#include <QNetworkInterface>
#include <QDebug>
#include <QtEndian>

const QHostAddress MdnsDiscovery::MDNS_ADDR = QHostAddress("224.0.0.251");

MdnsDiscovery::MdnsDiscovery(QObject *parent)
    : QObject(parent)
{
    connect(&m_socket, &QUdpSocket::readyRead,
            this, &MdnsDiscovery::onReadyRead);
    connect(&m_queryTimer, &QTimer::timeout,
            this, &MdnsDiscovery::sendQuery);
}

MdnsDiscovery::~MdnsDiscovery()
{
    stopScan();
}

void MdnsDiscovery::startScan()
{
    if (m_scanning)
        return;

    m_services.clear();
    emit servicesChanged();

    // Bind to mDNS port with multicast
    if (!m_socket.bind(QHostAddress::AnyIPv4, MDNS_PORT,
                       QAbstractSocket::ShareAddress | QAbstractSocket::ReuseAddressHint)) {
        qWarning() << "mDNS: failed to bind:" << m_socket.errorString();
        return;
    }

    // Join multicast group on all interfaces
    bool joined = false;
    for (const auto &iface : QNetworkInterface::allInterfaces()) {
        if (iface.flags().testFlag(QNetworkInterface::IsUp) &&
            iface.flags().testFlag(QNetworkInterface::IsRunning) &&
            !iface.flags().testFlag(QNetworkInterface::IsLoopBack)) {
            if (m_socket.joinMulticastGroup(MDNS_ADDR, iface)) {
                joined = true;
            }
        }
    }

    if (!joined) {
        // Try without specifying interface
        m_socket.joinMulticastGroup(MDNS_ADDR);
    }

    m_scanning = true;
    emit scanningChanged(true);

    // Send initial query, then repeat every 2 seconds for 10 seconds
    sendQuery();
    m_queryTimer.start(2000);

    // Auto-stop after 10 seconds
    QTimer::singleShot(10000, this, &MdnsDiscovery::stopScan);

    qInfo() << "mDNS: scan started for _m1rpc._tcp.local";
}

void MdnsDiscovery::stopScan()
{
    if (!m_scanning)
        return;

    m_queryTimer.stop();
    m_socket.leaveMulticastGroup(MDNS_ADDR);
    m_socket.close();
    m_scanning = false;
    emit scanningChanged(false);
    qInfo() << "mDNS: scan stopped, found" << m_services.size() << "service(s)";
}

QVariantList MdnsDiscovery::servicesAsVariant() const
{
    QVariantList list;
    for (const auto &s : m_services) {
        QVariantMap map;
        map["name"] = s.name;
        map["host"] = s.host;
        map["ip"] = s.ip.toString();
        map["port"] = s.port;
        map["target"] = s.ip.toString() + ":" + QString::number(s.port);
        list.append(map);
    }
    return list;
}

void MdnsDiscovery::sendQuery()
{
    QByteArray query = buildMdnsQuery("_m1rpc._tcp.local");
    m_socket.writeDatagram(query, MDNS_ADDR, MDNS_PORT);
}

QByteArray MdnsDiscovery::buildMdnsQuery(const QString &service)
{
    QByteArray packet;
    QDataStream ds(&packet, QIODevice::WriteOnly);
    ds.setByteOrder(QDataStream::BigEndian);

    // DNS header
    ds << quint16(0);      // Transaction ID
    ds << quint16(0);      // Flags: standard query
    ds << quint16(1);      // Questions: 1
    ds << quint16(0);      // Answer RRs
    ds << quint16(0);      // Authority RRs
    ds << quint16(0);      // Additional RRs

    // Question: _m1rpc._tcp.local PTR
    QStringList parts = service.split('.');
    for (const auto &part : parts) {
        QByteArray label = part.toUtf8();
        packet.append(static_cast<char>(label.size()));
        packet.append(label);
    }
    packet.append('\0');   // Root label

    // Type: PTR (12)
    QByteArray trailer;
    QDataStream ts(&trailer, QIODevice::WriteOnly);
    ts.setByteOrder(QDataStream::BigEndian);
    ts << quint16(12);     // Type PTR
    ts << quint16(1);      // Class IN
    packet.append(trailer);

    return packet;
}

void MdnsDiscovery::onReadyRead()
{
    while (m_socket.hasPendingDatagrams()) {
        QByteArray data;
        data.resize(m_socket.pendingDatagramSize());
        QHostAddress sender;
        m_socket.readDatagram(data.data(), data.size(), &sender);
        parseMdnsResponse(data, sender);
    }
}

QString MdnsDiscovery::readDnsName(const QByteArray &data, int &offset)
{
    QString name;
    int maxJumps = 10;
    int jumps = 0;
    int savedOffset = -1;

    while (offset < data.size() && jumps < maxJumps) {
        uint8_t len = static_cast<uint8_t>(data[offset]);

        if (len == 0) {
            offset++;
            break;
        }

        // Pointer (compression)
        if ((len & 0xC0) == 0xC0) {
            if (offset + 1 >= data.size()) break;
            if (savedOffset < 0) savedOffset = offset + 2;
            offset = ((len & 0x3F) << 8) | static_cast<uint8_t>(data[offset + 1]);
            jumps++;
            continue;
        }

        // Label
        offset++;
        if (offset + len > data.size()) break;
        if (!name.isEmpty()) name += '.';
        name += QString::fromUtf8(data.mid(offset, len));
        offset += len;
    }

    if (savedOffset >= 0) offset = savedOffset;
    return name;
}

void MdnsDiscovery::parseMdnsResponse(const QByteArray &data, const QHostAddress &sender)
{
    if (data.size() < 12) return;

    // Parse header
    quint16 flags = qFromBigEndian<quint16>(data.constData() + 2);
    if (!(flags & 0x8000)) return; // Not a response

    quint16 qdCount = qFromBigEndian<quint16>(data.constData() + 4);
    quint16 anCount = qFromBigEndian<quint16>(data.constData() + 6);
    quint16 nsCount = qFromBigEndian<quint16>(data.constData() + 8);
    quint16 arCount = qFromBigEndian<quint16>(data.constData() + 10);

    int offset = 12;

    // Skip questions
    for (int i = 0; i < qdCount && offset < data.size(); i++) {
        readDnsName(data, offset);
        offset += 4; // type + class
    }

    // Parse all resource records (answer + authority + additional)
    int totalRR = anCount + nsCount + arCount;

    QString srvHost;
    quint16 srvPort = 0;
    QString instanceName;
    QHostAddress resolvedIp;

    for (int i = 0; i < totalRR && offset < data.size(); i++) {
        int rrNameStart = offset;
        QString rrName = readDnsName(data, offset);
        if (offset + 10 > data.size()) break;

        quint16 rrType = qFromBigEndian<quint16>(data.constData() + offset);
        offset += 2;
        quint16 rrClass = qFromBigEndian<quint16>(data.constData() + offset);
        offset += 2;
        Q_UNUSED(rrClass);
        quint32 rrTtl = qFromBigEndian<quint32>(data.constData() + offset);
        offset += 4;
        Q_UNUSED(rrTtl);
        quint16 rdLen = qFromBigEndian<quint16>(data.constData() + offset);
        offset += 2;

        int rdStart = offset;

        if (rrType == 33 && rdLen >= 6) {
            // SRV record: priority(2) + weight(2) + port(2) + target
            offset += 4; // skip priority + weight
            srvPort = qFromBigEndian<quint16>(data.constData() + offset);
            offset += 2;
            srvHost = readDnsName(data, offset);
            instanceName = rrName.section('.', 0, 0); // First label is instance name
        } else if (rrType == 1 && rdLen == 4) {
            // A record: IPv4 address
            resolvedIp = QHostAddress(qFromBigEndian<quint32>(data.constData() + offset));
        }

        // Advance to next RR
        offset = rdStart + rdLen;
    }

    // Use sender IP if no A record found
    if (resolvedIp.isNull() && !sender.isNull()) {
        resolvedIp = sender;
    }

    // Did we find an SRV for our service?
    if (srvPort > 0 && !resolvedIp.isNull()) {
        // Check if this is a response for _m1rpc._tcp.local
        bool isOurs = false;
        for (int i = 0; i < data.size() - 5; i++) {
            // Quick check: look for "_m1rpc" in the response
            if (data.mid(i, 6) == "_m1rpc") {
                isOurs = true;
                break;
            }
        }

        if (!isOurs) return;

        // Check if already known
        for (const auto &existing : m_services) {
            if (existing.ip == resolvedIp && existing.port == srvPort)
                return;
        }

        MdnsService svc;
        svc.name = instanceName.isEmpty() ? srvHost : instanceName;
        svc.host = srvHost;
        svc.ip = resolvedIp;
        svc.port = srvPort;
        m_services.append(svc);

        qInfo() << "mDNS: found M1 device" << svc.name
                << "at" << svc.ip.toString() << ":" << svc.port;

        emit serviceFound(svc.name, svc.ip.toString(), svc.port);
        emit servicesChanged();
    }
}
