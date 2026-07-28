import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Item {
    id: view

    // Scrollable content region — sits ABOVE the pinned footer so the support
    // button is never overlapped, clipped, or pushed off-screen.
    ScrollView {
        id: aboutScroll
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            x: 24
            width: aboutScroll.availableWidth - 48
            // At least viewport-tall so the fillHeight spacers still center short
            // content; grows taller (and scrolls) when the Updates section expands
            // — otherwise the bottom items (incl. Buy me a coffee) get clipped.
            height: Math.max(implicitHeight, aboutScroll.availableHeight)
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

            // Find the platform-appropriate installer asset from release assets
            // Prefer .zip on all platforms (avoids MOTW on Windows, Gatekeeper
            // quarantine on macOS, and preserves executable bit on Linux)
            function findInstallerAsset(assets) {
                var os = Qt.platform.os
                var zipAsset = null
                var rawAsset = null
                for (var i = 0; i < assets.length; i++) {
                    var name = assets[i].name
                    if (os === "windows") {
                        var nl = name.toLowerCase()
                        if (nl.indexOf("windows") >= 0 && nl.indexOf(".zip") >= 0) return assets[i]
                        if (nl.indexOf("_setup") >= 0) {
                            if (nl.indexOf(".zip") >= 0) return assets[i]
                            if (nl.indexOf(".exe") >= 0) rawAsset = assets[i]
                        }
                    } else if (os === "osx") {
                        if (name.indexOf("macos") >= 0 && name.indexOf(".zip") >= 0) return assets[i]
                        if (name.indexOf(".dmg") >= 0) rawAsset = assets[i]
                    } else {
                        if (name.indexOf("linux") >= 0 && name.indexOf(".zip") >= 0) return assets[i]
                        if (name.indexOf(".AppImage") >= 0) rawAsset = assets[i]
                    }
                }
                return rawAsset
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
                text: "<a href=\"" + fallbackLink.htmlUrl + "\" style=\"color:#2196F3;\">Download " + updateSection.latestVersion + " from GitHub</a>"
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

            Item { Layout.fillHeight: true }
        }
    }

    // ── Pinned footer — ALWAYS visible at the bottom of the About page, no matter
    //    the window size or whether the Updates section above is expanded. The
    //    support button lives here so it can never be clipped or scrolled away. ──
    Rectangle {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        implicitHeight: footerCol.implicitHeight + 28
        color: "transparent"

        // hairline divider along the top edge of the footer
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Material.dividerColor
        }

        ColumnLayout {
            id: footerCol
            anchors.centerIn: parent
            spacing: 8

            Label {
                text: "Open Source — github.com/bedge117/qMonstatek"
                font.pixelSize: 12
                color: Material.hintTextColor
                Layout.alignment: Qt.AlignHCenter
            }

            // Support link — opens Buy Me a Coffee in the default browser. (The BMC
            // <script> embed is web-only; a native button + openUrlExternally is the
            // Qt equivalent.)
            Button {
                id: bmcButton
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 210
                implicitHeight: 46
                hoverEnabled: true
                background: Rectangle {
                    radius: 8
                    color: bmcButton.down ? "#E5C700" : "#FFDD00"
                    border.color: "#000000"
                    border.width: 1
                }
                contentItem: Text {
                    text: "☕  Buy me a coffee"
                    color: "#000000"
                    font.pixelSize: 16
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: Qt.openUrlExternally("https://www.buymeacoffee.com/edgehome")

                ToolTip.visible: hovered
                ToolTip.text: "buymeacoffee.com/edgehome"
            }
        }
    }
}
