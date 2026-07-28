import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

/*
 * FlashProgressDialog — a modal "flashing in progress" popup used by every flash
 * flow. Bind `visible` to the view's flashing/updating/busy flag; it opens
 * centered over the whole window (regardless of which tab, or window size) with a
 * status line + progress bar, and blocks the rest of the UI so the user can't
 * miss it or click flash again. Optional stalled warning + cancel button.
 */
Dialog {
    id: dlg

    property string statusText: ""
    property int    percent: 0
    property bool   indeterminate: percent <= 0
    property bool   stalled: false
    property string stalledText: "Hmmm… this is taking longer than expected. If it doesn't move, cancel and try again."
    property string cancelText: ""            // "" hides the cancel button
    property bool   cancelAlways: false       // true = show cancel throughout (not only when stalled)
    signal cancelRequested()

    title: "Flashing — please wait"
    modal: true
    closePolicy: Popup.NoAutoClose            // can't dismiss while flashing
    parent: Overlay.overlay
    anchors.centerIn: Overlay.overlay
    width: Math.min((Overlay.overlay ? Overlay.overlay.width : 480) - 80, 480)

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        Label {
            text: "⚠  Flashing in progress — don't unplug the device, close this app, or start another flash."
            font.pixelSize: 13; font.bold: true; color: "#FF9800"
            wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 420
        }
        Label {
            text: dlg.statusText.length > 0 ? dlg.statusText : "Flashing…"
            font.pixelSize: 14; wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 420
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            ProgressBar {
                Layout.fillWidth: true
                from: 0; to: 100; value: dlg.percent
                indeterminate: dlg.indeterminate
            }
            Label {
                text: dlg.percent > 0 ? dlg.percent + "%" : ""
                font.pixelSize: 14; font.bold: true; color: Material.accent
            }
        }
        Label {
            visible: dlg.stalled
            text: dlg.stalledText
            color: "#FF9800"; font.pixelSize: 13; font.bold: true
            wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.preferredWidth: 420
        }
        Button {
            visible: dlg.cancelText.length > 0 && (dlg.stalled || dlg.cancelAlways)
            text: dlg.cancelText
            Material.foreground: "#FF9800"
            Layout.alignment: Qt.AlignRight
            onClicked: dlg.cancelRequested()
        }
    }
}
