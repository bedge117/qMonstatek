import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import Monstatek.Backend 1.0

/*
 * MonoDisplay — Renders the 128x64 M1 screen upscaled with LCD appearance.
 * Supports click-to-control: clicking on different regions triggers button events.
 */
Item {
    id: display
    implicitWidth: 512
    implicitHeight: 256

    // Finished (already-upscaled) frames are PUSHED from M1Device — no image
    // provider pull, no conversion on the GUI thread (COMMS_REBUILD_SPEC §7).
    ScreenCanvas {
        id: screenCanvas
        anchors.fill: parent

        Connections {
            target: m1device
            function onScreenImageReady(image) { screenCanvas.setFrame(image) }
        }
    }

    // LCD bezel effect
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: "#333333"
        border.width: 2
        radius: 4
    }

    // Scanline overlay for LCD effect
    Canvas {
        anchors.fill: parent
        opacity: 0.08
        onPaint: {
            var ctx = getContext("2d")
            ctx.strokeStyle = "#000000"
            ctx.lineWidth = 1
            for (var y = 0; y < height; y += 4) {
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.lineTo(width, y)
                ctx.stroke()
            }
        }
    }

    // No-device placeholder
    Rectangle {
        anchors.fill: parent
        color: "#0A0A0A"
        visible: !m1device.connected || !m1device.screenStreaming
        radius: 4

        Label {
            anchors.centerIn: parent
            text: m1device.connected
                  ? "Click 'Start Stream' to begin"
                  : "No device connected"
            color: "#00FF66"
            font.pixelSize: 16
            font.family: "Courier New"
            opacity: 0.6
        }
    }

    // Click regions for button control
    MouseArea {
        anchors.fill: parent
        enabled: m1device.connected
        onClicked: function(mouse) {
            // Map click position to button zones
            var relX = mouse.x / width
            var relY = mouse.y / height

            if (relX < 0.25) {
                m1device.buttonClick(2)  // LEFT
            } else if (relX > 0.75) {
                m1device.buttonClick(3)  // RIGHT
            } else if (relY < 0.3) {
                m1device.buttonClick(1)  // UP
            } else if (relY > 0.7) {
                m1device.buttonClick(4)  // DOWN
            } else {
                m1device.buttonClick(0)  // OK (center)
            }
        }
    }
}
