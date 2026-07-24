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
    property bool flashAfterDownload: false   // set by "Download and Flash"
    property bool lastOpWasFlash: false        // so the done popup only follows a flash

    function basename(p) {
        var parts = p.split(/[/\\]/)
        return parts[parts.length - 1]
    }

    // Prefer the CRC-injected *_wCRC.bin, then any .bin that isn't an ESP/factory image.
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
    // (e.g. a working device connects while the user is on SWD Flash).
    function closeAllPopups() {
        swdInfoDialog.close()
        swdWiringDialog.close()
        swdProbeDialog.close()
        swdTroubleshootDialog.close()
        bankInfoDialog.close()
        swdDoneDialog.close()
        recoveryConfirmDialog.close()
        swapConfirmDialog.close()
        cloneConfirmDialog.close()
    }

    // ── SWD signals ──
    Connections {
        target: swdRecovery
        function onOperationComplete(message) {
            statusLabel.color = "#4CAF50"
            if (view.lastOpWasFlash) {
                view.lastOpWasFlash = false
                swdDoneDialog.open()
            }
        }
        function onOperationError(message) {
            statusLabel.color = "#F44336"
            view.lastOpWasFlash = false
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
            // The check runs with version 0, so a real release fires onReleaseFound.
            // This branch means the selected repo has no published release at all.
            swdGhStatusLabel.text = "No firmware release found on " + githubChecker.repoUrl +
                                    ". This repo may not publish releases — download the .bin " +
                                    "from its Releases page, then use 'Browse this PC' above."
            swdGhStatusLabel.color = "#E0A030"
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
            view.selectedFilePath = filePath
            view.selectedFileName = view.basename(filePath)
            // "Download and Flash": jump to the confirm dialog if the tool is ready.
            if (view.flashAfterDownload) {
                view.flashAfterDownload = false
                if (swdRecovery.isOpenOcdAvailable())
                    recoveryConfirmDialog.open()
            }
        }
    }

    // ===================== Popups =====================

    // ── "What is SWD?" explainer ──
    Dialog {
        id: swdInfoDialog
        title: "What is SWD?"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 560)
        height: Math.min(view.height - 80, 520)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: swdInfoDialog.availableWidth
                spacing: 12

                Label {
                    text: "SWD (Serial Wire Debug) is a two-wire hardware interface built into the " +
                          "M1's STM32 chip. With a small debug probe it gives your PC direct control " +
                          "of the processor and its flash memory."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }
                Label {
                    text: "Because it talks to the silicon directly, SWD can recover an M1 even when " +
                          "its firmware is completely dead and DFU mode can't be reached — it's the " +
                          "deepest recovery path short of replacing the chip."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }
                Label {
                    text: "It needs two things a normal update doesn't: a hardware debug probe (a " +
                          "Raspberry Pi Pico running debug firmware, or an ST-Link) and a few wires " +
                          "to the M1's flash header. Prefer DFU or a normal update when the device " +
                          "still boots — reach for SWD when nothing else works."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                    color: Material.hintTextColor
                }
            }
        }
    }

    // ── "Wiring & pin diagram" popup (with photo) ──
    Dialog {
        id: swdWiringDialog
        title: "Wiring & pin diagram"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 620)
        height: Math.min(view.height - 80, 700)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: swdWiringDialog.availableWidth
                spacing: 12

                Label {
                    text: "Connect your debug probe to the M1's flash header using these pins:"
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }

                GridLayout {
                    columns: 3
                    columnSpacing: 24
                    rowSpacing: 6

                    Label { text: "Signal"; font.bold: true; font.pixelSize: 13 }
                    Label { text: "M1 header pin"; font.bold: true; font.pixelSize: 13 }
                    Label { text: "STM32 GPIO"; font.bold: true; font.pixelSize: 13 }

                    Label { text: "SWCLK"; font.pixelSize: 13 }
                    Label { text: "Pin 10"; font.pixelSize: 13 }
                    Label { text: "PA14"; font.pixelSize: 13; color: Material.hintTextColor }

                    Label { text: "SWDIO"; font.pixelSize: 13 }
                    Label { text: "Pin 11"; font.pixelSize: 13 }
                    Label { text: "PA13"; font.pixelSize: 13; color: Material.hintTextColor }

                    Label { text: "GND"; font.pixelSize: 13 }
                    Label { text: "Pin 8 or 18"; font.pixelSize: 13 }
                    Label { text: ""; font.pixelSize: 13 }

                    Label { text: "+3.3V"; font.pixelSize: 13 }
                    Label { text: "Pin 9"; font.pixelSize: 13 }
                    Label { text: "(or just power the M1 by USB)"; font.pixelSize: 13; color: Material.hintTextColor }
                }

                Image {
                    source: "qrc:/images/swd_recovery.png"
                    fillMode: Image.PreserveAspectFit
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.maximumWidth: 420
                    visible: status === Image.Ready
                }

                Label {
                    text: "Power the M1 from its own USB cable while flashing. Keep the wires short, " +
                          "and double-check that SWCLK and SWDIO aren't swapped."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13
                    color: Material.hintTextColor
                }
            }
        }
    }

    // ── "Debug probe setup" popup (Pico + ST-Link) ──
    Dialog {
        id: swdProbeDialog
        title: "Debug probe setup"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 620)
        height: Math.min(view.height - 80, 700)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: swdProbeDialog.availableWidth
                spacing: 12

                // ── Required software ──
                Label { text: "Required software"; font.bold: true; font.pixelSize: 15 }
                Label {
                    text: "Each probe needs one free tool installed before flashing. The Debug probe " +
                          "panel on the main screen turns green once it's found."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13; color: Material.hintTextColor
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Label { text: "Pico → OpenOCD"; font.pixelSize: 13; font.bold: true }
                    Label {
                        text: "<a href='ide'>Get STM32CubeIDE (includes OpenOCD)</a>"
                        textFormat: Text.RichText; font.pixelSize: 14
                        linkColor: "#8FCBFF"; font.bold: true
                        onLinkActivated: Qt.openUrlExternally("https://www.st.com/en/development-tools/stm32cubeide.html")
                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                    }
                    Item { Layout.fillWidth: true }
                }
                Label {
                    text: "OpenOCD ships inside STM32CubeIDE. Advanced: drop a standalone OpenOCD build " +
                          "(openocd.org) into an openocd/ folder next to qmonstatek.exe."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 12; color: Material.hintTextColor
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Label { text: "ST-Link → STM32CubeProgrammer"; font.pixelSize: 13; font.bold: true }
                    Label {
                        text: "<a href='cube'>Get STM32CubeProgrammer</a>"
                        textFormat: Text.RichText; font.pixelSize: 14
                        linkColor: "#8FCBFF"; font.bold: true
                        onLinkActivated: Qt.openUrlExternally("https://www.st.com/en/development-tools/stm32cubeprog.html")
                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                    }
                    Item { Layout.fillWidth: true }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                // ── Pico ──
                Label { text: "Raspberry Pi Pico (CMSIS-DAP)"; font.bold: true; font.pixelSize: 15 }

                Label {
                    text: "<a href='pico'>Download debugprobe_on_pico.uf2</a>"
                    textFormat: Text.RichText
                    font.pixelSize: 15
                    linkColor: "#8FCBFF"; font.bold: true
                    onLinkActivated: Qt.openUrlExternally("https://github.com/raspberrypi/debugprobe/releases")
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                }

                Repeater {
                    model: [
                        "Hold the BOOTSEL button on the Pico and plug it into USB.",
                        "It appears as a USB drive (RPI-RP2) — drag the .uf2 file onto it.",
                        "The Pico reboots automatically as a CMSIS-DAP debug probe."
                    ]
                    delegate: RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Label { text: (index + 1) + "."; font.bold: true; Layout.alignment: Qt.AlignTop }
                        Label { text: modelData; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13 }
                    }
                }

                Label { text: "Pico wiring:"; font.bold: true; font.pixelSize: 13; Layout.topMargin: 4 }
                GridLayout {
                    columns: 2
                    columnSpacing: 24
                    rowSpacing: 4
                    Label { text: "Pico pin"; font.bold: true; font.pixelSize: 13 }
                    Label { text: "M1 connection"; font.bold: true; font.pixelSize: 13 }
                    Label { text: "GP2 (pin 4)"; font.pixelSize: 13 }
                    Label { text: "SWCLK → M1 header pin 10"; font.pixelSize: 13 }
                    Label { text: "GP3 (pin 5)"; font.pixelSize: 13 }
                    Label { text: "SWDIO → M1 header pin 11"; font.pixelSize: 13 }
                    Label { text: "GND (pin 3)"; font.pixelSize: 13 }
                    Label { text: "GND → M1 header pin 8 or 18"; font.pixelSize: 13 }
                }
                Label {
                    text: "Power the M1 from its own USB cable — the Pico's 3V3 OUT (~300 mA) may not " +
                          "be enough."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13; color: Material.hintTextColor
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                // ── ST-Link ──
                Label { text: "ST-Link V2"; font.bold: true; font.pixelSize: 15 }
                Label {
                    text: "Connect the ST-Link to your PC via USB and wire SWCLK → pin 10, " +
                          "SWDIO → pin 11, GND → pin 8 or 18. Power the M1 from its own USB cable."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13
                }
                Label {
                    text: "If you're using a Nucleo board's built-in ST-Link, remove the CN2 jumpers " +
                          "to free it from the onboard MCU."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13; color: Material.hintTextColor
                }
            }
        }
    }

    // ── "Troubleshooting" popup ──
    Dialog {
        id: swdTroubleshootDialog
        title: "SWD troubleshooting"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 600)
        height: Math.min(view.height - 80, 560)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: swdTroubleshootDialog.availableWidth
                spacing: 16

                Repeater {
                    model: [
                        {
                            q: "The probe or tool isn't detected",
                            a: "Check the tool status on the main screen. For a Pico you need OpenOCD; " +
                               "for ST-Link you need STM32CubeProgrammer. Install the matching tool, then " +
                               "reopen this screen."
                        },
                        {
                            q: "The operation fails to connect to the M1",
                            a: "Confirm the wiring — SWCLK to pin 10, SWDIO to pin 11, a solid GND — and " +
                               "make sure the M1 has power over its own USB cable. Swapped SWCLK/SWDIO is " +
                               "the most common cause."
                        },
                        {
                            q: "It connects but the flash fails partway",
                            a: "Keep the jumper wires short and the M1 powered the whole time. Long or loose " +
                               "wires cause dropouts at SWD speed. Try again — the Output Log below shows " +
                               "exactly where it stopped."
                        },
                        {
                            q: "When should I use SWD instead of DFU?",
                            a: "Use DFU (or a normal update) whenever the M1 still boots. SWD is for a truly " +
                               "bricked device that can't reach DFU mode."
                        }
                    ]
                    delegate: ColumnLayout {
                        Layout.fillWidth: true; spacing: 3
                        Label { text: modelData.q; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14 }
                        Label { text: modelData.a; wrapMode: Text.WordWrap; Layout.fillWidth: true; color: Material.hintTextColor; font.pixelSize: 13 }
                    }
                }
            }
        }
    }

    // ── "What's a flash bank?" explainer ──
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
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }
                Label {
                    text: "Only one bank is active and running at a time; the other sits idle as a " +
                          "spare. That means two firmware builds can live on the device side by side."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }
                Label {
                    text: "A normal update writes to the inactive bank and then switches which bank " +
                          "boots, so a bad update can't erase your known-good version — that's what " +
                          "makes updates safe to roll back."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                Label { text: "The SWD bank tools"; font.bold: true; font.pixelSize: 14 }
                Label {
                    text: "Swap Bank flips which bank boots (nothing is erased). Clone Bank copies " +
                          "Bank 1 into Bank 2 as a backup. Verify Bank 1 / Verify Bank 2 compare that " +
                          "bank's contents against a firmware file — handy to confirm what's installed " +
                          "without reflashing. Read Status reports which bank is currently active."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14; color: Material.hintTextColor
                }
            }
        }
    }

    // ── Completion popup after a successful SWD flash ──
    Dialog {
        id: swdDoneDialog
        title: "Flash complete"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 520)
        standardButtons: Dialog.Ok

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                text: "Firmware flashed over SWD."
                font.pixelSize: 16; font.bold: true; color: "#4CAF50"
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 460
            }
            Label {
                text: "The M1 was reset automatically and is booting the new firmware. You can " +
                      "disconnect the debug probe once it starts up."
                font.pixelSize: 14; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 460
            }
        }
    }

    // ===================== Main content =====================

    ScrollView {
        anchors.fill: parent

        ColumnLayout {
            width: view.width
            spacing: 16
            anchors.margins: 24

            // ── Title ──
            Label {
                text: "SWD Flash"
                font.pixelSize: 26
                font.bold: true
                color: "#C9A227"   // darker yellow
                Layout.topMargin: 24
                Layout.leftMargin: 24
            }

            // Subtitle — firmware-agnostic, sits a little below the title
            Label {
                text: "Flash an M1 through a hardware debug probe (SWD) — the deepest recovery path. " +
                      "It works even when the M1 is completely unresponsive and can't reach DFU mode, " +
                      "but it needs a debug probe (a Raspberry Pi Pico or an ST-Link) wired to the M1."
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
                    text: "<a href='s'>What is SWD?</a>"
                    textFormat: Text.RichText
                    font.pixelSize: 15
                    linkColor: "#8FCBFF"; font.bold: true
                    onLinkActivated: swdInfoDialog.open()
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                }
                Label {
                    text: "<a href='w'>Wiring & pin diagram</a>"
                    textFormat: Text.RichText
                    font.pixelSize: 15
                    linkColor: "#8FCBFF"; font.bold: true
                    onLinkActivated: swdWiringDialog.open()
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                }
                Label {
                    text: "<a href='p'>Probe setup</a>"
                    textFormat: Text.RichText
                    font.pixelSize: 15
                    linkColor: "#8FCBFF"; font.bold: true
                    onLinkActivated: swdProbeDialog.open()
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                }
                Label {
                    text: "<a href='t'>Troubleshooting</a>"
                    textFormat: Text.RichText
                    font.pixelSize: 15
                    linkColor: "#8FCBFF"; font.bold: true
                    onLinkActivated: swdTroubleshootDialog.open()
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                }
            }

            // ── Debug probe (selector + tool status) ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    Label {
                        text: "Debug probe"
                        font.bold: true
                        font.pixelSize: 16
                    }

                    RowLayout {
                        spacing: 12

                        Label { text: "Probe:"; font.pixelSize: 13 }

                        ComboBox {
                            id: probeCombo
                            model: ["Pico (CMSIS-DAP)", "ST-Link V2"]
                            currentIndex: swdRecovery.probeType
                            onCurrentIndexChanged: swdRecovery.probeType = currentIndex
                            enabled: !swdRecovery.running
                            // Size to the widest item so the label isn't clipped
                            implicitContentWidthPolicy: ComboBox.WidestText
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // Tool status (OpenOCD for Pico, STM32CubeProgrammer for ST-Link)
                    RowLayout {
                        spacing: 8

                        Rectangle {
                            width: 12; height: 12; radius: 6
                            color: swdRecovery.isOpenOcdAvailable() ? "#4CAF50" : "#F44336"
                        }
                        Label {
                            property bool isStLink: swdRecovery.probeType === 1
                            property string toolName: isStLink ? "STM32CubeProgrammer" : "OpenOCD"
                            text: swdRecovery.isOpenOcdAvailable() ? toolName + " found" : toolName + " not found"
                            font.pixelSize: 14
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Label {
                        property bool isStLink: swdRecovery.probeType === 1
                        text: swdRecovery.isOpenOcdAvailable()
                              ? swdRecovery.openOcdLocation()
                              : isStLink
                                ? "Install STM32CubeProgrammer from st.com, then reopen this screen."
                                : Qt.platform.os === "windows"
                                  ? "Install STM32CubeIDE, or place OpenOCD in an openocd/ folder next to qmonstatek.exe."
                                  : "Install STM32CubeIDE or OpenOCD (brew install openocd / apt install openocd)."
                        font.pixelSize: 13
                        color: Material.hintTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "New to this? See Wiring & pin diagram and Probe setup above."
                        font.pixelSize: 13
                        color: Material.hintTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
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
                        text: "Recover / Update Firmware"
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
                            enabled: !swdRecovery.running
                            onClicked: {
                                var f = uiSettings.dialogFolder("swdOpen")
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
                            enabled: !githubChecker.checking && !view.downloading && !swdRecovery.running
                            onClicked: {
                                view.releaseInfo = null
                                swdGhStatusLabel.visible = false
                                swdGhStatusLabel.color = Material.hintTextColor
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
                        id: swdGhStatusLabel
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

                    // Step 2 — flash it over SWD
                    Label {
                        text: "2.  Flash to the M1"
                        font.bold: true
                        font.pixelSize: 15
                        Layout.topMargin: 4
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
                            enabled: !swdRecovery.running && swdRecovery.isOpenOcdAvailable() &&
                                     view.selectedFileName.length > 0
                            onClicked: recoveryConfirmDialog.open()
                        }

                        Button {
                            text: view.downloading ? "Downloading…" : "Download and Flash Latest"
                            visible: view.releaseInfo !== null
                            enabled: !view.downloading && !swdRecovery.running && swdRecovery.isOpenOcdAvailable()
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
                        text: "Flashes the firmware to Bank 1 with a forced halt, verifies the write, " +
                              "and resets the M1 — the primary recovery method."
                        font.pixelSize: 12
                        color: Material.hintTextColor
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        visible: view.selectedFileName.length > 0 && !swdRecovery.isOpenOcdAvailable()
                        text: "The required tool for this probe isn't installed yet — see the note above."
                        font.pixelSize: 12
                        color: "#E0A030"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // ── Advanced bank operations ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        Label {
                            text: "Advanced bank operations"
                            font.bold: true
                            font.pixelSize: 16
                            Layout.fillWidth: true
                        }
                        Label {
                            text: "<a href='bank'>What's a flash bank?</a>"
                            textFormat: Text.RichText
                            font.pixelSize: 15
                            linkColor: "#8FCBFF"; font.bold: true
                            onLinkActivated: bankInfoDialog.open()
                            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                        }
                    }

                    // Swap Bank
                    RowLayout {
                        spacing: 12
                        Button {
                            text: "Swap Bank"
                            enabled: !swdRecovery.running && swdRecovery.isOpenOcdAvailable()
                            onClicked: swapConfirmDialog.open()
                            Layout.preferredWidth: 160
                        }
                        Label {
                            text: "Boot from the other flash bank (toggles the SWAP_BANK option byte). Nothing is erased."
                            wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13; color: Material.hintTextColor
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                    // Verify Bank 1 (active bank)
                    RowLayout {
                        spacing: 12
                        Button {
                            text: "Verify Bank 1"
                            enabled: !swdRecovery.running && swdRecovery.isOpenOcdAvailable() &&
                                     view.selectedFileName.length > 0
                            onClicked: swdRecovery.verifyBank1(view.selectedFilePath)
                            Layout.preferredWidth: 160
                        }
                        Label {
                            text: "Check the firmware already on Bank 1 against the selected file — without reflashing."
                            wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13; color: Material.hintTextColor
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                    // Verify Bank 2
                    RowLayout {
                        spacing: 12
                        Button {
                            text: "Verify Bank 2"
                            enabled: !swdRecovery.running && swdRecovery.isOpenOcdAvailable() &&
                                     view.selectedFileName.length > 0
                            onClicked: swdRecovery.verifyBank2(view.selectedFilePath)
                            Layout.preferredWidth: 160
                        }
                        Label {
                            text: "Compare Bank 2's contents against the selected firmware file."
                            wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13; color: Material.hintTextColor
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                    // Clone Bank 1 -> Bank 2
                    RowLayout {
                        spacing: 12
                        Button {
                            text: "Clone Bank"
                            enabled: !swdRecovery.running && swdRecovery.isOpenOcdAvailable()
                            onClicked: cloneConfirmDialog.open()
                            Layout.preferredWidth: 160
                        }
                        Label {
                            text: "Copy Bank 1 into Bank 2 as a safety backup."
                            wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13; color: Material.hintTextColor
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                    // Read Status
                    RowLayout {
                        spacing: 12
                        Button {
                            text: "Read Status"
                            enabled: !swdRecovery.running && swdRecovery.isOpenOcdAvailable()
                            onClicked: swdRecovery.readStatus()
                            Layout.preferredWidth: 160
                        }
                        Label {
                            text: "Read the OPTR register to see which bank is currently active."
                            wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13; color: Material.hintTextColor
                        }
                    }
                }
            }

            // ── Operation progress (phase + percentage) ──
            ColumnLayout {
                visible: swdRecovery.running
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Label {
                        text: swdRecovery.statusMessage.length > 0 ? swdRecovery.statusMessage : "Working…"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Label {
                        text: swdRecovery.progress > 0 ? swdRecovery.progress + "%" : ""
                        font.pixelSize: 14; font.bold: true; color: Material.accent
                    }
                }

                ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: swdRecovery.progress
                    indeterminate: swdRecovery.progress <= 0
                }
            }

            // ── Result / status (when not running) ──
            Label {
                id: statusLabel
                text: swdRecovery.statusMessage
                visible: !swdRecovery.running && swdRecovery.statusMessage.length > 0
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                font.pixelSize: 13
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
                            font.pixelSize: 12
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
                            font.pixelSize: 12
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
                            font.family: Qt.platform.os === "windows" ? "Consolas"
                                       : Qt.platform.os === "osx" ? "Menlo" : "monospace"
                            font.pixelSize: 12
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
                    font.pixelSize: 17; font.bold: true
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                Label {
                    text: view.releaseInfo
                          ? view.releaseInfo.versionFormatted +
                            (view.releaseInfo.prerelease ? "   (pre-release)" : "")
                          : ""
                    color: Material.accent; font.pixelSize: 14
                }
                Label {
                    text: view.releaseInfo ? view.releaseInfo.publishedAt : ""
                    color: Material.hintTextColor; font.pixelSize: 12
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
                        Label { text: modelData.name; font.pixelSize: 12; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
                        Label { text: (modelData.size / 1024).toFixed(0) + " KB"; font.pixelSize: 11; color: Material.hintTextColor }
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

    // ── File Dialog ──
    FileDialog {
        id: fileDialog
        title: "Select Firmware Binary"
        nameFilters: ["Binary files (*.bin)", "All files (*)"]
        Component.onCompleted: {
            var f = uiSettings.dialogFolder("swdOpen")
            if (f != "") currentFolder = f
        }
        onAccepted: {
            uiSettings.setDialogFolder("swdOpen", currentFolder)
            var path = selectedFile.toString().replace(root.filePathFilter, "")
            view.selectedFilePath = path
            view.selectedFileName = view.basename(path)
        }
    }

    // ── Confirmation Dialogs ──
    Dialog {
        id: recoveryConfirmDialog
        title: "Confirm SWD Flash"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12

            Label { text: "Flash firmware via SWD?"; font.bold: true; font.pixelSize: 14 }
            Label { text: "File: " + view.selectedFileName; font.pixelSize: 13 }
            Label {
                text: "This halts the MCU, flashes the firmware to Bank 1 (0x08000000), verifies the " +
                      "write, and resets the device. Make sure the debug probe is wired and the M1 is powered."
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                color: Material.hintTextColor
                Layout.preferredWidth: 440
            }
        }

        onAccepted: {
            view.lastOpWasFlash = true
            swdRecovery.recoveryFlash(view.selectedFilePath)
        }
    }

    Dialog {
        id: swapConfirmDialog
        title: "Confirm Bank Swap"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12
            Label { text: "Swap the active flash bank via SWD?"; font.bold: true; font.pixelSize: 14 }
            Label {
                text: "This toggles the SWAP_BANK option byte, so the device boots from the other " +
                      "flash bank after reset."
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                color: Material.hintTextColor
                Layout.preferredWidth: 440
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
            Label { text: "Clone Bank 1 to Bank 2?"; font.bold: true; font.pixelSize: 14 }
            Label {
                text: "This reads 1 MB from Bank 1 and writes it to Bank 2, overwriting Bank 2's " +
                      "contents. It takes roughly 30–60 seconds."
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                color: Material.hintTextColor
                Layout.preferredWidth: 440
            }
        }

        onAccepted: swdRecovery.cloneBank1ToBank2()
    }
}
