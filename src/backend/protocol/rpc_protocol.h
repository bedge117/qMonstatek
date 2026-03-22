/*
 * rpc_protocol.h — M1 RPC Protocol Definitions
 *
 * Shared command IDs and constants for the binary RPC protocol
 * between qMonstatek desktop app and M1 firmware.
 *
 * Frame format:
 *   [0xAA] [CMD:1] [SEQ:1] [LEN:2 LE] [PAYLOAD:0-1200] [CRC16:2]
 *
 * CRC-16/CCITT (poly 0x1021, init 0xFFFF) over CMD through PAYLOAD.
 */

#ifndef RPC_PROTOCOL_H
#define RPC_PROTOCOL_H

#include <cstdint>

namespace rpc {

/* Frame constants */
constexpr uint8_t  SYNC_BYTE       = 0xAA;
constexpr uint16_t HEADER_SIZE     = 5;     // SYNC + CMD + SEQ + LEN(2)
constexpr uint16_t CRC_SIZE        = 2;
constexpr uint16_t MAX_PAYLOAD     = 8192;
constexpr uint16_t MAX_FRAME_SIZE  = HEADER_SIZE + MAX_PAYLOAD + CRC_SIZE;
constexpr uint16_t SCREEN_FB_SIZE  = 1024;  // 128x64 / 8

/* Timeout and retry */
constexpr int CMD_TIMEOUT_MS  = 500;
constexpr int CMD_MAX_RETRIES = 3;

/* ──────────── System Commands (0x00–0x0F) ──────────── */
constexpr uint8_t CMD_PING             = 0x01;
constexpr uint8_t CMD_PONG             = 0x02;
constexpr uint8_t CMD_GET_DEVICE_INFO  = 0x03;
constexpr uint8_t CMD_DEVICE_INFO_RESP = 0x04;
constexpr uint8_t CMD_REBOOT           = 0x05;
constexpr uint8_t CMD_ACK              = 0x06;
constexpr uint8_t CMD_NACK             = 0x07;
constexpr uint8_t CMD_POWER_OFF        = 0x08;

/* ──────────── Screen Commands (0x10–0x1F) ──────────── */
constexpr uint8_t CMD_SCREEN_START     = 0x10;
constexpr uint8_t CMD_SCREEN_STOP      = 0x11;
constexpr uint8_t CMD_SCREEN_FRAME     = 0x12;
constexpr uint8_t CMD_SCREEN_CAPTURE   = 0x13;

/* ──────────── Input Commands (0x20–0x2F) ──────────── */
constexpr uint8_t CMD_BUTTON_PRESS     = 0x20;
constexpr uint8_t CMD_BUTTON_RELEASE   = 0x21;
constexpr uint8_t CMD_BUTTON_CLICK     = 0x22;

/* ──────────── File Commands (0x30–0x3F) ──────────── */
constexpr uint8_t CMD_FILE_LIST        = 0x30;
constexpr uint8_t CMD_FILE_LIST_RESP   = 0x31;
constexpr uint8_t CMD_FILE_READ        = 0x32;
constexpr uint8_t CMD_FILE_READ_DATA   = 0x33;
constexpr uint8_t CMD_FILE_WRITE_START = 0x34;
constexpr uint8_t CMD_FILE_WRITE_DATA  = 0x35;
constexpr uint8_t CMD_FILE_WRITE_FINISH= 0x36;
constexpr uint8_t CMD_FILE_DELETE      = 0x37;
constexpr uint8_t CMD_FILE_MKDIR       = 0x38;
constexpr uint8_t CMD_FILE_INFO        = 0x39;
constexpr uint8_t CMD_FILE_INFO_RESP   = 0x3A;
constexpr uint8_t CMD_SD_UNMOUNT       = 0x3B;
constexpr uint8_t CMD_SD_MOUNT         = 0x3C;

/* ──────────── Firmware Commands (0x40–0x4F) ──────────── */
constexpr uint8_t CMD_FW_INFO          = 0x40;
constexpr uint8_t CMD_FW_INFO_RESP     = 0x41;
constexpr uint8_t CMD_FW_UPDATE_START  = 0x42;
constexpr uint8_t CMD_FW_UPDATE_DATA   = 0x43;
constexpr uint8_t CMD_FW_UPDATE_FINISH = 0x44;
constexpr uint8_t CMD_FW_BANK_SWAP     = 0x45;
constexpr uint8_t CMD_FW_DFU_ENTER     = 0x46;
constexpr uint8_t CMD_FW_BANK_ERASE    = 0x47;

/* ──────────── ESP32 Commands (0x50–0x5F) ──────────── */
constexpr uint8_t CMD_ESP_INFO         = 0x50;
constexpr uint8_t CMD_ESP_INFO_RESP    = 0x51;
constexpr uint8_t CMD_ESP_UPDATE_START = 0x52;
constexpr uint8_t CMD_ESP_UPDATE_DATA  = 0x53;
constexpr uint8_t CMD_ESP_UPDATE_FINISH= 0x54;

/* ──────────── Debug / CLI Commands (0x60–0x6F) ──────────── */
constexpr uint8_t CMD_CLI_EXEC              = 0x60;
constexpr uint8_t CMD_CLI_RESP              = 0x61;
constexpr uint8_t CMD_ESP_UART_SNOOP        = 0x62;
constexpr uint8_t CMD_ESP_UART_SNOOP_RESP   = 0x63;

/* ──────────── Button IDs (match m1_system.h) ──────────── */
constexpr uint8_t BUTTON_OK    = 0;
constexpr uint8_t BUTTON_UP    = 1;
constexpr uint8_t BUTTON_LEFT  = 2;
constexpr uint8_t BUTTON_RIGHT = 3;
constexpr uint8_t BUTTON_DOWN  = 4;
constexpr uint8_t BUTTON_BACK  = 5;

/* ──────────── NACK Error Codes ──────────── */
constexpr uint8_t ERR_UNKNOWN_CMD     = 0x01;
constexpr uint8_t ERR_INVALID_PAYLOAD = 0x02;
constexpr uint8_t ERR_BUSY            = 0x03;
constexpr uint8_t ERR_SD_NOT_READY    = 0x04;
constexpr uint8_t ERR_FILE_NOT_FOUND  = 0x05;
constexpr uint8_t ERR_FILE_EXISTS     = 0x06;
constexpr uint8_t ERR_FLASH_ERROR     = 0x07;
constexpr uint8_t ERR_CRC_MISMATCH   = 0x08;
constexpr uint8_t ERR_SIZE_TOO_LARGE = 0x09;
constexpr uint8_t ERR_BANK_EMPTY     = 0x0A;
constexpr uint8_t ERR_ESP_FLASH      = 0x0B;

/* ESP32 flash sub-error codes (2nd NACK payload byte when ERR_ESP_FLASH) */
constexpr uint8_t ESP_SUB_CONNECT    = 0x01;  // connect_to_target failed
constexpr uint8_t ESP_SUB_ERASE      = 0x02;  // flash erase failed
constexpr uint8_t ESP_SUB_WRITE      = 0x03;  // flash write failed
constexpr uint8_t ESP_SUB_VERIFY     = 0x04;  // MD5 verify failed

/* ──────────── Device Info Response Structure ──────────── */
#pragma pack(push, 1)
struct DeviceInfoPayload {
    uint32_t magic;              // 0x4D314649 ("M1FI")
    uint8_t  fw_version_major;
    uint8_t  fw_version_minor;
    uint8_t  fw_version_build;
    uint8_t  fw_version_rc;
    uint16_t active_bank;        // 0x534A = Bank1, 0x1F41 = Bank2
    uint8_t  battery_level;      // 0-100
    uint8_t  battery_charging;   // 0 = discharging, 1 = charging
    uint8_t  sd_card_present;    // 0 = absent, 1 = present
    uint32_t sd_total_kb;        // SD total capacity in KB
    uint32_t sd_free_kb;         // SD free capacity in KB
    uint8_t  esp32_ready;        // 0 = not init, 1 = ready
    char     esp32_version[32];  // null-terminated AT version string
    uint8_t  ism_band_region;
    uint8_t  op_mode;            // current operation mode
    uint8_t  southpaw_mode;      // 0 = right-handed, 1 = left-handed
    uint8_t  c3_revision;        // C3 fork revision (0 = stock Monstatek)

