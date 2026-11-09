// Behind a dock tile that magnification lifts past the dock's top edge: the dock's own glass,
// under the tile's frosting, for just the part that's above the dock. With glass, a tile is a
// light frosted layer meant to sit on the dock; above it, over the bare wallpaper, it was
// nearly clear. With this it looks the same there as on the dock (and nothing changes on it).
// Put it first in the tile's slot, so it's under the tile:
//   DockBacking { dockTop: bg.y - row.y; color: win.bgColor; radius: … }
// (The slot is the strip's way up whichever edge the dock is on, so "above" is always up.)

import QtQuick

Item {
    id: b
    property real tileWidth: parent ? parent.width : 0
    property real tileHeight: tileWidth
    property real dockTop: 0            // where the dock's background starts, in the slot
    property real lift: 0               // how far the tile is raised (an app's launch bounce)
    property real radius: 0             // the tile's corners
    property color color: "transparent"
    readonly property real tileTop: (parent ? parent.height : 0) - tileHeight - lift
    x: ((parent ? parent.width : 0) - tileWidth) / 2
    y: tileTop
    width: tileWidth
    height: Math.max(0, Math.min(tileHeight, dockTop - tileTop))
    clip: true
    // (with no height, at rest, the clip hides it)
    visible: Config.glass

    // A rounded rectangle with the tile's corners (a squircle's sits just inside its curve)
    Rectangle {
        width: b.tileWidth; height: b.tileHeight
        radius: b.radius
        color: b.color
    }
}
