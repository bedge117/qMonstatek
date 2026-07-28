import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs
import "../components"

Item {
    id: view

    property var releaseInfo: null
    property bool downloading: false
    property int downloadPercent: 0
    property bool flashing: false
    property int flashPercent: 0
    property string flashStatus: ""
    property string selectedFilePath: ""
    property string selectedFileName: ""
    property string downloadedFilePath: ""
    property bool flashAfterDownload: false   // set by "Download and Flash"
    // True only while THIS view is driving the flash. The Factory Restore flow
    // also calls startFwUpdate; without this guard its shared fwUpdate* signals
    // would pop this view's dialogs over the Factory Restore screen.
    property bool ownFlash: false

    // Post-flash bank verification — the Dual Boot fwInfo, re-fetched when the
    // "Update written" dialog opens so the new bank's CRC is checked before a swap.
    property var fwInfo: null

    // Which firmware source the user picked — mutually exclusive so only one
    // Step-2 action is ever shown: "" (none) / "file" (Browse this PC) /
    // "release" (Check for updates). Choosing one clears the other.
    property string srcMode: ""

    // Unified Firmware Update page: switch to the other chip's pane, and run the
    // combined M1+ESP "check for updates" (both wired in main.qml).
    signal requestChip(string which)
    signal requestCheck()

    // Entered when a check-for-updates runs (from this pane or main.qml's unified
    // check): drop any browsed file so only the release path shows.
    function enterReleaseMode() {
        view.srcMode = "release"
        view.releaseInfo = null
        view.selectedFilePath = ""
        view.selectedFileName = ""
        view.flashStatus = ""
    }

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

    // newBank() = the bank the flash just wrote (currently inactive); curBank() = the
    // one running now. These + the formatters below mirror the Dual Boot cards.
    function newBank() { return !fwInfo ? null : (m1device.activeBank === 1 ? fwInfo.bank2 : fwInfo.bank1) }
    function curBank() { return !fwInfo ? null : (m1device.activeBank === 1 ? fwInfo.bank1 : fwInfo.bank2) }

    function isBankEmpty(b) {
        if (!b) return true
        if (b.major === 255 && b.minor === 255 && b.build === 255 && b.rc === 255) return true
        if (b.major === 0 && b.minor === 0 && b.build === 0 && b.rc === 0 && b.imageSize === 0) return true
        return false
    }
    function bankVerText(b) {
        if (!b) return "…"
        if (isBankEmpty(b)) return "Empty"
        var v = "v" + b.major + "." + b.minor + "." + b.build + "." + b.rc
        if (b.c3Revision > 0) v += "-C3." + b.c3Revision
        return v
    }
    function bankSizeText(b) {
        if (!b || isBankEmpty(b) || b.imageSize <= 0) return ""
        return (b.imageSize / 1024).toFixed(0) + " KB"
    }
    // True only if the new bank reads back as real, CRC-valid firmware — mirrors Dual
    // Boot's guard, so a corrupt write (even one FINISH reported "ok") can't be swapped.
    function newBankValid() {
        var b = newBank()
        if (!b || isBankEmpty(b)) return false
        if (b.imageSize > 0 && !b.crcValid) return false
        return true
    }

    function closeAllPopups() {
        bankInfoDialog.close()
        releaseNotesDialog.close()
        updateDoneDialog.close()
        fileConfirmDialog.close()
    }

    // ── Firmware-update signals ──
    Connections {
        target: m1device
        function onFwUpdateProgress(percent) {
            if (!view.ownFlash) return
            view.flashing = true
            view.flashPercent = percent
            view.flashStatus = "Writing firmware to the inactive bank…"
        }
        function onFwInfoReceived(info) {
            view.fwInfo = info
        }
        function onFwUpdateComplete() {
            if (!view.ownFlash) return
            view.ownFlash = false
            view.flashing = false
            view.flashStatus = "Success — firmware written and CRC-verified. Use Dual Boot to switch to it."
            flashStatusLabel.color = "#4CAF50"
            view.fwInfo = null          // show "verifying…" until fresh bank info arrives
            m1device.requestFwInfo()    // independently re-read the new bank's CRC
            updateDoneDialog.open()
        }
        function onFwUpdateError(message) {
            if (!view.ownFlash) return
            view.ownFlash = false
            view.flashing = false
            view.flashStatus = "Flash failed: " + message + "  —  reboot the M1 and try again."
            flashStatusLabel.color = "#F44336"
            flashErrorDialog.detail = message
            flashErrorDialog.open()
        }
    }

    // ── GitHub signals ──
    Connections {
        target: githubChecker
        function onReleaseFound(info) {
            view.releaseInfo = info
        }
        function onNoUpdateAvailable(message) {
            // Here the check uses the real device version, so this can mean
            // "already up to date" (good) OR the repo has no releases.
            if (message.indexOf("No releases") === 0) {
                ghStatusLabel.text = "No release found on " + githubChecker.repoUrl +
                    ". Download the .bin from its Releases page, then use 'Browse this PC'."
                ghStatusLabel.color = "#E0A030"
            } else {
                ghStatusLabel.text = message
                ghStatusLabel.color = "#4CAF50"
            }
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
            view.selectedFilePath = filePath
            view.selectedFileName = view.basename(filePath)
            if (view.flashAfterDownload) {
                view.flashAfterDownload = false
                if (m1device.connected) fileConfirmDialog.open()
            }
        }
    }

    // ===================== Popups =====================

    // Modal "flashing in progress" overlay — pops over everything so it can't be
    // missed at any window size, and blocks a second flash click.
    FlashProgressDialog {
        visible: view.flashing
        statusText: view.flashStatus
        percent: view.flashPercent
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
                    text: "An update here writes the new build to the inactive bank and leaves your " +
                          "running firmware untouched. Nothing changes until you switch banks in Dual " +
                          "Boot — so if a new build misbehaves, your known-good version is still there."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                Label {
                    text: "After flashing, open Dual Boot to make the new firmware active (the device " +
                          "reboots into it). You can switch back at any time."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14; color: Material.hintTextColor
                }
            }
        }
    }

    // ── Flash-failed popup — makes the "reboot first" fix unmistakable ──
    Dialog {
        id: flashErrorDialog
        title: "Update failed"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 560)
        standardButtons: Dialog.Close
        property string detail: ""

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                text: "The firmware update didn't complete."
                font.pixelSize: 16; font.bold: true; color: "#F44336"
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 480
            }
            Label {
                visible: flashErrorDialog.detail.length > 0
                text: "Reported: " + flashErrorDialog.detail
                font.pixelSize: 12; color: Material.hintTextColor
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 480
            }
            Label {
                text: "Reboot the M1, then flash again — this is almost always the fix."
                font.pixelSize: 15; font.bold: true; color: "#4CAF50"
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 480
            }
            Label {
                text: "The update needs a clean, contiguous flash buffer. If a background task is busy or " +
                      "the M1's memory is fragmented from earlier use, it can't get one and the write fails. " +
                      "A fresh reboot clears that state, and your current firmware is untouched, so it's safe to retry."
                font.pixelSize: 13; color: Material.hintTextColor
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 480
            }
            Button {
                text: "Reboot M1 now"
                highlighted: true
                enabled: m1device.connected
                onClicked: { m1device.reboot(); flashErrorDialog.close() }
            }
        }
    }

    // ── Troubleshooting / FAQ ──
    Dialog {
        id: updateFaqDialog
        title: "Firmware update — troubleshooting"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 600)
        height: Math.min(view.height - 80, 540)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: updateFaqDialog.availableWidth
                spacing: 16

                Repeater {
                    model: [
                        {
                            q: "The update failed or stalled",
                            a: "Reboot the M1 and try again — this is the number-one fix. Writing firmware needs " +
                               "a clean flash buffer; if a background task is busy or memory is fragmented from " +
                               "earlier use, the write can't proceed. A reboot clears it, and since the update only " +
                               "touches the inactive bank, your running firmware is safe to retry from."
                        },
                        {
                            q: "Do I need any extra software?",
                            a: "No. qMonstatek flashes the M1 directly over USB — no STM32CubeProgrammer or drivers " +
                               "needed (those are only for the DFU and SWD recovery screens)."
                        },
                        {
                            q: "Nothing changed after flashing",
                            a: "That's expected — the new build is written to the inactive bank and doesn't run yet. " +
                               "Open Dual Boot to switch the M1 to it (the device reboots into the new firmware)."
                        },
                        {
                            q: "It says I'm up to date but I want to reflash",
                            a: "Use \"Browse this PC\" and pick the .bin directly — that flashes it regardless of the " +
                               "version check."
                        },
                        {
                            q: "Which file do I flash here?",
                            a: "The M1 firmware image (usually the *_wCRC.bin from Releases). ESP32 firmware is flashed " +
                               "on the ESP32 Firmware tab of this page (the selector at the top), not here."
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

    // ── Completion popup (bank summary + one-click swap, or do it later) ──
    Dialog {
        id: updateDoneDialog
        title: "Update written"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 520)

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                text: "Firmware written to the inactive bank and CRC-verified."
                font.pixelSize: 16; font.bold: true; color: "#4CAF50"
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 460
            }

            // Bank summary — what's running now vs where the new build landed.
            Pane {
                visible: m1device.connected
                Layout.fillWidth: true
                Material.elevation: 0
                padding: 12
                background: Rectangle {
                    radius: 8
                    color: Material.theme === Material.Dark ? Qt.lighter(Material.backgroundColor, 1.3)
                                                            : Qt.darker(Material.backgroundColor, 1.03)
                    border.width: 1
                    border.color: Material.theme === Material.Dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.10)
                }
                RowLayout {
                    anchors.fill: parent
                    spacing: 16

                    // Currently-running (active) bank
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: 3
                        Label { text: "Currently running"; font.pixelSize: 11; color: Material.hintTextColor }
                        Label { text: "Bank " + m1device.activeBank; font.pixelSize: 15; font.bold: true }
                        Label { text: view.bankVerText(view.curBank()); font.pixelSize: 12 }
                        Label {
                            visible: view.fwInfo !== null
                            text: (view.curBank() && view.curBank().crcValid) ? "CRC: Valid" : "CRC: Invalid"
                            color: (view.curBank() && view.curBank().crcValid) ? "#4CAF50" : "#F44336"
                            font.pixelSize: 11
                        }
                        Label {
                            visible: view.bankSizeText(view.curBank()).length > 0
                            text: "Size: " + view.bankSizeText(view.curBank())
                            font.pixelSize: 11; color: Material.hintTextColor
                        }
                        Label {
                            visible: view.curBank() && view.curBank().buildDate && view.curBank().buildDate.length > 0
                            text: "Built: " + (view.curBank() ? view.curBank().buildDate : "")
                            font.pixelSize: 11; color: Material.hintTextColor
                        }
                    }

                    Label { text: "→"; font.pixelSize: 18; color: Material.hintTextColor; Layout.alignment: Qt.AlignVCenter }

                    // New firmware (the freshly-written, inactive bank)
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: 3
                        Label { text: "New firmware in"; font.pixelSize: 11; color: Material.hintTextColor }
                        Label { text: "Bank " + (m1device.activeBank === 1 ? 2 : 1); font.pixelSize: 15; font.bold: true; color: "#4CAF50" }
                        Label { text: view.bankVerText(view.newBank()); font.pixelSize: 12; font.bold: true; color: "#4CAF50" }
                        Label {
                            visible: view.fwInfo !== null
                            text: (view.newBank() && view.newBank().crcValid) ? "CRC: Valid" : "CRC: Invalid"
                            color: (view.newBank() && view.newBank().crcValid) ? "#4CAF50" : "#F44336"
                            font.pixelSize: 11
                        }
                        Label {
                            visible: view.bankSizeText(view.newBank()).length > 0
                            text: "Size: " + view.bankSizeText(view.newBank())
                            font.pixelSize: 11; color: Material.hintTextColor
                        }
                        Label {
                            visible: view.newBank() && view.newBank().buildDate && view.newBank().buildDate.length > 0
                            text: "Built: " + (view.newBank() ? view.newBank().buildDate : "")
                            font.pixelSize: 11; color: Material.hintTextColor
                        }
                    }
                }
            }

            // Independent verification of the freshly-written bank (belt-and-suspenders
            // beyond the flash's own CRC step) — so a corrupt/unreadable bank can never
            // be swapped into. The swap button stays disabled until this reads valid.
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label {
                    text: view.fwInfo === null ? "⟳" : (view.newBankValid() ? "✓" : "✕")
                    color: view.fwInfo === null ? Material.hintTextColor
                           : (view.newBankValid() ? "#4CAF50" : "#F44336")
                    font.pixelSize: 16; font.bold: true
                }
                Label {
                    text: view.fwInfo === null
                          ? "Verifying the new bank…"
                          : (view.newBankValid()
                             ? "New bank verified — CRC valid, safe to swap."
                             : "New bank did NOT verify (CRC invalid or unreadable). Do NOT swap — re-flash instead.")
                    color: view.fwInfo === null ? Material.hintTextColor
                           : (view.newBankValid() ? "#4CAF50" : "#F44336")
                    font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }

            Label {
                text: "Swap banks to boot the new firmware now — the M1 reboots into it. Or do it " +
                      "later in Dual Boot; either way you can switch back anytime."
                font.pixelSize: 14; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 460
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                Layout.topMargin: 4
                spacing: 10
                Button {
                    // "&&" renders a literal "&" (a single "&" is a keyboard mnemonic).
                    text: "Swap Bank && Reboot"
                    highlighted: true
                    enabled: m1device.connected && view.newBankValid()
                    onClicked: { m1device.swapBanks(); updateDoneDialog.close() }
                }
                Button {
                    text: "Later"
                    onClicked: updateDoneDialog.close()
                }
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
                    font.pixelSize: 17; font.bold: true
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                RowLayout {
                    spacing: 12
                    Label {
                        text: view.releaseInfo
                              ? view.releaseInfo.versionFormatted +
                                (view.releaseInfo.prerelease ? "   (pre-release)" : "")
                              : ""
                        color: Material.accent; font.pixelSize: 14
                    }
                    Label {
                        visible: view.releaseInfo && view.releaseInfo.isNewer
                        text: "NEWER THAN INSTALLED"
                        font.pixelSize: 13; font.bold: true; color: "#4CAF50"
                    }
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

    // ===================== Main content =====================

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Chip selector — LOCKED to the top (this one page covers M1 + ESP32) ──
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 20
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.bottomMargin: 8
            spacing: 8

            Label { text: "Update:"; font.pixelSize: 13; color: Material.hintTextColor }
            Button {
                text: "M1 Firmware"
                highlighted: true            // active pane
                onClicked: { /* already here */ }
            }
            Button {
                text: "ESP32 Firmware"
                onClicked: view.requestChip("esp")
            }
            Button {
                text: "Update All"
                onClicked: view.requestChip("all")
            }
        }

        // ── Scrolling middle ──
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

        ColumnLayout {
            width: view.width
            spacing: 16

            // ── Title ──
            Label {
                text: "M1 Firmware Update"
                font.pixelSize: 26
                font.bold: true
                color: "#4CAF50"   // green — the normal, healthy update path
                Layout.topMargin: 8
                Layout.leftMargin: 24
            }

            // Subtitle
            Label {
                text: "Install a firmware update over USB while your M1 is running — no extra software " +
                      "needed, qMonstatek flashes it directly. The new build is written to the spare " +
                      "flash bank, so your current firmware stays untouched until you switch to it in Dual Boot."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                color: Material.foreground
                font.pixelSize: 15
            }

            // ── Current firmware ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: "Installed firmware"
                        font.bold: true
                        font.pixelSize: 16
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Label {
                            text: m1device.connected ? m1device.firmwareVersion : "No device connected"
                            font.pixelSize: 14
                            font.bold: m1device.connected
                            color: m1device.connected ? Material.accent : Material.hintTextColor
                            Layout.fillWidth: true
                        }
                        Label {
                            text: "Active: Bank " + m1device.activeBank
                            visible: m1device.connected
                            font.pixelSize: 13
                            color: Material.hintTextColor
                        }
                    }
                }
            }

            // ── Update: choose a source, then flash ──
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

                    // Step 1 — choose the firmware
                    Label {
                        text: "1.  Choose firmware"
                        font.bold: true
                        font.pixelSize: 15
                    }

                    RowLayout {
                        spacing: 12
                        Button {
                            text: "Browse this PC…"
                            enabled: !view.flashing
                            onClicked: {
                                var f = uiSettings.dialogFolder("firmwareOpen")
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
                            text: (githubChecker.checking || esp32Checker.checking) ? "Checking…" : "Check for updates"
                            enabled: !githubChecker.checking && !esp32Checker.checking && !view.downloading && !view.flashing
                            onClicked: {
                                view.enterReleaseMode()
                                ghStatusLabel.visible = false
                                ghStatusLabel.color = Material.hintTextColor
                                view.requestCheck()
                            }
                        }
                        Label {
                            text: "Checks both chips against " + githubChecker.repoUrl +
                                  " and jumps to whichever needs an update. Choose a different repo in Settings."
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

                    // Nothing chosen yet — a single hint, no competing actions.
                    Label {
                        visible: view.srcMode === ""
                        text: "No firmware chosen yet — Browse this PC or Check for updates above."
                        color: Material.hintTextColor
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // ── FILE source: only the browsed file + its flash action ──
                    RowLayout {
                        visible: view.srcMode === "file"
                        Layout.fillWidth: true
                        spacing: 12
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
                    }

                    // Step 2 — flash it
                    Label {
                        text: "2.  Flash to the M1"
                        font.bold: true
                        font.pixelSize: 15
                        Layout.topMargin: 4
                    }

                    // ── RELEASE source: latest-release summary (after "Check for updates") ──
                    RowLayout {
                        visible: view.srcMode === "release" && view.releaseInfo !== null
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
                            visible: view.releaseInfo && view.releaseInfo.isNewer
                            text: "NEW"
                            font.pixelSize: 13; font.bold: true; color: "#4CAF50"
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

                        // FILE source → flash the browsed file
                        Button {
                            text: "Flash Selected File"
                            highlighted: true
                            visible: view.srcMode === "file"
                            enabled: m1device.connected && !view.flashing && view.selectedFileName.length > 0
                            onClicked: fileConfirmDialog.open()
                        }

                        // RELEASE source → download the latest and flash it
                        Button {
                            text: view.downloading ? "Downloading…" : "Download and Flash Latest"
                            visible: view.srcMode === "release" && view.releaseInfo !== null
                            enabled: !view.downloading && !view.flashing && m1device.connected
                            onClicked: {
                                var asset = view.pickFirmwareAsset()
                                if (!asset) { releaseNotesDialog.open(); return }
                                view.flashAfterDownload = true
                                view.downloading = true
                                view.downloadedFilePath = ""
                                githubChecker.downloadAsset(asset.downloadUrl, asset.name)
                            }
                        }

                        // Save a copy of a downloaded release (release source only)
                        Button {
                            text: "Save a copy…"
                            flat: true
                            font.pixelSize: 12
                            visible: view.srcMode === "release" && view.downloadedFilePath.length > 0 && !view.downloading
                            onClicked: {
                                var f = uiSettings.dialogFolder("firmwareSave")
                                if (f != "") saveDialog.currentFolder = f
                                saveDialog.open()
                            }
                        }
                    }

                    ProgressBar {
                        visible: view.downloading
                        Layout.fillWidth: true
                        value: view.downloadPercent / 100.0
                    }

                    Label {
                        text: "Writes to the inactive bank — your current firmware stays intact. " +
                              "Afterwards, use Dual Boot to switch to the new version."
                        font.pixelSize: 12
                        color: Material.hintTextColor
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        visible: view.selectedFileName.length > 0 && !m1device.connected
                        text: "Connect your M1 to enable flashing."
                        font.pixelSize: 12
                        color: "#E0A030"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // ── Flash progress (status + percentage) ──
            ColumnLayout {
                visible: view.flashing
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Label {
                        text: view.flashStatus.length > 0 ? view.flashStatus : "Flashing…"
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Label {
                        text: view.flashPercent > 0 ? view.flashPercent + "%" : ""
                        font.pixelSize: 14; font.bold: true; color: Material.accent
                    }
                }

                ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: view.flashPercent
                    indeterminate: view.flashPercent <= 0
                }
            }

            // ── Result / status (when not flashing) ──
            Label {
                id: flashStatusLabel
                visible: !view.flashing && view.flashStatus.length > 0
                text: view.flashStatus
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                font.pixelSize: 13
            }

            // Bottom spacer
            Item { Layout.preferredHeight: 24 }
        }
        }   // inner ScrollView

        // ── Help links — LOCKED to the bottom ──
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 6
            Layout.bottomMargin: 12
            spacing: 26

            Label {
                text: "<a href='bank'>What's a flash bank?</a>"
                textFormat: Text.RichText
                font.pixelSize: 15
                linkColor: "#8FCBFF"; font.bold: true
                onLinkActivated: bankInfoDialog.open()
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
            }
            Label {
                text: "<a href='faq'>Troubleshooting</a>"
                textFormat: Text.RichText
                font.pixelSize: 15
                linkColor: "#8FCBFF"; font.bold: true
                onLinkActivated: updateFaqDialog.open()
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
            }
        }
    }

    // ── File dialogs + confirm ──
    FileDialog {
        id: fileDialog
        title: "Select Firmware Binary"
        nameFilters: ["Binary files (*.bin)", "All files (*)"]
        Component.onCompleted: {
            var f = uiSettings.dialogFolder("firmwareOpen")
            if (f != "") currentFolder = f
        }
        onAccepted: {
            uiSettings.setDialogFolder("firmwareOpen", currentFolder)
            var path = selectedFile.toString().replace(root.filePathFilter, "")
            view.srcMode = "file"
            view.releaseInfo = null
            view.selectedFilePath = path
            view.selectedFileName = view.basename(path)
            flashStatusLabel.color = Material.foreground
            view.flashStatus = ""
        }
    }

    FileDialog {
        id: saveDialog
        title: "Save Firmware File"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Binary files (*.bin)", "All files (*)"]
        currentFile: "file:///" + view.basename(view.downloadedFilePath)
        Component.onCompleted: {
            var f = uiSettings.dialogFolder("firmwareSave")
            if (f != "") currentFolder = f
        }
        onAccepted: {
            uiSettings.setDialogFolder("firmwareSave", currentFolder)
            var dest = selectedFile.toString().replace(root.filePathFilter, "")
            githubChecker.saveFileTo(view.downloadedFilePath, dest)
        }
    }

    Dialog {
        id: fileConfirmDialog
        title: "Confirm Firmware Flash"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12

            Label { text: "Flash firmware to the inactive bank?"; font.bold: true; font.pixelSize: 14 }
            Label { text: "File: " + view.selectedFileName; font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.preferredWidth: 420 }
            Label {
                text: "The new firmware is written to the inactive bank; your current firmware keeps " +
                      "running. When it finishes, use Dual Boot to switch to the new version."
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                color: Material.hintTextColor
                Layout.preferredWidth: 420
            }
        }

        onAccepted: {
            flashStatusLabel.color = Material.foreground
            view.flashStatus = ""
            view.ownFlash = true
            m1device.startFwUpdate(view.selectedFilePath)
        }
    }
}
