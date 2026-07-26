/*
 * device_info.h — M1 device information data structure
 */

#ifndef DEVICE_INFO_H
#define DEVICE_INFO_H

#include <QString>
#include <cstdint>

struct DeviceInfo {
    // Firmware version
    uint8_t  fwMajor = 0;
    uint8_t  fwMinor = 0;
    uint8_t  fwBuild = 0;
    uint8_t  fwRC = 0;

    // Dual-boot
    uint16_t activeBank = 0;     // 0x534A = Bank1, 0x1F41 = Bank2
    bool isBankValid() const { return activeBank == 0x534A || activeBank == 0x1F41; }
    int  bankNumber() const { return activeBank == 0x534A ? 1 : 2; }

    // Battery
    uint8_t  batteryLevel = 0;   // 0-100
    bool     batteryCharging = false;
    uint16_t batteryVoltageMv = 0;   // millivolts
    int16_t  batteryCurrentMa = 0;   // mA (negative = discharging)
    uint8_t  batteryTempC = 0;       // degrees Celsius
    uint8_t  batteryHealth = 0;      // SOH 0-100%
    uint8_t  chargeState = 0;        // 0=off, 1=pre-charge, 2=fast, 3=done
    uint8_t  chargeFault = 0;        // BQ25896 fault code

    // SD card
    bool     sdCardPresent = false;
    uint32_t sdTotalKB = 0;
    uint32_t sdFreeKB = 0;

    // ESP32
    bool    esp32Ready = false;
    QString esp32Version;

    // Config
    uint8_t  ismBandRegion = 0;
    uint8_t  opMode = 0;
    bool     southpawMode = false;
    uint8_t  c3Revision = 0;

    // Firmware variant: 0 = normal working FW, 1 = Recovery, 2 = Restore Host
    uint8_t  fwVariant = 0;

    // True if we received valid device info via RPC
    bool hasDeviceInfo() const {
        return fwMajor != 0 || fwMinor != 0 || fwBuild != 0 || fwRC != 0;
    }

    // Helpers
    QString fwVersionString() const {
        if (!hasDeviceInfo())
            return QString();
        QString base = QString("v%1.%2.%3.%4")
            .arg(fwMajor).arg(fwMinor).arg(fwBuild).arg(fwRC);
        if (c3Revision > 0)
            base += QString("-C3.%1").arg(c3Revision);
        return base;
    }

    QString sdCapacityString() const {
        if (!sdCardPresent) return "No SD card";
        double totalMB = sdTotalKB / 1024.0;
        double freeMB = sdFreeKB / 1024.0;
        if (totalMB > 1024) {
            return QString("%1 GB / %2 GB free")
                .arg(totalMB / 1024.0, 0, 'f', 1)
                .arg(freeMB / 1024.0, 0, 'f', 1);
        }
        return QString("%1 MB / %2 MB free")
            .arg(totalMB, 0, 'f', 0)
            .arg(freeMB, 0, 'f', 0);
    }
};

#endif // DEVICE_INFO_H
