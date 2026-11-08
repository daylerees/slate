// An app's icon tile (drawn by scripts/appicon.py into Config.tileDir), by desktop id or
// window class. Used by the Spaces panel.

import QtQuick

Image {
    property string app: ""
    source: app ? "file://" + Config.tileDir + "/" + app.replace(/[^A-Za-z0-9._-]/g, "_") + ".png?v=" + Config.tileVersion : ""
    sourceSize: Qt.size(64, 64)
    smooth: true
    mipmap: true
    asynchronous: true
    layer.enabled: Config.iconTint > 0
    layer.effect: IconTint {}
    IconPlate { anchors.fill: parent; z: -1; visible: parent.status === Image.Ready && !Config.s.iconFill && Config.s.iconShape !== "original" }
}
