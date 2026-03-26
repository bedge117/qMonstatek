/*
 * serial_transport.cpp — QSerialPort wrapper for M1 communication
 */

#include "serial_transport.h"

#include <QDebug>
#ifdef Q_OS_LINUX
#include <QFileInfo>
#include <unistd.h>
#include <grp.h>
#endif

SerialTransport::SerialTransport(QObject *parent)
    : QObject(parent)
{
    connect(&m_port, &QSerialPort::readyRead,
            this, &SerialTransport::onReadyRead);
    connect(&m_port, &QSerialPort::errorOccurred,
            this, &SerialTransport::onError);
}

SerialTransport::~SerialTransport()
{
    close();
}

bool SerialTransport::open(const QString &portName)
{
    if (m_port.isOpen()) {
        close();
    }

    m_port.setPortName(portName);
    m_port.setBaudRate(QSerialPort::Baud115200);
    m_port.setDataBits(QSerialPort::Data8);
    m_port.setParity(QSerialPort::NoParity);
    m_port.setStopBits(QSerialPort::OneStop);
    m_port.setFlowControl(QSerialPort::NoFlowControl);

    if (!m_port.open(QIODevice::ReadWrite)) {
        QString err = QString("Failed to open %1: %2")
                          .arg(portName, m_port.errorString());
#ifdef Q_OS_LINUX
        /* Check if this is a permissions issue and give actionable guidance */
        QFileInfo fi(portName.startsWith("/") ? portName : ("/dev/" + portName));
        if (fi.exists() && !fi.isWritable()) {
            QString group = fi.group();
            if (group.isEmpty()) group = "dialout";
            err += QString("\n\nOn Linux, serial ports require group membership. Run:\n"
                           "  sudo usermod -aG %1 $USER\n"
                           "then log out and back in.").arg(group);
        }
#endif
        qWarning() << err;
        emit errorOccurred(err);
        return false;
    }

    // DTR/RTS control — keep DTR high, RTS low
    // This prevents the STM32 from resetting on connect
    m_port.setDataTerminalReady(true);
    m_port.setRequestToSend(false);

    qInfo() << "Serial port opened:" << portName;
    emit connectionChanged(true);
    return true;
}

void SerialTransport::close()
{
    if (m_port.isOpen()) {
        QString name = m_port.portName();
        m_port.close();
        qInfo() << "Serial port closed:" << name;
        emit connectionChanged(false);
    }
}

qint64 SerialTransport::send(const QByteArray &data)
{
    if (!m_port.isOpen()) {
        return -1;
    }
    return m_port.write(data);
}

bool SerialTransport::isConnected() const
{
    return m_port.isOpen();
}

QString SerialTransport::portName() const
{
    return m_port.portName();
}

void SerialTransport::onReadyRead()
{
    QByteArray data = m_port.readAll();
    if (!data.isEmpty()) {
        emit dataReceived(data);
    }
}

void SerialTransport::onError(QSerialPort::SerialPortError error)
{
    if (error == QSerialPort::NoError) {
        return;
    }

    // Resource error typically means the device was unplugged
    if (error == QSerialPort::ResourceError) {
        qWarning() << "Serial port resource error (device unplugged?)";
        close();
        return;
    }

    QString msg = QString("Serial error (%1): %2")
                      .arg(static_cast<int>(error))
                      .arg(m_port.errorString());
    qWarning() << msg;
    emit errorOccurred(msg);
}
