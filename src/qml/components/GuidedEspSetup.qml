import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// ── Guided ESP install ──────────────────────────────────────────────────────
// A friendly, zero-choice wizard for finishing setup after a guided M1 install:
// it fetches the latest ESP (brain) release, downloads the FACTORY image, and
// flashes it — hiding the factory/app-only/browse-PC choices of the full ESP tab.
// Uses the shared esp32Checker + m1device; its own `phase` guards keep the shared
// flash/download signals from crossing with the other views.
Dialog {
    id: dlg
    title: "Finish setup — install ESP firmware"
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min((Overlay.overlay ? Overlay.overlay.width : 520) - 80, 520)

    // "" idle · "downloading" · "flashing" · "done" · "error"
    property string phase: ""
    property int    pct: 0
    property string errMsg: ""
    property var    release: null

    readonly property bool busy: phase === "downloading" || phase === "flashing"
    readonly property bool espTracked: esp32Checker.repoUrl.length > 0

    closePolicy: busy ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
    standardButtons: busy ? Dialog.NoButton
                          : (phase === "done" ? Dialog.Close : Dialog.Cancel)

    onOpened: { dlg.phase = ""; dlg.pct = 0; dlg.errMsg = ""; dlg.release = null }

    function basename(p) { var a = p.split(/[/\\]/); return a[a.length - 1] }

    function pickFactory(rel) {
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

    // Kick off: fetch the latest release, then download + flash the factory image.
    function begin() {
        if (!m1device.connected || !dlg.espTracked) return
        dlg.phase = "downloading"
        dlg.pct = 0
        dlg.errMsg = ""
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) { dlg.fail("Couldn't reach the firmware repository (HTTP " + xhr.status + ")."); return }
            try {
                var j = JSON.parse(xhr.responseText)
                var assets = []
                if (j.assets) for (var i = 0; i < j.assets.length; i++)
                    assets.push({ name: j.assets[i].name, downloadUrl: j.assets[i].browser_download_url })
                dlg.release = { version: j.tag_name, assets: assets }
            } catch (e) { dlg.fail("Couldn't read the release information."); return }
            var asset = dlg.pickFactory(dlg.release)
            if (!asset) { dlg.fail("No ESP firmware image found in the latest release."); return }
            esp32Checker.downloadAsset(asset.downloadUrl, asset.name)
        }
        xhr.open("GET", "https://api.github.com/repos/" + esp32Checker.repoUrl + "/releases/latest")
        xhr.setRequestHeader("User-Agent", "qMonstatek/1.0")
        xhr.setRequestHeader("Accept", "application/vnd.github.v3+json")
        xhr.send()
    }

    function fail(msg) { dlg.phase = "error"; dlg.errMsg = msg }

    // ── Download → flash orchestration (guarded by phase) ──
    Connections {
        target: esp32Checker
        function onDownloadProgress(p) { if (dlg.phase === "downloading") dlg.pct = p }
        function onDownloadComplete(path) {
            if (dlg.phase !== "downloading") return
            if (dlg.basename(path).toLowerCase().endsWith(".md5")) return
            dlg.phase = "flashing"; dlg.pct = 0
            m1device.startEspUpdate(path, 0, false)   // factory image @ 0x0 — the safe one
        }
        function onDownloadError(msg) { if (dlg.phase === "downloading") dlg.fail("Download failed: " + msg) }
    }
    Connections {
        target: m1device
        function onEspUpdateProgress(p) { if (dlg.phase === "flashing") dlg.pct = p }
        function onEspUpdateComplete() {
            if (dlg.phase !== "flashing") return
            dlg.phase = "done"
            m1device.requestDeviceInfo()
            m1device.requestEspInfo()
        }
        function onEspUpdateError(msg) { if (dlg.phase === "flashing") dlg.fail("Flash failed: " + msg) }
        function onConnectionChanged(connected) {
            if (!connected && dlg.busy) dlg.fail("The device disconnected during the flash. Reconnect and try again.")
        }
    }

    contentItem: ColumnLayout {
        spacing: 12

        Label {
            text: "Your M1's main firmware is installed. The ESP32 radio chip still needs its " +
                  "matching firmware so WiFi and Bluetooth work. This installs the right one for " +
                  "you automatically — no files or options to choose."
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.preferredWidth: 460
            font.pixelSize: 14
        }

        // Can't proceed without a device / repo
        Label {
            visible: !m1device.connected
            text: "Connect your M1 to continue."
            color: "#E0A030"; font.pixelSize: 13
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        Label {
            visible: m1device.connected && !dlg.espTracked
            text: "No ESP firmware repository is set. Pick one in Settings → ESP32 Firmware Repository, " +
                  "then reopen this."
            color: "#E0A030"; font.pixelSize: 13
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }

        // Idle → the single action
        Button {
            visible: dlg.phase === "" && m1device.connected && dlg.espTracked
            text: "Install ESP firmware"
            highlighted: true
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            onClicked: dlg.begin()
        }

        // Progress
        ColumnLayout {
            visible: dlg.busy
            Layout.fillWidth: true
            spacing: 6
            Label {
                text: dlg.phase === "downloading" ? "Downloading the ESP firmware…"
                                                  : "Flashing the ESP32… keep the cable connected."
                font.pixelSize: 14; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            ProgressBar { Layout.fillWidth: true; from: 0; to: 100; value: dlg.pct; indeterminate: dlg.pct <= 0 }
            Label { text: dlg.pct + "%"; font.pixelSize: 12; color: Material.hintTextColor }
        }

        // Done
        ColumnLayout {
            visible: dlg.phase === "done"
            Layout.fillWidth: true
            spacing: 6
            Label {
                text: "✓  ESP firmware installed — setup complete!"
                font.pixelSize: 15; font.bold: true; color: "#4CAF50"
                wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            Label {
                text: "WiFi and Bluetooth are ready to use. You can close this window."
                font.pixelSize: 13; color: Material.hintTextColor
                wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
        }

        // Error
        ColumnLayout {
            visible: dlg.phase === "error"
            Layout.fillWidth: true
            spacing: 8
            Label {
                text: dlg.errMsg
                font.pixelSize: 14; color: "#F44336"
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 460
            }
            Label {
                text: "Flashing can hang on the first try — a reboot usually clears it. Reboot the M1, wait " +
                      "for it to reconnect, then try again."
                font.pixelSize: 12; color: Material.hintTextColor
                wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 460
            }
            RowLayout {
                spacing: 10
                Button {
                    text: "Reboot M1"
                    enabled: m1device.connected
                    onClicked: { m1device.reboot(); dlg.phase = "" }
                }
                Button {
                    text: "Try again"
                    highlighted: true
                    enabled: m1device.connected && dlg.espTracked
                    onClicked: dlg.begin()
                }
            }
        }
    }
}
