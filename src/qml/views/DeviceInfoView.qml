import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import "../components"

ScrollView {
    id: view
    contentWidth: availableWidth

    // TV-remote navigation driven by the on-screen M1 D-pad (wired in main.qml)
    signal navUp()
    signal navDown()
    signal navSelect()
    signal navBack()
    // Incompatible-firmware CTA (wired in main.qml → DFU Flash)
    signal goDfu()
    // Install/repair ESP firmware CTA (wired in main.qml → ESP32 Update tab)
    signal goEspUpdate()
    // Whether the ESP is actually talking (compatible brain firmware), vs merely
    // detected on the shared lines. Injected from main.qml.
    property bool espBrainRunning: false

    ColumnLayout {
        width: view.width
        spacing: 14

        Label {
            text: "Device Information"
            font.pixelSize: 24
            font.bold: true
            Layout.topMargin: 24
            Layout.leftMargin: 24
        }

        // ── States ──
        Label {
            visible: !m1device.connected
            text: "Connect your M1 device to view information."
            font.pixelSize: 14; color: Material.hintTextColor
            Layout.leftMargin: 24; Layout.topMargin: 20
            Layout.alignment: Qt.AlignHCenter
        }
        Label {
            visible: m1device.connected && !m1device.hasDeviceInfo
            text: "Device connected, but the firmware doesn't support device info.\n" +
                  "Use DFU Flash to install compatible firmware."
            font.pixelSize: 12; color: "#FF9800"
            wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
        }
        Button {
            visible: m1device.connected && !m1device.hasDeviceInfo
            text: "Go to DFU Flash"
            highlighted: true
            Layout.alignment: Qt.AlignHCenter
            onClicked: view.goDfu()
        }

        // ── Floating WiFi (ESP32) indicator ──
        Item {
            visible: m1device.connected
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 70
            Layout.preferredHeight: 54

            Canvas {
                id: wifiCanvas
                anchors.fill: parent
                property bool active: view.espBrainRunning
                onActiveChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var col = active ? "#4CAF50" : "#F44336"
                    ctx.strokeStyle = col; ctx.fillStyle = col
                    ctx.lineWidth = 3; ctx.lineCap = "round"
                    var cx = width / 2, cy = height * 0.80
                    for (var i = 1; i <= 3; i++) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, i * 9, Math.PI * 1.18, Math.PI * 1.82)
                        ctx.stroke()
                    }
                    ctx.beginPath(); ctx.arc(cx, cy, 3.2, 0, Math.PI * 2); ctx.fill()
                    if (!active) {                 // red slash when not active
                        ctx.lineWidth = 3.2
                        ctx.beginPath()
                        ctx.moveTo(width * 0.18, height * 0.14)
                        ctx.lineTo(width * 0.82, height * 0.9)
                        ctx.stroke()
                    }
                }
                // gentle float
                SequentialAnimation on y {
                    loops: Animation.Infinite; running: true
                    NumberAnimation { from: -3; to: 3; duration: 1800; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 3; to: -3; duration: 1800; easing.type: Easing.InOutSine }
                }
            }
        }

        // ESP status text (+ mismatch hint)
        ColumnLayout {
            visible: m1device.connected
            Layout.alignment: Qt.AlignHCenter
            spacing: 2

            Label {
                text: view.espBrainRunning
                      ? "ESP32 ready — " + m1device.esp32Version
                      : (m1device.esp32Ready
                         ? "ESP32 detected — incompatible firmware"
                         : "ESP32 coprocessor offline")
                font.pixelSize: 12
                color: view.espBrainRunning ? "#4CAF50"
                       : (m1device.esp32Ready ? "#FF9800" : "#F44336")
                Layout.alignment: Qt.AlignHCenter
            }
            // Incompatible (seen but wrong firmware — e.g. still stock/hosted): the
            // radios are wired but it can't speak the C3 protocol. Guide to a flash.
            Label {
                visible: m1device.hasDeviceInfo && m1device.esp32Ready && !view.espBrainRunning
                text: "The ESP is detected but running firmware this M1 build can't talk to " +
                      "(a reboot won't fix it). Install the matching ESP firmware to enable WiFi/BLE."
                font.pixelSize: 11
                color: Material.hintTextColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 360
                Layout.alignment: Qt.AlignHCenter
            }
            // Mobile session: this M1 is also connected to the phone app over WiFi.
            // Informational only — thanks to per-transport response routing the USB
            // link works normally alongside it.
            Label {
                // Only when THIS desktop is on USB — otherwise the desktop itself
                // is the WiFi/TCP client, so link_active just describes our own
                // connection, not a separate mobile app.
                visible: m1device.connected && m1device.mobileLinkActive
                         && m1device.connectionType === "USB"
                text: "📱  Also connected to the mobile app over WiFi"
                font.pixelSize: 11
                color: "#4CAF50"
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
            }
            // Offline (not detected at all): a reboot/replug or Initialize usually clears it.
            Label {
                visible: m1device.hasDeviceInfo && !m1device.esp32Ready
                text: "Press Initialize or Refresh below — a reboot or replug usually clears it too. " +
                      "If it stays offline, flash the matching build on the ESP32 Update tab."
                font.pixelSize: 11
                color: Material.hintTextColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 360
                Layout.alignment: Qt.AlignHCenter
            }

            // Right-here recovery, so the user doesn't have to hunt for the ESP32 tab.
            RowLayout {
                visible: m1device.connected && !view.espBrainRunning
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                spacing: 10

                // Offline → try to (re)initialize on the spot.
                Button {
                    text: "Initialize ESP"
                    visible: !m1device.esp32Ready
                    enabled: m1device.connected
                    onClicked: m1device.initEsp32()
                }
                // Detected-but-incompatible → the fix is a flash, not an init.
                Button {
                    text: "Install ESP firmware"
                    visible: m1device.esp32Ready
                    highlighted: true
                    enabled: m1device.connected
                    onClicked: view.goEspUpdate()
                }
                Button {
                    text: "Refresh"
                    enabled: m1device.connected
                    onClicked: { m1device.requestDeviceInfo(); m1device.requestEspInfo() }
                }
            }
        }

        // ── Screen-share controls: live-mirror the real screen on the graphic below.
        //    Start Stream flips the device graphic from the info readout to the live
        //    screen, and its buttons drive the real M1 (same as the old Screen Mirror). ──
        RowLayout {
            visible: m1device.connected
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            spacing: 12

            Label { text: "FPS:"; Layout.alignment: Qt.AlignVCenter }
            SpinBox {
                id: fpsSpinner
                from: 1; to: 15; value: 10
                editable: true
            }
            Button {
                text: m1device.screenStreaming ? "Stop Stream" : "Start Stream"
                enabled: m1device.connected
                highlighted: m1device.screenStreaming
                onClicked: {
                    if (m1device.screenStreaming)
                        m1device.stopScreenStream()
                    else
                        m1device.startScreenStream(fpsSpinner.value)
                }
            }
            Button {
                text: "Screenshot"
                enabled: m1device.connected
                onClicked: {
                    var path = "screenshot_" + Date.now() + ".png"
                    if (m1device.saveScreenshot(path)) {
                        screenshotLabel.text = "Saved: " + path
                        screenshotLabel.visible = true
                    }
                }
            }
        }
        Label {
            id: screenshotLabel
            visible: false
            color: Material.accent
            font.pixelSize: 12
            Layout.alignment: Qt.AlignHCenter
            Timer {
                running: screenshotLabel.visible
                interval: 3000
                onTriggered: screenshotLabel.visible = false
            }
        }

        // ── The M1: shows its own status on-screen, OR the live mirror while
        //    streaming (scales with the window) ──
        Item {
            visible: m1device.connected
            Layout.alignment: Qt.AlignHCenter
            // Fit to the available width, allowing a generous upscale on big windows.
            property real fit: Math.max(0.5, Math.min((view.width - 60) / 760, 1.7))
            Layout.preferredWidth: 760 * fit
            Layout.preferredHeight: 320 * fit

            M1DeviceSkin {
                anchors.centerIn: parent
                // Streaming → live mirror + buttons drive the real device.
                // Not streaming → static info readout + buttons drive the app menu.
                infoMode: !m1device.screenStreaming
                sendToDevice: m1device.screenStreaming
                caseTheme: uiSettings.caseColor
                scale: parent.fit
                transformOrigin: Item.Center
                onButtonPressed: function(id) {
                    if (m1device.screenStreaming) return   // press() already forwarded to the device
                    if (id === 1)      view.navUp()      // Up
                    else if (id === 4) view.navDown()    // Down
                    else if (id === 0) view.navSelect()  // OK
                    else if (id === 5) view.navBack()    // Back
                }
            }
        }

        // ── Connection card (its own card, under the device) ──
        Pane {
            visible: m1device.connected
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(view.width - 48, 420)
            Material.elevation: 0
            padding: 16
            background: Rectangle {
                radius: 12
                color: Material.theme === Material.Dark ? Qt.lighter(Material.backgroundColor, 1.35)
                                                        : Qt.darker(Material.backgroundColor, 1.03)
                border.width: 1
                border.color: Material.theme === Material.Dark ? Qt.rgba(1, 1, 1, 0.08)
                                                               : Qt.rgba(0, 0, 0, 0.10)
            }

            RowLayout {
                anchors.fill: parent
                spacing: 12
                Label { text: "🔌"; font.pixelSize: 18 }
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Label { text: "Connection"; font.bold: true; color: Material.accent; font.pixelSize: 13 }
                    Label {
                        text: m1device.portName + "  ·  " + m1device.connectionType
                        font.pixelSize: 14
                    }
                }
            }
        }

        // ── Battery details card ──
        Pane {
            visible: m1device.connected && m1device.hasDeviceInfo
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(view.width - 48, 420)
            Material.elevation: 0
            padding: 16
            background: Rectangle {
                radius: 12
                color: Material.theme === Material.Dark ? Qt.lighter(Material.backgroundColor, 1.35)
                                                        : Qt.darker(Material.backgroundColor, 1.03)
                border.width: 1
                border.color: Material.theme === Material.Dark ? Qt.rgba(1, 1, 1, 0.08)
                                                               : Qt.rgba(0, 0, 0, 0.10)
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 6
                Label { text: "Battery"; font.bold: true; color: Material.accent; font.pixelSize: 13 }
                GridLayout {
                    columns: 4
                    columnSpacing: 14
                    rowSpacing: 4
                    Label { text: "Voltage"; font.pixelSize: 11; color: Material.hintTextColor }
                    Label { text: (m1device.batteryVoltage / 1000.0).toFixed(2) + " V"; font.pixelSize: 12 }
                    Label { text: "Current"; font.pixelSize: 11; color: Material.hintTextColor }
                    Label { text: m1device.batteryCurrent + " mA"; font.pixelSize: 12 }
                    Label { text: "Temp"; font.pixelSize: 11; color: Material.hintTextColor }
                    Label { text: m1device.batteryTemp + " °C"; font.pixelSize: 12 }
                    Label { text: "Health"; font.pixelSize: 11; color: Material.hintTextColor }
                    Label {
                        text: m1device.batteryHealth + "%"
                        font.pixelSize: 12
                        color: m1device.batteryHealth > 70 ? Material.foreground : "#F44336"
                    }
                }
            }
        }

        // ── Refresh ──
        Button {
            visible: m1device.connected
            text: "Refresh"
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            onClicked: m1device.requestDeviceInfo()
        }

        Item { Layout.preferredHeight: 20 }
    }
}
