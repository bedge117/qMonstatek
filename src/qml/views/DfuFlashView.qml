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
    property bool flashAfterDownload: false  // set by "Download and Flash"

    function flashTargetValue() {
        switch (flashTargetIndex) {
        case 1:  return "bank1"
        case 2:  return "bank2"
        default: return "inactive"
        }
    }

    // Pick the best M1 firmware image from the release assets: prefer the
    // CRC-injected *_wCRC.bin, then any .bin that isn't an ESP/factory image.
    function pickFirmwareAsset() {
        if (!releaseInfo || !releaseInfo.assets) return null
        var a = releaseInfo.assets, i, n
        for (i = 0; i < a.length; i++) {
            n = a[i].name.toLowerCase()
            if (n.indexOf("wcrc") >= 0 && n.indexOf(".bin") >= 0 &&
                n.indexOf("esp") < 0 && n.indexOf("factory") < 0)
                return a[i]
        }
        for (i = 0; i < a.length; i++) {
            n = a[i].name.toLowerCase()
            if (n.indexOf(".bin") >= 0 && n.indexOf("esp") < 0 && n.indexOf("factory") < 0)
                return a[i]
        }
        return null
    }

    // Close every popup on this screen — called when we auto-navigate away
    // (e.g. a working device connects while the user is on DFU Flash).
    function closeAllPopups() {
        dfuInfoDialog.close()
        dfuEnterDialog.close()
        dfuTroubleshootDialog.close()
        zadigDialog.close()
        udevDialog.close()
        rebootDialog.close()
        releaseNotesDialog.close()
        bankInfoDialog.close()
        flashConfirmDialog.close()
        swapBankConfirmDialog.close()
    }

    // ── DFU Flasher signals ──
    Connections {
        target: dfuFlasher
        function onFlashComplete() {
            flashStatusLabel.text = "Flash complete! Hold Right + Back to reboot into the new firmware."
            flashStatusLabel.color = "#4CAF50"
            rebootDialog.open()
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
            // On this screen the check runs with version 0, so any real release is
            // "newer" and fires onReleaseFound. This branch means the selected repo
            // has no published release at all.
            ghStatusLabel.text = "No firmware release found on " + githubChecker.repoUrl +
                                 ". This repo may not publish releases — download the .bin " +
                                 "from its Releases page, then use 'Browse this PC' above."
            ghStatusLabel.color = "#E0A030"
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
            // Downloaded firmware becomes the selected firmware so the Flash button
            // (and the Download-and-Flash flow) can use it.
            view.selectedFilePath = filePath
            var parts = filePath.split(/[/\\]/)
            view.selectedFileName = parts[parts.length - 1]
            // "Download and Flash": jump straight to the confirm dialog if a device
            // is ready; otherwise leave it selected and let the connect hint show.
            if (view.flashAfterDownload) {
                view.flashAfterDownload = false
                if (dfuFlasher.dfuDeviceFound) {
                    flashConfirmDialog.selectedFile = view.selectedFilePath
                    flashConfirmDialog.displayName = view.selectedFileName
                    flashConfirmDialog.open()
                }
            }
        }
    }

    // ── "What is DFU?" explainer popup ──
    Dialog {
        id: dfuInfoDialog
        title: "What is DFU?"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 80, 520)
        standardButtons: Dialog.Close

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                text: "DFU (Device Firmware Update) is a low-level flashing mode built directly " +
                      "into the M1's STM32 chip. It lives in read-only ROM and runs before any of " +
                      "the device's own firmware loads."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.preferredWidth: 460
            }
            Label {
                text: "Because it doesn't depend on the installed firmware, DFU can flash a device " +
                      "even when that firmware is missing, corrupted, or won't boot. That makes it " +
                      "both the standard way to install a custom community build over the factory " +
                      "firmware and a reliable way to recover a bricked device."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.preferredWidth: 460
            }
            Label {
                text: "Over USB the M1 shows up on your PC as an \"STM32 DFU device.\" qMonstatek " +
                      "talks to it through STMicroelectronics' free STM32CubeProgrammer."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.preferredWidth: 460
                color: Material.hintTextColor
                font.pixelSize: 12
            }
        }
    }

    // ── "How to enter DFU mode" popup (illustrated steps) ──
    Dialog {
        id: dfuEnterDialog
        title: "How to enter DFU mode"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 600)
        height: Math.min(view.height - 80, 640)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true

            ColumnLayout {
                width: dfuEnterDialog.availableWidth
                spacing: 12

                Label {
                    text: "Easiest method — plug in first, so your PC confirms the moment DFU starts:"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    font.bold: true
                }

                Label {
                    text: "1.  Connect the M1 to your PC with a USB-C cable.\n\n" +
                          "2.  Power the M1 off (Settings → Power → Power Off → Right).\n\n" +
                          "3.  With the cable still attached, press and hold Up first, then add OK. " +
                          "Keep both held together for about 5 seconds, then release.\n\n" +
                          "4.  The screen stays dark the whole time — that's normal. The instant " +
                          "DFU starts, your PC detects it and it appears below as an STM32 DFU device."
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    lineHeight: 1.25
                }

                // Visual reference — button hold (enter_dfu.png)
                Image {
                    source: "qrc:/images/enter_dfu.png"
                    fillMode: Image.PreserveAspectFit
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.maximumWidth: 520
                    visible: status === Image.Ready
                }

                Label {
                    text: "Since the display never lights up in DFU mode, the STM32 DFU device " +
                          "appearing in this window is your only confirmation that it worked."
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    color: Material.hintTextColor
                    font.pixelSize: 12
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.preferredHeight: 1
                    color: Material.dividerColor
                }

                Label {
                    text: "Exiting DFU mode without flashing"
                    font.bold: true
                }
                Label {
                    text: "Hold Right + Back to reboot the M1 back into its normal firmware."
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Visual reference — reboot (reboot_device.png)
                Image {
                    source: "qrc:/images/reboot_device.png"
                    fillMode: Image.PreserveAspectFit
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.maximumWidth: 520
                    visible: status === Image.Ready
                }
            }
        }
    }

    // ── DFU Troubleshooting popup ──
    Dialog {
        id: dfuTroubleshootDialog
        title: "DFU troubleshooting"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 600)
        height: Math.min(view.height - 80, 560)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true

            ColumnLayout {
                width: dfuTroubleshootDialog.availableWidth
                spacing: 16

                Repeater {
                    model: [
                        {
                            q: "The M1 keeps powering back on instead of entering DFU",
                            a: "If OK registers before Up, the M1 reads it as a normal power-on. Press and " +
                               "hold Up first, then add OK a moment later, and keep both held down together."
                        },
                        {
                            q: "I held the buttons for 5 seconds and nothing happened",
                            a: "That's expected — in DFU mode the screen stays completely off. The chip " +
                               "is still awake and listening. Confirm it worked by watching for the STM32 DFU " +
                               "device to appear on the DFU Flash screen."
                        },
                        {
                            q: "The DFU device never shows up on my PC",
                            a: "Use a USB-C cable that carries data (some are charge-only) and try a different " +
                               "port. On Windows the device also needs the WinUSB driver — install it with " +
                               "Zadig using the steps on the DFU Flash screen."
                        },
                        {
                            q: "STM32CubeProgrammer isn't found",
                            a: "qMonstatek flashes DFU through STM32CubeProgrammer. Install it free from st.com " +
                               "to the default location, then restart qMonstatek."
                        }
                    ]
                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Label {
                            text: modelData.q
                            font.bold: true
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Label {
                            text: modelData.a
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            color: Material.hintTextColor
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }

    // ── Windows USB driver setup (Zadig) popup ──
    Dialog {
        id: zadigDialog
        title: "Windows USB driver setup"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 600)
        height: Math.min(view.height - 80, 560)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true

            ColumnLayout {
                width: zadigDialog.availableWidth
                spacing: 12

                Label {
                    text: "The first time you flash on Windows, the M1 in DFU mode needs the WinUSB " +
                          "driver. You install it once with Zadig, a small free utility. It can't be " +
                          "bundled with qMonstatek, so download it directly:"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Label {
                    text: "<a href='z'>Download Zadig (zadig.akeo.ie)</a>"
                    textFormat: Text.RichText
                    font.pixelSize: 16
                    linkColor: "#8FCBFF"; font.bold: true
                    onLinkActivated: Qt.openUrlExternally("https://zadig.akeo.ie")
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                }

                Repeater {
                    model: [
                        "Put your M1 into DFU mode first (see 'How to enter DFU mode').",
                        "Open Zadig, then choose Options → List All Devices.",
                        "In the dropdown, select 'STM32 BOOTLOADER' (VID 0x0483, PID 0xDF11).",
                        "Set the target driver to WinUSB (usually the default).",
                        "Click 'Install Driver' (or 'Replace Driver') and wait for it to finish.",
                        "Close Zadig and press Scan on the DFU Flash screen — the device should appear."
                    ]
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Label { text: (index + 1) + "."; font.bold: true; Layout.alignment: Qt.AlignTop }
                        Label { text: modelData; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    }
                }

                Label {
                    text: "You only need to do this once — the driver stays installed across reboots " +
                          "and reconnections."
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    color: Material.hintTextColor
                    font.pixelSize: 12
                }
            }
        }
    }

    // ── Linux USB permissions (udev) popup ──
    Dialog {
        id: udevDialog
        title: "Linux USB permissions"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 600)
        standardButtons: Dialog.Close

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                text: "If the DFU device isn't detected on Linux, add a udev rule so your user can " +
                      "access STM32 DFU devices without root. Run these two commands, then replug:"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.preferredWidth: 520
            }

            Repeater {
                model: [
                    "echo 'SUBSYSTEM==\"usb\", ATTRS{idVendor}==\"0483\", ATTRS{idProduct}==\"df11\", MODE=\"0666\"' | sudo tee /etc/udev/rules.d/99-stm32-dfu.rules",
                    "sudo udevadm control --reload-rules && sudo udevadm trigger"
                ]
                delegate: Label {
                    text: modelData
                    textFormat: Text.PlainText
                    font.family: "monospace"
                    font.pixelSize: 12
                    wrapMode: Text.WrapAnywhere
                    Layout.fillWidth: true
                    Layout.preferredWidth: 520
                }
            }
        }
    }

    // ── "What's a flash bank?" explainer popup ──
    Dialog {
        id: bankInfoDialog
        title: "What's a flash bank?"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 560)
        height: Math.min(view.height - 80, 560)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true

            ColumnLayout {
                width: bankInfoDialog.availableWidth
                spacing: 12

                Label {
                    text: "The M1's processor has its 2 MB of program memory split into two equal " +
                          "halves called banks — Bank 1 and Bank 2. Each bank is large enough to hold " +
                          "a complete, independent copy of the firmware."
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    font.pixelSize: 14
                }
                Label {
                    text: "Only one bank is active and running at a time; the other sits idle as a " +
                          "spare. That means two different firmware builds can live on the device " +
                          "side by side — for example your current version in one bank and a previous " +
                          "version in the other."
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    font.pixelSize: 14
                }
                Label {
                    text: "When you install an update, the new image is written to the inactive bank " +
                          "and the device then switches which bank it boots from. Because the old " +
                          "firmware is left untouched in the other bank, a bad update can't erase a " +
                          "known-good version — this is what makes updates safe to roll back."
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    font.pixelSize: 14
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                Label {
                    text: "What \"Swap Bank\" does"
                    font.bold: true
                    font.pixelSize: 14
                }
                Label {
                    text: "Swap Bank simply flips which bank the M1 boots from — nothing is erased or " +
                          "flashed. Use it to jump back to the firmware already stored in the other " +
                          "bank, such as returning to the previous version after an update misbehaves."
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    font.pixelSize: 14
                    color: Material.hintTextColor
                }
            }
        }
    }

    // ── Reboot prompt shown after a successful flash ──
    Dialog {
        id: rebootDialog
        title: "Flash complete"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 560)
        standardButtons: Dialog.Ok

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                text: "Firmware flashed successfully."
                font.pixelSize: 16
                font.bold: true
                color: "#4CAF50"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.preferredWidth: 500
            }
            Label {
                text: "Reboot the M1 to start the new firmware: hold Right + Back."
                font.pixelSize: 14
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.preferredWidth: 500
            }
            Image {
                source: "qrc:/images/reboot_device.png"
                fillMode: Image.PreserveAspectFit
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                Layout.maximumWidth: 500
                visible: status === Image.Ready
            }
        }
    }

    // ── Release notes popup (from GitHub) ──
    Dialog {
        id: releaseNotesDialog
        title: "Release notes"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 640)
        height: Math.min(view.height - 80, 640)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true

            ColumnLayout {
                width: releaseNotesDialog.availableWidth
                spacing: 12

                Label {
                    text: view.releaseInfo ? view.releaseInfo.name : ""
                    font.pixelSize: 17
                    font.bold: true
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Label {
                    text: view.releaseInfo
                          ? view.releaseInfo.versionFormatted +
                            (view.releaseInfo.prerelease ? "   (pre-release)" : "")
                          : ""
                    color: Material.accent
                    font.pixelSize: 14
                }
                Label {
                    text: view.releaseInfo ? view.releaseInfo.publishedAt : ""
                    color: Material.hintTextColor
                    font.pixelSize: 12
                }
                Label {
                    text: "<a href='gh'>View this release on GitHub</a>"
                    textFormat: Text.RichText
                    font.pixelSize: 16
                    linkColor: "#8FCBFF"; font.bold: true
                    visible: view.releaseInfo && view.releaseInfo.htmlUrl && view.releaseInfo.htmlUrl.length > 0
                    onLinkActivated: Qt.openUrlExternally(view.releaseInfo.htmlUrl)
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                Label { text: "Notes"; font.bold: true; font.pixelSize: 14 }
                Label {
                    text: view.releaseInfo ? view.releaseInfo.body : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    font.pixelSize: 14
                    lineHeight: 1.25
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                Label { text: "Assets (manual download)"; font.bold: true; font.pixelSize: 14 }
                Repeater {
                    model: view.releaseInfo ? view.releaseInfo.assets : []
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Label {
                            text: modelData.name
                            font.pixelSize: 12
                            wrapMode: Text.WrapAnywhere
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
                                view.flashAfterDownload = false
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
                font.pixelSize: 26
                font.bold: true
                color: "#C9A227"   // darker yellow
                Layout.topMargin: 24
                Layout.leftMargin: 24
            }

            // Subtitle — firmware-agnostic wording, sits a little below the title
            Label {
                text: "Flash firmware to an M1 over USB DFU — a bootloader mode built into the " +
                      "chip itself. Use it to move from the stock Monstatek firmware to a custom " +
                      "community build, or to recover a device that won't boot normally."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                color: "white"
                font.pixelSize: 15
            }

            // ── Help links (blue, underlined → open explainer popups) ──
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                spacing: 26

                Label {
                    text: "<a href='dfu'>What is DFU?</a>"
                    textFormat: Text.RichText
                    font.pixelSize: 15
                    linkColor: "#8FCBFF"; font.bold: true
                    onLinkActivated: dfuInfoDialog.open()
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                }
                Label {
                    text: "<a href='enter'>How to enter DFU mode</a>"
                    textFormat: Text.RichText
                    font.pixelSize: 15
                    linkColor: "#8FCBFF"; font.bold: true
                    onLinkActivated: dfuEnterDialog.open()
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                }
                Label {
                    text: "<a href='trouble'>Troubleshooting</a>"
                    textFormat: Text.RichText
                    font.pixelSize: 15
                    linkColor: "#8FCBFF"; font.bold: true
                    onLinkActivated: dfuTroubleshootDialog.open()
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
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
                                  : "No DFU device found. Enter DFU mode on your M1."
                            font.bold: true
                            font.pixelSize: 14
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "Scan"
                            enabled: !dfuFlasher.flashing
                            onClicked: dfuFlasher.scanOnce()
                        }
                    }

                    Label {
                        text: dfuFlasher.dfuDeviceInfo
                        visible: dfuFlasher.dfuDeviceFound && dfuFlasher.dfuDeviceInfo.length > 0
                        font.pixelSize: 13
                        color: Material.hintTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Guidance shown when no DFU device is present
                    Label {
                        visible: !dfuFlasher.dfuDeviceFound && !dfuFlasher.flashing
                        text: "Put your M1 into DFU mode, then press Scan. New to this? " +
                              "Open 'How to enter DFU mode' above for illustrated steps."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 12
                        color: Material.hintTextColor
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Layout.preferredHeight: 1
                        color: Material.dividerColor
                    }

                    // Requirement + one-time driver setup (collapsed into links)
                    Label {
                        text: "Flashing is handled by STM32CubeProgrammer, a free tool from " +
                              "STMicroelectronics that qMonstatek runs for you. Install it once " +
                              "before your first flash."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 12
                        color: Material.hintTextColor
                    }

                    Flow {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        spacing: 24

                        Label {
                            text: "<a href='cube'>Get STM32CubeProgrammer</a>"
                            textFormat: Text.RichText
                            font.pixelSize: 15
                            linkColor: "#8FCBFF"; font.bold: true
                            onLinkActivated: Qt.openUrlExternally("https://www.st.com/en/development-tools/stm32cubeprog.html")
                            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                        }
                        Label {
                            visible: Qt.platform.os === "windows"
                            text: "<a href='zadig'>Windows USB driver setup</a>"
                            textFormat: Text.RichText
                            font.pixelSize: 15
                            linkColor: "#8FCBFF"; font.bold: true
                            onLinkActivated: zadigDialog.open()
                            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                        }
                        Label {
                            visible: Qt.platform.os === "linux"
                            text: "<a href='udev'>Linux USB permissions</a>"
                            textFormat: Text.RichText
                            font.pixelSize: 15
                            linkColor: "#8FCBFF"; font.bold: true
                            onLinkActivated: udevDialog.open()
                            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                        }
                    }

                    // CubeProgrammer availability warning
                    Label {
                        visible: !dfuFlasher.isToolAvailable()
                        text: "STM32CubeProgrammer is not installed.\n\n" +
                              "Download it free from st.com (search 'STM32CubeProgrammer').\n" +
                              "Install to the default location, then restart qMonstatek."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 13
                        color: "#F44336"
                    }
                }
            }

            // ── Firmware: choose a source, then flash ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 14

                    Label {
                        text: "Update Firmware"
                        font.bold: true
                        font.pixelSize: 17
                    }

                    // Step 1 — choose the firmware to flash
                    Label {
                        text: "1.  Choose firmware"
                        font.bold: true
                        font.pixelSize: 15
                    }

                    RowLayout {
                        spacing: 12
                        Button {
                            text: "Browse this PC…"
                            enabled: !dfuFlasher.flashing
                            onClicked: {
                                var f = uiSettings.dialogFolder("dfuOpen")
                                if (f != "") fileDialog.currentFolder = f
                                fileDialog.open()
                            }
                        }
                        Label {
                            text: "Pick a firmware .bin already saved on your computer."
                            font.pixelSize: 13
                            color: Material.hintTextColor
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    RowLayout {
                        spacing: 12
                        Button {
                            text: githubChecker.checking ? "Checking…" : "Check for latest release"
                            enabled: !githubChecker.checking && !view.downloading
                            onClicked: {
                                view.releaseInfo = null
                                ghStatusLabel.visible = false
                                ghStatusLabel.color = Material.hintTextColor
                                githubChecker.checkForUpdates(0, 0, 0, 0, 0)
                            }
                        }
                        Label {
                            text: "Fetch the newest firmware from " + githubChecker.repoUrl +
                                  ". Choose a different repo in Settings."
                            font.pixelSize: 13
                            color: Material.hintTextColor
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    Label {
                        id: ghStatusLabel
                        visible: false
                        font.pixelSize: 13
                        color: Material.hintTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        height: 1
                        color: Material.dividerColor
                    }

                    Label {
                        text: view.selectedFileName.length > 0
                              ? "Selected firmware:  " + view.selectedFileName
                              : "No firmware chosen yet."
                        color: view.selectedFileName.length > 0 ? Material.accent : Material.hintTextColor
                        font.pixelSize: 14
                        font.bold: view.selectedFileName.length > 0
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }

                    // Step 2 — pick the destination bank and flash
                    Label {
                        text: "2.  Flash to the M1"
                        font.bold: true
                        font.pixelSize: 15
                        Layout.topMargin: 4
                    }

                    RowLayout {
                        spacing: 12

                        Label {
                            text: "Destination:"
                            font.pixelSize: 13
                        }

                        ComboBox {
                            id: flashTargetCombo
                            model: ["Inactive bank (safest)", "Bank 1", "Bank 2"]
                            currentIndex: view.flashTargetIndex
                            onCurrentIndexChanged: view.flashTargetIndex = currentIndex
                            enabled: !dfuFlasher.flashing
                            // Size to the widest item so the label isn't clipped
                            implicitContentWidthPolicy: ComboBox.WidestText
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // Latest-release summary (after "Check for latest release")
                    RowLayout {
                        visible: view.releaseInfo !== null
                        spacing: 16

                        Label {
                            text: "Latest on " + githubChecker.repoUrl + ":  " +
                                  (view.releaseInfo ? view.releaseInfo.versionFormatted : "")
                            font.pixelSize: 14
                            color: Material.accent
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Label {
                            text: "<a href='notes'>Release Notes</a>"
                            textFormat: Text.RichText
                            font.pixelSize: 16
                            linkColor: "#8FCBFF"; font.bold: true
                            onLinkActivated: releaseNotesDialog.open()
                            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                        }
                    }

                    RowLayout {
                        spacing: 12

                        Button {
                            text: "Flash Selected File"
                            highlighted: true
                            enabled: dfuFlasher.dfuDeviceFound && !dfuFlasher.flashing && view.selectedFileName.length > 0
                            onClicked: {
                                flashConfirmDialog.selectedFile = view.selectedFilePath
                                flashConfirmDialog.displayName = view.selectedFileName
                                flashConfirmDialog.open()
                            }
                        }

                        Button {
                            text: view.downloading ? "Downloading…" : "Download and Flash Latest"
                            visible: view.releaseInfo !== null
                            enabled: !view.downloading && !dfuFlasher.flashing
                            onClicked: {
                                var asset = view.pickFirmwareAsset()
                                if (!asset) { releaseNotesDialog.open(); return }
                                view.flashAfterDownload = true
                                view.downloading = true
                                view.downloadedFilePath = ""
                                githubChecker.downloadAsset(asset.downloadUrl, asset.name)
                            }
                        }
                    }

                    ProgressBar {
                        visible: view.downloading
                        Layout.fillWidth: true
                        value: view.downloadPercent / 100.0
                    }

                    Label {
                        text: {
                            switch (view.flashTargetIndex) {
                            case 0: return "Writes to the non-active bank, then swaps to it. Safest — your current firmware stays intact until the new one boots."
                            case 1: return "Writes to bank 1 and boots from bank 1."
                            case 2: return "Writes to bank 2 and boots from bank 2."
                            }
                        }
                        font.pixelSize: 12
                        color: Material.hintTextColor
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        visible: view.selectedFileName.length > 0 && !dfuFlasher.dfuDeviceFound
                        text: "Put the M1 into DFU mode and press Scan above to enable flashing."
                        font.pixelSize: 12
                        color: "#E0A030"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // ── Flash progress (phase + real percentage) ──
            ColumnLayout {
                visible: dfuFlasher.flashing
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Label {
                        text: dfuFlasher.statusMessage.length > 0
                              ? dfuFlasher.statusMessage
                              : "Preparing…"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Label {
                        // Only show a number once CubeProgrammer reports real progress
                        text: dfuFlasher.progress > 0 ? dfuFlasher.progress + "%" : ""
                        font.pixelSize: 14
                        font.bold: true
                        color: Material.accent
                    }
                }

                ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: dfuFlasher.progress
                    // Before the first % arrives (connecting / erasing) the exact
                    // amount is unknown, so animate instead of sitting at zero.
                    indeterminate: dfuFlasher.progress <= 0
                }
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

            // ── Swap flash bank (advanced) ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: "Swap Flash Bank (advanced)"
                        font.bold: true
                        font.pixelSize: 15
                    }

                    Label {
                        text: "Boot the M1 from its other flash bank without flashing anything new — " +
                              "useful to roll back to the firmware already stored in the inactive bank."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 13
                        color: Material.hintTextColor
                    }

                    Label {
                        text: "<a href='bank'>What's a flash bank?</a>"
                        textFormat: Text.RichText
                        font.pixelSize: 15
                        linkColor: "#8FCBFF"; font.bold: true
                        onLinkActivated: bankInfoDialog.open()
                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                    }

                    Button {
                        text: "Swap Bank"
                        enabled: dfuFlasher.dfuDeviceFound && !dfuFlasher.flashing
                        onClicked: swapBankConfirmDialog.open()
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
