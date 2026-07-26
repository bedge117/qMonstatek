import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ToolBar {
    id: bar
    Material.elevation: 0   // flat/integrated (modern) — the primary color still separates it

    // Hairline bottom divider so the flat bar reads cleanly against content
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Qt.rgba(0, 0, 0, 0.25)
    }

    // Driven by main.qml's periodic qMonstatek update check
    property bool updateAvailable: false
    property string updateVersion: ""
    signal openUpdate()

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        // Connection indicator
        Rectangle {
            width: 10; height: 10
            radius: 5
            color: m1device.connected ? "#4CAF50" : "#F44336"
        }

        Label {
            text: m1device.connected
                  ? m1device.firmwareVersion + " [" + m1device.connectionType + "]"
                  : "No device"
            font.pixelSize: 13
        }

        // Legacy-firmware compatibility indicator — the connected device predates
        // the CRC-table fix; qMonstatek is talking to it in a compat dialect so
        // the user can push the fixing update without DFU.
        Rectangle {
            visible: m1device.connected && m1device.legacyCompatMode
            Layout.leftMargin: 12
            implicitWidth: legacyRow.implicitWidth + 14
            implicitHeight: 22
            radius: 11
            color: "#44FF9800"   // soft fill, no hard border (modern chip)

            RowLayout {
                id: legacyRow
                anchors.centerIn: parent
                spacing: 5
                Label {
                    text: "⚠ Legacy FW — compatibility mode"
                    font.pixelSize: 12
                    color: "#FF9800"
                }
            }
            ToolTip.visible: legacyHover.hovered
            ToolTip.text: "This firmware predates the CRC fix. Updating the firmware "
                        + "from this app will restore normal operation."
            HoverHandler { id: legacyHover }
        }

        // Log-to-file indicator — shows when Debug Terminal logging is enabled,
        // so you can see it's capturing without switching to the debug screen.
        RowLayout {
            visible: m1device.logToFile
            spacing: 5
            Layout.leftMargin: 16

            Rectangle {
                width: 9; height: 9
                radius: 4.5
                color: "#F44336"
                SequentialAnimation on opacity {
                    running: m1device.logToFile
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.25; duration: 650; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.25; to: 1.0; duration: 650; easing.type: Easing.InOutQuad }
                }
            }
            Label {
                text: "Logging enabled"
                font.pixelSize: 12
                color: "#F44336"
            }
        }

        // qMonstatek update-available indicator (click → About page)
        Rectangle {
            visible: bar.updateAvailable
            Layout.leftMargin: 16
            implicitWidth: updateRow.implicitWidth + 16
            implicitHeight: 22
            radius: 11
            color: "#444CAF50"   // soft fill, no hard border (modern chip)

            RowLayout {
                id: updateRow
                anchors.centerIn: parent
                spacing: 5

                Rectangle {
                    width: 9; height: 9; radius: 4.5
                    color: "#4CAF50"
                    SequentialAnimation on opacity {
                        running: bar.updateAvailable
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.3; duration: 700; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 0.3; to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
                    }
                }
                Label {
                    text: "Update available!" + (bar.updateVersion.length > 0 ? "  " + bar.updateVersion : "")
                    font.pixelSize: 12
                    font.bold: true
                    color: "#4CAF50"
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: bar.openUpdate()
            }
            ToolTip.visible: updHover.hovered
            ToolTip.text: "A newer qMonstatek is available — click to open the About page and install"
            HoverHandler { id: updHover }
        }

        Item { Layout.fillWidth: true }

        // Battery indicator
        RowLayout {
            visible: m1device.connected
            spacing: 4

            Label {
                text: m1device.batteryCharging ? "⚡" : "🔋"
                font.pixelSize: 14
            }
            Label {
                text: m1device.batteryLevel + "%"
                font.pixelSize: 12
            }
        }

        // SD card indicator
        Label {
            visible: m1device.connected && m1device.sdCardPresent
            text: "💾 SD"
            font.pixelSize: 12
            Layout.leftMargin: 12
        }

        // ESP32 indicator
        Label {
            visible: m1device.connected
            text: m1device.esp32Ready ? "📡 ESP OK" : "📡 ESP ✗"
            font.pixelSize: 12
            color: m1device.esp32Ready ? Material.foreground : "#F44336"
            Layout.leftMargin: 12
        }

        // Connect/Disconnect button
        ToolButton {
            text: m1device.connected ? "Disconnect" : "Connect"
            onClicked: {
                if (m1device.connected) {
                    m1device.disconnect()
                } else {
                    deviceSelector.open()
                }
            }
        }
    }
}
