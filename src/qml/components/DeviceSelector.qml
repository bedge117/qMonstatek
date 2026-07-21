import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Dialog {
    id: dialog
    title: "Connect to M1"
    modal: true
    anchors.centerIn: parent
    width: 440
    standardButtons: Dialog.Cancel

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        Label {
            text: "Connect to your M1 device via USB or WiFi."
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ── USB Connection ──
        GroupBox {
            title: "USB Connection"
            Layout.fillWidth: true

            ColumnLayout {
                anchors.fill: parent

                Label {
                    visible: deviceDiscovery.availablePorts.length === 0
                    text: "No M1 devices detected.\nMake sure your M1 is connected via USB."
                    color: Material.hintTextColor
                    font.italic: true
                }

                Repeater {
                    model: deviceDiscovery.availablePorts
                    delegate: Button {
                        text: "Connect to " + modelData
                        Layout.fillWidth: true
                        highlighted: true
                        onClicked: {
                            m1device.connectToDevice(modelData)
                            dialog.close()
                        }
                    }
                }

                // Manual port entry
                RowLayout {
                    TextField {
                        id: manualPort
                        placeholderText: Qt.platform.os === "windows" ? "COM port (e.g., COM3)"
                                       : Qt.platform.os === "osx" ? "Port (e.g., /dev/cu.usbmodem)"
                                       : "Port (e.g., /dev/ttyACM0)"
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "Connect"
                        enabled: manualPort.text.length > 0
                        onClicked: {
                            m1device.connectToDevice(manualPort.text)
                            dialog.close()
                        }
                    }
                }
            }
        }

        // ── WiFi Connection ──
        GroupBox {
            title: "WiFi Connection"
            Layout.fillWidth: true

            ColumnLayout {
                anchors.fill: parent

                // mDNS discovered devices
                Label {
                    visible: !mdnsDiscovery.scanning && mdnsDiscovery.services.length === 0
                    text: "No M1 devices found on network.\nMake sure your M1 is connected to WiFi."
                    color: Material.hintTextColor
                    font.italic: true
                }

                BusyIndicator {
                    visible: mdnsDiscovery.scanning
                    running: mdnsDiscovery.scanning
                    Layout.alignment: Qt.AlignHCenter
                }

                Repeater {
                    model: mdnsDiscovery.services
                    delegate: Button {
                        text: modelData.name + " (" + modelData.ip + ":" + modelData.port + ")"
                        Layout.fillWidth: true
                        highlighted: true
                        Material.accent: Material.Teal
                        onClicked: {
                            m1device.connectToDeviceWifi(modelData.target)
                            dialog.close()
                        }
                    }
                }

                Button {
                    text: mdnsDiscovery.scanning ? "Scanning..." : "Scan for WiFi Devices"
                    Layout.fillWidth: true
                    enabled: !mdnsDiscovery.scanning
                    onClicked: mdnsDiscovery.startScan()
                }

                // Manual IP entry
                RowLayout {
                    TextField {
                        id: wifiAddress
                        placeholderText: "IP:Port (e.g., 192.168.1.50:3333)"
                        Layout.fillWidth: true
                    }

                    Button {
                        text: "Connect"
                        enabled: wifiAddress.text.length > 0
                        Material.accent: Material.Teal
                        onClicked: {
                            m1device.connectToDeviceWifi(wifiAddress.text)
                            dialog.close()
                        }
                    }
                }
            }
        }
    }
}
