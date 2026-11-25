// A row that saves something to a file (Settings → Debug's logs, Import & Export's settings):
// what it says while saving and once saved, with Show (the folder) and Export buttons.
//   ExportRow { label: "Export …"; about: "Saves …"; command: [...]
//               savedText: f => "Saved to " + f; failText: why => "Slate couldn't …" }
// The command prints the file it made on its last line of output; a line of its own on errors
// starting "Slate couldn't" is shown as it is.
import QtQuick
import Quickshell
import Quickshell.Io

SettingRow {
    id: row
    property string about: ""                  // what it does, while nothing's been saved
    property var command: []
    property int icon: 0                       // (the Export button's, if any)
    property var savedText: f => "Saved to " + f.replace(Quickshell.env("HOME"), "~")
    property var failText: why => why
    property string saved: ""                  // the file, once made
    property string status: ""
    readonly property bool running: exportRun.running
    signal finished(bool ok)
    detail: status !== "" ? status : about
    function start() { saved = ""; status = "Saving…"; exportRun.running = true; }
    Process {
        id: exportRun
        command: row.command
        stdout: StdioCollector { onStreamFinished: row.saved = text.trim().split("\n").pop() }
        // (why it couldn't, in Slate's words: too much in your own folders, say)
        stderr: StdioCollector { id: exportWhy }
        onExited: code => {
            const ok = code === 0 && row.saved !== "";
            const why = exportWhy.text.trim().split("\n").pop();
            row.status = ok ? row.savedText(row.saved) : row.failText(why.startsWith("Slate couldn't") ? why : "");
            row.finished(ok);
        }
    }
    Row {
        spacing: 8
        Button { visible: row.saved !== ""; label: "Show"; onClicked: Quickshell.execDetached(["xdg-open", row.saved.substring(0, row.saved.lastIndexOf("/"))]) }
        Button { icon: row.icon; label: "Export"; enabled: !row.running; onClicked: row.start() }
    }
}
