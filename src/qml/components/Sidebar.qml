import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Rectangle {
    id: sidebar
    Layout.preferredWidth: 190

    // Is the app in dark mode? Drives theme-correct shades below.
    readonly property bool dark: Material.theme === Material.Dark

    // Flat, richer-than-content rail (a la VS Code / Discord) — a gradient
    // just read as washed-out, so keep it a clean solid with depth via a
    // darker shade + the right-edge divider.
    color: sidebar.dark ? Qt.darker(Material.backgroundColor, 1.5)
                        : Qt.darker(Material.backgroundColor, 1.05)

    signal navigated(string viewName)

    property int selectedIndex: -1
    readonly property bool showCompatibleItems: m1device.connected && m1device.hasDeviceInfo
    // The minimal Recovery FW reports v0.8.0.0-C3.1 — a stripped image whose only
    // job is to re-flash. Treat it as "not a working FW" so the recovery tools stay
    // available on a device that still needs restoring.
    readonly property bool isRecoveryFw: m1device.hasDeviceInfo
                                         && m1device.fwMajor === 0 && m1device.fwMinor === 8
                                         && m1device.fwBuild === 0 && m1device.fwRC === 0
                                         && m1device.c3Revision === 1
    // A healthy, full firmware is connected. When true we hide the recovery tools;
    // when false (no device, stock/incompatible FW, or the Recovery FW) we show them.
    readonly property bool workingFwRecognized: showCompatibleItems && !isRecoveryFw

    readonly property var menuItems: [
        { name: "deviceInfo",     label: "Device Info",     icon: "ℹ",  section: "",         requires: "compatible" },
        { name: "screenMirror",   label: "Screen Mirror",   icon: "🖥", section: "",         requires: "compatible" },
        { name: "fileManager",    label: "File Manager",    icon: "📁", section: "",         requires: "compatible" },
        { name: "firmwareUpdate", label: "M1 Update",    icon: "⬆", section: "Firmware", requires: "compatible" },
        { name: "esp32Update",    label: "ESP32 Update", icon: "📡", section: "",         requires: "compatible" },
        { name: "dualBoot",       label: "Dual Boot",    icon: "🔄", section: "",         requires: "compatible" },
        { name: "dfuFlash",      label: "DFU Flash",        icon: "⚡", section: "Recovery", requires: "recovery" },
        { name: "swdRecovery",  label: "SWD Flash",        icon: "🔧", section: "",         requires: "recovery" },
        { name: "debugTerminal", label: "Debug Terminal",    icon: ">",  section: "System",   requires: "none" },
        { name: "settings",      label: "Settings",         icon: "⚙", section: "",         requires: "none" },
        { name: "power",        label: "Power",            icon: "⏻", section: "",         requires: "compatible" },
        { name: "about",         label: "About",            icon: "?",  section: "",         requires: "none" }
    ]

    function isItemVisible(item) {
        if (item.requires === "compatible") return showCompatibleItems
        if (item.requires === "recovery")   return !workingFwRecognized
        return true
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
        spacing: 3

        // ── Brand header ──
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.leftMargin: 4
            spacing: 8

            // Monstatek "M" mark
            Rectangle {
                width: 26; height: 26; radius: 13
                color: "#D6336C"
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.fillStyle = "#FFFFFF"
                        var w = width, h = height
                        ctx.beginPath()
                        ctx.moveTo(w*0.20, h*0.68); ctx.lineTo(w*0.36, h*0.34)
                        ctx.lineTo(w*0.50, h*0.56); ctx.lineTo(w*0.64, h*0.34)
                        ctx.lineTo(w*0.80, h*0.68); ctx.lineTo(w*0.66, h*0.68)
                        ctx.lineTo(w*0.57, h*0.52); ctx.lineTo(w*0.50, h*0.62)
                        ctx.lineTo(w*0.43, h*0.52); ctx.lineTo(w*0.34, h*0.68)
                        ctx.closePath(); ctx.fill()
                    }
                }
            }
            Label {
                text: "qMonstatek"
                font.pixelSize: 17
                font.bold: true
                color: Material.accent
                Layout.fillWidth: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.topMargin: 8
            Layout.bottomMargin: 4
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            color: Material.dividerColor
        }

        // ── Navigation ──
        Repeater {
            model: menuItems
            delegate: ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                visible: sidebar.isItemVisible(modelData)

                // Section header (label, not just a line)
                Label {
                    visible: modelData.section.length > 0 && sidebar.hasVisibleItemBefore(index)
                    text: modelData.section.toUpperCase()
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.5
                    color: Material.hintTextColor
                    Layout.topMargin: 12
                    Layout.leftMargin: 12
                    Layout.bottomMargin: 2
                }

                // Nav item
                Rectangle {
                    id: navItem
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 9
                    readonly property bool selected: sidebar.selectedIndex === index
                    color: selected
                           ? Qt.rgba(Material.accent.r, Material.accent.g, Material.accent.b, 0.16)
                           : navMa.containsMouse
                             ? (sidebar.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06))
                             : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    // left accent bar when selected
                    Rectangle {
                        visible: navItem.selected
                        width: 3; radius: 2
                        height: parent.height * 0.5
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: Material.accent
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 8
                        spacing: 12

                        Label {
                            text: modelData.icon
                            font.pixelSize: 16
                            Layout.preferredWidth: 22
                            horizontalAlignment: Text.AlignHCenter
                            opacity: navItem.selected ? 1.0 : 0.85
                        }
                        Label {
                            text: modelData.label
                            font.pixelSize: 13
                            font.bold: navItem.selected
                            color: navItem.selected ? Material.accent : Material.foreground
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: navMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            sidebar.selectedIndex = index
                            sidebar.navigated(modelData.name)
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }  // spacer

        // ── Connection status ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 10
            color: m1device.connected
                   ? (sidebar.dark ? "#173F1C" : "#E6F4EA")
                   : (sidebar.dark ? "#3A1010" : "#FBE7E4")
            border.color: m1device.connected ? "#2E7D32" : "#C0392B"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 8

                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: m1device.connected ? "#4CAF50" : "#EF5350"
                    SequentialAnimation on opacity {
                        running: !m1device.connected
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.35; duration: 800; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 0.35; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                    }
                }
                Label {
                    text: m1device.connected ? m1device.portName : "Connect a device"
                    font.pixelSize: 11
                    color: sidebar.dark ? "white"
                           : (m1device.connected ? "#1B5E20" : "#B71C1C")
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: { if (!m1device.connected) deviceSelector.open() }
                cursorShape: m1device.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
            }
        }
    }

    // Soft right-edge divider so the rail meets the content cleanly
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: Material.dividerColor
        opacity: 0.6
    }
}
