import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs
import "../components"

Item {
    id: view

    // Unified Firmware Update page: switch back to the M1 pane (wired in main.qml),
    // and whether the currently-selected repo actually publishes ESP firmware.
    signal requestChip(string which)
    property bool espTracked: true
    // Whether the ESP is actually running compatible (brain) firmware, vs merely
    // detected on the shared lines. Injected from main.qml (same check everywhere).
    property bool espBrainRunning: false

    // Which firmware source the user picked — mutually exclusive so only one
    // Step-2 action is ever shown: "" (none) / "file" (Browse this PC) /
    // "release" (Download latest). Choosing one clears the other.
    property string srcMode: ""

    // Entered when a download-latest / unified check runs: drop any browsed local
    // file so only the release path shows.
    function enterReleaseMode() {
        view.srcMode = "release"
        view.selectedFilePath = ""
        view.selectedFileName = ""
        view.flashFilePath = ""
        view.flashFileName = ""
    }

    property int flashAddr: 0x00000
    property bool updating: false
    property int updatePercent: 0
    property string espPhase: ""
    property bool espStalled: false
    property int espLastPct: -1

    // Flag a stalled flash (progress not moving) so we can prompt a reboot+retry.
    Timer {
        interval: 8000; repeat: true; running: view.updating
        onTriggered: {
            if (view.updating && view.updatePercent === view.espLastPct && view.updatePercent < 100)
                view.espStalled = true
            view.espLastPct = view.updatePercent
        }
    }

    // GitHub download state
    property string downloadedFilePath: ""
    property string downloadedFileName: ""
    property string downloadedVersion: ""
    property bool downloading: false
    property int downloadPercent: 0
    property var releaseInfo: null
    property bool flashAfterDownload: false   // set by "Download and Flash Latest"

    // MD5 verification state
    property string md5FilePath: ""
    property string md5FileName: ""
    property string md5Status: ""  // "", "verified", "mismatch", "error"
    property string md5Computed: ""
    property string md5Expected: ""

    // Manual file selection state
    property string selectedFilePath: ""
    property string selectedFileName: ""

    // Size-mismatch warning (live sanity check)
    property string sizeWarning: ""

    // The firmware that the single "Flash ESP32" button will write (set by
    // whichever source flow ran last — download, rollback, or browse).
    property string flashFilePath: ""
    property string flashFileName: ""

    function basename(p) {
        var parts = p.split(/[/\\]/)
        return parts[parts.length - 1]
    }

    // Pick the ESP firmware .bin from a release's assets: prefer a factory image,
    // then any .bin (never the .md5).
    function pickEspAsset() {
        if (!releaseInfo || !releaseInfo.assets) return null
        var a = releaseInfo.assets, i, n
        for (i = 0; i < a.length; i++) {
            n = (a[i].name || "").toLowerCase()
            if (n.indexOf("factory") >= 0 && n.indexOf(".bin") >= 0 && n.indexOf(".md5") < 0)
                return a[i]
        }
        for (i = 0; i < a.length; i++) {
            n = (a[i].name || "").toLowerCase()
            if (n.indexOf(".bin") >= 0 && n.indexOf(".md5") < 0)
                return a[i]
        }
        return null
    }

    Connections {
        target: m1device
        function onEspInfoReceived(version) {
            espVersionLabel.text = version
        }
        // Guard: the Factory Restore flow also drives startEspUpdate. view.updating
        // is set only when THIS view starts a flash, so ignore signals otherwise
        // (else this view's dialogs pop over the Factory Restore screen).
        function onEspUpdateProgress(percent) {
            if (!view.updating) return
            view.updatePercent = percent
        }
        function onEspUpdateStatus(status) {
            if (!view.updating) return
            view.espPhase = status
        }
        function onEspUpdateComplete() {
            if (!view.updating) return
            view.updating = false
            view.espPhase = ""
            espStatusLabel.text = "Success — ESP32 firmware flashed."
            espStatusLabel.color = "#4CAF50"
            espStatusLabel.visible = true
            espDoneDialog.open()
        }
        function onEspUpdateError(message) {
            if (!view.updating) return
            view.updating = false
            view.espPhase = ""
            espStatusLabel.text = "Flash failed: " + message + "  —  reboot the M1 and try again."
            espStatusLabel.color = "#F44336"
            espStatusLabel.visible = true
            espErrorDialog.detail = message
            espErrorDialog.open()
        }
    }

    // ── GitHub signals for ESP32 downloads ──
    Connections {
        target: esp32Checker
        function onReleaseFound(info) {
            view.releaseInfo = info
        }
        function onNoUpdateAvailable(message) {
            if (message.indexOf("No releases") === 0) {
                ghStatusLabel.text = "No release found on " + esp32Checker.repoUrl +
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
            var fname = view.basename(filePath)
            var nameLower = fname.toLowerCase()

            if (nameLower.endsWith(".md5")) {
                // MD5 checksum file — store for verification, NOT as flash target
                view.md5FilePath = filePath
                view.md5FileName = fname
                if (view.downloadedFilePath.length > 0)
                    view.verifyMd5()
                return
            }

            // Firmware binary
            view.downloadedFilePath = filePath
            view.downloadedFileName = fname
            view.flashFilePath = filePath
            view.flashFileName = fname
            if (view.releaseInfo)
                view.downloadedVersion = view.releaseInfo.version || ""

            // Auto-select flash offset based on filename. Factory (full flash at
            // 0x0) is the safe default; only pick app-only when the name clearly
            // marks it as an app image (e.g. app_m1-esp32-brain.bin). Full factory
            // images (bootloader + partitions + app) always flash at 0x0.
            var isApp = nameLower.indexOf("app_") >= 0 ||
                        nameLower.indexOf("app-") >= 0 ||
                        nameLower.indexOf("-app") >= 0 ||
                        nameLower.indexOf("app-only") >= 0
            if (isApp && nameLower.indexOf("factory") < 0) {
                appRadio.checked = true
                view.flashAddr = 0x60000
            } else {
                factoryRadio.checked = true
                view.flashAddr = 0x00000
            }

            // Auto-verify against stored .md5 if available
            if (view.md5FilePath.length > 0)
                view.verifyMd5()
            else
                view.md5Status = ""

            view.checkSizeWarning()

            // "Download and Flash Latest": the binary is here — go straight to the
            // flash confirm (only if the M1 is connected to flash it).
            if (view.flashAfterDownload) {
                view.flashAfterDownload = false
                if (m1device.connected && view.md5Status !== "mismatch")
                    confirmDialog.open()
            }
        }
        function onDownloadError(message) {
            view.downloading = false
            view.flashAfterDownload = false
        }
    }

    function checkSizeWarning() {
        var path = view.downloadedFilePath.length > 0
                   ? view.downloadedFilePath
                   : view.selectedFilePath
        if (path.length === 0) { view.sizeWarning = ""; return }

        var size = esp32Checker.fileSize(path)
        if (size <= 0) { view.sizeWarning = ""; return }

        var kb = Math.round(size / 1024)
        // Factory images vary widely (~1 MB trimmed to 4 MB padded), so size is
        // NOT a reliable factory test — the backend validates structure instead.
        // Only flag the one clear size tell: an app-only image that's too big.
        if (appRadio.checked && size >= 4000 * 1024) {
            view.sizeWarning = "This file is " + kb + " KB — too large for app-only. " +
                               "It may be a factory image (flash at 0x00000)."
        } else {
            view.sizeWarning = ""
        }
    }

    function verifyMd5() {
        // Only verify if base filenames match (e.g. factory_ESP32C6-SPI)
        var binBase = view.downloadedFileName.replace(/\.bin$/i, "")
        var md5Base = view.md5FileName.replace(/\.md5$/i, "")
        if (binBase !== md5Base) {
            view.md5Status = ""
            return
        }
        var result = esp32Checker.verifyFileMd5(view.downloadedFilePath, view.md5FilePath)
        if (result.error) {
            view.md5Status = "error"
            view.md5Computed = ""
            view.md5Expected = ""
        } else {
            view.md5Computed = result.computed
            view.md5Expected = result.expected
            view.md5Status = result.match ? "verified" : "mismatch"
        }
    }

    // ===================== Popups =====================

    // Modal "flashing in progress" overlay — unmissable at any window size.
    FlashProgressDialog {
        visible: view.updating
        statusText: view.espPhase.length > 0 ? view.espPhase : ("Flashing " + view.flashFileName)
        percent: view.updatePercent
        stalled: view.espStalled
        cancelText: "Cancel Flash and try again"
        onCancelRequested: {
            m1device.reboot()
            view.updating = false; view.espStalled = false
            espStatusLabel.text = "Cancelling and rebooting… it'll reconnect in a moment — then flash again."
            espStatusLabel.color = "#FF9800"; espStatusLabel.visible = true
        }
    }

    // ── "Factory vs app-only?" explainer ──
    Dialog {
        id: espImageDialog
        title: "Factory vs app-only image"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 560)
        height: Math.min(view.height - 80, 500)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: espImageDialog.availableWidth
                spacing: 12

                Label {
                    text: "The ESP32 firmware comes in two forms, written to different flash offsets:"
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }
                Label {
                    text: "Factory image (0x00000) — bootloader + partition table + app, all in one. " +
                          "Use it for a first-time flash, a recovery, or whenever the partition layout " +
                          "might have changed. This is the safe default."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }
                Label {
                    text: "App-only image (0x60000) — just the application partition. Smaller and faster, " +
                          "but only safe when the bootloader and partition table already on the ESP32 " +
                          "match this build."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14; color: Material.hintTextColor
                }
                Label {
                    text: "When in doubt, use the factory image. It's the complete, self-sufficient one — " +
                          "it can't leave the ESP32 in a half-updated state, so it always works."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14; font.bold: true; color: "#4CAF50"
                }
                Label {
                    text: "qMonstatek picks the offset automatically from the file name (files with " +
                          "\"factory\" flash at 0x00000) and warns if the file size doesn't match the choice."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13; color: Material.hintTextColor
                }
            }
        }
    }

    // ── "Which ESP firmware?" explainer ──
    Dialog {
        id: espFirmwareDialog
        title: "Which ESP32 firmware?"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 560)
        height: Math.min(view.height - 80, 460)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: espFirmwareDialog.availableWidth
                spacing: 12

                Label {
                    text: "The ESP32-C6 is a separate co-processor — a second chip that handles WiFi, " +
                          "Bluetooth, and the other radios. It runs its own firmware, independent of the " +
                          "main M1 firmware, and the two talk to each other over an internal link."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }
                Label {
                    text: "Because they're separate, the M1 firmware and the ESP32 firmware have to speak " +
                          "the same language. A given M1 build expects a matching ESP32 build — features " +
                          "like WiFi scanning or BLE only work when the two versions are compatible."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }
                Label {
                    text: "You can keep two different M1 firmwares side by side and switch between them in " +
                          "Dual Boot — but each may need its own compatible ESP32 firmware. If WiFi/BLE " +
                          "stops working after you switch M1 firmware, the fix is usually to flash the ESP32 " +
                          "build that matches the M1 firmware you're now running."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14; color: Material.hintTextColor
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                Label { text: "The ESP32 firmware types"; font.bold: true; font.pixelSize: 14 }
                Label {
                    text: "SPI Brain — what C3 firmware uses. The ESP32 runs the radio features natively " +
                          "and talks to the M1 over a custom binary link. Get it with \"Download latest " +
                          "(SPI brain)\". This is the one you want for C3."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14
                }
                Label {
                    text: "ESP-Hosted (genuine stock) — what the stock Monstatek M1 firmware uses; the " +
                          "ESP32 acts as a network co-processor. To return a device to stock, use " +
                          "Factory Restore, which flashes the matching stock ESP32 image — not this screen."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14; color: Material.hintTextColor
                }
                Label {
                    text: "In short: match the ESP32 firmware to your M1 firmware. For C3, download the " +
                          "latest SPI brain and flash it as a factory image. Download repos are set in Settings."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 14; font.bold: true; color: "#4CAF50"
                }
            }
        }
    }

    // ── Flash-failed popup — makes the "reboot first" fix unmistakable ──
    Dialog {
        id: espErrorDialog
        title: "ESP32 flash failed"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 560)
        standardButtons: Dialog.Close
        property string detail: ""

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                text: "The ESP32 update didn't complete."
                font.pixelSize: 16; font.bold: true; color: "#F44336"
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 480
            }
            Label {
                visible: espErrorDialog.detail.length > 0
                text: "Reported: " + espErrorDialog.detail
                font.pixelSize: 12; color: Material.hintTextColor
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 480
            }
            Label {
                text: "Reboot the M1, then flash again — this is almost always the fix."
                font.pixelSize: 15; font.bold: true; color: "#4CAF50"
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 480
            }
            Label {
                text: "Flashing the ESP32 needs the M1 to hand over a clean link and buffer. If a radio " +
                      "feature is still running or the M1's memory is fragmented from earlier use, the " +
                      "transfer can't start — and after any WiFi/BLE activity that's usually the state it's " +
                      "in. A fresh reboot clears it. Afterwards, Initialize the ESP if it isn't Ready, then flash."
                font.pixelSize: 13; color: Material.hintTextColor
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 480
            }
            Button {
                text: "Reboot M1 now"
                highlighted: true
                enabled: m1device.connected
                onClicked: { m1device.reboot(); espErrorDialog.close() }
            }
        }
    }

    // ── Troubleshooting / FAQ ──
    Dialog {
        id: espFaqDialog
        title: "ESP32 update — troubleshooting"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 600)
        height: Math.min(view.height - 80, 560)
        standardButtons: Dialog.Close

        contentItem: ScrollView {
            clip: true
            ColumnLayout {
                width: espFaqDialog.availableWidth
                spacing: 16

                Repeater {
                    model: [
                        {
                            q: "The flash fails, stalls, or times out",
                            a: "Reboot the M1 and try again — this is the number-one fix. The ESP update needs " +
                               "the M1 to free the radio link and hand over a clean buffer; if a WiFi/BLE feature " +
                               "was in use or memory is fragmented, it can't start. A fresh reboot clears that state."
                        },
                        {
                            q: "ESP32 shows \"Not initialized\"",
                            a: "Press Initialize (needs a connected M1). If it won't initialize, reboot the M1 first " +
                               "— the same busy/low-memory condition blocks init too."
                        },
                        {
                            q: "It says MD5 MISMATCH after downloading",
                            a: "The download was corrupted or the .md5 doesn't match the .bin. Don't flash it — " +
                               "download the firmware again. Flashing is blocked while a mismatch is showing."
                        },
                        {
                            q: "WiFi/BLE stopped working after switching M1 firmware",
                            a: "The ESP32 firmware must match the M1 firmware you're running. Flash the ESP build " +
                               "that goes with it — usually the latest SPI brain as a factory image (see \"Which ESP firmware?\")."
                        },
                        {
                            q: "Which image type should I pick?",
                            a: "When in doubt, use the factory image — it's complete and always safe. App-only is " +
                               "faster but only works when the bootloader/partitions already match."
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

    // ── Completion popup ──
    Dialog {
        id: espDoneDialog
        title: "ESP32 flash complete"
        modal: true
        anchors.centerIn: parent
        width: Math.min(view.width - 60, 520)
        standardButtons: Dialog.Ok

        ColumnLayout {
            anchors.fill: parent
            spacing: 12

            Label {
                text: "ESP32 firmware flashed successfully."
                font.pixelSize: 16; font.bold: true; color: "#4CAF50"
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 460
            }
            Label {
                text: "Reboot the M1 (or use Reboot ESP + Initialize above) so it reconnects to the " +
                      "newly-flashed ESP32."
                font.pixelSize: 14; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 460
            }
        }
    }

    // ── Release notes popup ──
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
                                view.downloading = true
                                view.downloadPercent = 0
                                if (!modelData.name.toLowerCase().endsWith(".md5")) {
                                    view.downloadedFilePath = ""
                                    view.downloadedFileName = ""
                                }
                                esp32Checker.downloadAsset(modelData.downloadUrl, modelData.name)
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

        // ── Chip selector — LOCKED to the top ──
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
                onClicked: view.requestChip("m1")
            }
            Button {
                text: "ESP32 Firmware"
                highlighted: true            // active pane
                onClicked: { /* already here */ }
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
            contentWidth: availableWidth
            clip: true

        ColumnLayout {
            width: view.width
            spacing: 16

            // ── Title ──
            Label {
                text: "ESP32-C6 Firmware Update"
                font.pixelSize: 26
                font.bold: true
                color: "#26A69A"   // teal — the ESP32 radio coprocessor
                Layout.topMargin: 8
                Layout.leftMargin: 24
            }

            // Subtitle
            Label {
                text: "Flash the ESP32-C6 radio coprocessor's firmware through the connected M1. " +
                      "No extra software is needed — the M1 talks to the ESP32's bootloader directly, " +
                      "so a compatible M1 on USB is all it takes."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                color: Material.foreground
                font.pixelSize: 15
            }

            // ── ESP32 status ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label { text: "ESP32 status"; font.bold: true; font.pixelSize: 16 }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            width: 12; height: 12; radius: 6
                            color: view.espBrainRunning ? "#4CAF50"
                                   : (m1device.esp32Ready ? "#FF9800" : "#F44336")
                        }
                        Label {
                            // "Ready" only when the ESP actually answers the C3 protocol.
                            // Detected-but-incompatible (e.g. stock/hosted) is amber, not green.
                            text: view.espBrainRunning ? "Ready"
                                  : (m1device.esp32Ready ? "Incompatible firmware" : "Not initialized")
                            font.pixelSize: 14
                            font.bold: true
                            color: view.espBrainRunning ? "#4CAF50"
                                   : (m1device.esp32Ready ? "#FF9800" : "#F44336")
                        }
                        Label { text: "Version:"; font.pixelSize: 13; color: Material.hintTextColor }
                        Label {
                            id: espVersionLabel
                            text: m1device.esp32Version.length > 0 ? m1device.esp32Version : "Unknown"
                            font.pixelSize: 13
                        }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: "Initialize"
                            visible: !m1device.esp32Ready
                            enabled: m1device.connected && !view.updating
                            onClicked: m1device.initEsp32()
                        }
                        Button {
                            text: "Reboot ESP"
                            enabled: m1device.connected && !view.updating
                            onClicked: m1device.rebootEsp32()
                        }
                        Button {
                            text: "Refresh"
                            enabled: m1device.connected
                            onClicked: {
                                m1device.requestDeviceInfo()
                                m1device.requestEspInfo()
                            }
                        }
                    }
                }
            }

            // ── Firmware-mismatch guidance (detect & guide) ──
            Pane {
                visible: m1device.connected && m1device.hasDeviceInfo && !view.espBrainRunning
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 2
                Material.background: Material.theme === Material.Dark ? "#3A2E12" : "#FFF3E0"

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6

                    RowLayout {
                        spacing: 8
                        Label { text: "⚠"; font.pixelSize: 18; color: "#FF9800" }
                        Label {
                            text: "The ESP32 isn't responding as expected"
                            font.bold: true; font.pixelSize: 14; color: "#FF9800"
                            Layout.fillWidth: true
                        }
                    }
                    Label {
                        text: "The ESP32 co-processor runs its own firmware, and the stock Monstatek and " +
                              "C3 M1 builds each expect a different one. If you just switched M1 firmware " +
                              "(e.g. via Dual Boot), the ESP32 is likely still running the other build's " +
                              "firmware, so WiFi/BLE won't work until it matches."
                        wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13
                    }
                    Label {
                        text: "Fix it: press Initialize / Refresh above (it auto-inits in a few seconds). " +
                              "If it stays offline, flash the matching ESP32 firmware below — for C3, use " +
                              "\"Download latest (SPI brain)\"."
                        wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13
                        color: Material.hintTextColor
                    }
                }
            }

            // ── Image type / flash address ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label { text: "Image type"; font.bold: true; font.pixelSize: 16 }

                    ButtonGroup { id: imageTypeGroup }

                    RadioButton {
                        id: factoryRadio
                        text: "Factory image  (0x00000)"
                        font.pixelSize: 14
                        checked: true
                        ButtonGroup.group: imageTypeGroup
                        onCheckedChanged: if (checked) { view.flashAddr = 0x00000; view.checkSizeWarning() }
                    }

                    RadioButton {
                        id: appRadio
                        text: "App-only  (0x60000)"
                        font.pixelSize: 14
                        ButtonGroup.group: imageTypeGroup
                        onCheckedChanged: if (checked) { view.flashAddr = 0x60000; view.checkSizeWarning() }
                    }

                    Label {
                        text: factoryRadio.checked
                              ? "Bootloader + partition table + app. Safe default — use for first-time or recovery flashes."
                              : "Application partition only. Faster, but only if the bootloader/partitions already match."
                        wrapMode: Text.WordWrap
                        font.pixelSize: 13
                        color: Material.hintTextColor
                        Layout.fillWidth: true
                    }

                    Label {
                        visible: view.sizeWarning.length > 0
                        text: view.sizeWarning
                        wrapMode: Text.WordWrap
                        font.pixelSize: 13
                        font.bold: true
                        color: "#FF9800"
                        Layout.fillWidth: true
                    }

                    CheckBox {
                        id: forceFlashCheck
                        text: "Force flash — skip image-type checks"
                        font.pixelSize: 13
                        ToolTip.visible: hovered
                        ToolTip.text: "Bypass the factory/app-only validation and flash the file as-is. " +
                                      "Only use this if you're sure the image and address are correct."
                    }
                }
            }

            // ── Update ESP32: choose a source, then flash ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 14

                    Label { text: "Update ESP32 Firmware"; font.bold: true; font.pixelSize: 17 }

                    // Step 1 — choose the firmware
                    Label { text: "1.  Choose firmware"; font.bold: true; font.pixelSize: 15 }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 12

                        Button {
                            text: "Browse this PC…"
                            enabled: !view.updating
                            onClicked: {
                                var f = uiSettings.dialogFolder("espOpen")
                                if (f != "") espFileDialog.currentFolder = f
                                espFileDialog.open()
                            }
                        }

                        Button {
                            text: esp32Checker.checking ? "Checking…" : "Check for updates"
                            enabled: view.espTracked && !esp32Checker.checking && !view.downloading && !view.updating
                            onClicked: {
                                // ESP-focused check: fetch the latest release and show it
                                // here (does NOT route away, unlike the M1 pane's check).
                                // Works even if the ESP isn't initialized.
                                view.srcMode = "release"
                                view.selectedFilePath = ""
                                view.selectedFileName = ""
                                view.flashFilePath = ""
                                view.flashFileName = ""
                                view.releaseInfo = null
                                view.downloadedFilePath = ""
                                view.downloadedFileName = ""
                                view.downloadedVersion = ""
                                view.md5FilePath = ""
                                view.md5FileName = ""
                                view.md5Status = ""
                                view.md5Computed = ""
                                view.md5Expected = ""
                                ghStatusLabel.visible = false
                                ghStatusLabel.color = Material.hintTextColor
                                esp32Checker.checkForUpdates(0, 0, 0, 0, 0)
                            }
                        }
                    }

                    Label {
                        visible: view.espTracked
                        text: "Checks " + esp32Checker.repoUrl + " for the latest SPI-brain release — even if " +
                              "the ESP isn't initialized. Or use \"Browse this PC…\" to flash a local image. " +
                              "Change repos in Settings."
                        font.pixelSize: 13
                        color: Material.hintTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Selected repo publishes only M1 firmware — no ESP source to pull.
                    Label {
                        visible: !view.espTracked
                        text: "The selected repo (" + githubChecker.repoUrl + ") only currently tracks " +
                              "M1 firmware — it has no ESP32 image to download. Pick a repo that ships ESP " +
                              "firmware in Settings, or use \"Browse this PC…\" to flash a local ESP image."
                        font.pixelSize: 13
                        font.bold: true
                        color: "#FF9800"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    Label {
                        id: ghStatusLabel
                        visible: false
                        font.pixelSize: 13
                        color: Material.hintTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    ProgressBar {
                        visible: view.downloading
                        Layout.fillWidth: true
                        value: view.downloadPercent / 100.0
                    }

                    // ── MD5 file downloaded but no .bin yet ──
                    Label {
                        visible: view.md5FileName.length > 0
                                 && view.downloadedFilePath.length === 0
                                 && !view.downloading
                        text: "Checksum saved: " + view.md5FileName +
                              " — download the .bin file to verify and flash"
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
                        text: "No firmware chosen yet — Check for updates or Browse this PC above."
                        color: Material.hintTextColor
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // ── RELEASE source: latest-release summary (after "Check for updates") ──
                    RowLayout {
                        visible: view.srcMode === "release" && view.releaseInfo !== null
                        spacing: 16

                        Label {
                            text: "Latest on " + esp32Checker.repoUrl + ":  " +
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

                    // ── Selected firmware summary (whatever will actually flash) ──
                    RowLayout {
                        visible: view.flashFileName.length > 0
                        Layout.fillWidth: true
                        spacing: 12

                        Label {
                            text: "Selected firmware:  " + view.flashFileName +
                                  (view.downloadedVersion.length > 0 ? "  (" + view.downloadedVersion + ")" : "")
                            color: Material.accent
                            font.pixelSize: 14
                            font.bold: true
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                        Label {
                            visible: view.md5Status === "verified"
                            text: "MD5 verified"
                            font.pixelSize: 13; font.bold: true; color: "#4CAF50"
                        }
                        Label {
                            visible: view.md5Status === "mismatch"
                            text: "MD5 MISMATCH"
                            font.pixelSize: 13; font.bold: true; color: "#F44336"
                        }
                        Label {
                            visible: view.md5Status === "error"
                            text: "MD5 error"
                            font.pixelSize: 13; font.bold: true; color: "#FF9800"
                        }
                    }

                    // MD5 mismatch detail
                    Label {
                        visible: view.md5Status === "mismatch"
                        text: "Expected: " + view.md5Expected
                        font.family: "Courier New"; font.pixelSize: 11; color: "#F44336"
                        wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                    }
                    Label {
                        visible: view.md5Status === "mismatch"
                        text: "Computed: " + view.md5Computed
                        font.family: "Courier New"; font.pixelSize: 11; color: "#F44336"
                        wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                    }

                    // Step 2 — flash it
                    Label { text: "2.  Flash to the ESP32"; font.bold: true; font.pixelSize: 15; Layout.topMargin: 4 }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // FILE source → flash the browsed file
                        Button {
                            text: "Flash ESP32"
                            highlighted: true
                            visible: view.srcMode === "file"
                            enabled: m1device.connected && !view.updating
                                     && view.flashFilePath.length > 0
                                     && view.md5Status !== "mismatch"
                            onClicked: confirmDialog.open()
                        }

                        // RELEASE source → download the latest and flash it
                        Button {
                            text: view.downloading ? "Downloading…" : "Download and Flash Latest"
                            highlighted: true
                            visible: view.srcMode === "release" && view.releaseInfo !== null
                            enabled: !view.downloading && !view.updating && m1device.connected
                            onClicked: {
                                var asset = view.pickEspAsset()
                                if (!asset) { releaseNotesDialog.open(); return }
                                view.flashAfterDownload = true
                                view.downloading = true
                                view.downloadPercent = 0
                                view.downloadedFilePath = ""
                                view.downloadedFileName = ""
                                esp32Checker.downloadAsset(asset.downloadUrl, asset.name)
                            }
                        }

                        Label {
                            text: "Target: 0x" + view.flashAddr.toString(16).toUpperCase().padStart(5, "0")
                                  + (factoryRadio.checked ? "  (Factory)" : "  (App-only)")
                            font.family: "Courier New"
                            font.pixelSize: 13
                            color: Material.hintTextColor
                            Layout.fillWidth: true
                        }
                    }

                    Label {
                        visible: view.flashFilePath.length > 0 && !m1device.connected
                        text: "Connect your M1 to enable flashing."
                        font.pixelSize: 12
                        color: "#E0A030"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // ── Flash progress (phase + percentage) ──
            ColumnLayout {
                visible: view.updating
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Label {
                        text: (view.espPhase.length > 0 ? view.espPhase : "Flashing " + view.flashFileName)
                        font.pixelSize: 14
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Label {
                        text: view.updatePercent > 0 ? view.updatePercent + "%" : ""
                        font.pixelSize: 14; font.bold: true; color: Material.accent
                    }
                }

                ProgressBar {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: view.updatePercent
                    indeterminate: view.updatePercent <= 0
                }

                Label {
                    visible: view.espStalled
                    text: "Hmmm… this is taking longer than expected."
                    font.pixelSize: 14; font.bold: true; color: "#FF9800"
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                Button {
                    visible: view.espStalled
                    text: "Cancel Flash and try again"
                    Material.foreground: "#FF9800"
                    onClicked: {
                        m1device.reboot()
                        view.updating = false; view.espStalled = false
                        espStatusLabel.text = "Cancelling and rebooting… it'll reconnect in a moment — then flash again."
                        espStatusLabel.color = "#FF9800"; espStatusLabel.visible = true
                    }
                }
            }

            // ── Result / status (when not flashing) ──
            Label {
                id: espStatusLabel
                visible: false
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                font.pixelSize: 13
            }

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
                text: "<a href='img'>Factory vs app-only?</a>"
                textFormat: Text.RichText
                font.pixelSize: 15
                linkColor: "#8FCBFF"; font.bold: true
                onLinkActivated: espImageDialog.open()
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
            }
            Label {
                text: "<a href='fw'>Which ESP firmware?</a>"
                textFormat: Text.RichText
                font.pixelSize: 15
                linkColor: "#8FCBFF"; font.bold: true
                onLinkActivated: espFirmwareDialog.open()
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
            }
            Label {
                text: "<a href='faq'>Troubleshooting</a>"
                textFormat: Text.RichText
                font.pixelSize: 15
                linkColor: "#8FCBFF"; font.bold: true
                onLinkActivated: espFaqDialog.open()
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
            }
        }
    }

    FileDialog {
        id: espFileDialog
        title: "Select ESP32 Firmware Binary"
        nameFilters: ["Binary files (*.bin)", "All files (*)"]
        Component.onCompleted: {
            var f = uiSettings.dialogFolder("espOpen")
            if (f != "") currentFolder = f
        }
        onAccepted: {
            uiSettings.setDialogFolder("espOpen", currentFolder)
            var path = selectedFile.toString().replace(root.filePathFilter, "")
            view.srcMode = "file"
            view.releaseInfo = null
            view.selectedFilePath = path
            view.selectedFileName = view.basename(path)
            // A browsed file becomes the flash target; it has no matching .md5
            view.flashFilePath = path
            view.flashFileName = view.selectedFileName
            view.downloadedFilePath = ""
            view.downloadedFileName = ""
            view.downloadedVersion = ""
            view.md5Status = ""
            espStatusLabel.visible = false
            view.checkSizeWarning()
        }
    }

    Dialog {
        id: confirmDialog
        title: "Confirm ESP32 Firmware Flash"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12

            Label { text: "Flash firmware directly to the ESP32?"; font.bold: true; font.pixelSize: 14 }
            Label {
                text: "File: " + view.flashFileName +
                      (view.downloadedVersion.length > 0 ? "  (" + view.downloadedVersion + ")" : "")
                font.pixelSize: 13; wrapMode: Text.WordWrap; Layout.preferredWidth: 440
            }
            Label {
                text: "Flash address: 0x" + view.flashAddr.toString(16).toUpperCase().padStart(5, "0")
                      + (factoryRadio.checked ? "  (Factory image)" : "  (App-only)")
                font.pixelSize: 13
            }
            Label {
                visible: view.md5Status === "verified"
                text: "MD5: verified"
                color: "#4CAF50"; font.pixelSize: 13
            }
            Label {
                text: "This connects to the ESP32 ROM bootloader, erases the target region, and writes " +
                      "the firmware directly. The ESP32 resets automatically when flashing completes."
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                color: Material.hintTextColor
                Layout.preferredWidth: 440
            }
        }

        onAccepted: {
            view.updating = true
            view.updatePercent = 0
            view.espStalled = false
            view.espLastPct = -1
            view.espPhase = ""
            espStatusLabel.text = ""
            espStatusLabel.color = Material.foreground
            espStatusLabel.visible = false
            m1device.startEspUpdate(view.flashFilePath, view.flashAddr, forceFlashCheck.checked)
        }
    }
}
