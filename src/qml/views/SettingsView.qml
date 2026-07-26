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
        }
        ListElement {
            url: "sincere360/M1_SiN360"
            label: "sincere360/M1_SiN360"
            isDefault: false
            status: ""
            checking: false
        }
        ListElement {
            url: "VintageVolts/M1_VintageVolts"
            label: "VintageVolts/M1_VintageVolts"
            isDefault: false
            status: ""
            checking: false
        }
        ListElement {
            url: "hapaxx11/M1"
            label: "hapaxx11/M1 (Hapax)"
            isDefault: false
            status: ""
            checking: false
        }
        ListElement {
            url: "dagnazty/M1_T-1000"
            label: "dagnazty/M1_T-1000"
            isDefault: false
            status: ""
            checking: false
        }
        ListElement {
            url: "RogueMaster/M1"
            label: "RogueMaster/M1"
            isDefault: false
            status: ""
            checking: false
        }
        ListElement {
            url: "Monstatek/M1"
            label: "Monstatek/M1 (Official)"
            isDefault: false
            status: ""
            checking: false
        }
    }

    ButtonGroup { id: repoGroup }

    function checkLatest(index) {
        repoModel.setProperty(index, "checking", true)
        repoModel.setProperty(index, "status", "Checking...")

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
                                Layout.bottomMargin: 4
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

                        // Reflect the persisted setting on load
                        Component.onCompleted: {
                            if (uiSettings.theme === "light") lightRadio.checked = true
                            else darkRadio.checked = true
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
