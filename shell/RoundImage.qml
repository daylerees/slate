// Image with rounded corners (used by the control centre)
import QtQuick
import QtQuick.Effects

Item {
    id: ri
    property url source
    property real radius: Config.corner(12)
    property real saturation: 0          // -1 = greyscale
    property real brightness: 0          // below 0 dims it
    readonly property int status: img.status
    // Decoded near the size it's drawn (twice, for sharpness on a scaled screen), not at the
    // picture's own size: an album cover or a screenshot can be thousands of pixels across and
    // is shown a few dozen wide. A caller can set its own (a size of 0 decodes the whole picture).
    property size decodeSize: Qt.size(width * 2, height * 2)
    // Off by default, so a caller that reads `status` right after setting `source` still sees
    // the picture loaded; those that can wait set it so a big picture doesn't hold up drawing.
    property bool asynchronous: false
    Image {
        id: img
        source: ri.source
        sourceSize: ri.decodeSize
        asynchronous: ri.asynchronous
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        visible: false
        smooth: true
        mipmap: true
    }
    Item {
        id: imgMask
        anchors.fill: parent
        visible: false
        // (a mask costs an offscreen texture: only while there's a picture to mask)
        layer.enabled: ri.visible && img.status === Image.Ready
        Rectangle { anchors.fill: parent; radius: ri.radius }
    }
    MultiEffect {
        anchors.fill: parent; source: img; maskEnabled: true; maskSource: imgMask
        saturation: ri.saturation; brightness: ri.brightness
    }
}
