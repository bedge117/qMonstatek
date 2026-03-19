import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Item {
    id: view

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        Item { Layout.fillHeight: true }

        // App title
        Label {
            text: "qMonstatek"
            font.pixelSize: 36
            font.bold: true
            color: Material.accent
            Layout.alignment: Qt.AlignHCenter
        }

        Label {
            text: "Desktop Companion for Monstatek M1"
            font.pixelSize: 16
            Layout.alignment: Qt.AlignHCenter
            color: Material.hintTextColor
        }

        Label {
            text: "Version " + Qt.application.version
            font.pixelSize: 14
            Layout.alignment: Qt.AlignHCenter
        }

        Rectangle {
            Layout.preferredWidth: 300
            Layout.preferredHeight: 1
            Layout.alignment: Qt.AlignHCenter
            color: Material.dividerColor
            Layout.topMargin: 16
            Layout.bottomMargin: 16
        }

        // Features list
        Label {
            text: "Features"
            font.bold: true
            font.pixelSize: 16
            Layout.alignment: Qt.AlignHCenter
        }

        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            columns: 2
            columnSpacing: 24
            rowSpacing: 8

            Label { text: "🖥  Screen Mirror"; font.pixelSize: 13 }
            Label { text: "Live display streaming + remote control"; font.pixelSize: 11; color: Material.hintTextColor }

            Label { text: "⬆  Firmware Update"; font.pixelSize: 13 }
            Label { text: "Update from GitHub or local file"; font.pixelSize: 11; color: Material.hintTextColor }

            Label { text: "📁  File Manager"; font.pixelSize: 13 }
            Label { text: "Browse, upload, download SD card files"; font.pixelSize: 11; color: Material.hintTextColor }

            Label { text: "🔄  Dual Boot"; font.pixelSize: 13 }
            Label { text: "Manage flash banks, swap, rollback"; font.pixelSize: 11; color: Material.hintTextColor }

            Label { text: "📡  ESP32 Update"; font.pixelSize: 13 }
            Label { text: "Flash ESP32-C6 coprocessor firmware"; font.pixelSize: 11; color: Material.hintTextColor }
        }

        Rectangle {
            Layout.preferredWidth: 300
            Layout.preferredHeight: 1
            Layout.alignment: Qt.AlignHCenter
            color: Material.dividerColor
            Layout.topMargin: 16
            Layout.bottomMargin: 16
        }

        // Check for Updates
        Label {
            text: "Updates"
            font.bold: true
            font.pixelSize: 16
            Layout.alignment: Qt.AlignHCenter
        }

        ColumnLayout {
            id: updateSection
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            property string updateStatus: ""
            property string updateUrl: ""
            property string latestVersion: ""

            Button {
                id: checkBtn
                text: appUpdateChecker.checking ? "Checking..." : "Check for Updates"
                enabled: !appUpdateChecker.checking
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    updateSection.updateStatus = ""
                    updateSection.updateUrl = ""
                    updateSection.latestVersion = ""
                    var parts = Qt.application.version.split(".")
                    appUpdateChecker.checkForUpdates(
                        parseInt(parts[0]) || 0,
                        parseInt(parts[1]) || 0,
                        parseInt(parts[2]) || 0,
                        0, 0)
                }
            }

            Label {
                id: statusLabel
                visible: updateSection.updateStatus.length > 0
                text: updateSection.updateStatus
                font.pixelSize: 12
                color: {
                    if (updateSection.updateUrl.length > 0) return "#4CAF50"
                    if (updateSection.updateStatus.indexOf("Error") === 0) return "#F44336"
                    if (updateSection.updateStatus.indexOf("Could not") === 0) return "#FF9800"
                    return "#4CAF50"
                }
                Layout.alignment: Qt.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 400
                horizontalAlignment: Text.AlignHCenter
            }

            Label {
                visible: updateSection.updateUrl.length > 0
                text: "<a href=\"" + updateSection.updateUrl + "\" style=\"color:#2196F3;\">Download " + updateSection.latestVersion + "</a>"
                font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
                onLinkActivated: function(link) { Qt.openUrlExternally(link) }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.NoButton
                }
            }

            Connections {
                target: appUpdateChecker
                function onReleaseFound(info) {
                    updateSection.updateStatus = "New version available: " + info.versionFormatted
                    updateSection.updateUrl = info.htmlUrl
                    updateSection.latestVersion = info.versionFormatted
                }
                function onNoUpdateAvailable(message) {
                    updateSection.updateStatus = "You are on the latest version (v" + Qt.application.version + ")"
                }
                function onCheckError(message) {
                    if (message.indexOf("ContentNotFoundError") >= 0 || message.indexOf("404") >= 0) {
                        updateSection.updateStatus = "Could not check for updates (no releases published)"
                    } else {
                        updateSection.updateStatus = "Error: " + message
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 300
            Layout.preferredHeight: 1
            Layout.alignment: Qt.AlignHCenter
            color: Material.dividerColor
            Layout.topMargin: 16
            Layout.bottomMargin: 16
        }

        Label {
            text: "Open Source — github.com/bedge117/qMonstatek"
            font.pixelSize: 12
            color: Material.hintTextColor
            Layout.alignment: Qt.AlignHCenter
        }

        Item { Layout.fillHeight: true }
    }
}
