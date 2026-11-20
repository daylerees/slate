// An app's icon tile (drawn by scripts/appicon.py into Config.tileDir), by desktop id or
// window class. Used by the Spaces panel and the dock's More grid. One not drawn yet is drawn
// here, as the dock's own cells do: an app that went straight into More, never on the dock,
// showed an empty space where its icon belonged.

import QtQuick
import Quickshell.Io

Image {
    id: tile
    property string app: ""
    readonly property string path: app ? Config.tilePath(app) : ""
    property int version: 0
    property string tried: ""            // the file last drawn for (once each, so a broken icon isn't retried forever)
    source: app ? "file://" + path + "?v=" + version + "." + Config.tileVersion : ""
    sourceSize: Qt.size(128, 128)      // sharp at its largest (the overview's 44 px, on a 2× screen)
    smooth: true
    mipmap: true
    asynchronous: true
    layer.enabled: Config.iconTint > 0
    layer.effect: IconTint {}
    onStatusChanged: if (app && status === Image.Error && !gen.running && tried !== path) { tried = path; gen.running = true; }
    Process {
        id: gen
        command: Config.tileCommand(tile.app, tile.path)
        onExited: tile.version++
        onRunningChanged: Config.tileDrawing(running)
        Component.onDestruction: if (running) Config.tileDrawing(false)
    }
    IconPlate { anchors.fill: parent; z: -1; visible: parent.status === Image.Ready && !Config.s.iconFill && Config.s.iconShape !== "original" }
    IconGloss { visible: parent.status === Image.Ready && Config.glassGloss && Config.s.iconShape !== "original" }   // glass: as on the dock
}
