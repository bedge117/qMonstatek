import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Rectangle {
    id: sidebar
    Layout.preferredWidth: 180
    color: Material.backgroundColor

    signal navigated(string viewName)

    property int selectedIndex: -1
    readonly property bool showCompatibleItems: m1device.connected && m1device.hasDeviceInfo

    readonly property var menuItems: [
        { name: "deviceInfo",     label: "Device Info",     icon: "ℹ",  section: "",         requires: "compatible" },
        { name: "screenMirror",   label: "Screen Mirror",   icon: "🖥", section: "",         requires: "compatible" },
        { name: "fileManager",    label: "File Manager",    icon: "📁", section: "",         requires: "compatible" },
        { name: "firmwareUpdate", label: "Firmware Update",  icon: "⬆", section: "Firmware", requires: "compatible" },
        { name: "dualBoot",      label: "Dual Boot",        icon: "🔄", section: "",         requires: "compatible" },
        { name: "esp32Update",    label: "ESP32 Update",     icon: "📡", section: "",         requires: "compatible" },
        { name: "dfuFlash",      label: "DFU Flash",        icon: "⚡", section: "Recovery", requires: "none" },
        { name: "swdRecovery",  label: "SWD Recovery",     icon: "🔧", section: "",         requires: "none" },
        { name: "debugTerminal", label: "Debug Terminal",    icon: ">",  section: "System",   requires: "compatible" },
        { name: "settings",      label: "Settings",         icon: "⚙", section: "",         requires: "none" },
        { name: "power",        label: "Power",            icon: "⏻", section: "",         requires: "compatible" },
        { name: "about",         label: "About",            icon: "?",  section: "",         requires: "none" }
    ]

    function isItemVisible(item) {
        return item.requires !== "compatible" || showCompatibleItems
    }

    function hasVisibleItemBefore(idx) {
        for (var i = 0; i < idx; i++) {
            if (isItemVisible(menuItems[i]))
                return true
        }
        return false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        // App title
        Label {
            text: "qMonstatek"
            font.pixelSize: 18
            font.bold: true
            color: Material.accent
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 12
        }

        // Navigation buttons
        Repeater {
            model: menuItems
            delegate: ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: sidebar.isItemVisible(modelData)

                // Section divider (only if there's a visible item above)
                Rectangle {
                    visible: modelData.section.length > 0 && sidebar.hasVisibleItemBefore(index)
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 8
                    Layout.bottomMargin: 4
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    color: Material.dividerColor
                }

                ItemDelegate {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40

                    highlighted: sidebar.selectedIndex === index
                    text: modelData.label
                    icon.source: ""

                    contentItem: RowLayout {
                        spacing: 12
                        Label {
                            text: modelData.icon
                            font.pixelSize: 16
                            Layout.preferredWidth: 24
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Label {
                            text: modelData.label
                            font.pixelSize: 13
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    onClicked: {
                        sidebar.selectedIndex = index
                        sidebar.navigated(modelData.name)
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }  // spacer

        // Connection status at bottom
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: 6
            color: m1device.connected ? "#1B5E20" : "#4A0000"

            Label {
                anchors.centerIn: parent
                text: m1device.connected
                      ? "Connected: " + m1device.portName
                      : "Connect M1"
                font.pixelSize: 11
                color: "white"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (!m1device.connected) {
                        deviceSelector.open()
                    }
                }
                cursorShape: m1device.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
            }
        }
    }
}
