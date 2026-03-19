import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: view

    property bool isActive: contentStack.currentIndex === viewIndex("swdRecovery")
    property string selectedFilePath: ""
    property string selectedFileName: ""
    property string downloadedFilePath: ""
    property bool downloading: false
    property int downloadPercent: 0
    property var releaseInfo: null

    // ── Signals ──
    Connections {
        target: swdRecovery
        function onOperationComplete(message) {
            statusLabel.color = "#4CAF50"
        }
        function onOperationError(message) {
            statusLabel.color = "#F44336"
        }
        function onRunningChanged(running) {
            if (running) statusLabel.color = Material.foreground
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
            swdGhStatusLabel.text = "Latest release: " + message
            swdGhStatusLabel.visible = true
        }
        function onCheckError(message) {
            swdGhStatusLabel.text = "GitHub error: " + message
            swdGhStatusLabel.color = "#F44336"
            swdGhStatusLabel.visible = true
        }
        function onDownloadProgress(percent) {
            view.downloadPercent = percent
        }
        function onDownloadComplete(filePath) {
            view.downloading = false
            view.downloadedFilePath = filePath
            // Auto-select downloaded file for recovery
            view.selectedFilePath = filePath
            var parts = filePath.split(/[/\\]/)
            view.selectedFileName = parts[parts.length - 1]
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
                text: "SWD Recovery"
                font.pixelSize: 24
                font.bold: true
                Layout.topMargin: 24
                Layout.leftMargin: 24
            }

            Label {
                text: "Advanced recovery tools using a hardware debug probe (SWD). " +
                      "Use this when your M1 is completely unresponsive and DFU mode is not available."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                color: Material.hintTextColor
                font.pixelSize: 12
            }

            // ── M1 Wiring ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: "M1 Flash Header Pinout"
                        font.bold: true
                        font.pixelSize: 14
                    }

                    Label {
                        text: "Connect your debug probe to the M1's flash header using these pins:"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 12
                        color: Material.hintTextColor
                    }

                    GridLayout {
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 4
                        Layout.leftMargin: 8

                        Label { text: "Signal"; font.bold: true; font.pixelSize: 12 }
                        Label { text: "M1 Header Pin"; font.bold: true; font.pixelSize: 12 }
                        Label { text: "STM32 GPIO"; font.bold: true; font.pixelSize: 12 }

                        Label { text: "SWCLK"; font.pixelSize: 12 }
                        Label { text: "Pin 10"; font.pixelSize: 12 }
                        Label { text: "PA14"; font.pixelSize: 12; color: Material.hintTextColor }

                        Label { text: "SWDIO"; font.pixelSize: 12 }
                        Label { text: "Pin 11"; font.pixelSize: 12 }
                        Label { text: "PA13"; font.pixelSize: 12; color: Material.hintTextColor }

                        Label { text: "GND"; font.pixelSize: 12 }
                        Label { text: "Pin 8 or 18"; font.pixelSize: 12 }
                        Label { text: ""; font.pixelSize: 12 }

                        Label { text: "+3.3V"; font.pixelSize: 12 }
                        Label { text: "Pin 9"; font.pixelSize: 12 }
                        Label { text: "(power the M1 via USB instead)"; font.pixelSize: 12; color: Material.hintTextColor }
                    }
                }
            }

            // ── Probe Setup ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: "Debug Probe Setup"
                        font.bold: true
                        font.pixelSize: 14
                    }

                    // Probe type selector
                    RowLayout {
                        spacing: 12

                        Label {
                            text: "Debug probe:"
                            font.pixelSize: 12
                        }

                        ComboBox {
                            id: probeCombo
                            model: ["Pico (CMSIS-DAP)", "ST-Link V2"]
                            currentIndex: swdRecovery.probeType
                            onCurrentIndexChanged: swdRecovery.probeType = currentIndex
                            enabled: !swdRecovery.running
                        }
                    }

                    // Pico-specific instructions
                    ColumnLayout {
                        visible: probeCombo.currentIndex === 0
                        spacing: 4
                        Layout.fillWidth: true

                        Label {
                            text: "Raspberry Pi Pico Setup:"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        Label {
                            text: "1. Download debugprobe_on_pico.uf2 from the latest release at:\n" +
                                  "     github.com/raspberrypi/debugprobe/releases\n" +
                                  "2. Hold the BOOTSEL button on the Pico and plug it into USB\n" +
                                  "3. The Pico appears as a USB drive (RPI-RP2) \u2014 drag the .uf2 file onto it\n" +
                                  "4. The Pico reboots automatically as a CMSIS-DAP debug probe"
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            lineHeight: 1.4
                        }

                        Label {
                            text: "Pico Wiring:"
                            font.bold: true
                            font.pixelSize: 12
                            Layout.topMargin: 4
                        }

                        GridLayout {
                            columns: 2
                            columnSpacing: 24
                            rowSpacing: 4
                            Layout.leftMargin: 8

                            Label { text: "Pico Pin"; font.bold: true; font.pixelSize: 12 }
                            Label { text: "M1 Connection"; font.bold: true; font.pixelSize: 12 }

                            Label { text: "GP2 (pin 4)"; font.pixelSize: 12 }
                            Label { text: "SWCLK \u2192 M1 Header Pin 10"; font.pixelSize: 12 }

                            Label { text: "GP3 (pin 5)"; font.pixelSize: 12 }
                            Label { text: "SWDIO \u2192 M1 Header Pin 11"; font.pixelSize: 12 }

                            Label { text: "GND (pin 3)"; font.pixelSize: 12 }
                            Label { text: "GND \u2192 M1 Header Pin 8 or 18"; font.pixelSize: 12 }
                        }

                        Label {
                            text: "Power: Connect the M1 to its own USB cable for power. " +
                                  "The Pico's 3V3 OUT pin can provide 3.3V but is limited to ~300mA, " +
                                  "which may not be sufficient for the M1."
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            font.pixelSize: 11
                            color: Material.hintTextColor
                            Layout.topMargin: 4
                        }
                    }

                    // ST-Link instructions
                    ColumnLayout {
                        visible: probeCombo.currentIndex === 1
                        spacing: 4
                        Layout.fillWidth: true

                        Label {
                            text: "ST-Link V2 Setup:"
                            font.bold: true
                            font.pixelSize: 12
                        }

                        Label {
                            text: "Connect the ST-Link to your PC via USB. Wire the SWD pins:\n" +
                                  "  SWCLK \u2192 M1 Header Pin 10\n" +
                                  "  SWDIO \u2192 M1 Header Pin 11\n" +
                                  "  GND \u2192 M1 Header Pin 8 or 18\n\n" +
                                  "Power the M1 via its own USB cable. No additional drivers are " +
                                  "needed if STM32CubeIDE is installed."
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            lineHeight: 1.4
                        }
                    }

                    // OpenOCD status
                    RowLayout {
                        spacing: 8
                        Layout.topMargin: 4

                        Rectangle {
                            width: 10; height: 10; radius: 5
                            color: swdRecovery.isOpenOcdAvailable() ? "#4CAF50" : "#F44336"
                        }

                        Label {
                            text: swdRecovery.isOpenOcdAvailable()
                                  ? "OpenOCD found"
                                  : "OpenOCD not found"
                            font.pixelSize: 12
                        }

                        Label {
                            text: swdRecovery.isOpenOcdAvailable()
                                  ? swdRecovery.openOcdLocation()
                                  : "Install STM32CubeIDE or place OpenOCD in openocd/ next to qmonstatek.exe"
                            font.pixelSize: 11
                            color: Material.hintTextColor
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }

            // ── Firmware File ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: "Firmware File"
                        font.bold: true
                        font.pixelSize: 14
                    }

                    Label {
                        text: "Select a local file or download from GitHub."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 12
                        color: Material.hintTextColor
                    }

                    RowLayout {
                        spacing: 12

                        Button {
                            text: "Select File..."
                            enabled: !swdRecovery.running
                            onClicked: fileDialog.open()
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
                            enabled: !githubChecker.checking && !view.downloading && !swdRecovery.running
                            onClicked: {
                                view.releaseInfo = null
                                swdGhStatusLabel.visible = false
                                swdGhStatusLabel.color = Material.hintTextColor
                                githubChecker.checkForUpdates(0, 0, 0, 0, 0)
                            }
                        }

                        Label {
                            id: swdGhStatusLabel
                            visible: false
                            font.pixelSize: 12
                            color: Material.hintTextColor
                        }
                    }

                    // Download progress
                    ProgressBar {
                        visible: view.downloading
                        Layout.fillWidth: true
                        value: view.downloadPercent / 100.0
                    }

                    // Downloaded file indicator
                    Label {
                        visible: view.downloadedFilePath.length > 0 && !view.downloading
                        text: "Downloaded: " + view.downloadedFilePath
                        font.pixelSize: 12
                        color: Material.accent
                        elide: Text.ElideLeft
                        Layout.fillWidth: true
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
                }
            }

            // ── Operations ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    Label {
                        text: "Operations"
                        font.bold: true
                        font.pixelSize: 14
                    }

                    // Recovery Flash
                    RowLayout {
                        spacing: 12

                        Button {
                            text: "Recovery Flash"
                            enabled: !swdRecovery.running &&
                                     swdRecovery.isOpenOcdAvailable() &&
                                     view.selectedFileName.length > 0
                            onClicked: recoveryConfirmDialog.open()
                            Layout.preferredWidth: 160
                        }

                        Label {
                            text: "Flash firmware to Bank 1 with forced halt. Primary recovery method."
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            color: Material.hintTextColor
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                    // Swap Bank
                    RowLayout {
                        spacing: 12

                        Button {
                            text: "Swap Bank"
                            enabled: !swdRecovery.running &&
                                     swdRecovery.isOpenOcdAvailable()
                            onClicked: swapConfirmDialog.open()
                            Layout.preferredWidth: 160
                        }

                        Label {
                            text: "Toggle the active flash bank via SWAP_BANK option byte."
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            color: Material.hintTextColor
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                    // Verify Bank 2
                    RowLayout {
                        spacing: 12

                        Button {
                            text: "Verify Bank 2"
                            enabled: !swdRecovery.running &&
                                     swdRecovery.isOpenOcdAvailable() &&
                                     view.selectedFileName.length > 0
                            onClicked: swdRecovery.verifyBank2(view.selectedFilePath)
                            Layout.preferredWidth: 160
                        }

                        Label {
                            text: "Compare Bank 2 contents against the selected firmware file."
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            color: Material.hintTextColor
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                    // Clone Bank 1 -> Bank 2
                    RowLayout {
                        spacing: 12

                        Button {
                            text: "Clone Bank"
                            enabled: !swdRecovery.running &&
                                     swdRecovery.isOpenOcdAvailable()
                            onClicked: cloneConfirmDialog.open()
                            Layout.preferredWidth: 160
                        }

                        Label {
                            text: "Copy Bank 1 to Bank 2 as a safety backup."
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            color: Material.hintTextColor
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                    // Read Status
                    RowLayout {
                        spacing: 12

                        Button {
                            text: "Read Status"
                            enabled: !swdRecovery.running &&
                                     swdRecovery.isOpenOcdAvailable()
                            onClicked: swdRecovery.readStatus()
                            Layout.preferredWidth: 160
                        }

                        Label {
                            text: "Read the OPTR register to check which bank is currently active."
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            color: Material.hintTextColor
                        }
                    }
                }
            }

            // ── Progress ──
            ProgressBar {
                visible: swdRecovery.running
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                value: swdRecovery.progress / 100.0
            }

            // ── Status ──
            Label {
                id: statusLabel
                text: swdRecovery.statusMessage
                visible: swdRecovery.statusMessage.length > 0
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                font.pixelSize: 12
            }

            // ── Cancel ──
            Button {
                text: "Cancel"
                visible: swdRecovery.running
                Layout.leftMargin: 24
                onClicked: swdRecovery.cancel()
            }

            // ── Output Log ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.preferredHeight: 220
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            text: "Output Log"
                            font.bold: true
                            font.pixelSize: 14
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "Copy"
                            flat: true
                            font.pixelSize: 11
                            enabled: swdRecovery.outputLog.length > 0
                            onClicked: {
                                logArea.selectAll()
                                logArea.copy()
                                logArea.deselect()
                            }
                        }

                        Button {
                            text: "Clear"
                            flat: true
                            font.pixelSize: 11
                            enabled: swdRecovery.outputLog.length > 0 && !swdRecovery.running
                            onClicked: swdRecovery.clearLog()
                        }
                    }

                    ScrollView {
                        id: logScrollView
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TextArea {
                            id: logArea
                            text: swdRecovery.outputLog
                            readOnly: true
                            wrapMode: Text.Wrap
                            font.family: "Consolas"
                            font.pixelSize: 11
                            color: "#CCCCCC"
                            selectByMouse: true
                            background: Rectangle { color: "#1E1E1E"; radius: 4 }
                            onTextChanged: cursorPosition = text.length
                        }
                    }
                }
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
        onAccepted: {
            var path = selectedFile.toString().replace("file:///", "")
            view.selectedFilePath = path
            var parts = path.split(/[/\\]/)
            view.selectedFileName = parts[parts.length - 1]
        }
    }

    // ── Confirmation Dialogs ──

    Dialog {
        id: recoveryConfirmDialog
        title: "Confirm Recovery Flash"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12

            Label {
                text: "Flash firmware via SWD?"
                font.bold: true
            }
            Label {
                text: "File: " + view.selectedFileName
            }
            Label {
                text: "This will halt the MCU, flash the firmware to Bank 1 " +
                      "(0x08000000), verify the write, and reset the device.\n\n" +
                      "Ensure the debug probe is connected and the M1 is powered."
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Material.hintTextColor
            }
        }

        onAccepted: swdRecovery.recoveryFlash(view.selectedFilePath)
    }

    Dialog {
        id: swapConfirmDialog
        title: "Confirm Bank Swap"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12

            Label {
                text: "Swap the active flash bank via SWD?"
                font.bold: true
            }
            Label {
                text: "This will toggle the SWAP_BANK option byte, causing the\n" +
                      "device to boot from the other flash bank after reset."
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Material.hintTextColor
            }
        }

        onAccepted: swdRecovery.swapBank()
    }

    Dialog {
        id: cloneConfirmDialog
        title: "Confirm Bank Clone"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12

            Label {
                text: "Clone Bank 1 to Bank 2?"
                font.bold: true
            }
            Label {
                text: "This will read 1 MB from Bank 1 and write it to Bank 2.\n" +
                      "Bank 2 contents will be overwritten.\n\n" +
                      "This operation takes approximately 30\u201360 seconds."
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Material.hintTextColor
            }
        }

        onAccepted: swdRecovery.cloneBank1ToBank2()
    }
}
