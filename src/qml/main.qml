import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import "components"
import "views"

ApplicationWindow {
    id: root
    width: 960
    height: 740
    minimumWidth: 800
    minimumHeight: 660
    visible: true
    title: "qMonstatek" + (m1device.connected ? " — " + m1device.portName : "")
    
    property string filePathFilter: Qt.platform.os === "windows" ? "file:///" : "file://"

    // ── qMonstatek self-update check (the APP only — firmware is never auto-checked) ──
    property bool appUpdateAvailable: false
    property string appUpdateVersion: ""

    // ── ESP firmware source ────────────────────────────────────────────────────
    // The ESP32 (SPI brain) repo is chosen independently in Settings and persisted
    // (esp32Checker). "Tracked" just means an ESP repo is configured — the user can
    // pick "None", which turns the ESP update paths into an M1-only experience.
    readonly property bool espTrackedByRepo: esp32Checker.repoUrl.length > 0

    // Whether the ESP is actually running compatible (brain) firmware — not just
    // "seen" on the shared lines. The M1 flags esp32Ready as soon as it detects the
    // co-processor, but a stock/hosted ESP can't answer the brain protocol, so its
    // version never resolves to a real number (stays blank / "checking"). Require a
    // parseable version so an incompatible ESP is correctly treated as "needs brain".
    readonly property bool espBrainRunning: m1device.esp32Ready
                                            && parseVerNums(m1device.esp32Version) !== null

    // ── Unified firmware update check (M1 + ESP together) ──────────────────────
    // One "Check for updates" queries both chips and jumps to whichever is behind,
    // so the user never has to guess which chip needs a flash. 0=pending, 1=behind,
    // 2=current, 3=none/not-tracked/error.
    property bool fwChkActive: false
    property int  fwChkM1:  0
    property int  fwChkEsp: 0
    function checkAllFirmware() {
        root.fwChkActive = true
        root.fwChkM1  = 0
        root.fwChkEsp = 0
        // A check-for-updates is the "release" source on both panes — clear any
        // browsed file so each pane shows only the release path.
        fwUpdateView.enterReleaseMode()
        githubChecker.checkForUpdates(m1device.fwMajor, m1device.fwMinor,
                                      m1device.fwBuild, m1device.fwRC,
                                      m1device.c3Revision)
        if (root.espTrackedByRepo) {
            espUpdateView.enterReleaseMode()
            esp32Checker.checkForUpdates(0, 0, 0, 0, 0)
        } else {
            root.fwChkEsp = 3   // M1-only repo → nothing to compare on the ESP side
        }
    }
    // Extract a dotted version (MAJOR.MINOR[.BUILD[.RC]]) from anywhere in a string.
    // The label prefix varies — the ESP reports e.g. "m1_link 1.0.0" while the release
    // tag is "v1.0.0" — so match the numeric version, not the whole string. Requiring
    // at least one dot avoids latching onto the "1" in a prefix like "m1_link".
    function parseVerNums(s) {
        var m = (s || "").match(/(\d+)\.(\d+)(?:\.(\d+))?(?:\.(\d+))?/)
        if (!m) return null
        return [parseInt(m[1] || "0"), parseInt(m[2] || "0"),
                parseInt(m[3] || "0"), parseInt(m[4] || "0")]
    }
    function cmpVerNums(a, b) {
        for (var i = 0; i < 4; i++) { if (a[i] !== b[i]) return a[i] - b[i] }
        return 0
    }
    // Best-effort ESP "is newer": the ESP release carries no C3 revision, so compare
    // the release version NUMBER to the installed ESP version NUMBER (ignoring the
    // differing label prefixes). Release strictly higher ⇒ newer. If the release can't
    // be parsed, don't nag; if only the installed side can't be parsed, offer it.
    function espReleaseIsNew(info) {
        var rv = parseVerNums((info.version || info.versionFormatted) || "")
        if (rv === null) return false
        var iv = parseVerNums(m1device.esp32Version || "")
        if (iv === null) return true
        return cmpVerNums(rv, iv) > 0
    }
    function fwRouteMaybe() {
        if (!root.fwChkActive) return
        if (root.fwChkM1 === 0) return
        if (root.espTrackedByRepo && root.fwChkEsp === 0) return
        root.fwChkActive = false
        var m1Behind  = (root.fwChkM1 === 1)
        var espBehind = (root.espTrackedByRepo && root.fwChkEsp === 1)
        // Auto-select the chip that needs attention; if both, start with M1.
        if (m1Behind)       root.showFwChip("m1")
        else if (espBehind) root.showFwChip("esp")
        // Neither behind → stay put; each pane's status line already says "up to date".
    }
    Connections {
        target: githubChecker
        function onReleaseFound(info) {
            root.m1UpdateAvailable = (info.isNewer === true)
            root.m1UpdateVersion   = info.versionFormatted
            if (root.fwChkActive) { root.fwChkM1 = info.isNewer ? 1 : 2; root.fwRouteMaybe() }
        }
        function onNoUpdateAvailable(msg) {
            root.m1UpdateAvailable = false
            if (root.fwChkActive) { root.fwChkM1 = 2; root.fwRouteMaybe() }
        }
        function onCheckError(msg) {
            if (root.fwChkActive) { root.fwChkM1 = 3; root.fwRouteMaybe() }
        }
    }
    Connections {
        target: esp32Checker
        function onReleaseFound(info) {
            var neu = root.espReleaseIsNew(info)
            root.espUpdateAvailable = neu
            root.espUpdateVersion   = info.versionFormatted
            if (root.fwChkActive) { root.fwChkEsp = neu ? 1 : 2; root.fwRouteMaybe() }
        }
        function onNoUpdateAvailable(msg) {
            root.espUpdateAvailable = false
            if (root.fwChkActive) { root.fwChkEsp = 3; root.fwRouteMaybe() }
        }
        function onCheckError(msg) {
            if (root.fwChkActive) { root.fwChkEsp = 3; root.fwRouteMaybe() }
        }
    }

    // ── Firmware update banners (checked once per connection) ──────────────────
    // On connect, once the device reports its version, silently check the selected
    // repo for a newer M1 build and (if the repo tracks it) a newer ESP build, and
    // surface a status-bar chip. Reuses the same checkers as the Firmware Update
    // page; the fwChkActive guard above keeps this from hijacking that page's nav.
    property bool m1UpdateAvailable: false
    property string m1UpdateVersion: ""
    property bool espUpdateAvailable: false
    property string espUpdateVersion: ""
    property bool fwBannerChecked: false
    readonly property bool fwUpdateBanner: m1UpdateAvailable || espUpdateAvailable
    readonly property string fwUpdateBannerText: {
        if (m1UpdateAvailable && espUpdateAvailable) return "Firmware updates available"
        if (m1UpdateAvailable) return "M1 firmware update" + (m1UpdateVersion.length > 0 ? "  " + m1UpdateVersion : "")
        if (espUpdateAvailable) return "ESP32 firmware update"
        return ""
    }
    function checkFirmwareBanners() {
        if (!m1device.connected || !m1device.hasDeviceInfo) return
        githubChecker.checkForUpdates(m1device.fwMajor, m1device.fwMinor,
                                      m1device.fwBuild, m1device.fwRC,
                                      m1device.c3Revision)
        if (root.espTrackedByRepo)
            esp32Checker.checkForUpdates(0, 0, 0, 0, 0)
        else
            root.espUpdateAvailable = false
    }
    // Switch the unified Firmware Update page between the M1, ESP and Update-All
    // tabs while keeping the single "Firmware Update" sidebar item highlighted.
    // "dfu" is a special exit → the DFU Flash recovery screen.
    function showFwChip(which) {
        // Leaving the one-click tab cancels the "return here on reconnect" flag.
        if (which !== "all")
            root.updateAllActive = false
        if (which === "dfu") {
            contentStack.currentIndex = viewIndex("dfuFlash")
            sidebar.selectByName("dfuFlash")
            sidebar.highlightIndex = -1
            return
        }
        var name = (which === "esp")  ? "esp32Update"
                 : (which === "all")  ? "updateAll"
                 : "firmwareUpdate"
        contentStack.currentIndex = viewIndex(name)
        sidebar.selectByName("firmwareUpdate")
        sidebar.highlightIndex = -1
        if (which === "all")
            updateAllView.refresh()
        else
            refreshView(name)
    }

    function checkAppUpdate() {
        var parts = Qt.application.version.split(".")
        appUpdateChecker.checkForUpdates(parseInt(parts[0]) || 0,
                                         parseInt(parts[1]) || 0,
                                         parseInt(parts[2]) || 0, 0, 0)
    }

    Connections {
        target: appUpdateChecker
        function onReleaseFound(info) {
            root.appUpdateAvailable = true
            root.appUpdateVersion = info.versionFormatted
        }
    }

    // First check shortly after launch, then a couple of times a day.
    Timer { interval: 8000;             running: true; repeat: false; onTriggered: root.checkAppUpdate() }
    Timer { interval: 6 * 60 * 60 * 1000; running: true; repeat: true;  onTriggered: root.checkAppUpdate() }

    // Accent is user-selectable in Settings and persisted. Default is a refined
    // emerald green (calmer than Material.Green's neon). The device-skin LCD keeps
    // its own green look regardless of this.
    readonly property color accentColor: {
        switch (uiSettings.accent) {
        case "magenta": return "#E24C82"   // Monstatek-brand pink/magenta
        case "indigo":  return "#7C6CF0"   // modern indigo-violet
        case "amber":   return "#F0A83A"   // warm amber
        case "cyan":    return "#2CB8C6"   // teal-cyan
        default:        return "#2FBF71"   // refined green (default)
        }
    }
    // Four themes: dark / light are the Material defaults; chrome is a silvery
    // Light variant; hacker is a black background with green text. chrome/hacker
    // override background/foreground — dark/light return undefined so the Material
    // style keeps its own defaults (assigning undefined resets an attached prop).
    Material.theme: (uiSettings.theme === "light" || uiSettings.theme === "chrome")
                    ? Material.Light : Material.Dark
    Material.accent: uiSettings.theme === "hacker" ? "#00E676" : root.accentColor
    Material.primary: uiSettings.theme === "hacker" ? "#0B0F0B" : Material.BlueGrey
    Material.background: {
        switch (uiSettings.theme) {
        case "chrome": return "#C6CBD3"    // silvery — like Light, pulled back from white
        case "hacker": return "#060A06"    // near-black
        default:       return undefined    // dark / light → Material default
        }
    }
    Material.foreground: {
        switch (uiSettings.theme) {
        case "hacker": return "#43E27A"    // green text
        default:       return undefined    // dark / light / chrome → Material default
        }
    }

    // ── Status Bar ──
    header: StatusBar {
        id: statusBar
        updateAvailable: root.appUpdateAvailable
        updateVersion: root.appUpdateVersion
        onOpenUpdate: {
            contentStack.currentIndex = viewIndex("about")
            sidebar.selectedIndex = viewIndex("about")
        }
        fwUpdateAvailable: root.fwUpdateBanner
        fwUpdateText: root.fwUpdateBannerText
        // The banner is the entry point to the one-click updater.
        onOpenFirmwareUpdate: root.showFwChip("all")
        // Guided setup follow-up: M1 core installed via DFU, ESP still needs the
        // compatible (brain) firmware — show until it actually answers the protocol.
        setupPending: uiSettings.guidedEspPending && m1device.connected
                      && m1device.hasDeviceInfo && !root.espBrainRunning
        onOpenSetup: guidedEspDialog.open()
    }

    // Screen order in the StackLayout (indices 0-11); used for M1 Back navigation.
    readonly property var viewNames: ["deviceInfo", "screenMirror", "fileManager",
                                      "firmwareUpdate", "dualBoot", "esp32Update",
                                      "dfuFlash", "swdRecovery", "debugTerminal",
                                      "settings", "power", "about",
                                      "welcome", "incompatible", "factoryRestore",
                                      "updateAll"]
    // True while a one-click Update All is mid-flash, so a reboot mid-process
    // returns to that tab when the device reconnects.
    property bool updateAllActive: false
    property string prevViewName: "deviceInfo"
    // Auto-jump to Factory Restore should happen ONCE when the Restore Host first
    // appears — not on every device-info refresh (which would trap the user on the
    // Factory Restore screen and block ESP32 Update / M1 Update / etc.). Reset on
    // disconnect so the next Restore-Host boot jumps again.
    property bool restoreHostJumped: false

    // M1 Back button (from Device Info): return to the previous screen, never a
    // recovery screen.
    function goBack() {
        var name = root.prevViewName
        if (name === "dfuFlash" || name === "swdRecovery" || !name)
            name = "deviceInfo"
        contentStack.currentIndex = viewIndex(name)
        sidebar.selectByName(name)
        sidebar.highlightIndex = -1
        refreshView(name)
    }

    // ── Main Layout: Sidebar + Content ──
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Sidebar ──
        Sidebar {
            id: sidebar
            Layout.fillHeight: true
            onNavigated: function(viewName) {
                // Remember the screen we're leaving so the M1 Back button can
                // return to it — but never record the recovery screens.
                var oldIdx = contentStack.currentIndex
                var oldName = (oldIdx >= 0 && oldIdx < root.viewNames.length) ? root.viewNames[oldIdx] : ""
                if (oldName && oldName !== viewName && oldName !== "dfuFlash" && oldName !== "swdRecovery")
                    root.prevViewName = oldName
                // Stop the screen stream when leaving a stream-capable view (Device
                // Info = 0, Screen Mirror = 1) for a non-stream view, so a stream is
                // never left running in the background. Switching between 0 and 1 keeps it.
                var oldStreamable = (contentStack.currentIndex === 0 || contentStack.currentIndex === 1)
                var newStreamable = (viewIndex(viewName) === 0 || viewIndex(viewName) === 1)
                if (oldStreamable && !newStreamable && m1device.screenStreaming)
                    m1device.stopScreenStream()
                contentStack.currentIndex = viewIndex(viewName)
                refreshView(viewName)
            }
        }

        // ── Separator ──
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Material.dividerColor
        }

        // ── Content Area ──
        StackLayout {
            id: contentStack
            Layout.fillWidth: true
            Layout.fillHeight: true

            DeviceInfoView {                               // 0
                id: deviceInfoView
                espBrainRunning: root.espBrainRunning
                onNavUp:     sidebar.moveHighlight(-1)
                onNavDown:   sidebar.moveHighlight(1)
                onNavSelect: sidebar.activateHighlight()
                onNavBack:   root.goBack()
                onGoDfu: {
                    contentStack.currentIndex = viewIndex("dfuFlash")
                    sidebar.selectByName("dfuFlash")
                }
                onGoEspUpdate: guidedEspDialog.open()
            }
            ScreenMirrorView   { id: screenMirrorView }    // 1
            FileManagerView    { id: fileManagerView }     // 2
            FirmwareUpdateView {                           // 3
                id: fwUpdateView
                onRequestChip: function(which) { root.showFwChip(which) }
                onRequestCheck: root.checkAllFirmware()
            }
            DualBootView       { id: dualBootView }        // 4
            Esp32UpdateView {                              // 5
                id: espUpdateView
                espTracked: root.espTrackedByRepo
                espBrainRunning: root.espBrainRunning
                onRequestChip: function(which) { root.showFwChip(which) }
            }
            DfuFlashView       { id: dfuFlashView }        // 6
            SwdRecoveryView    { id: swdRecoveryView }     // 7
            DebugTerminalView  { id: debugTerminalView }   // 8
            SettingsView       { id: settingsView }        // 9
            PowerView          { id: powerView }           // 10
            AboutView          { id: aboutView }           // 11

            // ── Welcome / Connect Prompt (shown when no device connected) ── // 12
            WelcomeView {
                onConnectRequested: deviceSelector.open()
                onSetupRequested: root.showFwChip("dfu")
            }

            // ── Incompatible Firmware (connected but no RPC support) ── // 13
            Item {
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16

                    Label {
                        text: "Incompatible Firmware"
                        font.pixelSize: 28
                        font.bold: true
                        color: "#FF9800"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Label {
                        text: "Connected to " + m1device.portName + ", but the installed firmware\n" +
                              "is not compatible with this application.\n\n" +
                              "Use DFU Flash or SWD Recovery to install compatible firmware."
                        font.pixelSize: 14
                        color: Material.hintTextColor
                        horizontalAlignment: Text.AlignHCenter
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Button {
                        text: "Go to DFU Flash"
                        highlighted: true
                        Layout.alignment: Qt.AlignHCenter
                        onClicked: {
                            contentStack.currentIndex = viewIndex("dfuFlash")
                            sidebar.selectedIndex = 6
                        }
                    }
                }
            }

            FactoryRestoreView {                           // 14
                id: factoryRestoreView
                onInstallCustomRequested: {
                    contentStack.currentIndex = viewIndex("firmwareUpdate")
                    sidebar.selectByName("firmwareUpdate")
                }
            }

            UpdateAllView {                                // 15
                id: updateAllView
                espTracked: root.espTrackedByRepo
                onRequestChip: function(which) { root.showFwChip(which) }
                onUpdateInFlight: function(active) { root.updateAllActive = active }
            }
        }
    }

    // ── Device selector dialog ──
    DeviceSelector {
        id: deviceSelector
    }

    // ── Guided ESP install (friendly one-button wizard) ──
    GuidedEspSetup {
        id: guidedEspDialog
    }

    // Auto-jump to Factory Restore when the device comes up on the Restore Host
    // (fw_variant == 2) — Stage 1 flashed it and it just rebooted.
    Connections {
        target: m1device
        function onDeviceInfoUpdated() {
            if (m1device.isRestoreHost && !root.restoreHostJumped
                    && contentStack.currentIndex !== viewIndex("factoryRestore")) {
                contentStack.currentIndex = viewIndex("factoryRestore")
                sidebar.selectByName("factoryRestore")
                root.restoreHostJumped = true
            }
        }
    }

    // ── View index mapping ──
    function viewIndex(name) {
        switch (name) {
            case "deviceInfo":      return 0
            case "screenMirror":    return 1
            case "fileManager":     return 2
            case "firmwareUpdate":  return 3
            case "dualBoot":        return 4
            case "esp32Update":     return 5
            case "dfuFlash":        return 6
            case "swdRecovery":     return 7
            case "debugTerminal":   return 8
            case "settings":        return 9
            case "power":           return 10
            case "about":           return 11
            case "welcome":         return 12
            case "incompatible":    return 13
            // Single sidebar entry that lands on the right "no usable device"
            // screen: the incompatible-FW screen if a device is attached, else
            // the connect/welcome screen with setup instructions.
            case "connect":         return m1device.connected ? 13 : 12
            case "factoryRestore":  return 14
            case "updateAll":       return 15
            default:                return 0
        }
    }

    // Views that require compatible firmware.
    // Debug Terminal (8) is intentionally NOT here: its Debug Log tab shows
    // app-side logs that exist regardless of connection, so it must stay open
    // when the M1 drops (the CLI controls inside gray out on their own).
    function viewRequiresCompatible(idx) {
        // 14 = Factory Restore: only valid on a compatible/recovery-host FW (both
        // report device info). After a restore the device boots genuine stock,
        // which qM can't read — so leave Factory Restore for the Incompatible view.
        return idx <= 5 || idx === 10 || idx === 14
    }

    // ── Auto-navigate on connection state changes ──
    Connections {
        target: m1device
        function onConnectionChanged(connected) {
            if (connected) {
                m1device.requestDeviceInfo()
                reconnectRefreshTimer.restart()
                dfuFlasher.stopScanning()   // a normal device is here; no DFU polling
                // WiFi connections prove compatible firmware — go straight to device info
                if (m1device.connectionType === "WiFi") {
                    incompatibleCheckTimer.stop()
                    contentStack.currentIndex = 0
                    sidebar.selectedIndex = 0
                }
            } else {
                // No normal device — watch for one appearing in DFU mode so the
                // welcome screen can offer "Setup M1". Harmless if CubeProgrammer
                // isn't installed (the scan no-ops).
                dfuFlasher.startScanning()
                reconnectRefreshTimer.stop()
                incompatibleCheckTimer.stop()
                root.restoreHostJumped = false   // re-arm the one-shot Restore-Host jump
                // Clear firmware banners + re-arm the one-shot per-connection check
                root.fwBannerChecked = false
                root.m1UpdateAvailable = false
                root.espUpdateAvailable = false
                // Navigate away from device-dependent views
                var idx = contentStack.currentIndex
                if (viewRequiresCompatible(idx) || idx === 13) {
                    contentStack.currentIndex = 12
                    sidebar.selectedIndex = -1
                }
            }
        }
        function onDeviceInfoUpdated() {
            if (!m1device.connected) return
            if (m1device.hasDeviceInfo) {
                // Compatible firmware detected
                incompatibleCheckTimer.stop()
                // Resume a one-click Update All that was mid-flash when the device
                // rebooted — return to that tab so the user can re-run it.
                if (root.updateAllActive) {
                    root.showFwChip("all")
                    return
                }
                // The minimal Recovery FW reports v0.8.0.0-C3.1 — keep the recovery
                // tools open for it so it can still be re-flashed.
                var isRecovery = (m1device.fwMajor === 0 && m1device.fwMinor === 8 &&
                                  m1device.fwBuild === 0 && m1device.fwRC === 0 &&
                                  m1device.c3Revision === 1)
                var idx = contentStack.currentIndex
                // Placeholders (12/13) always yield; the real DFU Flash (6) and SWD
                // Flash (7) views yield only for a genuine working firmware. Close any
                // open popups on those screens as we leave.
                if (idx === 12 || idx === 13 ||
                    ((idx === 6 || idx === 7) && !isRecovery)) {
                    dfuFlashView.closeAllPopups()
                    swdRecoveryView.closeAllPopups()
                    contentStack.currentIndex = 0
                    sidebar.selectedIndex = 0
                }
                // First-connect highlight sync: at launch the app already defaults to
                // Device Info (index 0), so the block above no-ops (idx is already 0)
                // and the sidebar selection is never set — the item stays unhighlighted
                // until the user clicks something. Now that the compatible menu is
                // available, point the highlight at whatever view we're actually on.
                if (sidebar.selectedIndex < 0) {
                    if (contentStack.currentIndex === 0)
                        sidebar.selectByName("deviceInfo")
                }
                // Firmware banners: once per connection, silently check the selected
                // repo for a newer M1 (and, if tracked, ESP) build and flag it in the
                // status bar — so a new release is surfaced at launch, not just when
                // the user happens to open the Firmware Update page.
                if (!root.fwBannerChecked) {
                    root.fwBannerChecked = true
                    root.checkFirmwareBanners()
                }
                // Guided setup completes only when the ESP is running compatible brain
                // firmware (a real version came back) — not merely "seen" on the lines.
                if (uiSettings.guidedEspPending && root.espBrainRunning)
                    uiSettings.guidedEspPending = false
                // Don't call refreshCurrentView() here — it triggers requestDeviceInfo()
                // which creates an infinite loop: request → response → updated → request
            } else {
                // Got a response but no valid firmware version — incompatible.
                // Show the Device Info screen (index 0) in its device-image
                // "incompatible" state (mockup + warning + Go to DFU Flash),
                // consistent whether the device was attached at launch or hot-plugged.
                incompatibleCheckTimer.stop()
                var cur = contentStack.currentIndex
                if (cur === 12 || cur === 13 || viewRequiresCompatible(cur)) {
                    contentStack.currentIndex = 0
                    sidebar.selectedIndex = -1
                }
            }
        }
    }

    Timer {
        id: reconnectRefreshTimer
        interval: 2000
        onTriggered: {
            if (m1device.connected) {
                m1device.requestDeviceInfo()
                refreshCurrentView()
                // If still no device info (USB only — WiFi proves compatibility)
                if (!m1device.hasDeviceInfo && m1device.connectionType !== "WiFi")
                    incompatibleCheckTimer.restart()
            }
        }
    }

    // Fallback: if stock firmware never responds to RPC, switch to incompatible view
    Timer {
        id: incompatibleCheckTimer
        interval: 3000
        onTriggered: {
            if (m1device.connected && !m1device.hasDeviceInfo) {
                var idx = contentStack.currentIndex
                if (idx === 12 || idx === 13 || viewRequiresCompatible(idx)) {
                    // Incompatible → Device Info (index 0) device-image state,
                    // the single canonical incompatible screen.
                    contentStack.currentIndex = 0
                    sidebar.selectedIndex = -1
                }
            }
        }
    }

    function refreshCurrentView() {
        var names = ["deviceInfo", "screenMirror", "fileManager",
                     "firmwareUpdate", "dualBoot", "esp32Update",
                     "dfuFlash", "swdRecovery", "debugTerminal",
                     "settings", "power", "about"]
        refreshView(names[contentStack.currentIndex] || "")
    }

    function refreshView(viewName) {
        if (!m1device.connected) return
        switch (viewName) {
            case "deviceInfo":
                m1device.requestDeviceInfo()
                break
            case "fileManager":
                fileManagerView.refresh()
                break
            case "dualBoot":
                m1device.requestFwInfo()
                break
            case "esp32Update":
                m1device.requestDeviceInfo()
                m1device.requestEspInfo()
                break
            // screenMirror, firmwareUpdate, settings, about: no auto-refresh needed
        }
    }

    // ── Keyboard shortcuts for remote control ──
    Shortcut {
        sequence: "Up"
        enabled: contentStack.currentIndex === 1 && m1device.connected
        onActivated: m1device.buttonClick(1)  // BUTTON_UP
    }
    Shortcut {
        sequence: "Down"
        enabled: contentStack.currentIndex === 1 && m1device.connected
        onActivated: m1device.buttonClick(4)  // BUTTON_DOWN
    }
    Shortcut {
        sequence: "Left"
        enabled: contentStack.currentIndex === 1 && m1device.connected
        onActivated: m1device.buttonClick(2)  // BUTTON_LEFT
    }
    Shortcut {
        sequence: "Right"
        enabled: contentStack.currentIndex === 1 && m1device.connected
        onActivated: m1device.buttonClick(3)  // BUTTON_RIGHT
    }
    Shortcut {
        sequence: "Return"
        enabled: contentStack.currentIndex === 1 && m1device.connected
        onActivated: m1device.buttonClick(0)  // BUTTON_OK
    }
    Shortcut {
        sequence: "Escape"
        enabled: contentStack.currentIndex === 1 && m1device.connected
        onActivated: m1device.buttonClick(5)  // BUTTON_BACK
    }

    // Start on the Connect prompt — or, if a device is already attached at launch,
    // kick the same connect flow onConnectionChanged runs. Without this, a device
    // present before the UI wired up never starts the incompatible-check timer, so
    // an incompatible unit was left on a different (partial) screen than a hot-plug.
    Component.onCompleted: {
        if (!m1device.connected) {
            contentStack.currentIndex = 12
            sidebar.selectedIndex = -1
            dfuFlasher.startScanning()   // watch for a DFU device on the welcome screen
        } else {
            m1device.requestDeviceInfo()
            reconnectRefreshTimer.restart()
            if (m1device.connectionType !== "WiFi")
                incompatibleCheckTimer.restart()
        }
    }
}
