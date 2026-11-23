import QtQuick
import Quickshell.Io

// Draws an app's icon tile (scripts/appicon.py, into Config.tileDir) when its picture can't be
// loaded: once for each file, so a broken icon isn't tried again and again. `version` goes up
// each time it's drawn: put it in the picture's source so the new one is loaded.
//   TileDrawer { id: drawer; app: id; path: Config.tilePath(id) }
//   Image { source: "file://" + drawer.path + "?v=" + drawer.version + "." + Config.tileVersion
//           onStatusChanged: if (status === Image.Error) drawer.missing() }
Process {
    id: drawer
    property string app: ""
    property string path: ""
    property int version: 0
    property string tried: ""
    function missing() { if (app !== "" && path !== "" && !running && tried !== path) { tried = path; running = true; } }
    command: Config.tileCommand(app, path)
    onExited: version++
    onRunningChanged: Config.tileDrawing(running)
    Component.onDestruction: if (running) Config.tileDrawing(false)
}