    // Extended battery detail (appended for backward compat)
    uint16_t batt_voltage_mv;    // BQ27421 voltage in millivolts
    int16_t  batt_current_ma;    // BQ27421 current in mA (negative = discharging)
    uint8_t  batt_temp_c;        // BQ27421 temperature in degrees C
    uint8_t  batt_health;        // BQ27421 state-of-health 0-100%
    uint8_t  charge_state;       // BQ25896 stat: 0=off, 1=pre, 2=fast, 3=done
    uint8_t  charge_fault;       // BQ25896 fault code
};
#pragma pack(pop)

constexpr uint32_t DEVICE_INFO_MAGIC = 0x4D314649; // "M1FI"
// Minimum payload size for basic device info (without extended battery)
constexpr int DEVICE_INFO_BASE_SIZE = 58;  // up to and including c3_revision
constexpr uint16_t BANK1_ACTIVE      = 0x534A;
constexpr uint16_t BANK2_ACTIVE      = 0x1F41;

/* ──────────── Firmware Info Response Structure ──────────── */
#pragma pack(push, 1)
struct FwBankInfo {
    uint8_t  fw_version_major;
    uint8_t  fw_version_minor;
    uint8_t  fw_version_build;
    uint8_t  fw_version_rc;
    uint8_t  crc_valid;          // 0 = invalid/empty, 1 = valid
    uint32_t crc32;              // CRC-32 of bank firmware
    uint32_t image_size;         // firmware size in bytes
    uint8_t  c3_revision;        // C3 fork revision (0 = stock or unknown)
    char     build_date[20];     // "MMM DD YYYY HH:MM:SS" null-terminated
};

struct FwInfoPayload {
    uint16_t   active_bank;      // which bank is currently booted
    FwBankInfo bank1;
    FwBankInfo bank2;
};
#pragma pack(pop)

/* ──────────── File List Entry ──────────── */
#pragma pack(push, 1)
struct FileEntry {
    uint8_t  is_dir;             // 1 = directory, 0 = file
    uint32_t size;               // file size in bytes (0 for dirs)
    uint16_t date;               // FAT date
    uint16_t time;               // FAT time
    char     name[256];          // null-terminated filename
};
#pragma pack(pop)

/* Helper: command name for debug logging */
inline const char* cmdName(uint8_t cmd) {
    switch (cmd) {
        case CMD_PING:             return "PING";
        case CMD_PONG:             return "PONG";
        case CMD_GET_DEVICE_INFO:  return "GET_DEVICE_INFO";
        case CMD_DEVICE_INFO_RESP: return "DEVICE_INFO_RESP";
        case CMD_REBOOT:           return "REBOOT";
        case CMD_ACK:              return "ACK";
        case CMD_NACK:             return "NACK";
        case CMD_POWER_OFF:        return "POWER_OFF";
        case CMD_SCREEN_START:     return "SCREEN_START";
        case CMD_SCREEN_STOP:      return "SCREEN_STOP";
        case CMD_SCREEN_FRAME:     return "SCREEN_FRAME";
        case CMD_SCREEN_CAPTURE:   return "SCREEN_CAPTURE";
        case CMD_BUTTON_PRESS:     return "BUTTON_PRESS";
        case CMD_BUTTON_RELEASE:   return "BUTTON_RELEASE";
        case CMD_BUTTON_CLICK:     return "BUTTON_CLICK";
        case CMD_FW_INFO:          return "FW_INFO";
        case CMD_FW_INFO_RESP:     return "FW_INFO_RESP";
        case CMD_FW_UPDATE_START:  return "FW_UPDATE_START";
        case CMD_FW_UPDATE_DATA:   return "FW_UPDATE_DATA";
        case CMD_FW_UPDATE_FINISH: return "FW_UPDATE_FINISH";
        case CMD_FW_BANK_SWAP:     return "FW_BANK_SWAP";
        case CMD_FW_DFU_ENTER:     return "FW_DFU_ENTER";
        case CMD_CLI_EXEC:         return "CLI_EXEC";
        case CMD_CLI_RESP:         return "CLI_RESP";
        case CMD_ESP_UART_SNOOP:   return "ESP_UART_SNOOP";
        case CMD_ESP_UART_SNOOP_RESP: return "ESP_UART_SNOOP_RESP";
        case CMD_SD_UNMOUNT:       return "SD_UNMOUNT";
        case CMD_SD_MOUNT:         return "SD_MOUNT";
        default:                   return "UNKNOWN";
    }
}

} // namespace rpc

#endif // RPC_PROTOCOL_H
