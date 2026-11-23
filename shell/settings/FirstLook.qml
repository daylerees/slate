import QtQuick
import Quickshell.Io
import ".."

// A process a page runs to see how things stand (its status rows wait on it): counted
// while it runs, so the tests take their picture once the rows are there (win.checking)
Process {
    readonly property var win: SettingsHost.win
    property bool counted: false
    function count() { if (running !== counted) { win.checking += running ? 1 : -1; counted = running; } }
    onRunningChanged: count()
    Component.onCompleted: count()
    Component.onDestruction: if (counted) win.checking -= 1
}
