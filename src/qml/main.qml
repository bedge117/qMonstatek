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

    Material.theme: Material.Dark
    Material.accent: Material.Green
    Material.primary: Material.BlueGrey

    // ── Status Bar ──
    header: StatusBar {
        id: statusBar
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

            DeviceInfoView     { id: deviceInfoView }      // 0
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

            // ── Connect Prompt (shown when no device connected) ── // 12
            Item {
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16

                    Label {
                        text: m1device.connected ? "Connecting..." : "Connect M1"
                        font.pixelSize: 28
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Label {
                        text: m1device.connected
                              ? "Reading device info..."
                              : "Connect your M1 device to get started.\nDFU Flash and SWD Recovery are available without a connection."
                        font.pixelSize: 14
                        color: Material.hintTextColor
                        horizontalAlignment: Text.AlignHCenter
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Button {
                        visible: !m1device.connected
                        text: "Connect"
                        highlighted: true
                        Layout.alignment: Qt.AlignHCenter
                        onClicked: deviceSelector.open()
                    }
                }
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

    // Views that require compatible firmware
    function viewRequiresCompatible(idx) {
        return idx <= 5 || idx === 8 || idx === 10
    }

    // ── Auto-navigate on connection state changes ──
    Connections {
        target: m1device
        function onConnectionChanged(connected) {
            if (connected) {
                m1device.requestDeviceInfo()
                reconnectRefreshTimer.restart()
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
                if (contentStack.currentIndex === 12 || contentStack.currentIndex === 13) {
                    contentStack.currentIndex = 0
                    sidebar.selectedIndex = 0
                }
                refreshCurrentView()
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
                // If still no device info, start the incompatible fallback timer
                if (!m1device.hasDeviceInfo)
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
