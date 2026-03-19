import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: view

    property var releaseInfo: null
    property bool downloading: false
    property int downloadPercent: 0
    property bool flashing: false
    property int flashPercent: 0
    property string flashStatus: ""
    property string selectedFilePath: ""
    property string selectedFileName: ""
    property string downloadedFilePath: ""

    Connections {
        target: m1device
        function onFwUpdateProgress(percent) {
            view.flashing = true
            view.flashPercent = percent
            view.flashStatus = "Flashing firmware... " + percent + "%"
        }
        function onFwUpdateComplete() {
            view.flashing = false
            view.flashStatus = "Success! Firmware written and CRC verified! Use Dual Boot to swap."
            flashStatusLabel.color = "#4CAF50"
        }
        function onFwUpdateError(message) {
            view.flashing = false
            view.flashStatus = "Flash error: " + message
            flashStatusLabel.color = "#F44336"
        }
    }

    Connections {
        target: githubChecker
        function onReleaseFound(info) {
            view.releaseInfo = info
        }
        function onNoUpdateAvailable(message) {
            noUpdateLabel.text = message
            noUpdateLabel.visible = true
        }
        function onCheckError(message) {
            errorLabel.text = message
            errorLabel.visible = true
        }
        function onDownloadProgress(percent) {
            view.downloadPercent = percent
        }
        function onDownloadComplete(filePath) {
            view.downloading = false
            view.downloadedFilePath = filePath
            downloadedFileLabel.text = "Downloaded: " + filePath
            downloadedFileLabel.visible = true
        }
    }

    ScrollView {
        anchors.fill: parent

        ColumnLayout {
            width: view.width
            spacing: 16
            anchors.margins: 24

            Label {
                text: "Firmware Update"
                font.pixelSize: 24
                font.bold: true
                Layout.topMargin: 24
                Layout.leftMargin: 24
            }

            // Current version
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                RowLayout {
                    anchors.fill: parent
                    Label {
                        text: "Current firmware:"
                        font.bold: true
                    }
                    Label {
                        text: m1device.connected ? m1device.firmwareVersion : "Not connected"
                        Layout.fillWidth: true
                    }
                    Label {
                        text: "Bank " + m1device.activeBank
                        visible: m1device.connected
                    }
                }
            }

            // Update source info
            Label {
                text: {
                    var repo = githubChecker.repoUrl
                    var suffix = (repo === "bedge117/M1") ? " (Default)" : ""
                    return "Update source: " + repo + suffix + "  \u2014  Change in Settings"
                }
                font.pixelSize: 11
                color: Material.hintTextColor
                Layout.leftMargin: 24
            }

            // Check for updates
            RowLayout {
                Layout.leftMargin: 24
                spacing: 12

                Button {
                    text: githubChecker.checking ? "Checking..." : "Check for Updates"
                    enabled: !githubChecker.checking
                    highlighted: true
                    onClicked: {
                        noUpdateLabel.visible = false
                        errorLabel.visible = false
                        view.releaseInfo = null
                        githubChecker.checkForUpdates(
                            m1device.fwMajor, m1device.fwMinor,
                            m1device.fwBuild, m1device.fwRC,
                            m1device.c3Revision)
                    }
                }

                Button {
                    text: "Flash from File..."
                    enabled: !view.flashing
                    onClicked: fileDialog.open()
                }

                Label {
                    text: view.selectedFileName.length > 0
                          ? view.selectedFileName
                          : ""
                    visible: view.selectedFileName.length > 0
                    color: Material.foreground
                    elide: Text.ElideMiddle
                }

                Button {
                    text: "Flash Firmware"
                    highlighted: true
                    visible: view.selectedFileName.length > 0
                    enabled: m1device.connected && !view.flashing
                    onClicked: fileConfirmDialog.open()
                }
            }

            Label {
                id: noUpdateLabel
                text: ""
                visible: false
                color: "#4CAF50"
                Layout.leftMargin: 24
                font.pixelSize: 13
            }

            Label {
                id: errorLabel
                visible: false
                color: "#F44336"
                Layout.leftMargin: 24
            }

            // Flash-from-file progress
            ProgressBar {
                visible: view.flashing
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                value: view.flashPercent / 100.0
            }

            Label {
                id: flashStatusLabel
                visible: view.flashStatus.length > 0
                text: view.flashStatus
                Layout.leftMargin: 24
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // Release info card
            Pane {
                visible: releaseInfo !== null
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 2

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    Label {
                        text: releaseInfo ? releaseInfo.name : ""
                        font.pixelSize: 18
                        font.bold: true
                    }

                    RowLayout {
                        spacing: 12
                        Label {
                            text: releaseInfo ? "Version: " + releaseInfo.versionFormatted : ""
                            color: Material.accent
                        }
                        Label {
                            visible: releaseInfo && releaseInfo.isNewer
                            text: "NEW UPDATE AVAILABLE"
                            font.bold: true
                            color: "#4CAF50"
                        }
                        Label {
                            visible: releaseInfo && releaseInfo.currentVersion
                            text: releaseInfo ? "(current: " + releaseInfo.currentVersion + ")" : ""
                            font.pixelSize: 11
                            color: Material.hintTextColor
                        }
                    }

                    Label {
                        text: releaseInfo ? releaseInfo.publishedAt : ""
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Material.dividerColor
                    }

                    // Release notes
                    Label {
                        text: "Release Notes"
                        font.bold: true
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150

                        TextArea {
                            text: releaseInfo ? releaseInfo.body : ""
                            readOnly: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: 12
                        }
                    }

                    // Assets list
                    Label {
                        text: "Assets"
                        font.bold: true
                    }

                    Repeater {
                        model: releaseInfo ? releaseInfo.assets : []
                        delegate: RowLayout {
                            Layout.fillWidth: true

                            Label {
                                text: modelData.name
                                font.pixelSize: 12
                                Layout.fillWidth: true
                            }
                            Label {
                                text: (modelData.size / 1024).toFixed(0) + " KB"
                                font.pixelSize: 11
                                color: Material.hintTextColor
                            }
                            Button {
                                text: "Download"
                                enabled: !view.downloading
                                font.pixelSize: 11
                                onClicked: {
                                    view.downloading = true
                                    view.downloadedFilePath = ""
                                    var dest = modelData.name
                                    githubChecker.downloadAsset(modelData.downloadUrl, dest)
                                }
                            }
                        }
                    }

                    // Download progress
                    ProgressBar {
                        visible: view.downloading
                        Layout.fillWidth: true
                        value: view.downloadPercent / 100.0
                    }

                    Label {
                        id: downloadedFileLabel
                        visible: false
                        color: Material.accent
                    }

                    RowLayout {
                        visible: view.downloadedFilePath.length > 0 && !view.downloading
                        spacing: 12

                        Button {
                            text: "Flash Downloaded Firmware"
                            highlighted: true
                            enabled: m1device.connected && !view.flashing
                            onClicked: downloadedConfirmDialog.open()
                        }

                        Button {
                            text: "Save to PC"
                            onClicked: saveDialog.open()
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: "Select Firmware Binary"
        nameFilters: ["Binary files (*.bin)", "All files (*)"]
        onAccepted: {
            var path = selectedFile.toString().replace("file:///", "")
            view.selectedFilePath = path
            var parts = path.split(/[/\\]/)
            view.selectedFileName = parts[parts.length - 1]
            flashStatusLabel.color = Material.foreground
            view.flashStatus = ""
        }
    }

    Dialog {
        id: fileConfirmDialog
        title: "Confirm Firmware Flash"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12

            Label {
                text: "Flash firmware to inactive bank?"
                font.bold: true
            }
            Label {
                text: "File: " + view.selectedFileName
            }
            Label {
                text: "The firmware will be written to the inactive bank.\n" +
                      "Use Dual Boot to swap banks after flashing."
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Material.hintTextColor
            }
        }

        onAccepted: {
            flashStatusLabel.color = Material.foreground
            view.flashStatus = ""
            m1device.startFwUpdate(view.selectedFilePath)
        }
    }

    FileDialog {
        id: saveDialog
        title: "Save Firmware File"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Binary files (*.bin)", "All files (*)"]
        currentFile: {
            var parts = view.downloadedFilePath.split(/[/\\]/)
            var name = parts[parts.length - 1]
            return "file:///" + name
        }
        onAccepted: {
            var dest = selectedFile.toString().replace("file:///", "")
            githubChecker.saveFileTo(view.downloadedFilePath, dest)
        }
    }

    Dialog {
        id: downloadedConfirmDialog
        title: "Confirm Firmware Flash"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12

            Label {
                text: "Flash firmware to inactive bank?"
                font.bold: true
            }
            Label {
                text: "File: " + view.downloadedFilePath
                wrapMode: Text.WordWrap
            }
            Label {
                text: "The firmware will be written to the inactive bank.\n" +
                      "Use Dual Boot to swap banks after flashing."
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Material.hintTextColor
            }
        }

        onAccepted: {
            flashStatusLabel.color = Material.foreground
            view.flashStatus = ""
            m1device.startFwUpdate(view.downloadedFilePath)
        }
    }
}
