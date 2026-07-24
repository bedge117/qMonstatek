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

        // ── Floating WiFi (ESP32) indicator ──
        Item {
            visible: m1device.connected
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 70
            Layout.preferredHeight: 54

            Canvas {
                id: wifiCanvas
                anchors.fill: parent
                property bool active: m1device.esp32Ready
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

        // ESP status text
        Label {
            visible: m1device.connected
            text: m1device.esp32Ready
                  ? "ESP32 ready — " + m1device.esp32Version
                  : "ESP32 coprocessor not initialized"
            font.pixelSize: 12
            color: m1device.esp32Ready ? "#4CAF50" : "#F44336"
            Layout.alignment: Qt.AlignHCenter
        }

        // ── The M1, showing its own status on-screen (scales with the window) ──
        Item {
            visible: m1device.connected
            Layout.alignment: Qt.AlignHCenter
            // Fit to the available width, allowing a generous upscale on big windows.
            property real fit: Math.max(0.5, Math.min((view.width - 60) / 760, 1.7))
            Layout.preferredWidth: 760 * fit
            Layout.preferredHeight: 320 * fit

            M1DeviceSkin {
                anchors.centerIn: parent
                infoMode: true
                sendToDevice: false          // buttons drive the app menu, not the device
                caseTheme: uiSettings.caseColor
                scale: parent.fit
                transformOrigin: Item.Center
                onButtonPressed: function(id) {
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
            Material.elevation: 2

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
            Material.elevation: 1

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
