import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: view

    property bool isActive: contentStack.currentIndex === viewIndex("esp32Update")
    property int flashAddr: 0x00000
    property bool updating: false
    property int updatePercent: 0
    property string espPhase: ""

    // GitHub download state
    property string downloadedFilePath: ""
    property string downloadedFileName: ""
    property bool downloading: false
    property int downloadPercent: 0
    property var releaseInfo: null
    property bool restoring: false
    property string restoreStatus: ""

    // Manual file selection state
    property string selectedFilePath: ""
    property string selectedFileName: ""

    // Set by whichever flow triggers the flash
    property string flashFilePath: ""
    property string flashFileName: ""

    Connections {
        target: m1device
        function onEspInfoReceived(version) {
            espVersionLabel.text = version
        }
        function onEspUpdateProgress(percent) {
            view.updatePercent = percent
        }
        function onEspUpdateStatus(status) {
            view.espPhase = status
        }
        function onEspUpdateComplete() {
            view.updating = false
            view.espPhase = ""
            espStatusLabel.text = "Success! ESP32 firmware flashed successfully!\n" +
                               "Reboot the M1 to start the new firmware."
            espStatusLabel.color = "#4CAF50"
            espStatusLabel.visible = true
        }
        function onEspUpdateError(message) {
            view.updating = false
            view.espPhase = ""
            espStatusLabel.text = "Error: " + message
            espStatusLabel.color = "#F44336"
            espStatusLabel.visible = true
        }
    }

    // ── GitHub signals for ESP32 downloads ──
    Connections {
        target: esp32Checker
        function onReleaseFound(info) {
            view.releaseInfo = info
        }
        function onNoUpdateAvailable(message) {
            ghStatusLabel.text = message
            ghStatusLabel.color = Material.hintTextColor
            ghStatusLabel.visible = true
        }
        function onCheckError(message) {
            ghStatusLabel.text = "GitHub error: " + message
            ghStatusLabel.color = "#F44336"
            ghStatusLabel.visible = true
        }
        function onDownloadProgress(percent) {
            view.downloadPercent = percent
        }
        function onDownloadComplete(filePath) {
            view.downloading = false
            view.downloadedFilePath = filePath
            var parts = filePath.split(/[/\\]/)
            var fname = parts[parts.length - 1]
            view.downloadedFileName = fname
            // Auto-select flash offset based on filename
            var nameLower = fname.toLowerCase()
            if (nameLower.indexOf("factory") >= 0) {
                factoryRadio.checked = true
                view.flashAddr = 0x00000
            } else {
                // esp-at.bin or any non-factory → App-Only
                appRadio.checked = true
                view.flashAddr = 0x60000
            }
            if (view.restoring) {
                view.restoring = false
                view.restoreStatus = "Stock firmware downloaded. Ready to flash."
            }
        }
        function onDownloadError(message) {
            view.downloading = false
            if (view.restoring) {
                view.restoring = false
                view.restoreStatus = "Download failed: " + message
            }
        }
    }

    function startRestore() {
        view.restoring = true
        view.restoreStatus = "Fetching v1.0.0 release..."
        view.releaseInfo = null
        view.downloadedFilePath = ""
        view.downloadedFileName = ""

        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var json = JSON.parse(xhr.responseText)
                        var assets = json.assets
                        // Find the factory .bin asset (prefer "factory" in name)
                        var factoryUrl = ""
                        var factoryName = ""
                        var fallbackUrl = ""
                        var fallbackName = ""
                        for (var i = 0; i < assets.length; i++) {
                            var name = assets[i].name
                            if (name.indexOf(".bin") >= 0) {
                                if (name.toLowerCase().indexOf("factory") >= 0) {
                                    factoryUrl = assets[i].browser_download_url
                                    factoryName = name
                                    break
                                }
                                if (fallbackUrl.length === 0) {
                                    fallbackUrl = assets[i].browser_download_url
                                    fallbackName = name
                                }
                            }
                        }
                        if (factoryUrl.length === 0) {
                            factoryUrl = fallbackUrl
                            factoryName = fallbackName
                        }
                        if (factoryUrl.length > 0) {
                            view.restoreStatus = "Downloading " + factoryName + "..."
                            view.downloading = true
                            view.downloadPercent = 0
                            esp32Checker.downloadAsset(factoryUrl, factoryName)
                        } else {
                            view.restoring = false
                            view.restoreStatus = "No .bin asset found in v1.0.0 release"
                        }
                    } catch (e) {
                        view.restoring = false
                        view.restoreStatus = "Error parsing release info"
                    }
                } else if (xhr.status === 404) {
                    view.restoring = false
                    view.restoreStatus = "v1.0.0 release not found"
                } else {
                    view.restoring = false
                    view.restoreStatus = "Error fetching release (HTTP " + xhr.status + ")"
                }
            }
        }
        xhr.open("GET", "https://api.github.com/repos/bedge117/esp32-at-monstatek-m1/releases/tags/v1.0.0")
        xhr.setRequestHeader("User-Agent", "qMonstatek/1.0")
        xhr.setRequestHeader("Accept", "application/vnd.github.v3+json")
        xhr.send()
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            width: view.width
            spacing: 16

            Label {
                text: "ESP32-C6 Firmware Update"
                font.pixelSize: 24
                font.bold: true
                Layout.topMargin: 24
                Layout.leftMargin: 24
            }

            Label {
                text: "Flash ESP32-C6 coprocessor firmware directly via the M1."
                color: Material.hintTextColor
                Layout.leftMargin: 24
            }

            // ESP32 status
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                RowLayout {
                    anchors.fill: parent
                    spacing: 12

                    Label { text: "ESP32 Status:"; font.bold: true }
                    Label {
                        text: m1device.esp32Ready ? "Ready" : "Not initialized"
                        color: m1device.esp32Ready ? "#4CAF50" : "#F44336"
                    }
                    Item { Layout.fillWidth: true }
                    Label { text: "Version:" }
                    Label {
                        id: espVersionLabel
                        text: m1device.esp32Version.length > 0 ? m1device.esp32Version : "Unknown"
                    }
                    Button {
                        text: "Initialize"
                        visible: !m1device.esp32Ready
                        enabled: m1device.connected && !view.updating
                        onClicked: m1device.initEsp32()
                    }
                    Button {
                        text: "Refresh"
                        enabled: m1device.connected
                        onClicked: {
                            m1device.requestDeviceInfo()
                            m1device.requestEspInfo()
                        }
                    }
                }
            }

            // Flash address selector
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label { text: "Flash Configuration"; font.bold: true }

                    ButtonGroup { id: imageTypeGroup }

                    RadioButton {
                        id: factoryRadio
                        text: "Factory Image — bootloader + partition table + app (0x00000)"
                        checked: true
                        ButtonGroup.group: imageTypeGroup
                        onCheckedChanged: if (checked) view.flashAddr = 0x00000
                    }

                    RadioButton {
                        id: appRadio
                        text: "App-Only — application partition only (0x60000)"
                        ButtonGroup.group: imageTypeGroup
                        onCheckedChanged: if (checked) view.flashAddr = 0x60000
                    }

                    Label {
                        text: factoryRadio.checked
                              ? "Factory image includes bootloader + partition table + app. " +
                                "Use for first-time flash or when changing partition layout."
                              : "App-only image is smaller and faster. " +
                                "Use only if bootloader and partition table are already correct."
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        color: Material.hintTextColor
                        Layout.fillWidth: true
                    }
                }
            }

            // Download from GitHub
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    Label { text: "Download from GitHub"; font.bold: true }

                    Label {
                        text: "Download ESP32-C6 firmware from bedge117/esp32-at-monstatek-m1"
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }

                    RowLayout {
                        spacing: 12

                        Button {
                            text: esp32Checker.checking ? "Checking..." : "Download Latest"
                            highlighted: true
                            enabled: !esp32Checker.checking && !view.downloading && !view.updating
                            onClicked: {
                                view.releaseInfo = null
                                view.downloadedFilePath = ""
                                view.downloadedFileName = ""
                                ghStatusLabel.visible = false
                                ghStatusLabel.color = Material.hintTextColor
                                esp32Checker.checkForUpdates(0, 0, 0, 0, 0)
                            }
                        }

                        Button {
                            text: view.restoring ? "Restoring..." : "Restore Stock (v1.0.0)"
                            enabled: !view.restoring && !view.downloading && !view.updating
                            onClicked: view.startRestore()
                        }

                        Label {
                            id: ghStatusLabel
                            visible: false
                            font.pixelSize: 12
                            color: Material.hintTextColor
                        }
                    }

                    // Restore status
                    Label {
                        visible: view.restoreStatus.length > 0
                        text: view.restoreStatus
                        font.pixelSize: 12
                        color: {
                            if (view.restoreStatus.indexOf("Ready") >= 0) return "#4CAF50"
                            if (view.restoreStatus.indexOf("Error") >= 0 ||
                                view.restoreStatus.indexOf("failed") >= 0 ||
                                view.restoreStatus.indexOf("not found") >= 0) return "#F44336"
                            return Material.hintTextColor
                        }
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // Download progress
                    ProgressBar {
                        visible: view.downloading
                        Layout.fillWidth: true
                        value: view.downloadPercent / 100.0
                    }

                    // ── Downloaded firmware: ready to flash ──
                    RowLayout {
                        visible: view.downloadedFileName.length > 0 && !view.downloading
                        spacing: 12

                        Label {
                            text: "Downloaded: " + view.downloadedFileName
                            font.pixelSize: 12
                            color: "#4CAF50"
                            Layout.fillWidth: true
                        }

                        Label {
                            text: "Target: 0x" + view.flashAddr.toString(16).toUpperCase().padStart(5, "0")
                                  + (factoryRadio.checked ? " (Factory)" : " (App-Only)")
                            font.family: "Courier New"
                            font.pixelSize: 12
                            color: Material.hintTextColor
                        }

                        Button {
                            text: "Flash ESP32"
                            highlighted: true
                            enabled: m1device.connected && !view.updating
                            onClicked: {
                                view.flashFilePath = view.downloadedFilePath
                                view.flashFileName = view.downloadedFileName
                                confirmDialog.open()
                            }
                        }
                    }
                }
            }

            // Release info card
            Pane {
                visible: view.releaseInfo !== null
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 2

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    Label {
                        text: view.releaseInfo ? view.releaseInfo.name : ""
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Label {
                        text: view.releaseInfo
                              ? "Version: " + view.releaseInfo.versionFormatted
                              : ""
                        color: Material.accent
                    }

                    Label {
                        text: view.releaseInfo ? view.releaseInfo.publishedAt : ""
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Material.dividerColor
                    }

                    Label {
                        text: "Assets"
                        font.bold: true
                    }

                    Repeater {
                        model: view.releaseInfo ? view.releaseInfo.assets : []
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
                                    view.downloadPercent = 0
                                    view.downloadedFilePath = ""
                                    view.downloadedFileName = ""
                                    esp32Checker.downloadAsset(modelData.downloadUrl, modelData.name)
                                }
                            }
                        }
                    }
                }
            }

            // ── Flash Firmware from File ──
            Pane {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    Label { text: "Flash Firmware from File"; font.bold: true }

                    RowLayout {
                        spacing: 12

                        Button {
                            text: "Select File..."
                            enabled: m1device.connected && !view.updating
                            onClicked: espFileDialog.open()
                        }

                        Label {
                            text: view.selectedFileName.length > 0
                                  ? view.selectedFileName
                                  : "No file selected"
                            color: view.selectedFileName.length > 0
                                   ? Material.foreground
                                   : Material.hintTextColor
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                        }
                    }

                    RowLayout {
                        spacing: 12

                        Button {
                            text: "Flash ESP32"
                            highlighted: true
                            enabled: m1device.connected && !view.updating
                                     && view.selectedFilePath.length > 0
                            onClicked: {
                                view.flashFilePath = view.selectedFilePath
                                view.flashFileName = view.selectedFileName
                                confirmDialog.open()
                            }
                        }

                        Label {
                            text: "Target: 0x" + view.flashAddr.toString(16).toUpperCase().padStart(5, "0")
                                  + (factoryRadio.checked ? " (Factory)" : " (App-Only)")
                            font.family: "Courier New"
                            font.pixelSize: 12
                            color: Material.hintTextColor
                        }
                    }
                }
            }

            // Progress (shared — only one flash at a time)
            Pane {
                visible: view.updating
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Material.elevation: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    Label {
                        text: "Flashing: " + view.flashFileName
                        font.bold: true
                    }

                    ProgressBar {
                        Layout.fillWidth: true
                        value: view.updatePercent / 100.0
                    }

                    Label {
                        text: view.espPhase.length > 0
                              ? view.espPhase + "  " + view.updatePercent + "%"
                              : "Flashing... " + view.updatePercent + "%"
                    }
                }
            }

            // Status
            Label {
                id: espStatusLabel
                visible: false
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
            }

            Item { height: 24 }
        }
    }

    FileDialog {
        id: espFileDialog
        title: "Select ESP32 Firmware Binary"
        nameFilters: ["Binary files (*.bin)", "All files (*)"]
        onAccepted: {
            var path = selectedFile.toString().replace("file:///", "")
            view.selectedFilePath = path
            var parts = path.split(/[/\\]/)
            view.selectedFileName = parts[parts.length - 1]
            espStatusLabel.visible = false
        }
    }

    Dialog {
        id: confirmDialog
        title: "Confirm ESP32 Firmware Flash"
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel

        ColumnLayout {
            spacing: 12

            Label {
                text: "Flash firmware directly to ESP32?"
                font.bold: true
            }
            Label {
                text: "File: " + view.flashFileName
            }
            Label {
                text: "Flash address: 0x" + view.flashAddr.toString(16).toUpperCase().padStart(5, "0")
                      + (factoryRadio.checked ? " (Factory Image)" : " (App-Only)")
            }
            Label {
                text: "This will connect to the ESP32 ROM bootloader, erase the\n" +
                      "target region, and write the firmware directly. The ESP32\n" +
                      "will be reset automatically when flashing completes."
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Material.hintTextColor
            }
        }

        onAccepted: {
            view.updating = true
            view.updatePercent = 0
            view.espPhase = ""
            espStatusLabel.text = ""
            espStatusLabel.color = Material.foreground
            espStatusLabel.visible = false
            m1device.startEspUpdate(view.flashFilePath, view.flashAddr)
        }
    }
}
