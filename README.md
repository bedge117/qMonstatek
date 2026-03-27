# qMonstatek

Desktop companion app for the [Monstatek M1](https://monstatek.com) multi-tool device. Connects via USB to manage firmware, configure settings, and monitor device status.

## For Users

### Quick Start

1. Download the latest release `.zip` from the [Releases](../../releases) page
2. Extract the zip to any folder (e.g. `C:\qMonstatek\`)
3. Run `qmonstatek.exe`
4. Connect your M1 via USB-C — it will auto-detect on the COM port

No installation required. All dependencies are included in the zip.

**Linux users (Arch based distorbutions) that experience issues with the AppImage, build from source with the directions below.**

### Features

- **Device Info** — View firmware version, battery status, SD card, ESP32 status
- **Firmware Update** — Flash M1 firmware over USB (requires compatible RPC firmware)
- **DFU Flash** — Flash firmware via STM32 DFU mode (works with any firmware, including stock)
- **Dual Boot** — View and swap between two firmware banks
- **ESP32 Update** — Flash ESP32-C6 coprocessor firmware
- **Screen Mirror** — Live view of the M1's display
- **WiFi Management** — Connect to networks, manage saved credentials
- **File Browser** — Browse and manage files on the M1's SD card
- **Sub-GHz / NFC / RFID / IR** — View and manage captured signal files

### DFU Flash (Recovery / Initial Setup)

If your M1 is running stock Monstatek firmware or is in an unresponsive state, use DFU Flash:

1. Power off the M1 (Settings → Power → Power Off → Right Button)
2. Hold **Up + OK** buttons for 5 seconds to enter DFU mode (screen stays dark)
3. Connect to PC via USB-C
4. Open qMonstatek → DFU Flash page
5. Select a firmware `.bin` file and click Flash

To exit DFU mode without flashing, hold **Right + Back** to reboot.

### Swap Bank

The M1 has two flash banks for dual-boot. You can swap between them:

- **Via DFU mode**: Use the Swap Bank button on the DFU Flash page
- **Via firmware**: Use the Dual Boot page (requires compatible firmware)

## For Developers

### Firmware Compatibility

qMonstatek communicates with the M1 using a binary RPC protocol over USB CDC. Stock Monstatek firmware does not include this protocol — features like firmware update, device info, and file management require firmware that implements it.

To make your firmware compatible with qMonstatek, integrate the RPC protocol from:

**https://github.com/bedge117/M1** (branch: `feature/enhanced-firmware`)

Key files to integrate:
- `m1_csrc/m1_cli.c` / `m1_cli.h` — RPC command handler
- `Core/Src/cli_app.c` / `Core/Inc/cli_app.h` — Command definitions and dispatch
- `USB/Class/CDC/Src/usbd_cdc_if.c` — USB CDC receive → RPC frame codec

The RPC protocol uses a simple frame format over the CDC serial link. See the source files above for the command IDs and payload structures.

### DFU Flash (No RPC Required)

The DFU Flash feature works with **any** firmware — it uses the STM32H573's built-in ROM bootloader and ST's CubeProgrammer API. No RPC integration needed.

### Building from Source (Windows)

**Requirements:**
- Qt 6.4+ (MinGW 64-bit)
- CMake 3.16+
- MinGW GCC (included with Qt)

**Build:**
```bash
cd qMonstatek
mkdir build && cd build
cmake .. -G "MinGW Makefiles" -DCMAKE_PREFIX_PATH="C:/Qt/6.4.2/mingw_64"
mingw32-make -j8
```

The executable is at `build/src/qmonstatek.exe`.

**DFU Flash helper** (optional — only needed for DFU Flash feature):
```bash
gcc -O2 -o tools/stm32_dfu_flash.exe tools/stm32_dfu_flash.c
```

Place `stm32_dfu_flash.exe` in a `stm32prog/` folder next to the main executable, along with the CubeProgrammer API DLLs and `Data_Base/` directory. See the [STM32CubeProgrammer API documentation](https://www.st.com/en/development-tools/stm32cubeprog.html) for the required files.

### Building from Source (Linux)

**Requirements:**
- Qt 6 (Core, Gui, Quick, SerialPort, Network, Widgets)
- CMake 3.21+
- GCC / Make

On Arch Linux / EndeavourOS, install the dependencies:
\`\`\`bash
sudo pacman -S base-devel cmake qt6-base qt6-declarative qt6-serialport
\`\`\`

**Build:**
\`\`\`bash
cd qMonstatek
mkdir build && cd build
cmake ..
make -j$(nproc)
\`\`\`

The executable will be generated at `build/src/qmonstatek`.

**Linux Device Permissions:**
To allow the application to communicate with the M1 over USB without requiring `root` or `sudo`:
1. Ensure your user is added to the `uucp` or `dialout` group (depending on your distro):
   \`\`\`bash
   sudo usermod -aG uucp $USER
   \`\`\`
   *(You must log out and log back in for this to take effect).*

2. **DFU Flash Helper:** Install `STM32CubeProgrammer` (e.g., `yay -S stm32cubeprog` on Arch) and ensure the `STM32_Programmer_CLI` is in your system PATH or installed to `/opt/st/STM32CubeProgrammer/bin/`. 
3. **udev Rules:** Ensure you have the proper udev rules installed (usually `/etc/udev/rules.d/99-stm32-dfu.rules`) for `0483:df11` to allow user-space DFU flashing (These are included with `STM32CubeProgrammer` in the Drivers/rules/ directory with instructions). Additionally, you can run the following:
   \`\`\`bash
   echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="df11", MODE="0666"' | sudo tee /etc/udev/rules.d/99-stm32-dfu.rules
   sudo udevadm control --reload-rules && sudo udevadm trigger
   \`\`\`


## License

This project is provided as-is for use with Monstatek M1 devices.
