import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: view

    property bool isActive: contentStack.currentIndex === viewIndex("dfuFlash")
    property string selectedFilePath: ""
    property string selectedFileName: ""
    property string downloadedFilePath: ""
    property bool downloading: false
    property int downloadPercent: 0
    property var releaseInfo: null
    property int flashTargetIndex: 0  // 0=inactive, 1=bank1, 2=bank2

    function flashTargetValue() {
        switch (flashTargetIndex) {
        case 1:  return "bank1"
        case 2:  return "bank2"
        default: return "inactive"
        }
    }

    // ── DFU Flasher signals ──
    Connections {
        target: dfuFlasher
        function onFlashComplete() {
            flashStatusLabel.text = "Flash complete! Hold Right + Back to reboot into the new firmware."
            flashStatusLabel.color = "#4CAF50"
        }
        function onFlashError(message) {
            flashStatusLabel.text = message
            flashStatusLabel.color = "#F44336"
        }
        function onSwapBankComplete(message) {
            flashStatusLabel.text = message + " Hold Right + Back to reboot."
            flashStatusLabel.color = "#4CAF50"
        }
        function onSwapBankError(message) {
            flashStatusLabel.text = message
            flashStatusLabel.color = "#F44336"
        }
    }

    // ── GitHub signals (guarded to this view only) ──
    Connections {
        target: githubChecker
        enabled: view.isActive
        function onReleaseFound(info) {
            view.releaseInfo = info
        }
        function onNoUpdateAvailable(message) {
            ghStatusLabel.text = "Latest release: " + message
            ghStatusLabel.visible = true
        }
        function onCheckError(message) {
            ghStatusLabel.text = "GitHub error: " + message
            ghStatusLabel.color = "#F44336"
            ghStatusLabel.visible = true
        }
        function onDownloadProgress(percent) {
            view.downloadPercent = percent
        }
        function onDownloadComplete(filePath) {
            view.downloading = false
            view.downloadedFilePath = filePath
        }
    }

    ScrollView {
        anchors.fill: parent

        ColumnLayout {
            width: view.width
            spacing: 16
            anchors.margins: 24

            // ── Title ──
            Label {
                text: "DFU Flash"
                font.pixelSize: 24
                font.bold: true
                Layout.topMargin: 24
                Layout.leftMargin: 24
            }

            Label {
                text: "Flash firmware to an M1 device via USB DFU. Use this to upgrade from stock " +
                      "Monstatek firmware to C3, or for recovery."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                color: Material.hintTextColor
                font.pixelSize: 12
            }

            // ── Step-by-step instructions ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: "How to enter DFU mode"
                        font.bold: true
                        font.pixelSize: 14
                    }

                    Label {
                        text: "1.  Power off your M1 through the menu\n" +
                              "     (Settings \u2192 Power \u2192 Power Off \u2192 Right Button)\n\n" +
                              "2.  Hold the Up + OK buttons simultaneously for 5 seconds\n" +
                              "     to enter DFU mode (the screen will stay dark)\n\n" +
                              "3.  Connect the device to your PC using the USB-C cable\n\n" +
                              "4.  The device should appear below as an STM32 DFU device\n\n" +
                              "To exit DFU mode without flashing, hold Right + Back to reboot."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 12
                        lineHeight: 1.2
                    }
                }
            }

            // ── DFU Device Status ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    RowLayout {
                        spacing: 12

                        Rectangle {
                            width: 14; height: 14; radius: 7
                            color: dfuFlasher.dfuDeviceFound ? "#4CAF50" : "#F44336"
                        }

                        Label {
                            text: dfuFlasher.dfuDeviceFound
                                  ? "STM32 DFU device detected"
                                  : "No DFU device found"
                            font.bold: true
                            font.pixelSize: 14
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            text: "Scan"
                            enabled: !dfuFlasher.flashing
                            onClicked: dfuFlasher.scanOnce()
                        }
                    }

                    Label {
                        text: dfuFlasher.dfuDeviceInfo
                        visible: dfuFlasher.dfuDeviceFound && dfuFlasher.dfuDeviceInfo.length > 0
                        font.pixelSize: 11
                        color: Material.hintTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label {
                        visible: !dfuFlasher.dfuDeviceFound && !dfuFlasher.flashing
                        text: dfuFlasher.statusMessage
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }

                    // CubeProgrammer availability warning
                    Label {
                        visible: !dfuFlasher.isToolAvailable()
                        text: "STM32CubeProgrammer is not installed.\n\n" +
                              "Download it free from st.com (search 'STM32CubeProgrammer').\n" +
                              "Install to the default location, then restart qMonstatek."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 11
                        color: "#F44336"
                    }
                }
            }

            // ── WinUSB Driver (Zadig) Instructions — Windows Only ──
            Pane {
                visible: Qt.platform.os === "windows"
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: "Windows USB Driver Setup (First Time Only)"
                        font.bold: true
                        font.pixelSize: 14
                    }

                    Label {
                        text: "Windows requires the WinUSB driver to communicate with the M1 in DFU mode. " +
                              "If the device is not detected after entering DFU mode, install the driver using Zadig:"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 12
                        color: Material.hintTextColor
                    }

                    Label {
                        text: "1.  Download Zadig from https://zadig.akeo.ie\n\n" +
                              "2.  Put your M1 into DFU mode first (see steps above)\n\n" +
                              "3.  Open Zadig \u2192 Options \u2192 List All Devices\n\n" +
                              "4.  Select \"STM32 BOOTLOADER\" from the dropdown\n" +
                              "     (VID: 0x0483, PID: 0xDF11)\n\n" +
                              "5.  Set the target driver to WinUSB (should be the default)\n\n" +
                              "6.  Click \"Install Driver\" (or \"Replace Driver\")\n\n" +
                              "7.  Close Zadig and click Scan above \u2014 the device should now be detected"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 12
                        lineHeight: 1.2
                    }

                    Label {
                        text: "You only need to do this once. The driver persists across reboots and reconnections."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }
                }
            }

            // ── Linux USB Permissions Note ──
            Pane {
                visible: Qt.platform.os === "linux"
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: "Linux USB Permissions (First Time Only)"
                        font.bold: true
                        font.pixelSize: 14
                    }

                    Label {
                        text: "If the DFU device is not detected, you may need to add a udev rule " +
                              "so your user can access STM32 DFU devices without root:"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 12
                        color: Material.hintTextColor
                    }

                    Label {
                        text: "echo 'SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"0483\", ATTRS{idProduct}==\"df11\", MODE=\"0666\"' " +
                              "| sudo tee /etc/udev/rules.d/99-stm32-dfu.rules\n" +
                              "sudo udevadm control --reload-rules && sudo udevadm trigger"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.family: "monospace"
                        font.pixelSize: 11
                    }
                }
            }

            // ── Swap Bank ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: "Swap Flash Bank"
                        font.bold: true
                        font.pixelSize: 14
                    }

                    Label {
                        text: "Toggle the active flash bank without flashing new firmware. " +
                              "The device will reboot into the other bank."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 12
                        color: Material.hintTextColor
                    }

                    Button {
                        text: "Swap Bank"
                        enabled: dfuFlasher.dfuDeviceFound && !dfuFlasher.flashing
                        onClicked: swapBankConfirmDialog.open()
                    }
                }
            }

            // ── Firmware Selection ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    Label {
                        text: "Select Firmware"
                        font.bold: true
                        font.pixelSize: 14
                    }

                    // Flash target selector
                    RowLayout {
                        spacing: 12

                        Label {
                            text: "Flash target:"
                            font.pixelSize: 12
                        }

                        ComboBox {
                            id: flashTargetCombo
                            model: ["Inactive Bank (safest)", "Bank 1", "Bank 2"]
                            currentIndex: view.flashTargetIndex
                            onCurrentIndexChanged: view.flashTargetIndex = currentIndex
                            enabled: !dfuFlasher.flashing
                        }

                        Label {
                            text: {
                                switch (view.flashTargetIndex) {
                                case 0: return "Writes to the non-active bank, then swaps to it"
                                case 1: return "Writes to bank 1 and boots from bank 1"
                                case 2: return "Writes to bank 2 and boots from bank 2"
                                }
                            }
                            font.pixelSize: 11
                            color: Material.hintTextColor
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Material.dividerColor
                    }

                    // Local file selection
                    RowLayout {
                        spacing: 12

                        Button {
                            text: "Select File..."
                            enabled: !dfuFlasher.flashing
                            onClicked: {
                                var f = uiSettings.dialogFolder("dfuOpen")
                                if (f != "") fileDialog.currentFolder = f
                                fileDialog.open()
                            }
                        }

                        Label {
                            text: view.selectedFileName.length > 0
                                  ? view.selectedFileName
                                  : "No file selected"
                            color: view.selectedFileName.length > 0
                                   ? Material.foreground
                                   : Material.hintTextColor
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "Flash"
                            highlighted: true
                            visible: view.selectedFileName.length > 0
                            enabled: dfuFlasher.dfuDeviceFound && !dfuFlasher.flashing
                            onClicked: flashConfirmDialog.selectedFile = view.selectedFilePath,
                                       flashConfirmDialog.displayName = view.selectedFileName,
                                       flashConfirmDialog.open()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Material.dividerColor
                    }

                    // GitHub download
                    RowLayout {
                        spacing: 12

                        Button {
                            text: githubChecker.checking ? "Checking..." : "Download from GitHub"
                            enabled: !githubChecker.checking && !view.downloading
                            onClicked: {
                                view.releaseInfo = null
                                ghStatusLabel.visible = false
                                ghStatusLabel.color = Material.hintTextColor
                                // Pass zeros — stock device has no RPC version info
                                githubChecker.checkForUpdates(0, 0, 0, 0, 0)
                            }
                        }

                        Label {
                            id: ghStatusLabel
                            visible: false
                            font.pixelSize: 12
                            color: Material.hintTextColor
                        }
                    }

                    // Downloaded file flash button
                    RowLayout {
                        visible: view.downloadedFilePath.length > 0 && !view.downloading
                        spacing: 12

                        Label {
                            text: "Downloaded: " + view.downloadedFilePath
                            font.pixelSize: 12
                            color: Material.accent
                            Layout.fillWidth: true
                            elide: Text.ElideLeft
                        }

                        Button {
                            text: "Flash Downloaded"
                            highlighted: true
                            enabled: dfuFlasher.dfuDeviceFound && !dfuFlasher.flashing
                            onClicked: {
                                var parts = view.downloadedFilePath.split(/[/\\]/)
                                flashConfirmDialog.selectedFile = view.downloadedFilePath
                                flashConfirmDialog.displayName = parts[parts.length - 1]
                                flashConfirmDialog.open()
                            }
                        }
                    }
                }
            }

            // ── Release info card (from GitHub) ──
            Pane {
                visible: view.releaseInfo !== null
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 2

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    Label {
                        text: view.releaseInfo ? view.releaseInfo.name : ""
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Label {
                        text: view.releaseInfo
                              ? "Version: " + view.releaseInfo.versionFormatted
                              : ""
                        color: Material.accent
                    }

                    Label {
                        text: view.releaseInfo ? view.releaseInfo.publishedAt : ""
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Material.dividerColor
                    }

                    Label {
                        text: "Release Notes"
                        font.bold: true
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 120

                        TextArea {
                            text: view.releaseInfo ? view.releaseInfo.body : ""
                            readOnly: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: 12
                        }
                    }

                    Label {
                        text: "Assets"
                        font.bold: true
                    }

                    Repeater {
                        model: view.releaseInfo ? view.releaseInfo.assets : []
                        delegate: RowLayout {
                            Layout.fillWidth: true

                            Label {
                                text: modelData.name
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }
                            Label {
                                text: (modelData.size / 1024).toFixed(0) + " KB"
                                font.pixelSize: 11
                                color: Material.hintTextColor
                            }
                            Button {
                                text: "Download"
                                enabled: !view.downloading
                                font.pixelSize: 11
                                onClicked: {
                                    view.downloading = true
                                    view.downloadedFilePath = ""
                                    githubChecker.downloadAsset(modelData.downloadUrl, modelData.name)
                                }
                            }
                        }
                    }

                    ProgressBar {
                        visible: view.downloading
                        Layout.fillWidth: true
                        value: view.downloadPercent / 100.0
                    }
                }
            }

            // ── Flash progress ──
            ProgressBar {
                visible: dfuFlasher.flashing
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                value: dfuFlasher.progress / 100.0
            }

            Label {
                id: flashStatusLabel
                visible: text.length > 0
                text: ""
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                font.pixelSize: 12
            }

            // Cancel button during flash
            Button {
                text: "Cancel Flash"
                visible: dfuFlasher.flashing
                Layout.leftMargin: 24
                onClicked: dfuFlasher.cancel()
            }

            // Bottom spacer
            Item { Layout.preferredHeight: 24 }
        }
    }

    // ── File Dialog ──
    FileDialog {
        id: fileDialog
        title: "Select Firmware Binary"
        nameFilters: ["Binary files (*.bin)", "All files (*)"]
        Component.onCompleted: {
            var f = uiSettings.dialogFolder("dfuOpen")
            if (f != "") currentFolder = f
        }
        onAccepted: {
            uiSettings.setDialogFolder("dfuOpen", currentFolder)
            var path = selectedFile.toString().replace(root.filePathFilter, "")
            view.selectedFilePath = path
            var parts = path.split(/[/\\]/)
            view.selectedFileName = parts[parts.length - 1]
            flashStatusLabel.text = ""
        }
    }

    // ── Flash Confirmation Dialog ──
    Dialog {
        id: flashConfirmDialog
        title: "Confirm DFU Flash"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        property string selectedFile: ""
        property string displayName: ""

        ColumnLayout {
            spacing: 12

            Label {
                text: "Flash firmware via DFU?"
                font.bold: true
            }
            Label {
                text: "File: " + flashConfirmDialog.displayName
            }
            Label {
                text: "Target: " + flashTargetCombo.currentText
                font.bold: true
            }
            Label {
                text: "This will write the firmware directly to the M1's flash memory.\n" +
                      "The device will reboot into the new firmware after flashing.\n\n" +
                      "Do not disconnect the USB cable during the flash process."
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Material.hintTextColor
            }
        }

        onAccepted: {
            flashStatusLabel.text = ""
            flashStatusLabel.color = Material.foreground
            dfuFlasher.startFlash(flashConfirmDialog.selectedFile, view.flashTargetValue())
        }
    }

    // ── Swap Bank Confirmation Dialog ──
    Dialog {
        id: swapBankConfirmDialog
        title: "Confirm Bank Swap"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12

            Label {
                text: "Swap the active flash bank?"
                font.bold: true
            }
            Label {
                text: "This will toggle the SWAP_BANK option byte, causing the\n" +
                      "device to reboot into the firmware on the other bank.\n\n" +
                      "Use this to switch between two installed firmware versions."
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Material.hintTextColor
            }
        }

        onAccepted: {
            flashStatusLabel.text = ""
            flashStatusLabel.color = Material.foreground
            dfuFlasher.swapBank()
        }
    }

    // ── Start/stop scanning when view becomes active/inactive ──
    onIsActiveChanged: {
        if (isActive) {
            dfuFlasher.startScanning()
        } else {
            dfuFlasher.stopScanning()
        }
    }
}
