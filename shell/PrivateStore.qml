import QtQuick
import Quickshell
import Quickshell.Io

// Saves something personal (the notifications' history, Nova's conversation) where only you can
// read it: its folder made yours alone (700) before the first save, so the file is never where
// another account could read it, not even for the moment before its own chmod; then each save
// writes through `file` (the FileView that reads it back) and makes the file 600.
//   PrivateStore { id: keep; file: store }        …        keep.save(JSON.stringify(…))
QtObject {
    id: keeper
    required property FileView file
    property bool folderReady: false
    property string pending: ""
    function save(text) {
        pending = text;
        if (folderReady) write();
        else { folder.running = false; folder.running = true; }
    }
    function write() {
        file.setText(pending);
        Quickshell.execDetached(["chmod", "600", "--", file.path]);
    }
    property Process folder: Process {
        command: ["sh", "-c", 'mkdir -p "${0%/*}" && chmod 700 "${0%/*}"', keeper.file.path]
        onExited: code => { if (code === 0) { keeper.folderReady = true; keeper.write(); } }
    }
}
