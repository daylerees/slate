// Image with rounded corners (used by the control centre)
import QtQuick
import QtQuick.Effects
import Quickshell

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
    // A person's picture (an account picture): with no picture, or one that can't be loaded, a themed
    // head-and-shoulders icon fills the box instead of leaving it empty. It follows `radius`, so
    // it's as round (or square) as the picture would be.
    property bool fallback: false
    readonly property bool showingFallback: fallback && img.status !== Image.Ready
    // The icon font. The login screen can't read it from here, so it passes its own copy.
    property url fontSource: "file://" + Quickshell.shellPath("fonts/tabler.ttf")
    FontLoader { id: tabler; source: ri.fontSource }
    Rectangle {
        id: bust
        visible: ri.showingFallback
        anchors.fill: parent
        radius: ri.radius
        // Opaque (the accent mixed into a neutral), so glass never shows one shape through another;
        // it dims with the picture's `brightness` when the pointer is over it
        color: Qt.darker(Qt.tint(Config.palette.control, Qt.rgba(Config.accent.r, Config.accent.g, Config.accent.b, 0.2)),
                         1 - ri.brightness * 1.8)
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(0xEB4D)     // user
            color: Qt.tint(Config.palette.dim, Qt.rgba(Config.accent.r, Config.accent.g, Config.accent.b, 0.35))
            opacity: Math.max(0, 1 + ri.brightness * 1.2)
            font.family: tabler.name
            font.pixelSize: Math.round(Math.min(ri.width, ri.height) * 0.6)
        }
    }
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
    // Made afresh each time a picture is ready: kept across one that couldn't be loaded, it held
    // on to the mask from before and drew nothing when the same picture came back (the login
    // screen, from you to someone without a picture and back)
    Loader {
        anchors.fill: parent
        active: img.status === Image.Ready
        sourceComponent: MultiEffect {
            source: img; maskEnabled: true; maskSource: imgMask
            saturation: ri.saturation; brightness: ri.brightness
        }
    }
}
