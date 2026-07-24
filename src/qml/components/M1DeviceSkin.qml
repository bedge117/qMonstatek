import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

/*
 * M1DeviceSkin — a stylized rendering of the physical M1 (qFlipper-style):
 * white rounded body, black glossy face, the live screen on the left, and a
 * clickable D-pad + OK/Back + Monstatek logo on the right.
 *
 * Drawn at a fixed 760x320 design size; scale the whole item from the parent.
 * Button IDs: OK=0, Up=1, Left=2, Right=3, Down=4, Back=5.
 */
Item {
    id: skin
    width: 760
    height: 320

    // Every button press emits this; when sendToDevice is true it ALSO forwards
    // to the physical M1 (Screen Mirror). Device Info sets sendToDevice:false and
    // uses buttonPressed() to drive the app's sidebar instead.
    signal buttonPressed(int id)
    property bool sendToDevice: true
    function press(id) {
        buttonPressed(id)
        if (sendToDevice && m1device.connected) m1device.buttonClick(id)
    }

    // When true, the screen shows a static device-status readout (firmware,
    // bank, SD + a phone-style battery corner) instead of the live mirror.
    property bool infoMode: false

    // ── Case colour (white/black/clear/orange/green) ──
    property string caseTheme: "white"
    readonly property var _cases: ({
        "white":  { top: "#FCFCFD",   bot: "#DCDEE4",   brd: "#C2C5CC", ring: "#FFFFFF", ringOp: 0.55 },
        "black":  { top: "#3B3C42",   bot: "#141518",   brd: "#000000", ring: "#7A7B82", ringOp: 0.35 },
        "clear":  { top: "#96E9EDF5", bot: "#5AC0C6D4", brd: "#C0FFFFFF", ring: "#FFFFFF", ringOp: 0.40 },
        "orange": { top: "#FFB74D",   bot: "#EF6C00",   brd: "#B85200", ring: "#FFE0B2", ringOp: 0.45 },
        "green":  { top: "#7FC983",   bot: "#2E7D32",   brd: "#1B5E20", ring: "#C8E6C9", ringOp: 0.45 }
    })
    readonly property var _c: _cases[caseTheme] !== undefined ? _cases[caseTheme] : _cases["white"]

    // ── Body (rounded, soft gradient) ──
    Rectangle {
        anchors.fill: parent
        radius: height * 0.30
        gradient: Gradient {
            GradientStop { position: 0.0; color: skin._c.top }
            GradientStop { position: 1.0; color: skin._c.bot }
        }
        border.color: skin._c.brd
        border.width: 2
    }
    Rectangle {                       // inner highlight ring
        anchors.fill: parent
        anchors.margins: 3
        radius: (height - 6) * 0.30
        color: "transparent"
        border.color: skin._c.ring
        border.width: 2
        opacity: skin._c.ringOp
    }

    // ── Black glossy face ──
    Rectangle {
        id: face
        anchors.fill: parent
        anchors.margins: 22
        radius: height * 0.20
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#34353B" }
            GradientStop { position: 0.5; color: "#17191D" }
            GradientStop { position: 1.0; color: "#0B0C0F" }
        }
        border.color: "#050506"
        border.width: 1

        Rectangle {                   // glossy top sheen
            x: parent.width * 0.05; y: 7
            width: parent.width * 0.90; height: parent.height * 0.30
            radius: height
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#3AFFFFFF" }
                GradientStop { position: 1.0; color: "#00FFFFFF" }
            }
        }
    }

    // ── Screen (left) ──
    Rectangle {
        x: 44; y: 56
        width: 388; height: 208
        radius: 10
        color: "#050506"
        border.color: "#000000"; border.width: 2

        MonoDisplay {
            visible: !skin.infoMode
            anchors.centerIn: parent
            width: 364
            height: 182
        }

        // ── Static status readout (info mode) — the M1 "showing" its own
        //    status on-screen with a green LCD aesthetic ──
        Item {
            visible: skin.infoMode
            anchors.centerIn: parent
            width: 364
            height: 182
            readonly property color lcd: "#5BE585"

            // top-left tag
            Label {
                anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 8
                text: "M1"
                color: "#5BE585"; opacity: 0.75
                font.pixelSize: 12; font.family: "Courier New"; font.bold: true
            }

            // phone-style battery corner (top-right)
            Row {
                anchors.top: parent.top; anchors.right: parent.right
                anchors.topMargin: 7; anchors.rightMargin: 6
                spacing: 4
                Label {
                    text: "⚡"; font.pixelSize: 12; color: "#5BE585"
                    visible: m1device.batteryCharging || m1device.chargeState > 0
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item {
                    width: 25; height: 13; anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        id: battBody
                        width: 22; height: 13; radius: 2
                        color: "transparent"; border.color: "#5BE585"; border.width: 1.5
                        Rectangle {
                            anchors.left: parent.left; anchors.leftMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(1, (parent.width - 4) * m1device.batteryLevel / 100.0)
                            height: parent.height - 4; radius: 1
                            color: m1device.batteryLevel > 20 ? "#5BE585" : "#FF6B6B"
                        }
                    }
                    Rectangle {   // nub
                        anchors.left: battBody.right; anchors.verticalCenter: parent.verticalCenter
                        width: 2.5; height: 6; radius: 1; color: "#5BE585"
                    }
                }
                Label {
                    text: m1device.batteryLevel + "%"; color: "#5BE585"
                    font.pixelSize: 13; font.family: "Courier New"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // centre status — sized to fill the screen
            Column {
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 12
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: m1device.hasDeviceInfo ? m1device.firmwareVersion : "—"
                    color: "#5BE585"
                    font.pixelSize: 27; font.bold: true; font.family: "Courier New"
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 14
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: m1device.hasDeviceInfo ? "Boot Bank " + m1device.activeBank : ""
                    color: "#5BE585"; opacity: 0.9
                    font.pixelSize: 18; font.family: "Courier New"
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: m1device.sdCardPresent ? "SD  " + m1device.sdCapacity : "No SD card"
                    color: "#5BE585"; opacity: 0.9
                    font.pixelSize: 18; font.family: "Courier New"
                }
            }
        }
    }

    // ── D-pad (cross) ──
    QtObject {
        id: dp
        readonly property real cx: 544
        readonly property real cy: 172
        readonly property real aw: 44      // arm thickness
        readonly property real al: 50      // arm length
        readonly property real gap: 17     // gap from center to arm
    }

    // helper visuals: cross backing bars for a seamless look
    Rectangle {
        x: dp.cx - dp.aw/2; y: dp.cy - dp.al - dp.gap
        width: dp.aw; height: (dp.al + dp.gap) * 2
        radius: 12; color: "#303138"
    }
    Rectangle {
        x: dp.cx - dp.al - dp.gap; y: dp.cy - dp.aw/2
        width: (dp.al + dp.gap) * 2; height: dp.aw
        radius: 12; color: "#303138"
    }

    // Up
    Rectangle {
        x: dp.cx - dp.aw/2; y: dp.cy - dp.al - dp.gap
        width: dp.aw; height: dp.al; radius: 11
        color: upMa.pressed ? "#5B8DEF" : "#3C3D45"
        scale: upMa.pressed ? 0.9 : 1.0
        Behavior on scale { NumberAnimation { duration: 60 } }
        Label { anchors.centerIn: parent; text: "▲"; color: "#E6E7EA"; font.pixelSize: 16 }
        MouseArea { id: upMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: skin.press(1) }
    }
    // Down
    Rectangle {
        x: dp.cx - dp.aw/2; y: dp.cy + dp.gap
        width: dp.aw; height: dp.al; radius: 11
        color: dnMa.pressed ? "#5B8DEF" : "#3C3D45"
        scale: dnMa.pressed ? 0.9 : 1.0
        Behavior on scale { NumberAnimation { duration: 60 } }
        Label { anchors.centerIn: parent; text: "▼"; color: "#E6E7EA"; font.pixelSize: 16 }
        MouseArea { id: dnMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: skin.press(4) }
    }
    // Left
    Rectangle {
        x: dp.cx - dp.al - dp.gap; y: dp.cy - dp.aw/2
        width: dp.al; height: dp.aw; radius: 11
        color: lfMa.pressed ? "#5B8DEF" : "#3C3D45"
        scale: lfMa.pressed ? 0.9 : 1.0
        Behavior on scale { NumberAnimation { duration: 60 } }
        Label { anchors.centerIn: parent; text: "◄"; color: "#E6E7EA"; font.pixelSize: 16 }
        MouseArea { id: lfMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: skin.press(2) }
    }
    // Right
    Rectangle {
        x: dp.cx + dp.gap; y: dp.cy - dp.aw/2
        width: dp.al; height: dp.aw; radius: 11
        color: rtMa.pressed ? "#5B8DEF" : "#3C3D45"
        scale: rtMa.pressed ? 0.9 : 1.0
        Behavior on scale { NumberAnimation { duration: 60 } }
        Label { anchors.centerIn: parent; text: "►"; color: "#E6E7EA"; font.pixelSize: 16 }
        MouseArea { id: rtMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: skin.press(3) }
    }
    // Center (also OK, for muscle memory)
    Rectangle {
        x: dp.cx - 18; y: dp.cy - 18; width: 36; height: 36; radius: 18
        color: ctMa.pressed ? "#43A047" : "#484951"
        scale: ctMa.pressed ? 0.88 : 1.0
        Behavior on scale { NumberAnimation { duration: 60 } }
        MouseArea { id: ctMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: skin.press(0) }
    }

    // ── OK pill ──
    Rectangle {
        x: 630; y: 118; width: 80; height: 44; radius: 22
        color: okMa.pressed ? "#43A047" : "#3C3D45"
        border.color: "#4CAF50"; border.width: 1
        scale: okMa.pressed ? 0.94 : 1.0
        Behavior on scale { NumberAnimation { duration: 60 } }
        Label { anchors.centerIn: parent; text: "OK"; color: "#CFEFD2"; font.pixelSize: 14; font.bold: true }
        MouseArea { id: okMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: skin.press(0) }
    }
    // ── Back pill ──
    Rectangle {
        x: 630; y: 190; width: 80; height: 44; radius: 22
        color: bkMa.pressed ? "#C62828" : "#3C3D45"
        border.color: "#EF5350"; border.width: 1
        scale: bkMa.pressed ? 0.94 : 1.0
        Behavior on scale { NumberAnimation { duration: 60 } }
        Label { anchors.centerIn: parent; text: "BACK"; color: "#F3C9C9"; font.pixelSize: 12; font.bold: true }
        MouseArea { id: bkMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: skin.press(5) }
    }

    // ── Monstatek logo (top-right) ──
    Rectangle {
        x: 656; y: 44; width: 48; height: 48; radius: 24
        color: "#D6336C"
        Label {
            anchors.centerIn: parent
            text: "♨"        // stylised placeholder mark
            visible: false
        }
        // double-peak "M" mark drawn with two triangles
        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = "#FFFFFF"
                var w = width, h = height
                ctx.beginPath()
                ctx.moveTo(w*0.20, h*0.68)
                ctx.lineTo(w*0.36, h*0.34)
                ctx.lineTo(w*0.50, h*0.56)
                ctx.lineTo(w*0.64, h*0.34)
                ctx.lineTo(w*0.80, h*0.68)
                ctx.lineTo(w*0.66, h*0.68)
                ctx.lineTo(w*0.57, h*0.52)
                ctx.lineTo(w*0.50, h*0.62)
                ctx.lineTo(w*0.43, h*0.52)
                ctx.lineTo(w*0.34, h*0.68)
                ctx.closePath()
                ctx.fill()
            }
        }
    }

    // Dim the whole device when nothing is connected
    opacity: m1device.connected ? 1.0 : 0.65
}
