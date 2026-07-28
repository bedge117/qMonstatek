import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Item {
    id: view

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        Label {
            text: "Power Management"
            font.pixelSize: 24
            font.bold: true
        }

        Label {
            text: "Control your M1 device power state remotely."
            color: Material.hintTextColor
        }

        Label {
            visible: !m1device.connected
            text: "Connect your M1 to use power controls."
            color: Material.hintTextColor
        }

        // Power controls
        Pane {
            visible: m1device.connected
            Layout.fillWidth: true
            Material.elevation: 1

            ColumnLayout {
                anchors.fill: parent
                spacing: 16

                Label {
                    text: "Device Controls"
                    font.bold: true
                    font.pixelSize: 16
                }

                RowLayout {
                    spacing: 16

                    Button {
                        text: "Reboot"
                        icon.source: ""
                        highlighted: true
                        onClicked: rebootConfirm.open()

                        contentItem: RowLayout {
                            spacing: 8
                            Label {
                                text: "\u{1F504}"
                                font.pixelSize: 18
                            }
                            Label {
                                text: "Reboot"
                                font.pixelSize: 14
                            }
                        }
                    }

                    Button {
                        text: "Shutdown"
                        Material.background: "#B71C1C"
                        onClicked: shutdownConfirm.open()

                        contentItem: RowLayout {
                            spacing: 8
                            Label {
                                text: "\u23FB"
                                font.pixelSize: 18
                            }
                            Label {
                                text: "Shutdown"
                                font.pixelSize: 14
                                color: Material.foreground
                            }
                        }
                    }
                }

                Label {
                    text: "Reboot restarts the M1. Shutdown powers it off completely — " +
                          "you'll need to physically press the power button to turn it back on."
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    font.pixelSize: 12
                    color: Material.hintTextColor
                }
            }
        }

        // Status label
        Label {
            id: powerStatus
            visible: text.length > 0
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.pixelSize: 14
        }

        Item { Layout.fillHeight: true }
    }

    Dialog {
        id: rebootConfirm
        title: "Reboot M1"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Yes | Dialog.No

        Label {
            text: "Are you sure you want to reboot the M1?\n\n" +
                  "The device will disconnect briefly during reboot."
            wrapMode: Text.WordWrap
        }

        onAccepted: {
            m1device.reboot()
            powerStatus.text = "Reboot command sent — device is restarting..."
            powerStatus.color = Material.accent
        }
    }

    Dialog {
        id: shutdownConfirm
        title: "Shutdown M1"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Yes | Dialog.No

        Label {
            text: "Are you sure you want to shut down the M1?\n\n" +
                  "You will need to physically press the power button to turn it back on."
            wrapMode: Text.WordWrap
        }

        onAccepted: {
            m1device.shutdown()
            powerStatus.text = "Shutdown command sent — device is powering off..."
            powerStatus.color = Material.accent
        }
    }
}
