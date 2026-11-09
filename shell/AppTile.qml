// An app's icon tile (drawn by scripts/appicon.py into Config.tileDir), by desktop id or
// window class. Used by the Spaces panel.

import QtQuick

Image {
    property string app: ""
    source: app ? "file://" + Config.tilePath(app) + "?v=" + Config.tileVersion : ""
    sourceSize: Qt.size(128, 128)      // sharp at its largest (the overview's 44 px, on a 2× screen)
    smooth: true
    mipmap: true
    asynchronous: true
    layer.enabled: Config.iconTint > 0
    layer.effect: IconTint {}
    IconPlate { anchors.fill: parent; z: -1; visible: parent.status === Image.Ready && !Config.s.iconFill && Config.s.iconShape !== "original" }
}
