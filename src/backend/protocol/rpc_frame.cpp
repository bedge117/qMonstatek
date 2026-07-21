/*
 * rpc_frame.cpp — RPC Frame encoder/decoder
 */

#include "rpc_frame.h"
#include "rpc_protocol.h"
#include "crc16.h"

#include <QDebug>

namespace rpc {

FrameCodec::FrameCodec(QObject *parent)
    : QObject(parent)
{
}

QByteArray FrameCodec::buildFrame(uint8_t cmd, uint8_t seq,
                                   const QByteArray &payload)
{
    return buildFrame(cmd, seq,
                      reinterpret_cast<const uint8_t*>(payload.constData()),
                      static_cast<uint16_t>(payload.size()));
}

QByteArray FrameCodec::buildFrame(uint8_t cmd, uint8_t seq,
                                   const uint8_t *payload, uint16_t len)
{
    QByteArray frame;
    frame.reserve(HEADER_SIZE + len + CRC_SIZE);

    // Sync byte
    frame.append(static_cast<char>(SYNC_BYTE));

    // Command
    frame.append(static_cast<char>(cmd));

    // Sequence number
    frame.append(static_cast<char>(seq));

    // Payload length (little-endian)
    frame.append(static_cast<char>(len & 0xFF));
    frame.append(static_cast<char>((len >> 8) & 0xFF));

    // Payload
    if (len > 0 && payload) {
        frame.append(reinterpret_cast<const char*>(payload), len);
    }

    // CRC-16 over CMD through PAYLOAD (bytes 1..N, skipping SYNC). Uses the
    // active TX dialect so we can address old (legacy-CRC) firmware too.
    uint16_t crc = crc16_ccitt_tx(
        reinterpret_cast<const uint8_t*>(frame.constData() + 1),
        static_cast<size_t>(frame.size() - 1)
    );
    frame.append(static_cast<char>(crc & 0xFF));
    frame.append(static_cast<char>((crc >> 8) & 0xFF));

    return frame;
}

void FrameCodec::feed(const QByteArray &data)
{
    for (int i = 0; i < data.size(); ++i) {
        processByte(static_cast<uint8_t>(data.at(i)));
    }
}

void FrameCodec::reset()
{
    m_state = State::WaitSync;
    m_headerBuf.clear();
    m_payloadBuf.clear();
    m_crcBuf.clear();
    m_cmd = 0;
    m_seq = 0;
    m_payloadLen = 0;
    m_seqCounter = 0;
}

uint8_t FrameCodec::nextSeq()
{
    return m_seqCounter++;
}

void FrameCodec::processByte(uint8_t byte)
{
    switch (m_state) {

    case State::WaitSync:
        if (byte == SYNC_BYTE) {
            m_headerBuf.clear();
            m_state = State::ReadHeader;
        }
        break;

    case State::ReadHeader:
        m_headerBuf.append(static_cast<char>(byte));
        if (m_headerBuf.size() == 4) {
            // Parse: CMD(1) + SEQ(1) + LEN(2 LE)
            m_cmd = static_cast<uint8_t>(m_headerBuf.at(0));
            m_seq = static_cast<uint8_t>(m_headerBuf.at(1));
            m_payloadLen = static_cast<uint16_t>(
                (static_cast<uint8_t>(m_headerBuf.at(2))) |
                (static_cast<uint8_t>(m_headerBuf.at(3)) << 8)
            );

            if (m_payloadLen > MAX_PAYLOAD) {
                // Invalid length — abort and re-sync
                qWarning() << "RPC: payload length" << m_payloadLen
                           << "exceeds max" << MAX_PAYLOAD << "- resync";
                m_state = State::WaitSync;
                break;
            }

            m_payloadBuf.clear();
            m_payloadBuf.reserve(m_payloadLen);

            if (m_payloadLen == 0) {
                // No payload — go straight to CRC
                m_crcBuf.clear();
                m_state = State::ReadCrc;
            } else {
                m_state = State::ReadPayload;
            }
        }
        break;

    case State::ReadPayload:
        m_payloadBuf.append(static_cast<char>(byte));
        if (m_payloadBuf.size() == m_payloadLen) {
            m_crcBuf.clear();
            m_state = State::ReadCrc;
        }
        break;

    case State::ReadCrc:
        m_crcBuf.append(static_cast<char>(byte));
        if (m_crcBuf.size() == 2) {
            finalizeFrame();
            m_state = State::WaitSync;
        }
        break;
    }
}

void FrameCodec::finalizeFrame()
{
    // Reconstruct the data that was CRC'd: CMD + SEQ + LEN + PAYLOAD
    QByteArray crcData;
    crcData.reserve(4 + m_payloadLen);
    crcData.append(m_headerBuf);       // CMD + SEQ + LEN(2)
    crcData.append(m_payloadBuf);      // PAYLOAD

    uint16_t received = static_cast<uint16_t>(
        (static_cast<uint8_t>(m_crcBuf.at(0))) |
        (static_cast<uint8_t>(m_crcBuf.at(1)) << 8)
    );

    // Accept a frame whose CRC matches EITHER dialect (correct or legacy). The
    // first match after connect latches the peer's dialect for TX.
    if (!crc16ValidateRx(
            reinterpret_cast<const uint8_t*>(crcData.constData()),
            static_cast<size_t>(crcData.size()), received)) {
        qWarning() << "RPC: CRC mismatch for cmd" << Qt::hex << m_cmd
                   << "seq" << m_seq << "received:" << received;
        emit frameCrcError(m_cmd, m_seq);
        return;
    }

    Frame frame;
    frame.cmd = m_cmd;
    frame.seq = m_seq;
    frame.payload = m_payloadBuf;

    emit frameReady(frame);
}

} // namespace rpc
