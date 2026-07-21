/*
 * abstract_transport.h — Base class for M1 communication transports
 *
 * Provides a common interface for serial (USB) and TCP (WiFi) transports.
 */

#ifndef ABSTRACT_TRANSPORT_H
#define ABSTRACT_TRANSPORT_H

#include <QObject>
#include <QByteArray>
#include <QString>

class AbstractTransport : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectionChanged)

public:
    explicit AbstractTransport(QObject *parent = nullptr) : QObject(parent) {}
    virtual ~AbstractTransport() = default;

    /**
     * Open a connection to the specified target.
     * For serial: target is a port name (e.g., "COM3")
     * For TCP:    target is "host:port" (e.g., "192.168.1.50:3333")
     */
    virtual bool open(const QString &target) = 0;

    /** Close the connection. */
    virtual void close() = 0;

    /** Send raw bytes. Returns bytes written or -1 on error. */
    virtual qint64 send(const QByteArray &data) = 0;

    /** Check if connected. */
    virtual bool isConnected() const = 0;

    /** Human-readable transport name (e.g., "USB" or "WiFi"). */
    virtual QString transportName() const = 0;

    /** Connection target (port name or ip:port). */
    virtual QString targetName() const = 0;

signals:
    void dataReceived(const QByteArray &data);
    void connectionChanged(bool connected);
    void errorOccurred(const QString &message);
};

#endif // ABSTRACT_TRANSPORT_H
