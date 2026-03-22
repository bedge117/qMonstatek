import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs

Item {
    id: view

    property string currentPath: "0:/"
    property var fileEntries: []
    property string statusText: "Ready"
    property bool pendingDelete: false

    // Selection tracking: plain JS array of booleans, same length as fileEntries
    property var checkedState: []
    property int selectionCount: 0

    function clearSelection() {
        var arr = []
        for (var i = 0; i < fileEntries.length; i++) arr.push(false)
        checkedState = arr
        selectionCount = 0
    }

    function toggleIndex(idx) {
        var arr = checkedState.slice()  // copy
        arr[idx] = !arr[idx]
        checkedState = arr
        var c = 0
        for (var i = 0; i < arr.length; i++) if (arr[i]) c++
        selectionCount = c
    }

    function selectAll() {
        var arr = []
        for (var i = 0; i < fileEntries.length; i++) arr.push(true)
        checkedState = arr
        selectionCount = fileEntries.length
    }

    function getSelectedNames() {
        var names = []
        for (var i = 0; i < fileEntries.length; i++) {
            if (checkedState[i]) names.push(fileEntries[i].name)
        }
        return names
    }

    // Build a proper remote path with separator
    function buildRemotePath(name) {
        var p = currentPath
        if (!p.endsWith("/")) p += "/"
        return p + name
    }

    Connections {
        target: m1device
        function onFileListReceived(path, entries) {
            view.currentPath = path
            view.fileEntries = entries
            view.statusText = "Received " + entries.length + " entries for: " + path
            errorLabel.visible = false
            uploadProgress.visible = false
            view.pendingDelete = false
            clearSelection()
        }
        function onFileOperationError(message) {
            errorLabel.text = "File error: " + message
            errorLabel.visible = true
            view.statusText = "ERROR: " + message
            uploadProgress.visible = false
            view.pendingDelete = false
        }
        function onErrorOccurred(message) {
            errorLabel.text = "Device error: " + message
            errorLabel.visible = true
            view.statusText = "DEVICE ERROR: " + message
            uploadProgress.visible = false
        }
        function onFileUploadProgress(percent) {
            uploadProgress.visible = true
            uploadProgress.value = percent / 100.0
            view.statusText = "Uploading... " + percent + "%"
        }
        function onFileUploadComplete() {
            uploadProgress.visible = false
            view.statusText = "Upload complete"
            refresh()
        }
        function onMultiUploadProgress(fileIndex, totalFiles, fileName) {
            uploadProgress.visible = true
            if (totalFiles > 0)
                uploadProgress.value = fileIndex / totalFiles
            view.statusText = "Uploading " + fileName + " (" + fileIndex + "/" + totalFiles + ")"
        }
        function onMultiUploadComplete(totalFiles) {
            uploadProgress.visible = false
            view.statusText = "Uploaded " + totalFiles + " files"
            refresh()
        }
        function onFileDeleteComplete() {
            if (bulkDeleteQueue.length > 0) {
                var next = bulkDeleteQueue.shift()
                bulkDeleteQueue = bulkDeleteQueue  // trigger change
                view.statusText = "Deleting " + next + " (" + (bulkDeleteTotal - bulkDeleteQueue.length) + "/" + bulkDeleteTotal + ")..."
                view.pendingDelete = true
                m1device.deleteFile(buildRemotePath(next))
            } else {
                view.pendingDelete = false
                view.statusText = bulkDeleteTotal > 1
                    ? "Deleted " + bulkDeleteTotal + " items"
                    : "Deleted successfully"
                bulkDeleteTotal = 0
                refresh()
            }
        }
        function onFileMkdirComplete() {
            view.statusText = "Folder created"
            refresh()
        }
        function onSdMountChanged(mounted) {
            if (mounted) {
                view.statusText = "SD card mounted"
                refresh()
            } else {
                view.statusText = "SD card unmounted — accessible from Windows"
                view.fileEntries = []
                clearSelection()
            }
        }
        function onConnectionChanged(connected) {
            if (connected && view.pendingDelete) {
                view.statusText = "Reconnected -- checking delete result..."
                reconnectRefreshTimer.start()
            }
        }
    }

    property var bulkDeleteQueue: []
    property int bulkDeleteTotal: 0

    Timer {
        id: reconnectRefreshTimer
        interval: 500
        repeat: false
        onTriggered: {
            view.pendingDelete = false
            refresh()
        }
    }

    function refresh() {
        if (m1device.connected) {
            view.statusText = "Requesting file list for: " + currentPath + " ..."
            errorLabel.visible = false
            m1device.requestFileList(currentPath)
        } else {
            view.statusText = "Not connected"
        }
    }

    function navigateTo(name) {
        var newPath = currentPath
        if (!newPath.endsWith("/")) newPath += "/"
        newPath += name
        currentPath = newPath
        view.statusText = "Navigating to: " + newPath + " ..."
        m1device.requestFileList(newPath)
    }

    function navigateUp() {
        var parts = currentPath.split("/")
        parts.pop()
        if (parts.length < 1) parts = ["0:"]
        currentPath = parts.join("/") + "/"
        view.statusText = "Navigating up to: " + currentPath + " ..."
        m1device.requestFileList(currentPath)
    }

    function bulkDelete(names) {
        if (names.length === 0) return
        bulkDeleteQueue = names.slice(1)
        bulkDeleteTotal = names.length
        view.pendingDelete = true
        view.statusText = "Deleting " + names[0] + " (1/" + names.length + ")..."
        m1device.deleteFile(buildRemotePath(names[0]))
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        // Title + toolbar
        RowLayout {
            Label {
                text: "File Manager"
                font.pixelSize: 24
                font.bold: true
            }
            Item { Layout.fillWidth: true }

            Button { text: "Up"; onClicked: navigateUp(); enabled: m1device.connected && m1device.sdMounted }
            Button { text: "Refresh"; onClicked: refresh(); enabled: m1device.connected && m1device.sdMounted }
            Button {
                text: "Upload Files"
                enabled: m1device.connected && m1device.sdMounted
                onClicked: uploadDialog.open()
            }
            Button {
                text: "Upload Folder"
                enabled: m1device.connected && m1device.sdMounted
                onClicked: folderUploadDialog.open()
            }
            Button {
                text: "New Folder"
                enabled: m1device.connected && m1device.sdMounted
                onClicked: newFolderDialog.open()
            }
            Button {
                text: m1device.sdMounted ? "Unmount SD" : "Mount SD"
                enabled: m1device.connected
                Material.foreground: m1device.sdMounted ? Material.foreground : "#4CAF50"
                onClicked: {
                    if (m1device.sdMounted)
                        m1device.unmountSdCard()
                    else
                        m1device.mountSdCard()
                }
            }
        }

        // Current path
        Pane {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Material.elevation: 1
            padding: 8

            Label {
                text: "\uD83D\uDCC1 " + currentPath
                font.pixelSize: 13
                font.family: "Courier New"
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // SD unmounted banner
        Pane {
            visible: m1device.connected && !m1device.sdMounted
            Layout.fillWidth: true
            Material.elevation: 1
            Material.background: "#FFF3E0"
            padding: 12

            RowLayout {
                anchors.fill: parent
                Label {
                    text: "SD card is unmounted — accessible from Windows. Click Mount SD when done."
                    font.pixelSize: 12
                    color: "#E65100"
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }

        // Bulk action bar
        RowLayout {
            visible: selectionCount > 0
            Layout.fillWidth: true
            spacing: 12

            Label {
                text: selectionCount + " selected"
                font.pixelSize: 13
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Button {
                text: "Select All"
                flat: true
                font.pixelSize: 12
                onClicked: selectAll()
            }
            Button {
                text: "Deselect"
                flat: true
                font.pixelSize: 12
                onClicked: clearSelection()
            }
            Button {
                text: "Delete Selected"
                flat: true
                font.pixelSize: 12
                Material.foreground: "#F44336"
                onClicked: {
                    var names = getSelectedNames()
                    if (names.length > 0) {
                        bulkDeleteConfirm.itemNames = names
                        bulkDeleteConfirm.open()
                    }
                }
            }
        }

        // Upload progress bar
        ProgressBar {
            id: uploadProgress
            visible: false
            Layout.fillWidth: true
            from: 0.0
            to: 1.0
            value: 0.0
        }

        // Status label
        Label {
            id: statusLabel
            text: view.statusText
            font.pixelSize: 11
            color: Material.hintTextColor
            Layout.fillWidth: true
        }

        // Error label
        Label {
            id: errorLabel
            visible: false
            color: "#F44336"
            font.pixelSize: 12
            font.bold: true
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        // Not connected
        Label {
            visible: !m1device.connected
            text: "Connect your M1 device, then click Refresh to browse files."
            color: Material.hintTextColor
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 40
        }

        // File list
        ListView {
            id: fileList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: view.fileEntries

            delegate: ItemDelegate {
                width: fileList.width
                height: 40

                contentItem: RowLayout {
                    spacing: 8

                    CheckBox {
                        checked: (index >= 0 && index < view.checkedState.length)
                                 ? view.checkedState[index] : false
                        onClicked: view.toggleIndex(index)
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                    }

                    Label {
                        text: modelData.isDir ? "\uD83D\uDCC1" : fileIcon(modelData.name)
                        font.pixelSize: 16
                        Layout.preferredWidth: 24
                    }

                    Label {
                        text: modelData.name
                        font.pixelSize: 13
                        font.bold: modelData.isDir
                        Layout.fillWidth: true
                    }

                    Label {
                        text: modelData.isDir ? "" : formatSize(modelData.size)
                        font.pixelSize: 11
                        color: Material.hintTextColor
                        Layout.preferredWidth: 80
                        horizontalAlignment: Text.AlignRight
                    }

                    Button {
                        text: "\u2B07"
                        visible: !modelData.isDir
                        flat: true
                        font.pixelSize: 14
                        onClicked: {
                            downloadDialog.remotePath = buildRemotePath(modelData.name)
                            downloadDialog.open()
                        }
                    }

                    Button {
                        text: "\uD83D\uDDD1"
                        visible: true
                        flat: true
                        font.pixelSize: 14
                        onClicked: {
                            deleteConfirm.itemName = modelData.name
                            deleteConfirm.open()
                        }
                    }
                }

                onDoubleClicked: {
                    if (modelData.isDir) {
                        navigateTo(modelData.name)
                    }
                }
            }

            // Empty state
            Label {
                visible: fileList.count === 0 && m1device.connected && m1device.sdMounted
                text: "Empty directory"
                anchors.centerIn: parent
                color: Material.hintTextColor
            }
        }
    }

    // File icon helper
    function fileIcon(name) {
        if (name.endsWith(".sub")) return "\uD83D\uDCFB"
        if (name.endsWith(".nfc")) return "\uD83D\uDCF1"
        if (name.endsWith(".rfid")) return "\uD83D\uDCB3"
        if (name.endsWith(".ir")) return "\uD83D\uDD34"
        if (name.endsWith(".txt")) return "\uD83D\uDCC4"
        if (name.endsWith(".bin")) return "\uD83D\uDCBE"
        return "\uD83D\uDCC4"
    }

    function formatSize(bytes) {
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB"
        return (bytes / 1048576).toFixed(1) + " MB"
    }

    // Dialogs — Upload supports multi-file selection
    FileDialog {
        id: uploadDialog
        title: "Select Files to Upload"
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            if (selectedFiles.length === 1) {
                var localPath = selectedFiles[0].toString().replace("file:///", "")
                var fileName = localPath.split("/").pop().split("\\").pop()
                m1device.uploadFile(localPath, buildRemotePath(fileName))
            } else if (selectedFiles.length > 1) {
                m1device.uploadFiles(selectedFiles, currentPath)
            }
        }
    }

    FolderDialog {
        id: folderUploadDialog
        title: "Select Folder to Upload"
        onAccepted: {
            m1device.uploadFolder(selectedFolder.toString(), currentPath)
        }
    }

    Dialog {
        id: newFolderDialog
        title: "Create New Folder"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Ok | Dialog.Cancel

        TextField {
            id: folderNameField
            placeholderText: "Folder name"
            width: 300
        }

        onAccepted: {
            if (folderNameField.text.length > 0) {
                m1device.makeDirectory(buildRemotePath(folderNameField.text))
                folderNameField.text = ""
            }
        }
    }

    Dialog {
        id: deleteConfirm
        property string itemName: ""
        title: "Delete"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Yes | Dialog.No

        Label { text: "Delete \"" + deleteConfirm.itemName + "\"?" }

        onAccepted: {
            view.pendingDelete = true
            view.statusText = "Deleting " + itemName + "..."
            m1device.deleteFile(buildRemotePath(itemName))
        }
    }

    Dialog {
        id: bulkDeleteConfirm
        property var itemNames: []
        title: "Bulk Delete"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Yes | Dialog.No

        Label {
            text: {
                var n = bulkDeleteConfirm.itemNames.length
                var msg = "Delete " + n + " items?"
                var preview = bulkDeleteConfirm.itemNames.slice(0, 10)
                if (preview.length > 0)
                    msg += "\n\n" + preview.join("\n")
                if (n > 10)
                    msg += "\n... and " + (n - 10) + " more"
                return msg
            }
            wrapMode: Text.Wrap
        }

        onAccepted: {
            clearSelection()
            bulkDelete(itemNames)
        }
    }

    FileDialog {
        id: downloadDialog
        property string remotePath: ""
        title: "Save File As"
        fileMode: FileDialog.SaveFile
        onAccepted: {
            var localPath = selectedFile.toString().replace("file:///", "")
            m1device.downloadFile(remotePath, localPath)
        }
    }

    Component.onCompleted: {
        if (m1device.connected) refresh()
    }
}
