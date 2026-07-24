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

    Material.theme: uiSettings.theme === "light" ? Material.Light : Material.Dark
    Material.accent: Material.Green
    Material.primary: Material.BlueGrey

    // ── Status Bar ──
    header: StatusBar {
        id: statusBar
        updateAvailable: root.appUpdateAvailable
        updateVersion: root.appUpdateVersion
        onOpenUpdate: {
            contentStack.currentIndex = viewIndex("about")
            sidebar.selectedIndex = viewIndex("about")
        }
    }

    // Screen order in the StackLayout (indices 0-11); used for M1 Back navigation.
    readonly property var viewNames: ["deviceInfo", "screenMirror", "fileManager",
                                      "firmwareUpdate", "dualBoot", "esp32Update",
                                      "dfuFlash", "swdRecovery", "debugTerminal",
                                      "settings", "power", "about"]
    property string prevViewName: "deviceInfo"

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
                // Stop screen stream when leaving Screen Mirror view
                if (contentStack.currentIndex === 1 && viewIndex(viewName) !== 1) {
                    if (m1device.screenStreaming)
                        m1device.stopScreenStream()
                }
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
                onNavUp:     sidebar.moveHighlight(-1)
                onNavDown:   sidebar.moveHighlight(1)
                onNavSelect: sidebar.activateHighlight()
                onNavBack:   root.goBack()
            }
            ScreenMirrorView   { id: screenMirrorView }    // 1
            FileManagerView    { id: fileManagerView }     // 2
            FirmwareUpdateView { id: fwUpdateView }        // 3
            DualBootView       { id: dualBootView }        // 4
            Esp32UpdateView    { id: espUpdateView }       // 5
            DfuFlashView       { id: dfuFlashView }        // 6
            SwdRecoveryView    { id: swdRecoveryView }     // 7
            DebugTerminalView  { id: debugTerminalView }   // 8
            SettingsView       { id: settingsView }        // 9
            PowerView          { id: powerView }           // 10
            AboutView          { id: aboutView }           // 11

            // ── Welcome / Connect Prompt (shown when no device connected) ── // 12
            WelcomeView {
                onConnectRequested: deviceSelector.open()
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
        }
    }

    // ── Device selector dialog ──
    DeviceSelector {
        id: deviceSelector
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
            default:                return 0
        }
    }

    // Views that require compatible firmware.
    // Debug Terminal (8) is intentionally NOT here: its Debug Log tab shows
    // app-side logs that exist regardless of connection, so it must stay open
    // when the M1 drops (the CLI controls inside gray out on their own).
    function viewRequiresCompatible(idx) {
        return idx <= 5 || idx === 10
    }

    // ── Auto-navigate on connection state changes ──
    Connections {
        target: m1device
        function onConnectionChanged(connected) {
            if (connected) {
                m1device.requestDeviceInfo()
                reconnectRefreshTimer.restart()
                // WiFi connections prove compatible firmware — go straight to device info
                if (m1device.connectionType === "WiFi") {
                    incompatibleCheckTimer.stop()
                    contentStack.currentIndex = 0
                    sidebar.selectedIndex = 0
                }
            } else {
                reconnectRefreshTimer.stop()
                incompatibleCheckTimer.stop()
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
                // Don't call refreshCurrentView() here — it triggers requestDeviceInfo()
                // which creates an infinite loop: request → response → updated → request
            } else {
                // Got a response but no valid firmware version — incompatible
                incompatibleCheckTimer.stop()
                if (contentStack.currentIndex === 12) {
                    contentStack.currentIndex = 13
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
                if (idx === 12 || viewRequiresCompatible(idx)) {
                    contentStack.currentIndex = 13
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

    // Start on the Connect prompt
    Component.onCompleted: {
        if (!m1device.connected) {
            contentStack.currentIndex = 12
            sidebar.selectedIndex = -1
        }
    }
}
