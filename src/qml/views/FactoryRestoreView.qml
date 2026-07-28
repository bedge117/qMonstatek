import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import "../components"

ScrollView {
    id: view
    contentWidth: availableWidth

    // Emitted when the user chooses to install their own firmware instead of a
    // factory restore — main.qml routes this to the M1 Update screen.
    signal installCustomRequested()

    // ── Version → asset mapping (bundled in the app) ──
    readonly property var versions: [
        // 0800/0802 pair with the AT-over-SPI ESP firmware built against esp-at
        // v4.1.1.0 (the version the stock M1 master targets) — confirmed working.
        // The old esp_network_adapter image never worked with 0800/0802.
        { label: "v0.8.0.0", m1: "m1_v0800_wCRC.bin", esp: "esp_at_spi.bin", espName: "AT-SPI" },
        { label: "v0.8.0.2", m1: "m1_v0802_wCRC.bin", esp: "esp_at_spi.bin", espName: "AT-SPI" },
        { label: "v0.8.0.4", m1: "m1_v0804_wCRC.bin", esp: "esp_stealthhybrid.bin", espName: "StealthHybrid" }
    ]
    property int selectedIdx: 2          // default newest (0804) — the confirmed pair
    // What to flash in Stage 2: "full" = ESP then M1 (+bank swap), "m1" = M1 only
    // (+bank swap), "esp" = ESP only (no M1, no bank swap).
    property string restoreMode: "full"

    // ── Orchestration state ──
    property string phase: ""            // "", "host", "esp", "m1", "done"
    property bool   busy: false
    property int    pct: 0
    property string statusMsg: ""
    property string pendingM1: ""
    property bool   stalled: false       // true when progress hasn't moved for a while
    property int    lastPct: -1

    readonly property bool onRestoreHost: m1device.connected && m1device.isRestoreHost

    // Reboot the device (same action as Power ▾). Flashing can hang on the first
    // try; a reboot clears it and the user re-runs. Also resets this view's state.
    function rebootDevice() {
        m1device.reboot()
        view.busy = false; view.phase = ""; view.stalled = false
        view.statusMsg = "Cancelling and rebooting the device… it'll reconnect in a moment — then just run it again."
    }

    // Watchdog for a stalled flash: if % hasn't advanced for the interval, flag it.
    Timer {
        id: stallTimer
        interval: 8000
        repeat: true
        running: view.busy
        onTriggered: {
            if (view.busy && view.pct === view.lastPct && view.pct < 100)
                view.stalled = true
            view.lastPct = view.pct
        }
    }

    // ===================== Orchestration =====================

    // Stage 1: flash the bundled Restore Host FW into the inactive bank.
    function startStage1() {
        var p = selfUpdater.extractStockAsset("M1_RestoreHost_C3.1.0_wCRC.bin")
        if (p === "") return
        view.busy = true; view.phase = "host"; view.pct = 0
        view.stalled = false; view.lastPct = -1
        view.statusMsg = "Flashing the Restore Host firmware…"
        m1device.startFwUpdate(p)
    }

    // Stage 2: flash per the selected mode.
    //   full → ESP then M1 (+swap)   m1 → M1 only (+swap)   esp → ESP only (no swap)
    function startStage2() {
        var v = view.versions[view.selectedIdx]

        if (view.restoreMode === "m1") {
            // M1 only — skip the ESP entirely.
            var m1Only = selfUpdater.extractStockAsset(v.m1)
            if (m1Only === "") return
            view.pendingM1 = ""
            view.busy = true; view.phase = "m1"; view.pct = 0
            view.stalled = false; view.lastPct = -1
            view.statusMsg = "Flashing the stock M1 firmware…"
            m1device.startFwUpdate(m1Only)
            return
        }

        // full or esp — ESP first. For "full" we remember the M1 to flash next.
        selfUpdater.extractStockAsset(v.esp.replace(".bin", ".md5"))   // md5 sidecar
        var espPath = selfUpdater.extractStockAsset(v.esp)
        if (espPath === "") return
        view.pendingM1 = (view.restoreMode === "full") ? v.m1 : ""
        view.busy = true; view.phase = "esp"; view.pct = 0
        view.stalled = false; view.lastPct = -1
        view.statusMsg = "Flashing the stock ESP32 firmware (" + v.espName + ")…"
        m1device.startEspUpdate(espPath, 0, false)
    }

    Connections {
        target: m1device
        function onEspUpdateProgress(p)  { if (view.phase === "esp") view.pct = p }
        function onEspUpdateComplete() {
            if (view.phase !== "esp") return
            if (view.restoreMode === "esp") {
                // ESP-only — done. The M1 stays on the Restore Host; no bank swap.
                view.busy = false; view.phase = "done"
                espDoneDialog.open()
                return
            }
            var m1Path = selfUpdater.extractStockAsset(view.pendingM1)
            if (m1Path === "") { view.busy = false; view.phase = ""; return }
            view.phase = "m1"; view.pct = 0
            view.stalled = false; view.lastPct = -1
            view.statusMsg = "Flashing the stock M1 firmware…"
            m1device.startFwUpdate(m1Path)
        }
        // If the device drops mid-flash (a hang → watchdog reboot, or the user hit
        // Reboot Device), clear busy so they can simply run it again on reconnect.
        function onConnectionChanged(connected) {
            if (!connected && view.busy) {
                view.busy = false; view.phase = ""; view.stalled = false
                view.statusMsg = "Device disconnected mid-flash. If it stalled, it likely " +
                                 "rebooted — reconnect and run it again."
            }
        }
        function onEspUpdateError(msg) {
            if (view.phase !== "esp") return
            view.busy = false; view.phase = ""
            errorDialog.msg = "ESP32 flash failed:\n" + msg
            errorDialog.open()
        }
        function onFwUpdateProgress(p) { if (view.phase === "host" || view.phase === "m1") view.pct = p }
        function onFwUpdateComplete() {
            if (view.phase === "host") {
                // Written to the inactive bank — now swap+reboot into the Restore
                // Host. main.qml auto-navigates to Stage 2 when isRestoreHost turns
                // true after the device reconnects.
                view.busy = false; view.phase = ""
                view.statusMsg = "Restore Host flashed. Swapping banks and rebooting into it…"
                m1device.swapBanks()
            } else if (view.phase === "m1") {
                view.busy = false; view.phase = "done"
                doneDialog.open()
            }
        }
        function onFwUpdateError(msg) {
            /* Only react when Factory Restore actually owns the M1/host flash.
             * All views are instantiated in the content stack, so this handler is
             * live even when the user is in another view; without this guard a
             * failed flash from the M1 Update view popped BOTH that view's dialog
             * and this one. Mirrors the onEspUpdateError / onFwUpdateProgress guards. */
            if (view.phase !== "host" && view.phase !== "m1") return
            var was = view.phase
            view.busy = false; view.phase = ""
            errorDialog.msg = (was === "host" ? "Restore Host flash failed:\n"
                                              : "M1 flash failed:\n") + msg
            errorDialog.open()
        }
    }

    // ===================== UI =====================
    ColumnLayout {
        width: view.width
        spacing: 16

        Label {
            text: "Factory Restore"
            font.pixelSize: 24; font.bold: true
            Layout.topMargin: 24; Layout.leftMargin: 24
        }
        Label {
            text: "Return this M1 to genuine stock Monstatek firmware — both the M1 and its " +
                  "ESP32 co-processor — as a matched, working pair."
            font.pixelSize: 14; color: Material.hintTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
        }

        // ── Not connected ──
        Label {
            visible: !m1device.connected
            text: "Connect your M1 device to begin."
            font.pixelSize: 14; color: Material.hintTextColor
            Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 20
        }

        // ── Busy / progress ──
        Pane {
            visible: view.busy || view.statusMsg.length > 0
            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
            Material.elevation: 2
            ColumnLayout {
                anchors.fill: parent; spacing: 8
                Label { text: view.statusMsg; font.pixelSize: 14; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                ProgressBar {
                    visible: view.busy
                    Layout.fillWidth: true
                    value: view.pct / 100.0
                }
                Label {
                    visible: view.busy
                    text: view.pct + "%"
                    font.pixelSize: 12; color: Material.hintTextColor
                }
                // Stall nudge — friendly, and the "cancel" is really a reboot+retry
                // (flashing can hang on the first try; a quick reboot clears it).
                Label {
                    visible: view.stalled
                    text: "Hmmm… this is taking longer than expected."
                    font.pixelSize: 14; font.bold: true; color: "#FF9800"
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                Button {
                    visible: view.stalled
                    text: "Cancel Flash and try again"
                    Material.foreground: "#FF9800"
                    onClicked: view.rebootDevice()
                }
            }
        }

        // ══════════ STAGE 1 — on normal FW ══════════
        Pane {
            visible: m1device.connected && !view.onRestoreHost && !view.busy
            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
            Material.elevation: 1
            ColumnLayout {
                anchors.fill: parent; spacing: 12

                Label { text: "Step 1 — Prepare"; font.bold: true; font.pixelSize: 16; color: Material.accent }
                Label {
                    text: "Factory Restore runs from a clean minimal host. Clicking below flashes the " +
                          "Restore Host firmware and reboots into it. This screen will then continue " +
                          "automatically to the version picker."
                    font.pixelSize: 14; color: Material.hintTextColor
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
                Button {
                    text: "Start Factory Restore"
                    highlighted: true
                    Layout.alignment: Qt.AlignLeft
                    onClicked: confirmStage1.open()
                }
            }
        }

        // ══════════ STAGE 2 — on Restore Host ══════════
        Pane {
            visible: view.onRestoreHost && !view.busy && view.phase !== "done"
            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
            Material.elevation: 1
            ColumnLayout {
                anchors.fill: parent; spacing: 14

                RowLayout {
                    spacing: 8
                    Label { text: "✓"; color: "#4CAF50"; font.pixelSize: 18; font.bold: true }
                    Label { text: "Restore Host ready"; font.bold: true; font.pixelSize: 16; color: "#4CAF50" }
                }

                Label { text: "Step 2 — Choose the stock version"; font.bold: true; font.pixelSize: 15 }
                Label {
                    text: "Pick the stock Monstatek firmware version to restore. The matching ESP32 image " +
                          "is flashed automatically."
                    font.pixelSize: 13; color: Material.hintTextColor
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }

                ButtonGroup { id: verGroup }
                Repeater {
                    model: view.versions
                    delegate: RadioButton {
                        required property int index
                        required property var modelData
                        text: modelData.label + "   →   ESP: " + modelData.espName
                        font.pixelSize: 14
                        checked: index === view.selectedIdx
                        ButtonGroup.group: verGroup
                        onCheckedChanged: if (checked) view.selectedIdx = index
                    }
                }

                Label { text: "Step 3 — What to flash"; font.bold: true; font.pixelSize: 15; Layout.topMargin: 6 }
                ButtonGroup { id: modeGroup }
                RowLayout {
                    spacing: 18
                    RadioButton {
                        text: "Full (ESP + M1)"; font.pixelSize: 14
                        checked: view.restoreMode === "full"
                        ButtonGroup.group: modeGroup
                        onCheckedChanged: if (checked) view.restoreMode = "full"
                    }
                    RadioButton {
                        text: "M1 only"; font.pixelSize: 14
                        checked: view.restoreMode === "m1"
                        ButtonGroup.group: modeGroup
                        onCheckedChanged: if (checked) view.restoreMode = "m1"
                    }
                    RadioButton {
                        text: "ESP only"; font.pixelSize: 14
                        checked: view.restoreMode === "esp"
                        ButtonGroup.group: modeGroup
                        onCheckedChanged: if (checked) view.restoreMode = "esp"
                    }
                }
                Label {
                    text: view.restoreMode === "esp"
                            ? "Flashes only the stock ESP32 firmware. The M1 stays on the Restore Host — no bank swap."
                          : view.restoreMode === "m1"
                            ? "Flashes only the stock M1 firmware into the inactive bank, then swaps banks."
                            : "Flashes the stock ESP32, then the stock M1 into the inactive bank, then swaps banks."
                    font.pixelSize: 13; color: Material.hintTextColor
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }

                RowLayout {
                    spacing: 12
                    Layout.topMargin: 4
                    Button {
                        text: view.restoreMode === "esp" ? "Flash ESP Firmware"
                            : view.restoreMode === "m1"  ? "Flash M1 Firmware"
                            : "Restore to Factory"
                        highlighted: true
                        onClicked: confirmStage2.open()
                    }
                    Button {
                        text: "Install Custom Firmware…"
                        onClicked: view.installCustomRequested()
                    }
                }
                Label {
                    text: "Restoring to factory isn't your only choice — \"Install Custom Firmware\" " +
                          "opens M1 Update so you can flash any firmware .bin from here."
                    font.pixelSize: 13; color: Material.hintTextColor
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
        }
    }

    // ===================== Dialogs =====================

    // Modal "flashing in progress" overlay — unmissable at any window size + blocks a second action.
    FlashProgressDialog {
        visible: view.busy
        statusText: view.statusMsg
        percent: view.pct
        stalled: view.stalled
        cancelText: "Cancel and reboot, then try again"
        onCancelRequested: view.rebootDevice()
    }

    Dialog {
        id: confirmStage1
        title: "Start Factory Restore"
        anchors.centerIn: Overlay.overlay
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label {
            width: 420
            wrapMode: Text.WordWrap
            text: "This will flash the Restore Host firmware and reboot the device into it. " +
                  "You'll then pick the stock version to restore. Continue?"
        }
        onAccepted: view.startStage1()
    }

    Dialog {
        id: confirmStage2
        title: view.restoreMode === "esp" ? "Flash ESP Firmware"
             : view.restoreMode === "m1"  ? "Flash M1 Firmware"
             : "Restore to Factory"
        anchors.centerIn: Overlay.overlay
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label {
            width: 440
            wrapMode: Text.WordWrap
            text: {
                var ver = (view.selectedIdx >= 0 ? "(" + view.versions[view.selectedIdx].label + ") " : "")
                if (view.restoreMode === "esp")
                    return "This will flash the stock ESP32 firmware " + ver +
                           "onto the co-processor. The M1 stays on the Restore Host — no bank swap. Continue?"
                if (view.restoreMode === "m1")
                    return "This will flash the stock M1 firmware " + ver +
                           "into the inactive bank. When it finishes you'll be asked to swap banks. Continue?"
                return "This will flash the stock ESP32 firmware, then the stock M1 firmware " + ver +
                       "into the inactive bank. When it finishes you'll be asked to swap banks. Continue?"
            }
        }
        onAccepted: view.startStage2()
    }

    Dialog {
        id: doneDialog
        title: "Restore Complete"
        anchors.centerIn: Overlay.overlay
        modal: true
        closePolicy: Popup.NoAutoClose
        standardButtons: Dialog.Ok
        Label {
            width: 440
            wrapMode: Text.WordWrap
            text: (view.restoreMode === "m1"
                    ? "The stock M1 firmware has been flashed. "
                    : "The stock ESP32 and M1 firmware have been flashed. ") +
                  "Click OK to swap to the restored firmware and reboot into it."
        }
        onAccepted: { view.phase = ""; m1device.swapBanks() }
    }

    // ESP-only completion — no bank swap (the M1 is still the Restore Host).
    Dialog {
        id: espDoneDialog
        title: "ESP Firmware Flashed"
        anchors.centerIn: Overlay.overlay
        modal: true
        closePolicy: Popup.NoAutoClose
        standardButtons: Dialog.Ok
        Label {
            width: 440
            wrapMode: Text.WordWrap
            text: "The stock ESP32 firmware has been flashed. The M1 is still running the " +
                  "Restore Host — run a Full or M1-only restore to finish, or install custom firmware."
        }
        onAccepted: { view.phase = ""; view.statusMsg = "ESP firmware flashed. The M1 is still on the Restore Host." }
    }

    Dialog {
        id: errorDialog
        property string msg: ""
        title: "Factory Restore Failed"
        anchors.centerIn: Overlay.overlay
        modal: true
        // The "Cancel & try again" button is really a reboot+retry — flashing can
        // hang on the first try, and a quick reboot clears it.
        footer: DialogButtonBox {
            Button { text: "Cancel Flash and try again"; onClicked: { view.rebootDevice(); errorDialog.close() } }
            Button { text: "Close"; onClicked: errorDialog.close() }
        }
        ColumnLayout {
            width: 440
            spacing: 8
            Label { width: 440; wrapMode: Text.WordWrap; text: errorDialog.msg; Layout.fillWidth: true }
            Label {
                text: "This one didn't take. Click \"Cancel Flash and try again\", wait for the device " +
                      "to reconnect, then run the restore once more — it usually works the next time."
                font.pixelSize: 13; color: Material.hintTextColor
                wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
        }
    }
}
