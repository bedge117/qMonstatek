/*
 * tcp_transport.h — TCP socket transport for WiFi M1 communication
 */

#ifndef TCP_TRANSPORT_H
#define TCP_TRANSPORT_H

#include "abstract_transport.h"
#include <QTcpSocket>
#include <QTimer>
#include <QString>

class TcpTransport : public AbstractTransport {
    Q_OBJECT

public:
    explicit TcpTransport(QObject *parent = nullptr);
    ~TcpTransport() override;

    bool open(const QString &target) override;
    void close() override;
    qint64 send(const QByteArray &data) override;
    bool isConnected() const override;
    QString transportName() const override { return QStringLiteral("WiFi"); }
    QString targetName() const override { return m_target; }

private slots:
    void onConnected();
    void onDisconnected();
    void onReadyRead();
    void onError(QAbstractSocket::SocketError error);

private:
    QTcpSocket m_socket;
    QTimer *m_rxCheckTimer = nullptr;
    QString m_target;
    bool m_connected = false;
};

#endif // TCP_TRANSPORT_H
