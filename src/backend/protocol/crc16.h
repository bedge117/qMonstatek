/*
 * crc16.h — CRC-16/CCITT implementation
 *
 * Polynomial: 0x1021, Initial: 0xFFFF
 * Used for RPC frame integrity checking.
 *
 * Dual-dialect compatibility
 * --------------------------
 * Firmware released before the CRC-table fix shipped a lookup table with 46
 * wrong entries (indices 0x40-0x5F and 0xD7-0xE4). That "legacy" table is a
 * different-but-deterministic CRC. To let a current qMonstatek talk to an old
 * in-field device (e.g. to push the firmware update that fixes it, instead of
 * forcing DFU), this module can compute BOTH dialects:
 *   - crc16_ccitt()        — the correct standard table (current firmware)
 *   - crc16_ccitt_legacy() — the pre-fix corrupted table (old firmware)
 * On connect the transport probes both; the first validated inbound frame
 * latches the peer's dialect and points TX at it. The legacy path is a
 * transitional shim — deletable once the fleet is updated.
 */

#ifndef CRC16_H
#define CRC16_H

#include <cstdint>
#include <cstddef>

namespace rpc {

/** Which CRC table a frame is built/validated with. */
enum class CrcDialect : int {
    Correct = 0,   // standard CRC-16/CCITT (current firmware + qMonstatek)
    Legacy  = 1,   // pre-fix corrupted-table CRC (old in-field firmware)
};

/**
 * Compute CRC-16/CCITT over a byte buffer using the correct standard table.
 * @param data   Pointer to data
 * @param length Number of bytes
 * @param init   Initial CRC value (default 0xFFFF)
 * @return       16-bit CRC
 */
uint16_t crc16_ccitt(const uint8_t *data, size_t length, uint16_t init = 0xFFFF);

/**
 * Compute CRC-16/CCITT using the legacy (pre-fix, corrupted) table. Bit-compatible
 * with old M1/qMonstatek field firmware. Compatibility shim only.
 */
uint16_t crc16_ccitt_legacy(const uint8_t *data, size_t length, uint16_t init = 0xFFFF);

/**
 * Compute a TX CRC using the currently-active dialect (see setTxCrcDialect()).
 */
uint16_t crc16_ccitt_tx(const uint8_t *data, size_t length, uint16_t init = 0xFFFF);

/* ---- Session dialect state (process-global; qMonstatek has one active link) ---- */

/** Set the dialect that buildFrame()/crc16_ccitt_tx() use for outgoing frames. */
void       setTxCrcDialect(CrcDialect d);
/** Current TX dialect (default Correct). */
CrcDialect txCrcDialect();

/**
 * True once a validated inbound frame has latched the peer's dialect since the
 * last resetCrcDialect(). While false, the handshake alternates TX dialects to
 * discover whether the device speaks the correct or the legacy CRC.
 */
bool crcDialectLocked();

/** Clear the latch and reset TX to Correct. Call on every (re)connect. */
void resetCrcDialect();

/**
 * Validate a received frame body against both dialects. Accepts a frame whose
 * trailing CRC matches EITHER table (integrity is preserved — it must still
 * match one of the two). On the first match after resetCrcDialect(), latches
 * the session dialect and repoints TX at whichever matched.
 * @return true if either dialect matched.
 */
bool crc16ValidateRx(const uint8_t *data, size_t length, uint16_t received);

} // namespace rpc

#endif // CRC16_H
