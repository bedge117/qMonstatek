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

    // Send multiple commands with a short delay between each
    property var _cmdQueue: []
    Timer {
        id: cmdQueueTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (view._cmdQueue.length > 0) {
                var next = view._cmdQueue.shift()
                quickCmd(next)
                if (view._cmdQueue.length > 0)
                    cmdQueueTimer.start()
            }
        }
    }
    function quickCmdChain(cmds) {
        quickCmd(cmds[0])
        if (cmds.length > 1) {
            view._cmdQueue = cmds.slice(1)
            cmdQueueTimer.start()
        }
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
                            text: "M1 CLI Terminal\nType 'mtest' for help, or use the quick buttons below.\n\n"
                        }
                    }
                }

                // Command input
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
                        placeholderText: "Enter command..."
                        enabled: m1device.connected

                        onAccepted: sendCommand()

                        Keys.onUpPressed: {
                            // TODO: command history
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

                // Quick command dropdown menus (single row)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        text: "Quick:"
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }

                    // ── Help button ──
                    Button {
                        text: "Help"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        onClicked: quickCmd("mtest")
                    }

                    // ── LED menu ──
                    Button {
                        text: "LED \u25BE"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        onClicked: ledMenu.open()
                        Menu {
                            id: ledMenu
                            title: "LED Control"
                            MenuItem { text: "All Off (stop animation)"; onTriggered: quickCmdChain(["mtest 20 0 0 0", "mtest 21 0"]) }
                            MenuSeparator {}
                            MenuItem { text: "Red Solid";         onTriggered: quickCmdChain(["mtest 20 0 0 0", "mtest 22 128"]) }
                            MenuItem { text: "Green Solid";       onTriggered: quickCmdChain(["mtest 20 0 0 0", "mtest 23 128"]) }
                            MenuItem { text: "Blue Solid";        onTriggered: quickCmdChain(["mtest 20 0 0 0", "mtest 24 128"]) }
                            MenuItem { text: "Red Full";          onTriggered: quickCmdChain(["mtest 20 0 0 0", "mtest 22 255"]) }
                            MenuItem { text: "Green Full";        onTriggered: quickCmdChain(["mtest 20 0 0 0", "mtest 23 255"]) }
                            MenuItem { text: "Blue Full";         onTriggered: quickCmdChain(["mtest 20 0 0 0", "mtest 24 255"]) }
                            MenuSeparator {}
                            MenuItem { text: "RGB Blink (slow)";  onTriggered: quickCmd("mtest 20 7 128 2000") }
                            MenuItem { text: "RGB Blink (fast)";  onTriggered: quickCmd("mtest 20 7 128 500") }
                            MenuItem { text: "Red Blink";         onTriggered: quickCmd("mtest 20 1 128 1000") }
                            MenuItem { text: "Green Blink";       onTriggered: quickCmd("mtest 20 2 128 1000") }
                            MenuItem { text: "Blue Blink";        onTriggered: quickCmd("mtest 20 4 128 1000") }
                        }
                    }

                    // ── Display menu ──
                    Button {
                        text: "Display \u25BE"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        onClicked: displayMenu.open()
                        Menu {
                            id: displayMenu
                            MenuItem { text: "Backlight Off";     onTriggered: quickCmd("mtest 30 0") }
                            MenuItem { text: "Backlight 25%";     onTriggered: quickCmd("mtest 30 64") }
                            MenuItem { text: "Backlight 50%";     onTriggered: quickCmd("mtest 30 128") }
                            MenuItem { text: "Backlight 100%";    onTriggered: quickCmd("mtest 30 255") }
                            MenuSeparator {}
                            MenuItem { text: "Clear Display";     onTriggered: quickCmd("mtest 32 0") }
                            MenuItem { text: "Re-init Display";   onTriggered: quickCmd("mtest 35 0") }
                            MenuSeparator {}
                            MenuItem { text: "Buzzer Beep";       onTriggered: quickCmd("mtest 1 1000 200") }
                            MenuItem { text: "Buzzer Long";       onTriggered: quickCmd("mtest 1 800 1000") }
                        }
                    }

                    // ── GPIO menu ──
                    Button {
                        text: "GPIO \u25BE"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        onClicked: gpioMenu.open()
                        Menu {
                            id: gpioMenu
                            MenuItem { text: "Ext 3V3 On";   onTriggered: quickCmd("mtest 80 1") }
                            MenuItem { text: "Ext 3V3 Off";  onTriggered: quickCmd("mtest 80 0") }
                            MenuSeparator {}
                            MenuItem { text: "Ext 5V On";    onTriggered: quickCmd("mtest 81 1") }
                            MenuItem { text: "Ext 5V Off";   onTriggered: quickCmd("mtest 81 0") }
                        }
                    }

                    // ── Sub-GHz menu ──
                    Button {
                        text: "Sub-GHz \u25BE"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        onClicked: subghzMenu.open()
                        Menu {
                            id: subghzMenu
                            MenuItem { text: "Init 315 MHz";     onTriggered: quickCmd("mtest 60 315") }
                            MenuItem { text: "Init 433 MHz";     onTriggered: quickCmd("mtest 60 433") }
                            MenuItem { text: "Init 915 MHz";     onTriggered: quickCmd("mtest 60 915") }
                            MenuSeparator {}
                            MenuItem { text: "RX Mode Ch0";      onTriggered: quickCmd("mtest 63 0") }
                            MenuItem { text: "CW TX Ch0";        onTriggered: quickCmd("mtest 61 0") }
                            MenuItem { text: "CW TX Off";        onTriggered: quickCmd("mtest 61 256") }
                            MenuSeparator {}
                            MenuItem { text: "TX Power 20";      onTriggered: quickCmd("mtest 62 20") }
                            MenuItem { text: "TX Power 127 (max)"; onTriggered: quickCmd("mtest 62 127") }
                            MenuSeparator {}
                            MenuItem { text: "Frontend: 315";    onTriggered: quickCmd("mtest 64 0") }
                            MenuItem { text: "Frontend: 433";    onTriggered: quickCmd("mtest 64 1") }
                            MenuItem { text: "Frontend: 915";    onTriggered: quickCmd("mtest 64 2") }
                            MenuItem { text: "Frontend: None";   onTriggered: quickCmd("mtest 64 3") }
                            MenuSeparator {}
                            MenuItem { text: "Get RSSI";         onTriggered: quickCmd("mtest 68 0") }
                            MenuItem { text: "Get State";        onTriggered: quickCmd("mtest 69 0") }
                        }
                    }

                    // ── IR menu ──
                    Button {
                        text: "IR \u25BE"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        onClicked: irMenu.open()
                        Menu {
                            id: irMenu
                            MenuItem { text: "NEC: Addr 0 Cmd 0";   onTriggered: quickCmd("mtest 40 2 0 0 0") }
                            MenuItem { text: "NEC: Addr 0 Cmd 1";   onTriggered: quickCmd("mtest 40 2 0 1 0") }
                            MenuItem { text: "RC5: Addr 0 Cmd 0";   onTriggered: quickCmd("mtest 40 10 0 0 0") }
                            MenuItem { text: "Samsung: Addr 7 Cmd 2"; onTriggered: quickCmd("mtest 40 6 7 2 0") }
                        }
                    }

                    // ── SD Card menu ──
                    Button {
                        text: "SD \u25BE"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        onClicked: sdMenu.open()
                        Menu {
                            id: sdMenu
                            MenuItem { text: "List /";           onTriggered: quickCmd("mtest 19 /") }
                            MenuItem { text: "List /subghz";     onTriggered: quickCmd("mtest 19 /subghz") }
                            MenuItem { text: "List /infrared";   onTriggered: quickCmd("mtest 19 /infrared") }
                            MenuItem { text: "List /nfc";        onTriggered: quickCmd("mtest 19 /nfc") }
                            MenuItem { text: "List /rfid";       onTriggered: quickCmd("mtest 19 /rfid") }
                            MenuItem { text: "List /badusb";     onTriggered: quickCmd("mtest 19 /badusb") }
                            MenuSeparator {}
                            MenuItem { text: "Format SD";        onTriggered: quickCmd("mtest 18 0") }
                        }
                    }

                    // ── Power menu ──
                    Button {
                        text: "Power \u25BE"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        onClicked: powerMenu.open()
                        Menu {
                            id: powerMenu
                            MenuItem { text: "Battery Info";         onTriggered: quickCmd("mtest 59 0") }
                            MenuSeparator {}
                            MenuItem { text: "Charger Dump (BQ25896)"; onTriggered: quickCmd("mtest 52 bc") }
                            MenuItem { text: "Fuel Gauge Dump (BQ27421)"; onTriggered: quickCmd("mtest 53 bc") }
                            MenuItem { text: "USB-PD Dump (FUSB302)"; onTriggered: quickCmd("mtest 52 pd") }
                        }
                    }

                    // ── ESP32 menu ──
                    Button {
                        text: "ESP32 \u25BE"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        onClicked: espMenu.open()
                        Menu {
                            id: espMenu
                            MenuItem { text: "Init ESP32";       onTriggered: quickCmd("mtest 70 0") }
                            MenuItem { text: "Reset ESP32";      onTriggered: quickCmd("mtest 78 0") }
                            MenuItem { text: "Deinit (for flash)"; onTriggered: quickCmd("mtest 79 0") }
                            MenuSeparator {}
                            MenuItem { text: "Ping ESP (link)";  onTriggered: quickCmd("mtest 72 0") }
                            MenuItem { text: "Scan APs";         onTriggered: quickCmd("mtest 71 0") }
                            MenuSeparator {}
                            MenuItem {
                                text: "Boot Snoop (~3s)"
                                onTriggered: {
                                    appendOutput("> [ESP32 UART Snoop] Capturing boot output (~3s)...")
                                    m1device.sendEspUartSnoop()
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // ── Always-visible: Reboot & Power Off ──
                    Button {
                        text: "Reboot"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        Material.foreground: "#FFC107"
                        onClicked: quickCmd("mtest 51 0")
                    }

                    Button {
                        text: "Power Off"
                        flat: true; font.pixelSize: 11; padding: 4
                        enabled: m1device.connected
                        Material.foreground: "#F44336"
                        onClicked: quickCmd("mtest 50 0")
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

                // Device-side UART verbosity. OFF keeps the M1 quiet (WARN) so its
                // UART isn't flooded with m1link/RPC traces; ON raises it to INFO
                // for a capture. Off by default — normal users never need it.
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
                              : "Device quiet (WARN only)"
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
