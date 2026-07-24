import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

/*
 * WelcomeView — the landing screen shown when no device is connected.
 * Branded welcome + hero M1 skin + a celebratory "What's new" panel.
 * Emits connectRequested() (handled in main.qml → deviceSelector.open()).
 */
Item {
    id: welcome
    signal connectRequested()

    // subtle accent glow behind the hero
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.16
        width: Math.min(parent.width * 0.7, 620)
        height: width * 0.45
        radius: height / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#2243A047" }
            GradientStop { position: 1.0; color: "#0043A047" }
        }
        opacity: 0.7
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            id: content
            width: welcome.width
            spacing: 14

            // Entrance animation
            property real appear: 0.0
            opacity: appear
            transform: Translate { y: (1.0 - content.appear) * 22 }
            Component.onCompleted: appearAnim.start()
            NumberAnimation {
                id: appearAnim
                target: content; property: "appear"
                from: 0.0; to: 1.0; duration: 480; easing.type: Easing.OutCubic
            }

            Item { Layout.preferredHeight: 18 }

            // ── Hero: the M1 skin, gently floating ──
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 404
                Layout.preferredHeight: 178

                M1DeviceSkin {
                    anchors.centerIn: parent
                    caseTheme: uiSettings.caseColor
                    scale: 0.52
                    transformOrigin: Item.Center
                    SequentialAnimation on anchors.verticalCenterOffset {
                        loops: Animation.Infinite
                        running: true
                        NumberAnimation { from: -6; to: 6; duration: 2000; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 6; to: -6; duration: 2000; easing.type: Easing.InOutSine }
                    }
                }
            }

            // ── "Major update" badge ──
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: badgeRow.implicitWidth + 22
                implicitHeight: 26
                radius: 13
                color: "#2243A047"
                border.color: "#4CAF50"; border.width: 1

                RowLayout {
                    id: badgeRow
                    anchors.centerIn: parent
                    spacing: 6
                    Label {
                        text: "✨"
                        font.pixelSize: 13
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite; running: true
                            NumberAnimation { from: 1.0; to: 0.4; duration: 900; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 0.4; to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                        }
                    }
                    Label {
                        text: "Major update  ·  v" + Qt.application.version
                        font.pixelSize: 12; font.bold: true
                        color: "#4CAF50"
                    }
                }
            }

            // ── Wordmark ──
            Label {
                text: "qMonstatek"
                font.pixelSize: 34
                font.bold: true
                color: Material.accent
                Layout.alignment: Qt.AlignHCenter
            }
            Label {
                text: "Flash, control, and manage your M1 — all in one place."
                font.pixelSize: 14
                color: Material.hintTextColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 520
            }

            // ── Connect action / connecting state ──
            Button {
                visible: !m1device.connected
                text: "Connect a device"
                highlighted: true
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                onClicked: welcome.connectRequested()
            }
            RowLayout {
                visible: m1device.connected
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                spacing: 8
                BusyIndicator { running: true; implicitWidth: 22; implicitHeight: 22 }
                Label { text: "Connecting — reading device info…"; font.pixelSize: 13 }
            }
            Label {
                visible: !m1device.connected
                text: "No device? DFU Flash and SWD Flash work without one."
                font.pixelSize: 11
                color: Material.hintTextColor
                Layout.alignment: Qt.AlignHCenter
            }

            // ── What's new card ──
            Pane {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 10
                Layout.maximumWidth: 620
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 2

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    RowLayout {
                        spacing: 8
                        Label { text: "🎉"; font.pixelSize: 16 }
                        Label {
                            text: "What's new in this update"
                            font.pixelSize: 15; font.bold: true
                            Layout.fillWidth: true
                        }
                    }

                    Repeater {
                        model: [
                            "Redesigned flash tools — DFU, SWD, M1 & ESP32 updates, each with built-in guides, wiring diagrams and troubleshooting",
                            "Full file browser — rename, move, and delete folders (with everything inside)",
                            "Live M1 device skin — clickable controls plus swappable case colors",
                            "Automatic app-update checks and a light / dark theme",
                            "Clearer progress, errors, and one-click recovery help throughout"
                        ]
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Label { text: "✦"; color: Material.accent; font.pixelSize: 14; Layout.alignment: Qt.AlignTop }
                            Label {
                                text: modelData
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 24 }
        }
    }
}
