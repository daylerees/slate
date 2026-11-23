// An app's icon tile (drawn by scripts/appicon.py into Config.tileDir), by desktop id or
// window class. Used by the Spaces panel and the dock's More grid. One not drawn yet is drawn
// here, as the dock's own cells do: an app that went straight into More, never on the dock,
// showed an empty space where its icon belonged.

import QtQuick

Image {
    id: tile
    property string app: ""
    readonly property string path: app ? Config.tilePath(app) : ""
    source: app ? "file://" + path + "?v=" + gen.version + "." + Config.tileVersion : ""
    sourceSize: Qt.size(128, 128)      // sharp at its largest (the overview's 44 px, on a 2× screen)
    smooth: true
    mipmap: true
    asynchronous: true
    layer.enabled: Config.iconTint > 0
    layer.effect: IconTint {}
    onStatusChanged: if (status === Image.Error) gen.missing()
    TileDrawer { id: gen; app: tile.app; path: tile.path }
    IconPlate { anchors.fill: parent; z: -1; visible: parent.status === Image.Ready && !Config.s.iconFill && Config.s.iconShape !== "original" }
    IconGloss { visible: parent.status === Image.Ready && Config.glassGloss && Config.s.iconShape !== "original" }   // glass: as on the dock
}
