/*
 * serial_transport.h — QSerialPort wrapper for M1 communication
 */

#ifndef SERIAL_TRANSPORT_H
#define SERIAL_TRANSPORT_H

#include "abstract_transport.h"
#include <QSerialPort>
#include <QString>

class SerialTransport : public AbstractTransport {
    Q_OBJECT

public:
    explicit SerialTransport(QObject *parent = nullptr);
    ~SerialTransport() override;

    bool open(const QString &portName) override;
    void close() override;
    qint64 send(const QByteArray &data) override;
    bool isConnected() const override;
    QString transportName() const override { return QStringLiteral("USB"); }
    QString targetName() const override { return m_port.portName(); }

    /** Legacy accessor for port name. */
    QString portName() const { return m_port.portName(); }

private slots:
    void onReadyRead();
    void onError(QSerialPort::SerialPortError error);

private:
    QSerialPort m_port;
};

#endif // SERIAL_TRANSPORT_H
