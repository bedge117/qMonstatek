import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import "../components"

// ── One-click "Update All to latest C3" ─────────────────────────────────────
// Downloads the latest ESP (SPI brain) and M1 (C3) firmware from the configured
// repos, flashes the ESP, then the M1 into the inactive bank, then swaps banks
// and reboots into the new build — all from one button. Mirrors Factory Restore's
// staged orchestration + stall/fail/reboot handling, but targets the newest custom
// firmware instead of stock.
//
// Only works on COMPATIBLE firmware (any C3 build / Recovery / Restore Host), which
// exposes the update RPC. On genuine stock (incompatible) qM can't flash over USB —
// that must start from DFU Flash, which this screen points to.
ScrollView {
    id: view
    contentWidth: availableWidth

    // Switch to another chip's pane (wired in main.qml).
    signal requestChip(string which)
    // Tell main.qml a one-click run is / isn't in flight, so a mid-flash reboot
    // returns here on reconnect.
    signal updateInFlight(bool active)

    property bool espTracked: true

    // ── Latest releases (fetched on entry) ──
    property var m1Release: null
    property var espRelease: null

    // ── Orchestration state ──
    // "" idle · "dlEsp" · "flashEsp" · "dlM1" · "flashM1" · "done"
    property string phase: ""
    property bool   busy: false
    property int    pct: 0
    property string statusMsg: ""
    property bool   stalled: false
    property int    lastPct: -1
    property string espPath: ""
    property string m1Path: ""

    readonly property bool compatible: m1device.connected && m1device.hasDeviceInfo
    readonly property bool m1Ready:  m1Release !== null && pickM1(m1Release) !== null
    readonly property bool espReady: !espTracked || (espRelease !== null && pickEsp(espRelease) !== null)
    readonly property bool canUpdate: compatible && !busy && m1Ready && espReady

    function basename(p) { var a = p.split(/[/\\]/); return a[a.length - 1] }

    function pickM1(rel) {
        if (!rel || !rel.assets) return null
        var a = rel.assets, i, n
        for (i = 0; i < a.length; i++) {
            n = (a[i].name || "").toLowerCase()
            if (n.indexOf("wcrc") >= 0 && n.indexOf(".bin") >= 0 && n.indexOf("esp") < 0 && n.indexOf("factory") < 0) return a[i]
        }
        for (i = 0; i < a.length; i++) {
            n = (a[i].name || "").toLowerCase()
            if (n.indexOf(".bin") >= 0 && n.indexOf("esp") < 0 && n.indexOf("factory") < 0) return a[i]
        }
        return null
    }
    function pickEsp(rel) {
        if (!rel || !rel.assets) return null
        var a = rel.assets, i, n
        for (i = 0; i < a.length; i++) {
            n = (a[i].name || "").toLowerCase()
            if (n.indexOf("factory") >= 0 && n.indexOf(".bin") >= 0 && n.indexOf(".md5") < 0) return a[i]
        }
        for (i = 0; i < a.length; i++) {
            n = (a[i].name || "").toLowerCase()
            if (n.indexOf(".bin") >= 0 && n.indexOf(".md5") < 0) return a[i]
        }
        return null
    }

    // Fetch the latest release (tag + assets) for a repo, regardless of whether it's
    // newer than what's installed — so "Update All" can flash latest even to reflash.
    function fetchLatest(repo, onOk) {
        if (!repo || repo.length === 0) { onOk(null); return }
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var j = JSON.parse(xhr.responseText)
                        var assets = []
                        if (j.assets)
                            for (var i = 0; i < j.assets.length; i++)
                                assets.push({ name: j.assets[i].name, downloadUrl: j.assets[i].browser_download_url })
                        onOk({ version: j.tag_name, htmlUrl: j.html_url || "", assets: assets })
                    } catch (e) { onOk(null) }
                } else {
                    onOk(null)
                }
            }
        }
        xhr.open("GET", "https://api.github.com/repos/" + repo + "/releases/latest")
        xhr.setRequestHeader("User-Agent", "qMonstatek/1.0")
        xhr.setRequestHeader("Accept", "application/vnd.github.v3+json")
        xhr.send()
    }

    // Fetch the latest release for both chips (called when the tab is shown).
    function refresh() {
        if (!compatible || busy) return
        view.m1Release = null
        view.espRelease = null
        fetchLatest(githubChecker.repoUrl, function(r) { view.m1Release = r })
        if (view.espTracked)
            fetchLatest(esp32Checker.repoUrl, function(r) { view.espRelease = r })
    }

    function startUpdate() {
        if (!view.canUpdate) return
        var espAsset = view.espTracked ? pickEsp(view.espRelease) : null
        var m1Asset  = pickM1(view.m1Release)
        if (!m1Asset) { errorDialog.msg = "No M1 firmware asset found in the latest release."; errorDialog.open(); return }
        if (view.espTracked && !espAsset) { errorDialog.msg = "No ESP firmware asset found in the latest release."; errorDialog.open(); return }

        view.busy = true; view.stalled = false; view.lastPct = -1; view.pct = 0
        view.updateInFlight(true)

        if (view.espTracked) {
            view.phase = "dlEsp"
            view.statusMsg = "Downloading the latest ESP32 firmware…"
            esp32Checker.downloadAsset(espAsset.downloadUrl, espAsset.name)
        } else {
            // No ESP source configured — M1 only.
            view.phase = "dlM1"
            view.statusMsg = "Downloading the latest M1 firmware…"
            githubChecker.downloadAsset(m1Asset.downloadUrl, m1Asset.name)
        }
    }

    // Reboot + reset (stall/fail escape hatch — flashing can hang on the first try).
    function rebootDevice() {
        m1device.reboot()
        view.busy = false; view.phase = ""; view.stalled = false
        view.statusMsg = "Rebooting the device… it'll reconnect in a moment — then run it again."
    }

    // Watchdog for a stalled flash.
    Timer {
        interval: 8000; repeat: true; running: view.busy
        onTriggered: {
            if (view.busy && view.pct === view.lastPct && view.pct < 100) view.stalled = true
            view.lastPct = view.pct
        }
    }

    // ── Download signals (routed by phase) ──
    Connections {
        target: esp32Checker
        function onDownloadProgress(p) { if (view.phase === "dlEsp") view.pct = p }
        function onDownloadComplete(path) {
            if (view.phase !== "dlEsp") return
            if (view.basename(path).toLowerCase().endsWith(".md5")) return
            view.espPath = path
            view.phase = "flashEsp"; view.pct = 0; view.stalled = false; view.lastPct = -1
            view.statusMsg = "Flashing the ESP32 firmware…"
            m1device.startEspUpdate(path, 0, false)   // factory image at 0x0
        }
        function onDownloadError(msg) {
            if (view.phase !== "dlEsp") return
            view.fail("ESP firmware download failed:\n" + msg)
        }
    }
    Connections {
        target: githubChecker
        function onDownloadProgress(p) { if (view.phase === "dlM1") view.pct = p }
        function onDownloadComplete(path) {
            if (view.phase !== "dlM1") return
            view.m1Path = path
            view.phase = "flashM1"; view.pct = 0; view.stalled = false; view.lastPct = -1
            view.statusMsg = "Flashing the M1 firmware to the inactive bank…"
            m1device.startFwUpdate(path)
        }
        function onDownloadError(msg) {
            if (view.phase !== "dlM1") return
            view.fail("M1 firmware download failed:\n" + msg)
        }
    }

    // ── Flash signals (routed by phase) ──
    Connections {
        target: m1device
        function onEspUpdateProgress(p) { if (view.phase === "flashEsp") view.pct = p }
        function onEspUpdateComplete() {
            if (view.phase !== "flashEsp") return
            // ESP done → download + flash the M1.
            var m1Asset = view.pickM1(view.m1Release)
            if (!m1Asset) { view.fail("No M1 firmware asset found."); return }
            view.phase = "dlM1"; view.pct = 0; view.stalled = false; view.lastPct = -1
            view.statusMsg = "Downloading the latest M1 firmware…"
            githubChecker.downloadAsset(m1Asset.downloadUrl, m1Asset.name)
        }
        function onEspUpdateError(msg) {
            if (view.phase !== "flashEsp") return
            view.fail("ESP32 flash failed:\n" + msg)
        }
        function onFwUpdateProgress(p) { if (view.phase === "flashM1") view.pct = p }
        function onFwUpdateComplete() {
            if (view.phase !== "flashM1") return
            // Both flashed → swap banks + reboot into the new build. Clear the
            // in-flight flag first so the post-swap reboot doesn't bounce us back.
            view.phase = "done"; view.busy = false
            view.updateInFlight(false)
            view.statusMsg = "Both firmwares flashed. Swapping banks and rebooting into the new build…"
            doneDialog.open()
        }
        function onFwUpdateError(msg) {
            if (view.phase !== "flashM1") return
            view.fail("M1 flash failed:\n" + msg)
        }
        function onConnectionChanged(connected) {
            if (!connected && view.busy) {
                view.busy = false; view.phase = ""; view.stalled = false
                view.statusMsg = "Device disconnected mid-flash. If it stalled it likely rebooted — reconnect and run it again."
                // keep updateActive set so main.qml returns here on reconnect
            }
        }
    }

    function fail(msg) {
        view.busy = false; view.phase = ""; view.stalled = false
        view.updateInFlight(false)
        errorDialog.msg = msg
        errorDialog.open()
    }

    // ===================== UI =====================
    ColumnLayout {
        width: view.width
        spacing: 16

        // ── Chip selector (M1 | ESP32 | Update All) ──
        RowLayout {
            Layout.topMargin: 20
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            spacing: 8
            Label { text: "Update:"; font.pixelSize: 13; color: Material.hintTextColor }
            Button { text: "M1 Firmware";    onClicked: view.requestChip("m1") }
            Button { text: "ESP32 Firmware"; onClicked: view.requestChip("esp") }
            Button { text: "Update All";     highlighted: true; onClicked: { /* already here */ } }
        }

        Label {
            text: "One-Click Update"
            font.pixelSize: 26; font.bold: true
            color: "#7C6CF0"   // indigo — the "do everything" path
            Layout.topMargin: 8; Layout.leftMargin: 24
        }
        Label {
            text: "Bring both chips up to the latest C3 firmware in one step: download the newest " +
                  "ESP32 and M1 builds, flash the ESP32, flash the M1 to the spare bank, then reboot " +
                  "into the new build."
            wrapMode: Text.WordWrap
            Layout.fillWidth: true; Layout.topMargin: 8; Layout.leftMargin: 24; Layout.rightMargin: 24
            color: Material.foreground; font.pixelSize: 15
        }

        // ── Not connected ──
        Label {
            visible: !m1device.connected
            text: "Connect your M1 device to begin."
            font.pixelSize: 14; color: Material.hintTextColor
            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 20
        }

        // ── Stock / incompatible → must start from DFU ──
        Pane {
            visible: m1device.connected && !m1device.hasDeviceInfo
            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
            Material.elevation: 2
            Material.background: Material.theme === Material.Dark ? "#3A2E12" : "#FFF3E0"
            ColumnLayout {
                anchors.fill: parent; spacing: 8
                Label { text: "This device is on stock / incompatible firmware"; font.bold: true; font.pixelSize: 15; color: "#FF9800" }
                Label {
                    text: "qMonstatek installs C3 firmware over the device's update link, which stock " +
                          "firmware doesn't provide. To get onto C3 the first time, flash it with DFU " +
                          "Flash. After that, this one-click updater keeps both chips current."
                    wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 13; color: Material.hintTextColor
                }
                Button { text: "Go to DFU Flash"; highlighted: true; onClicked: view.requestChip("dfu") }
            }
        }

        // ── Compatible: status + the button ──
        Pane {
            visible: view.compatible
            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
            Material.elevation: 1
            ColumnLayout {
                anchors.fill: parent; spacing: 10

                Label { text: "Installed"; font.bold: true; font.pixelSize: 16 }
                GridLayout {
                    columns: 3; columnSpacing: 14; rowSpacing: 4
                    Label { text: "M1:"; color: Material.hintTextColor; font.pixelSize: 13 }
                    Label { text: m1device.firmwareVersion; font.pixelSize: 13; font.bold: true; color: Material.accent }
                    Label {
                        text: view.m1Release ? ("→ latest " + view.m1Release.version) : "→ checking…"
                        font.pixelSize: 13
                        color: view.m1Release ? "#4CAF50" : Material.hintTextColor
                    }
                    Label { text: "ESP32:"; color: Material.hintTextColor; font.pixelSize: 13 }
                    Label { text: m1device.esp32Version.length > 0 ? m1device.esp32Version : "unknown"; font.pixelSize: 13; font.bold: true; color: Material.accent }
                    Label {
                        text: !view.espTracked ? "→ no ESP repo set (Settings)"
                              : view.espRelease ? ("→ latest " + view.espRelease.version)
                              : "→ checking…"
                        font.pixelSize: 13
                        color: view.espTracked && view.espRelease ? "#4CAF50" : Material.hintTextColor
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Material.dividerColor }

                RowLayout {
                    spacing: 12
                    Button {
                        text: view.busy ? "Updating…" : "Update everything to latest C3"
                        highlighted: true
                        enabled: view.canUpdate
                        onClicked: confirmDialog.open()
                    }
                    Button {
                        text: "Re-check"
                        flat: true
                        enabled: !view.busy
                        onClicked: view.refresh()
                    }
                }
                Label {
                    text: view.espTracked
                          ? "Flashes the ESP32, then the M1 to the spare bank, then reboots into it. Your " +
                            "current firmware stays intact until the reboot."
                          : "No ESP repo is set in Settings, so only the M1 will be updated. Set an ESP repo " +
                            "to update both."
                    font.pixelSize: 12; color: Material.hintTextColor
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
        }

        // ── Progress ──
        Pane {
            visible: view.busy || (view.statusMsg.length > 0 && view.phase !== "")
            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
            Material.elevation: 2
            ColumnLayout {
                anchors.fill: parent; spacing: 8
                Label { text: view.statusMsg; font.pixelSize: 14; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                ProgressBar { visible: view.busy; Layout.fillWidth: true; from: 0; to: 100; value: view.pct; indeterminate: view.pct <= 0 }
                Label { visible: view.busy; text: view.pct + "%"; font.pixelSize: 12; color: Material.hintTextColor }
                Label {
                    visible: view.stalled
                    text: "Hmmm… this is taking longer than expected."
                    font.pixelSize: 14; font.bold: true; color: "#FF9800"
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                Button {
                    visible: view.stalled
                    text: "Cancel and reboot, then try again"
                    Material.foreground: "#FF9800"
                    onClicked: view.rebootDevice()
                }
            }
        }

        // ── Status when idle ──
        Label {
            visible: !view.busy && view.statusMsg.length > 0 && view.phase === ""
            text: view.statusMsg
            font.pixelSize: 13; wrapMode: Text.WordWrap
            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
        }

        Rectangle {
            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
            Layout.topMargin: 4
            height: 1; color: Material.dividerColor
        }

        // ── qMonstatek app update (the desktop app itself — also on the About page) ──
        Pane {
            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
            Material.elevation: 1

            // Local self-updater state (mirrors AboutView's updateSection). The
            // shared appUpdateChecker/selfUpdater are global; per-listener guards
            // (qmUpd.downloading) keep this independent of the About copy.
            QtObject {
                id: qmUpd
                property string status: ""
                property string latestVersion: ""
                property string installerUrl: ""
                property string installerName: ""
                property string fallbackUrl: ""
                property bool downloading: false
                property int downloadPct: 0
                property string downloadedPath: ""

                function findInstallerAsset(assets) {
                    var os = Qt.platform.os
                    var raw = null
                    for (var i = 0; i < assets.length; i++) {
                        var nl = assets[i].name.toLowerCase()
                        if (os === "windows") {
                            if (nl.indexOf("windows") >= 0 && nl.indexOf(".zip") >= 0) return assets[i]
                            if (nl.indexOf("_setup") >= 0 && nl.indexOf(".zip") >= 0) return assets[i]
                            if (nl.indexOf("_setup") >= 0 && nl.indexOf(".exe") >= 0) raw = assets[i]
                        } else if (os === "osx") {
                            if (nl.indexOf("macos") >= 0 && nl.indexOf(".zip") >= 0) return assets[i]
                            if (nl.indexOf(".dmg") >= 0) raw = assets[i]
                        } else {
                            if (nl.indexOf("linux") >= 0 && nl.indexOf(".zip") >= 0) return assets[i]
                            if (nl.indexOf(".appimage") >= 0) raw = assets[i]
                        }
                    }
                    return raw
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "qMonstatek app"; font.bold: true; font.pixelSize: 16; Layout.fillWidth: true }
                    Label { text: "v" + Qt.application.version; font.pixelSize: 13; color: Material.hintTextColor }
                }
                Label {
                    text: "Update this desktop app itself (same updater as the About page)."
                    font.pixelSize: 12; color: Material.hintTextColor
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }

                RowLayout {
                    spacing: 12
                    Button {
                        text: appUpdateChecker.checking ? "Checking…" : "Check for qMonstatek updates"
                        enabled: !appUpdateChecker.checking && !qmUpd.downloading
                        onClicked: {
                            qmUpd.status = ""; qmUpd.latestVersion = ""; qmUpd.installerUrl = ""
                            qmUpd.installerName = ""; qmUpd.downloadedPath = ""; qmUpd.downloadPct = 0
                            qmUpd.fallbackUrl = ""
                            var p = Qt.application.version.split(".")
                            appUpdateChecker.checkForUpdates(parseInt(p[0]) || 0, parseInt(p[1]) || 0,
                                                             parseInt(p[2]) || 0, 0, 0)
                        }
                    }
                    Button {
                        visible: qmUpd.installerUrl.length > 0 && !qmUpd.downloading && qmUpd.downloadedPath.length === 0
                        text: "Download & Install " + qmUpd.latestVersion
                        highlighted: true
                        onClicked: {
                            qmUpd.downloading = true; qmUpd.downloadPct = 0
                            appUpdateChecker.downloadAsset(qmUpd.installerUrl,
                                                           selfUpdater.tempDir() + "/" + qmUpd.installerName)
                        }
                    }
                    Button {
                        visible: qmUpd.downloadedPath.length > 0
                        text: "Install Now"
                        highlighted: true
                        onClicked: selfUpdater.launchInstallerAndQuit(qmUpd.downloadedPath)
                    }
                }

                Label {
                    visible: qmUpd.status.length > 0
                    text: qmUpd.status
                    font.pixelSize: 12
                    color: (qmUpd.installerUrl.length > 0 || qmUpd.downloadedPath.length > 0) ? "#4CAF50"
                           : (qmUpd.status.indexOf("Error") === 0 ? "#F44336" : Material.hintTextColor)
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                Label {
                    visible: qmUpd.latestVersion.length > 0 && qmUpd.installerUrl.length === 0
                             && !qmUpd.downloading && qmUpd.fallbackUrl.length > 0
                    text: "<a href=\"" + qmUpd.fallbackUrl + "\">Download " + qmUpd.latestVersion + " from GitHub</a>"
                    font.pixelSize: 12; linkColor: "#8FCBFF"
                    onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                }
                ColumnLayout {
                    visible: qmUpd.downloading
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: "Downloading… " + qmUpd.downloadPct + "%"; font.pixelSize: 12 }
                    ProgressBar { from: 0; to: 100; value: qmUpd.downloadPct; Layout.fillWidth: true }
                }

                Connections {
                    target: appUpdateChecker
                    function onReleaseFound(info) {
                        qmUpd.status = "New version available: " + info.versionFormatted
                        qmUpd.latestVersion = info.versionFormatted
                        var inst = qmUpd.findInstallerAsset(info.assets)
                        if (inst) { qmUpd.installerUrl = inst.downloadUrl; qmUpd.installerName = inst.name }
                        else { qmUpd.installerUrl = ""; qmUpd.fallbackUrl = info.htmlUrl }
                    }
                    function onNoUpdateAvailable(message) {
                        qmUpd.status = "You are on the latest version (v" + Qt.application.version + ")"
                    }
                    function onCheckError(message) {
                        qmUpd.status = (message.indexOf("404") >= 0 || message.indexOf("ContentNotFound") >= 0)
                            ? "Could not check for updates (no releases published)"
                            : "Error: " + message
                    }
                    function onDownloadProgress(percent) { if (qmUpd.downloading) qmUpd.downloadPct = percent }
                    function onDownloadComplete(filePath) {
                        qmUpd.downloading = false; qmUpd.downloadedPath = filePath
                        qmUpd.status = "Download complete — click Install Now."
                    }
                    function onDownloadError(message) {
                        qmUpd.downloading = false; qmUpd.status = "Error downloading: " + message
                    }
                }
                Connections {
                    target: selfUpdater
                    function onUpdateError(message) { qmUpd.status = "Error: " + message }
                }
            }
        }

        Item { Layout.preferredHeight: 20 }
    }

    // ===================== Dialogs =====================

    // Modal "flashing in progress" overlay — unmissable at any window size.
    FlashProgressDialog {
        visible: view.busy
        statusText: view.statusMsg
        percent: view.pct
        stalled: view.stalled
        cancelText: "Cancel and reboot, then try again"
        onCancelRequested: view.rebootDevice()
    }

    Dialog {
        id: confirmDialog
        title: "Update to latest C3"
        anchors.centerIn: Overlay.overlay
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label {
            width: 440; wrapMode: Text.WordWrap
            text: view.espTracked
                  ? "This will download and flash the latest ESP32 firmware, then the latest M1 firmware " +
                    "to the spare bank, then reboot into it. Continue?"
                  : "No ESP repo is set, so this will download and flash the latest M1 firmware to the spare " +
                    "bank, then reboot into it. Continue?"
        }
        onAccepted: view.startUpdate()
    }

    Dialog {
        id: doneDialog
        title: "Update Complete"
        anchors.centerIn: Overlay.overlay
        modal: true
        closePolicy: Popup.NoAutoClose
        standardButtons: Dialog.Ok
        Label {
            width: 440; wrapMode: Text.WordWrap
            text: "Both firmwares are flashed. Click OK to swap to the new M1 build and reboot into it."
        }
        onAccepted: { view.phase = ""; view.statusMsg = ""; m1device.swapBanks() }
    }

    Dialog {
        id: errorDialog
        property string msg: ""
        title: "Update Failed"
        anchors.centerIn: Overlay.overlay
        modal: true
        footer: DialogButtonBox {
            Button { text: "Cancel & reboot, then try again"; onClicked: { view.rebootDevice(); errorDialog.close() } }
            Button { text: "Close"; onClicked: errorDialog.close() }
        }
        ColumnLayout {
            width: 440; spacing: 8
            Label { width: 440; wrapMode: Text.WordWrap; text: errorDialog.msg; Layout.fillWidth: true }
            Label {
                text: "Flashing can hang on the first try. Click \"Cancel & reboot\", wait for the device " +
                      "to reconnect, then run it again — it usually works the next time. Your current " +
                      "firmware is untouched until the final reboot."
                font.pixelSize: 13; color: Material.hintTextColor
                wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
        }
    }
}
