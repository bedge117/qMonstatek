import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: view

    property var logEntries: []

    // Hidden helper for clipboard copy
    TextEdit {
        id: clipHelper
        visible: false
    }

    Connections {
        target: m1device
        function onCliResponseReceived(response) {
            appendOutput("< " + response.trim())
        }
        function onEspUartSnoopReceived(output) {
            appendOutput("\n=== ESP32 Boot Output (" + output.length + " bytes) ===")
            appendOutput(output)
            appendOutput("=== End ESP32 Boot Output ===\n")
            snoopBtn.enabled = true
        }
        function onErrorOccurred(message) {
            appendOutput("[ERROR] " + message)
        }
        function onM1LogReceived(line) {
            appLog.append("[M1] " + line)
        }
    }

    // Capture app log lines for the debug log tab
    Connections {
        target: appLog
        function onLineAppended(line) {
            if (tabBar.currentIndex === 1) {
                // Auto-scroll only when viewing the log tab
                logScrollTimer.start()
            }
        }
    }

    Timer {
        id: logScrollTimer
        interval: 50
        repeat: false
        onTriggered: {
            debugLogView.positionViewAtEnd()
        }
    }

    function appendOutput(text) {
        outputArea.text += text + "\n"
        // Auto-scroll to bottom
        Qt.callLater(function() {
            outputArea.cursorPosition = outputArea.length
        })
    }

    function quickCmd(cmd) {
        cmdInput.text = cmd
        sendCommand()
    }

    // Put a catalog command into the input field, ready to edit + Enter
    function pickCommand(cmd) {
        cmdInput.text = cmd
        cmdInput.forceActiveFocus()
        cmdInput.cursorPosition = cmdInput.text.length
    }

    // Tab-completion: cycle through catalog commands that start with whatever
    // the user last typed (reset by onTextEdited).
    property string _tabBase: ""
    property int _tabIdx: -1
    function tabComplete() {
        var base = view._tabBase.toLowerCase()
        var matches = []
        for (var i = 0; i < view.allCommands.length; i++) {
            if (view.allCommands[i].toLowerCase().indexOf(base) === 0)
                matches.push(view.allCommands[i])
        }
        if (matches.length === 0) return
        view._tabIdx = (view._tabIdx + 1) % matches.length
        cmdInput.text = matches[view._tabIdx]
        cmdInput.cursorPosition = cmdInput.text.length
    }

    // ── Command catalog: drives the ▾ picker and tab-completion.
    // { h: "Header" } starts a group; { t: label, c: command } is an entry. ──
    readonly property var cmdCatalog: [
        { h: "Help" },
        { t: "Show command help",            c: "mtest" },
        { h: "LED" },
        { t: "Off / stop",                   c: "mtest 21 0" },
        { t: "Red (half)",                   c: "mtest 22 128" },
        { t: "Green (half)",                 c: "mtest 23 128" },
        { t: "Blue (half)",                  c: "mtest 24 128" },
        { t: "Red (full)",                   c: "mtest 22 255" },
        { t: "Green (full)",                 c: "mtest 23 255" },
        { t: "Blue (full)",                  c: "mtest 24 255" },
        { t: "RGB blink slow",               c: "mtest 20 7 128 2000" },
        { t: "RGB blink fast",               c: "mtest 20 7 128 500" },
        { t: "Red blink",                    c: "mtest 20 1 128 1000" },
        { t: "Green blink",                  c: "mtest 20 2 128 1000" },
        { t: "Blue blink",                   c: "mtest 20 4 128 1000" },
        { h: "Display / LCD" },
        { t: "Backlight off",                c: "mtest 30 0" },
        { t: "Backlight 25%",                c: "mtest 30 64" },
        { t: "Backlight 50%",                c: "mtest 30 128" },
        { t: "Backlight 100%",               c: "mtest 30 255" },
        { t: "Clear display",                c: "mtest 32 0" },
        { t: "Re-init display",              c: "mtest 35 0" },
        { t: "Power save on",                c: "mtest 31 1" },
        { t: "Power save off",               c: "mtest 31 0" },
        { t: "Set contrast (edit value)",    c: "mtest 33 128" },
        { t: "Set reg ratio (edit 0-7)",     c: "mtest 34 4" },
        { h: "Buzzer" },
        { t: "Beep",                         c: "mtest 1 1000 200" },
        { t: "Long tone",                    c: "mtest 1 800 1000" },
        { h: "GPIO" },
        { t: "Ext 3V3 on",                   c: "mtest 80 1" },
        { t: "Ext 3V3 off",                  c: "mtest 80 0" },
        { t: "Ext 5V on",                    c: "mtest 81 1" },
        { t: "Ext 5V off",                   c: "mtest 81 0" },
        { h: "Sub-GHz" },
        { t: "Init 315 MHz",                 c: "mtest 60 315" },
        { t: "Init 433 MHz",                 c: "mtest 60 433" },
        { t: "Init 915 MHz",                 c: "mtest 60 915" },
        { t: "RX mode ch0",                  c: "mtest 63 0" },
        { t: "CW TX ch0",                    c: "mtest 61 0" },
        { t: "CW TX off",                    c: "mtest 61 256" },
        { t: "TX power 20",                  c: "mtest 62 20" },
        { t: "TX power 127 (max)",           c: "mtest 62 127" },
        { t: "Frontend 315",                 c: "mtest 64 0" },
        { t: "Frontend 433",                 c: "mtest 64 1" },
        { t: "Frontend 915",                 c: "mtest 64 2" },
        { t: "Frontend none",                c: "mtest 64 3" },
        { t: "Get RSSI",                     c: "mtest 68 0" },
        { t: "Get state",                    c: "mtest 69 0" },
        { h: "Infrared" },
        { t: "NEC addr0 cmd0",               c: "mtest 40 2 0 0 0" },
        { t: "NEC addr0 cmd1",               c: "mtest 40 2 0 1 0" },
        { t: "RC5 addr0 cmd0",               c: "mtest 40 10 0 0 0" },
        { t: "Samsung addr7 cmd2",           c: "mtest 40 6 7 2 0" },
        { h: "SD Card" },
        { t: "List /",                       c: "mtest 19 /" },
        { t: "List /subghz",                 c: "mtest 19 /subghz" },
        { t: "List /infrared",               c: "mtest 19 /infrared" },
        { t: "List /nfc",                    c: "mtest 19 /nfc" },
        { t: "List /rfid",                   c: "mtest 19 /rfid" },
        { t: "List /badusb",                 c: "mtest 19 /badusb" },
        { t: "Format SD",                    c: "mtest 18 0" },
        { h: "Power" },
        { t: "Battery info",                 c: "mtest 59 0" },
        { t: "Charger dump (BQ25896)",       c: "mtest 52 bc" },
        { t: "USB-PD dump (FUSB302)",        c: "mtest 52 pd" },
        { t: "Reboot menu (on-device)",      c: "mtest 51 0" },
        { t: "Power off (CLI)",              c: "mtest 50 0" },
        { h: "ESP32" },
        { t: "Init ESP32",                   c: "mtest 70 0" },
        { t: "Reset ESP32",                  c: "mtest 78 0" },
        { t: "Deinit (for flash)",           c: "mtest 79 0" },
        { t: "Ping link",                    c: "mtest 72 0" },
        { t: "Scan APs",                     c: "mtest 71 0" },
        { h: "WiFi (init ESP32 first)" },
        { t: "Monitor start (channel hop)",  c: "mtest 73 0" },
        { t: "Monitor stats + sample",       c: "mtest 74 0" },
        { t: "Monitor stop",                 c: "mtest 75 0" },
        { t: "Captive start (SSID M1-Test)", c: "mtest 76 M1-Test" },
        { t: "Captive show creds",           c: "mtest 77 0" },
        { t: "Captive diag",                 c: "mtest 77 2" },
        { t: "Captive stop",                 c: "mtest 77 1" }
    ]

    readonly property var allCommands: {
        var a = []
        for (var i = 0; i < cmdCatalog.length; i++)
            if (cmdCatalog[i].c !== undefined) a.push(cmdCatalog[i].c)
        return a
    }

    function sendCommand() {
        var cmd = cmdInput.text.trim()
        if (cmd.length === 0) return

        appendOutput("> " + cmd)

        if (m1device.connected) {
            m1device.sendCliCommand(cmd)
        } else {
            appendOutput("[NOT CONNECTED]")
        }

        cmdInput.text = ""
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        Label {
            text: "Debug Terminal"
            font.pixelSize: 24
            font.bold: true
        }

        // Tab bar: CLI Terminal | Debug Log
        TabBar {
            id: tabBar
            Layout.fillWidth: true

            TabButton { text: "CLI Terminal" }
            TabButton { text: "Debug Log" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // ── Tab 0: CLI Terminal ──
            ColumnLayout {
                spacing: 8

                // Output area
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#1a1a1a"
                    radius: 4
                    border.color: Material.dividerColor

                    ScrollView {
                        id: outputScroll
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true

                        TextArea {
                            id: outputArea
                            readOnly: true
                            selectByMouse: true
                            font.family: "Consolas"
                            font.pixelSize: 12
                            color: "#00FF00"
                            wrapMode: TextEdit.Wrap
                            background: null
                            text: "M1 CLI Terminal\nType a command and press Enter (Tab to complete), or pick one from the ▾ list.\n\n"
                        }
                    }
                }

                // ── Command input (free text + catalog dropdown + Tab complete) ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: "cli>"
                        font.family: "Consolas"
                        font.pixelSize: 13
                        color: Material.accent
                    }

                    TextField {
                        id: cmdInput
                        Layout.fillWidth: true
                        font.family: "Consolas"
                        font.pixelSize: 13
                        placeholderText: "Type a command (Tab to complete), or pick from ▾"
                        enabled: m1device.connected
                        onAccepted: sendCommand()
                        onTextEdited: { view._tabBase = text; view._tabIdx = -1 }
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Tab) {
                                event.accepted = true
                                view.tabComplete()
                            }
                        }
                    }

                    // Categorized command picker — fills the field so params stay editable
                    Button {
                        text: "▾"
                        font.pixelSize: 15
                        Layout.preferredWidth: 40
                        enabled: m1device.connected
                        onClicked: cmdMenu.popup()

                        Menu {
                            id: cmdMenu
                            width: 340
                            Repeater {
                                model: view.cmdCatalog
                                MenuItem {
                                    text: modelData.h !== undefined
                                          ? "——  " + modelData.h + "  ——"
                                          : "     " + modelData.t
                                    enabled: modelData.c !== undefined
                                    font.bold: modelData.h !== undefined
                                    font.pixelSize: 12
                                    onTriggered: if (modelData.c !== undefined) view.pickCommand(modelData.c)
                                }
                            }
                        }
                    }

                    Button {
                        text: "Send"
                        enabled: m1device.connected && cmdInput.text.trim().length > 0
                        onClicked: sendCommand()
                    }

                    Button {
                        text: "Copy"
                        flat: true
                        onClicked: {
                            outputArea.selectAll()
                            outputArea.copy()
                            outputArea.deselect()
                        }
                    }

                    Button {
                        text: "Clear"
                        flat: true
                        onClicked: {
                            outputArea.text = ""
                        }
                    }
                }

                // ── Quick actions (one-click; also available in the ▾ list) ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: "Quick:"
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }

                    Button {
                        id: snoopBtn
                        text: "Boot Snoop (~3s)"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        onClicked: {
                            snoopBtn.enabled = false
                            appendOutput("> [ESP32 UART Snoop] Capturing boot output (~3s)...")
                            m1device.sendEspUartSnoop()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // ── Power menu (real RPC actions + on-device CLI variants) ──
                    Button {
                        text: "Power ▾"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        Material.foreground: "#FFC107"
                        onClicked: powerMenu.popup()

                        Menu {
                            id: powerMenu
                            MenuItem {
                                text: "Reboot"
                                onTriggered: {
                                    appendOutput("> [Power] Reboot — device will restart")
                                    m1device.reboot()
                                }
                            }
                            MenuItem {
                                text: "Power off"
                                onTriggered: {
                                    appendOutput("> [Power] Power off")
                                    m1device.shutdown()
                                }
                            }
                            MenuSeparator {}
                            MenuItem {
                                text: "Reboot ESP32"
                                onTriggered: quickCmd("mtest 78 0")
                            }
                            MenuItem {
                                text: "Reboot menu (on-device)"
                                onTriggered: quickCmd("mtest 51 0")
                            }
                            MenuSeparator {}
                            MenuItem {
                                text: "Enter DFU mode"
                                onTriggered: {
                                    appendOutput("> [Power] Entering DFU mode")
                                    m1device.enterDfu()
                                }
                            }
                        }
                    }
                }
            }

            // ── Tab 1: Debug Log (app-level qDebug output) ──
            ColumnLayout {
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#1a1a1a"
                    radius: 4
                    border.color: Material.dividerColor

                    ListView {
                        id: debugLogView
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        model: appLog

                        delegate: Text {
                            width: debugLogView.width
                            text: model.message
                            font.family: "Consolas"
                            font.pixelSize: 11
                            color: {
                                if (model.message.startsWith("[ERR]") || model.message.startsWith("[FTL]"))
                                    return "#F44336"
                                if (model.message.startsWith("[WRN]"))
                                    return "#FFC107"
                                if (model.message.startsWith("[INF]"))
                                    return "#90CAF9"
                                // M1 firmware log levels: [M1] ... [E], [W], [I], [D], [T]
                                if (model.message.startsWith("[M1]")) {
                                    if (model.message.indexOf("[E]") > 0)
                                        return "#F44336"
                                    if (model.message.indexOf("[W]") > 0)
                                        return "#FFC107"
                                    if (model.message.indexOf("[I]") > 0)
                                        return "#4FC3F7"
                                    return "#81C784"  // debug/trace = green
                                }
                                return "#AAAAAA"
                            }
                            wrapMode: Text.Wrap
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Button {
                        text: "Copy All"
                        flat: true
                        onClicked: {
                            var allText = appLog.fullText()
                            clipHelper.text = allText
                            clipHelper.selectAll()
                            clipHelper.copy()
                            clipHelper.deselect()
                        }
                    }

                    Button {
                        text: "Clear Log"
                        flat: true
                        onClicked: appLog.clear()
                    }

                    Button {
                        text: "Scroll to Bottom"
                        flat: true
                        onClicked: debugLogView.positionViewAtEnd()
                    }

                    Item { Layout.fillWidth: true }

                    Label {
                        text: appLog.count + " lines"
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }
                }

                // Opt-in log capture to file (off by default). Lets devs save
                // logs without a firmware/code change, to a path of their choice.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Switch {
                        id: logToFileSwitch
                        text: "Save log to file"
                        checked: m1device.logToFile
                        onToggled: m1device.logToFile = checked
                    }

                    TextField {
                        Layout.fillWidth: true
                        readOnly: true
                        text: m1device.logFilePath
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }

                    Button {
                        text: "Browse…"
                        flat: true
                        onClicked: {
                            var f = uiSettings.dialogFolder("logSave")
                            if (f != "") logFileDialog.currentFolder = f
                            logFileDialog.open()
                        }
                    }
                }

                // Device-side verbosity. OFF disables streamed device logs so the
                // USB control link remains available for normal operation; ON raises
                // the device to INFO for a focused capture.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Switch {
                        id: deviceVerboseSwitch
                        text: "Verbose device logging (UART)"
                        enabled: m1device.connected
                        checked: m1device.deviceLogVerbose
                        onToggled: m1device.deviceLogVerbose = checked
                    }

                    Label {
                        Layout.fillWidth: true
                        text: m1device.deviceLogVerbose
                              ? "Device streaming INFO logs — turn off when done"
                              : "Device log streaming off"
                        font.pixelSize: 11
                        color: m1device.deviceLogVerbose ? "#F44336" : Material.hintTextColor
                    }
                }
            }
        }
    }

    FileDialog {
        id: logFileDialog
        title: "Save M1 Log As"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "log"
        Component.onCompleted: {
            var f = uiSettings.dialogFolder("logSave")
            if (f != "") currentFolder = f
        }
        onAccepted: {
            uiSettings.setDialogFolder("logSave", currentFolder)
            m1device.logFilePath = selectedFile
        }
    }
}
