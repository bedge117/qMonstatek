import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Item {
    id: view

    ListModel {
        id: repoModel
        ListElement {
            url: "bedge117/M1"
            label: "bedge117/M1 (C3 Enhanced)"
            isDefault: true
            status: ""
            checking: false
            releaseUrl: ""
            assetUrl: ""
            assetName: ""
        }
        ListElement {
            url: "sincere360/M1_SiN360"
            label: "sincere360/M1_SiN360"
            isDefault: false
            status: ""
            checking: false
            releaseUrl: ""
            assetUrl: ""
            assetName: ""
        }
        ListElement {
            url: "VintageVolts/M1_VintageVolts"
            label: "VintageVolts/M1_VintageVolts"
            isDefault: false
            status: ""
            checking: false
            releaseUrl: ""
            assetUrl: ""
            assetName: ""
        }
        ListElement {
            url: "hapaxx11/M1"
            label: "hapaxx11/M1 (Hapax)"
            isDefault: false
            status: ""
            checking: false
            releaseUrl: ""
            assetUrl: ""
            assetName: ""
        }
        ListElement {
            url: "dagnazty/M1_T-1000"
            label: "dagnazty/M1_T-1000"
            isDefault: false
            status: ""
            checking: false
            releaseUrl: ""
            assetUrl: ""
            assetName: ""
        }
        ListElement {
            url: "RogueMaster/M1"
            label: "RogueMaster/M1"
            isDefault: false
            status: ""
            checking: false
            releaseUrl: ""
            assetUrl: ""
            assetName: ""
        }
        ListElement {
            url: "Monstatek/M1"
            label: "Monstatek/M1 (Official)"
            isDefault: false
            status: ""
            checking: false
            releaseUrl: ""
            assetUrl: ""
            assetName: ""
        }
    }

    ButtonGroup { id: repoGroup }

    // Pick the M1 firmware .bin from a release's assets: prefer the CRC-injected
    // *_wCRC.bin, then any .bin that isn't an ESP/factory image.
    function pickM1Asset(assets) {
        if (!assets) return null
        var i, n
        for (i = 0; i < assets.length; i++) {
            n = (assets[i].name || "").toLowerCase()
            if (n.indexOf("wcrc") >= 0 && n.indexOf(".bin") >= 0 &&
                n.indexOf("esp") < 0 && n.indexOf("factory") < 0)
                return assets[i]
        }
        for (i = 0; i < assets.length; i++) {
            n = (assets[i].name || "").toLowerCase()
            if (n.indexOf(".bin") >= 0 && n.indexOf("esp") < 0 && n.indexOf("factory") < 0)
                return assets[i]
        }
        return null
    }

    function checkLatest(index) {
        repoModel.setProperty(index, "checking", true)
        repoModel.setProperty(index, "status", "Checking...")
        repoModel.setProperty(index, "releaseUrl", "")
        repoModel.setProperty(index, "assetUrl", "")
        repoModel.setProperty(index, "assetName", "")

        var repo = repoModel.get(index).url
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                repoModel.setProperty(index, "checking", false)
                if (xhr.status === 200) {
                    try {
                        var json = JSON.parse(xhr.responseText)
                        var dateStr = json.published_at ? json.published_at.substring(0, 10) : ""
                        var result = "Latest: " + json.tag_name
                        if (dateStr.length > 0)
                            result += "  (" + dateStr + ")"
                        repoModel.setProperty(index, "status", result)
                        repoModel.setProperty(index, "releaseUrl",
                            json.html_url || ("https://github.com/" + repo + "/releases/tag/" + json.tag_name))
                        var asset = view.pickM1Asset(json.assets)
                        if (asset) {
                            repoModel.setProperty(index, "assetUrl", asset.browser_download_url || "")
                            repoModel.setProperty(index, "assetName", asset.name || "")
                        }
                    } catch (e) {
                        repoModel.setProperty(index, "status", "Error parsing response")
                    }
                } else if (xhr.status === 404) {
                    repoModel.setProperty(index, "status", "No release candidates found")
                } else {
                    repoModel.setProperty(index, "status", "Error checking repository (HTTP " + xhr.status + ")")
                }
            }
        }
        xhr.open("GET", "https://api.github.com/repos/" + repo + "/releases/latest")
        xhr.setRequestHeader("User-Agent", "qMonstatek/1.0")
        xhr.setRequestHeader("Accept", "application/vnd.github.v3+json")
        xhr.send()
    }

    // ── ESP32 firmware repo (independent, persisted via esp32Checker) ──
    property string espStatus: ""
    property bool   espChecking: false
    property string espReleaseUrl: ""
    property string espAssetUrl: ""
    property string espAssetName: ""

    function pickEspAsset(assets) {
        if (!assets) return null
        var i, n
        for (i = 0; i < assets.length; i++) {
            n = (assets[i].name || "").toLowerCase()
            if (n.indexOf("factory") >= 0 && n.indexOf(".bin") >= 0 && n.indexOf(".md5") < 0)
                return assets[i]
        }
        for (i = 0; i < assets.length; i++) {
            n = (assets[i].name || "").toLowerCase()
            if (n.indexOf(".bin") >= 0 && n.indexOf(".md5") < 0)
                return assets[i]
        }
        return null
    }

    function checkLatestEsp() {
        if (esp32Checker.repoUrl.length === 0) { view.espStatus = "No ESP repo selected."; return }
        view.espChecking = true; view.espStatus = "Checking..."
        view.espReleaseUrl = ""; view.espAssetUrl = ""; view.espAssetName = ""
        var repo = esp32Checker.repoUrl
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                view.espChecking = false
                if (xhr.status === 200) {
                    try {
                        var json = JSON.parse(xhr.responseText)
                        var d = json.published_at ? json.published_at.substring(0, 10) : ""
                        view.espStatus = "Latest: " + json.tag_name + (d.length > 0 ? "  (" + d + ")" : "")
                        view.espReleaseUrl = json.html_url || ("https://github.com/" + repo + "/releases/tag/" + json.tag_name)
                        var a = view.pickEspAsset(json.assets)
                        if (a) { view.espAssetUrl = a.browser_download_url || ""; view.espAssetName = a.name || "" }
                    } catch (e) { view.espStatus = "Error parsing response" }
                } else if (xhr.status === 404) {
                    view.espStatus = "No release candidates found"
                } else {
                    view.espStatus = "Error checking repository (HTTP " + xhr.status + ")"
                }
            }
        }
        xhr.open("GET", "https://api.github.com/repos/" + repo + "/releases/latest")
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
                text: "Settings"
                font.pixelSize: 24
                font.bold: true
                Layout.topMargin: 24
                Layout.leftMargin: 24
            }

            // Firmware Update Repositories
            GroupBox {
                title: "Firmware Update Repositories"
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4

                    Label {
                        text: "Select which repository to check for firmware updates. " +
                              "Use 'Check Latest' to see the most recent release in each repo. " +
                              "Only the selected repo is used by the Firmware Update page."
                        font.pixelSize: 11
                        color: Material.hintTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Layout.bottomMargin: 8
                    }

                    Repeater {
                        model: repoModel
                        delegate: ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                spacing: 4

                                RadioButton {
                                    ButtonGroup.group: repoGroup
                                    text: model.label + (model.isDefault ? "  [Default]" : "")
                                    font.pixelSize: 13
                                    Component.onCompleted: checked = (githubChecker.repoUrl === model.url)
                                    onClicked: githubChecker.repoUrl = model.url
                                }

                                Item { Layout.fillWidth: true }

                                Button {
                                    text: model.checking ? "Checking..." : "Check Latest"
                                    font.pixelSize: 11
                                    flat: true
                                    enabled: !model.checking
                                    onClicked: view.checkLatest(index)
                                }
                            }

                            Label {
                                visible: model.status.length > 0
                                text: model.status
                                font.pixelSize: 11
                                color: {
                                    if (model.status.indexOf("Latest:") === 0) return "#4CAF50"
                                    if (model.status === "Checking...") return Material.hintTextColor
                                    if (model.status.indexOf("No release") === 0) return "#FF9800"
                                    return "#F44336"
                                }
                                leftPadding: 48
                            }

                            // Release-notes link + direct download, shown once a
                            // release is found (same hyperlink scheme as elsewhere).
                            RowLayout {
                                visible: model.releaseUrl.length > 0
                                Layout.leftMargin: 48
                                Layout.bottomMargin: 4
                                spacing: 16

                                Label {
                                    text: "<a href='notes'>Release notes</a>"
                                    textFormat: Text.RichText
                                    font.pixelSize: 11
                                    linkColor: "#8FCBFF"
                                    onLinkActivated: Qt.openUrlExternally(model.releaseUrl)
                                    MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                                }
                                Button {
                                    text: "Download"
                                    font.pixelSize: 11
                                    flat: true
                                    enabled: model.assetUrl.length > 0 || model.releaseUrl.length > 0
                                    ToolTip.visible: hovered
                                    ToolTip.text: model.assetName.length > 0
                                                  ? "Download " + model.assetName + " in your browser"
                                                  : "Open the release page to download"
                                    onClicked: Qt.openUrlExternally(
                                        model.assetUrl.length > 0 ? model.assetUrl : model.releaseUrl)
                                }
                            }
                        }
                    }

                    // Custom repository option
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        RowLayout {
                            spacing: 4

                            RadioButton {
                                id: customRadio
                                ButtonGroup.group: repoGroup
                                text: "Custom:"
                                font.pixelSize: 13
                                Component.onCompleted: {
                                    // Check if saved repo doesn't match any built-in
                                    var saved = githubChecker.repoUrl
                                    var isBuiltIn = false
                                    for (var i = 0; i < repoModel.count; i++) {
                                        if (repoModel.get(i).url === saved) {
                                            isBuiltIn = true
                                            break
                                        }
                                    }
                                    if (!isBuiltIn) {
                                        checked = true
                                        customRepoField.text = saved
                                    }
                                }
                                onClicked: {
                                    if (customRepoField.text.length > 0)
                                        githubChecker.repoUrl = customRepoField.text
                                }
                            }

                            TextField {
                                id: customRepoField
                                placeholderText: "owner/repo"
                                font.pixelSize: 13
                                Layout.fillWidth: true
                                onTextEdited: {
                                    if (customRadio.checked && text.length > 0)
                                        githubChecker.repoUrl = text
                                }
                                onAccepted: {
                                    customRadio.checked = true
                                    if (text.length > 0)
                                        githubChecker.repoUrl = text
                                }
                            }

                            Button {
                                id: customCheckBtn
                                property bool customChecking: false
                                text: customChecking ? "Checking..." : "Check Latest"
                                font.pixelSize: 11
                                flat: true
                                enabled: !customChecking && customRepoField.text.length > 0
                                onClicked: {
                                    customCheckBtn.customChecking = true
                                    customStatus.text = "Checking..."
                                    customStatus.color = Material.hintTextColor

                                    var repo = customRepoField.text
                                    var xhr = new XMLHttpRequest()
                                    xhr.onreadystatechange = function() {
                                        if (xhr.readyState === XMLHttpRequest.DONE) {
                                            customCheckBtn.customChecking = false
                                            if (xhr.status === 200) {
                                                try {
                                                    var json = JSON.parse(xhr.responseText)
                                                    var dateStr = json.published_at ? json.published_at.substring(0, 10) : ""
                                                    var result = "Latest: " + json.tag_name
                                                    if (dateStr.length > 0)
                                                        result += "  (" + dateStr + ")"
                                                    customStatus.text = result
                                                    customStatus.color = "#4CAF50"
                                                } catch (e) {
                                                    customStatus.text = "Error parsing response"
                                                    customStatus.color = "#F44336"
                                                }
                                            } else if (xhr.status === 404) {
                                                customStatus.text = "No release candidates found"
                                                customStatus.color = "#FF9800"
                                            } else {
                                                customStatus.text = "Error checking repository (HTTP " + xhr.status + ")"
                                                customStatus.color = "#F44336"
                                            }
                                        }
                                    }
                                    xhr.open("GET", "https://api.github.com/repos/" + repo + "/releases/latest")
                                    xhr.setRequestHeader("User-Agent", "qMonstatek/1.0")
                                    xhr.setRequestHeader("Accept", "application/vnd.github.v3+json")
                                    xhr.send()
                                }
                            }
                        }

                        Label {
                            id: customStatus
                            visible: text.length > 0
                            text: ""
                            font.pixelSize: 11
                            leftPadding: 48
                            Layout.bottomMargin: 4
                        }
                    }
                }
            }

            // ESP32 Firmware Repository (independent of the M1 repo above)
            GroupBox {
                title: "ESP32 Firmware Repository"
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4

                    Label {
                        text: "Where to fetch ESP32 (SPI brain) firmware — used by the ESP32 Update tab and " +
                              "the one-click Update All. This is separate from the M1 repo above."
                        font.pixelSize: 11
                        color: Material.hintTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        Layout.bottomMargin: 8
                    }

                    ButtonGroup { id: espRepoGroup }

                    RadioButton {
                        ButtonGroup.group: espRepoGroup
                        text: "bedge117/m1-esp32-brain (SPI brain)  [Default]"
                        font.pixelSize: 13
                        Component.onCompleted: checked = (esp32Checker.repoUrl === "bedge117/m1-esp32-brain")
                        onClicked: esp32Checker.repoUrl = "bedge117/m1-esp32-brain"
                    }

                    RowLayout {
                        spacing: 4
                        RadioButton {
                            id: espCustomRadio
                            ButtonGroup.group: espRepoGroup
                            text: "Custom:"
                            font.pixelSize: 13
                            Component.onCompleted: {
                                var r = esp32Checker.repoUrl
                                if (r.length > 0 && r !== "bedge117/m1-esp32-brain") {
                                    checked = true
                                    espCustomField.text = r
                                }
                            }
                            onClicked: { if (espCustomField.text.length > 0) esp32Checker.repoUrl = espCustomField.text }
                        }
                        TextField {
                            id: espCustomField
                            placeholderText: "owner/repo"
                            font.pixelSize: 13
                            Layout.fillWidth: true
                            onTextEdited: { if (espCustomRadio.checked && text.length > 0) esp32Checker.repoUrl = text }
                            onAccepted: { espCustomRadio.checked = true; if (text.length > 0) esp32Checker.repoUrl = text }
                        }
                    }

                    RadioButton {
                        ButtonGroup.group: espRepoGroup
                        text: "None — don't track ESP firmware"
                        font.pixelSize: 13
                        Component.onCompleted: checked = (esp32Checker.repoUrl.length === 0)
                        onClicked: esp32Checker.repoUrl = ""
                    }

                    RowLayout {
                        spacing: 8
                        Layout.topMargin: 4
                        Button {
                            text: view.espChecking ? "Checking..." : "Check Latest"
                            font.pixelSize: 11
                            flat: true
                            enabled: !view.espChecking && esp32Checker.repoUrl.length > 0
                            onClicked: view.checkLatestEsp()
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Label {
                        visible: view.espStatus.length > 0
                        text: view.espStatus
                        font.pixelSize: 11
                        color: {
                            if (view.espStatus.indexOf("Latest:") === 0) return "#4CAF50"
                            if (view.espStatus === "Checking...") return Material.hintTextColor
                            if (view.espStatus.indexOf("No release") === 0) return "#FF9800"
                            return "#F44336"
                        }
                        leftPadding: 24
                    }

                    RowLayout {
                        visible: view.espReleaseUrl.length > 0
                        Layout.leftMargin: 24
                        spacing: 16
                        Label {
                            text: "<a href='notes'>Release notes</a>"
                            textFormat: Text.RichText
                            font.pixelSize: 11
                            linkColor: "#8FCBFF"
                            onLinkActivated: Qt.openUrlExternally(view.espReleaseUrl)
                            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; cursorShape: Qt.PointingHandCursor }
                        }
                        Button {
                            text: "Download"
                            font.pixelSize: 11
                            flat: true
                            enabled: view.espAssetUrl.length > 0 || view.espReleaseUrl.length > 0
                            ToolTip.visible: hovered
                            ToolTip.text: view.espAssetName.length > 0
                                          ? "Download " + view.espAssetName + " in your browser"
                                          : "Open the release page to download"
                            onClicked: Qt.openUrlExternally(
                                view.espAssetUrl.length > 0 ? view.espAssetUrl : view.espReleaseUrl)
                        }
                    }
                }
            }

            // Screen Mirror Settings
            GroupBox {
                title: "Screen Mirror"
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    RowLayout {
                        Label { text: "Default FPS:" }
                        SpinBox {
                            id: defaultFps
                            from: 1; to: 15; value: 10
                        }
                    }

                    Label {
                        text: "Higher FPS uses more bandwidth. 10 FPS recommended."
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }
                }
            }

            // Connection Settings
            GroupBox {
                title: "Connection"
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 8

                    CheckBox {
                        id: autoConnectCheck
                        text: "Auto-connect when M1 device is detected"
                        checked: true
                    }

                    Label {
                        text: "When enabled, qMonstatek will automatically connect to " +
                              "the first M1 device detected on USB."
                        font.pixelSize: 11
                        color: Material.hintTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            // Theme
            GroupBox {
                title: "Appearance"
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    RowLayout {
                        Label { text: "Theme:" }

                        ButtonGroup { id: themeGroup }

                        RadioButton {
                            id: darkRadio
                            text: "Dark"
                            ButtonGroup.group: themeGroup
                            onClicked: uiSettings.theme = "dark"
                        }
                        RadioButton {
                            id: lightRadio
                            text: "Light"
                            ButtonGroup.group: themeGroup
                            onClicked: uiSettings.theme = "light"
                        }
                        RadioButton {
                            id: chromeRadio
                            text: "Chrome"
                            ButtonGroup.group: themeGroup
                            onClicked: uiSettings.theme = "chrome"
                        }
                        RadioButton {
                            id: hackerRadio
                            text: "Hacker"
                            ButtonGroup.group: themeGroup
                            onClicked: uiSettings.theme = "hacker"
                        }

                        // Reflect the persisted setting on load
                        Component.onCompleted: {
                            if (uiSettings.theme === "light")       lightRadio.checked = true
                            else if (uiSettings.theme === "chrome") chromeRadio.checked = true
                            else if (uiSettings.theme === "hacker") hackerRadio.checked = true
                            else                                    darkRadio.checked = true
                        }
                    }

                    // App accent color (persisted; drives Material.accent app-wide)
                    RowLayout {
                        spacing: 10
                        Label { text: "Accent color:" }
                        Repeater {
                            model: [
                                { key: "green",   col: "#2FBF71", label: "Emerald (default)" },
                                { key: "magenta", col: "#E24C82", label: "Monstatek magenta" },
                                { key: "indigo",  col: "#7C6CF0", label: "Indigo" },
                                { key: "amber",   col: "#F0A83A", label: "Amber" },
                                { key: "cyan",    col: "#2CB8C6", label: "Cyan" }
                            ]
                            delegate: Rectangle {
                                width: 26; height: 26; radius: 13
                                color: modelData.col
                                border.color: uiSettings.accent === modelData.key ? Material.foreground : "#88808080"
                                border.width: uiSettings.accent === modelData.key ? 3 : 1
                                ToolTip.visible: acHover.hovered
                                ToolTip.delay: 300
                                ToolTip.text: modelData.label
                                HoverHandler { id: acHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: uiSettings.accent = modelData.key
                                }
                            }
                        }
                    }

                    // M1 device-skin case colour (shown on Screen Mirror & Device Info)
                    RowLayout {
                        spacing: 10
                        Label { text: "M1 case color:" }
                        Repeater {
                            model: [
                                { key: "white",  col: "#FCFCFD",  label: "White" },
                                { key: "black",  col: "#202124",  label: "Black" },
                                { key: "clear",  col: "#80CBD2DC", label: "Clear" },
                                { key: "orange", col: "#F57C00",  label: "Orange" },
                                { key: "green",  col: "#43A047",  label: "Green" }
                            ]
                            delegate: Rectangle {
                                width: 26; height: 26; radius: 13
                                color: modelData.col
                                border.color: uiSettings.caseColor === modelData.key ? Material.accent : "#88808080"
                                border.width: uiSettings.caseColor === modelData.key ? 3 : 1
                                ToolTip.visible: swHover.hovered
                                ToolTip.delay: 300
                                ToolTip.text: modelData.label
                                HoverHandler { id: swHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: uiSettings.caseColor = modelData.key
                                }
                            }
                        }
                    }
                }
            }

            Item { height: 24 }
        }
    }
}
