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
            property string latestVersion: ""
            property string installerUrl: ""
            property string installerName: ""
            property bool downloading: false
            property int downloadPct: 0
            property string downloadedPath: ""

            // Find the _setup.zip asset from release assets (fall back to _setup.exe)
            function findInstallerAsset(assets) {
                var zipAsset = null
                var exeAsset = null
                for (var i = 0; i < assets.length; i++) {
                    var name = assets[i].name
                    if (name.indexOf("_setup") >= 0) {
                        if (name.indexOf(".zip") >= 0) zipAsset = assets[i]
                        else if (name.indexOf(".exe") >= 0) exeAsset = assets[i]
                    }
                }
                return zipAsset || exeAsset
            }

            Button {
                id: checkBtn
                text: appUpdateChecker.checking ? "Checking..." : "Check for Updates"
                enabled: !appUpdateChecker.checking && !updateSection.downloading
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    updateSection.updateStatus = ""
                    updateSection.latestVersion = ""
                    updateSection.installerUrl = ""
                    updateSection.installerName = ""
                    updateSection.downloadedPath = ""
                    updateSection.downloadPct = 0
                    var parts = Qt.application.version.split(".")
                    appUpdateChecker.checkForUpdates(
                        parseInt(parts[0]) || 0,
                        parseInt(parts[1]) || 0,
                        parseInt(parts[2]) || 0,
                        0, 0)
                }
            }

            // Status text
            Label {
                id: statusLabel
                visible: updateSection.updateStatus.length > 0
                text: updateSection.updateStatus
                font.pixelSize: 12
                color: {
                    if (updateSection.installerUrl.length > 0) return "#4CAF50"
                    if (updateSection.updateStatus.indexOf("Error") === 0) return "#F44336"
                    if (updateSection.updateStatus.indexOf("Could not") === 0) return "#FF9800"
                    return "#4CAF50"
                }
                Layout.alignment: Qt.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 400
                horizontalAlignment: Text.AlignHCenter
            }

            // Download & Install button (shown when installer asset found)
            Button {
                id: installBtn
                visible: updateSection.installerUrl.length > 0 && !updateSection.downloading
                         && updateSection.downloadedPath.length === 0
                text: "Download & Install " + updateSection.latestVersion
                highlighted: true
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    updateSection.downloading = true
                    updateSection.downloadPct = 0
                    var destPath = selfUpdater.tempDir() + "/" + updateSection.installerName
                    appUpdateChecker.downloadAsset(updateSection.installerUrl, destPath)
                }
            }

            // Fallback: link to GitHub releases if no installer asset
            Label {
                id: fallbackLink
                visible: updateSection.latestVersion.length > 0
                         && updateSection.installerUrl.length === 0
                         && !updateSection.downloading
                text: "<a href=\"" + updateSection.htmlUrl + "\" style=\"color:#2196F3;\">Download " + updateSection.latestVersion + " from GitHub</a>"
                font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
                onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                property string htmlUrl: ""
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.NoButton
                }
            }

            // Progress bar during download
            ColumnLayout {
                visible: updateSection.downloading
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                Label {
                    text: "Downloading... " + updateSection.downloadPct + "%"
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignHCenter
                }
                ProgressBar {
                    from: 0; to: 100
                    value: updateSection.downloadPct
                    Layout.preferredWidth: 300
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            // Launch button (shown after download completes)
            Button {
                visible: updateSection.downloadedPath.length > 0
                text: "Install Now"
                highlighted: true
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    selfUpdater.launchInstallerAndQuit(updateSection.downloadedPath)
                }
            }

            Connections {
                target: appUpdateChecker
                function onReleaseFound(info) {
                    updateSection.updateStatus = "New version available: " + info.versionFormatted
                    updateSection.latestVersion = info.versionFormatted

                    // Look for installer asset
                    var assets = info.assets
                    var installer = updateSection.findInstallerAsset(assets)
                    if (installer) {
                        updateSection.installerUrl = installer.downloadUrl
                        updateSection.installerName = installer.name
                    } else {
                        // No installer asset — fall back to GitHub link
                        updateSection.installerUrl = ""
                        fallbackLink.htmlUrl = info.htmlUrl
                    }
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
                function onDownloadProgress(percent) {
                    if (updateSection.downloading)
                        updateSection.downloadPct = percent
                }
                function onDownloadComplete(filePath) {
                    updateSection.downloading = false
                    updateSection.downloadedPath = filePath
                    updateSection.updateStatus = "Download complete! Click Install Now to update."
                }
                function onDownloadError(message) {
                    updateSection.downloading = false
                    updateSection.updateStatus = "Error downloading: " + message
                }
            }

            Connections {
                target: selfUpdater
                function onUpdateError(message) {
                    updateSection.updateStatus = "Error: " + message
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
