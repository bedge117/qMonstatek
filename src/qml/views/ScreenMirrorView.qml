import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import "../components"

Item {
    id: view
    focus: true

    // Keyboard shortcuts for remote control
    Keys.onUpPressed:     if (m1device.connected) m1device.buttonClick(1)
    Keys.onDownPressed:   if (m1device.connected) m1device.buttonClick(4)
    Keys.onLeftPressed:   if (m1device.connected) m1device.buttonClick(2)
    Keys.onRightPressed:  if (m1device.connected) m1device.buttonClick(3)
    Keys.onReturnPressed: if (m1device.connected) m1device.buttonClick(0)
    Keys.onEscapePressed: if (m1device.connected) m1device.buttonClick(5)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // Title row
        RowLayout {
            Label {
                text: "Screen Mirror"
                font.pixelSize: 24
                font.bold: true
                Layout.fillWidth: true
            }

            // FPS selector
            Label { text: "FPS:" }
            SpinBox {
                id: fpsSpinner
                from: 1; to: 15; value: 10
                editable: true
            }

            // Stream toggle
            Button {
                text: m1device.screenStreaming ? "Stop Stream" : "Start Stream"
                enabled: m1device.connected
                highlighted: m1device.screenStreaming
                onClicked: {
                    if (m1device.screenStreaming) {
                        m1device.stopScreenStream()
                    } else {
                        m1device.startScreenStream(fpsSpinner.value)
                    }
                }
            }

            // Screenshot
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

        // ── M1 device (live screen + on-device controls) ──
        Item {
            id: deviceArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            M1DeviceSkin {
                anchors.centerIn: parent
                caseTheme: uiSettings.caseColor
                // Fixed 760x320 design — scale to fit the available area
                // (allow a little upscale on big windows).
                scale: Math.max(0.3, Math.min((deviceArea.width - 24) / 760,
                                              (deviceArea.height - 24) / 320, 1.4))
                transformOrigin: Item.Center
            }
        }


        // Keyboard hint
        Label {
            text: "Click the buttons, or use the keyboard:  Arrow keys = D-pad  ·  Enter = OK  ·  Esc = Back"
            font.pixelSize: 11
            color: Material.hintTextColor
            Layout.alignment: Qt.AlignHCenter
        }

        // Screenshot notification
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
    }
}
