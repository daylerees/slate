// What a see-through window shows behind it on screen: the wallpaper, blurred the way
// Hyprland blurs it (Config.hyprBlur). Put it behind a window's live preview so a translucent
// terminal looks as it does on the desktop. Opaque windows simply cover it.
//   WallBlur { anchors.fill: preview; win: <the window's rect on its screen>; screen: <the
//              screen's size>; pixelScale: <preview pixels per screen pixel>; radius: … }
// win and screen can be in any units (Hyprland's pixels, or fractions of the screen), as long
// as they're the same.

import QtQuick
import QtQuick.Effects

Item {
    id: wb
    property string wallpaper: Config.wallpaper ? "file://" + Config.wallpaper : ""
    property rect win: Qt.rect(0, 0, 1, 1)
    property size screen: Qt.size(1, 1)
    property real pixelScale: 0.25          // for the blur's size
    property real radius: 0
    // (the size the wallpaper's decoded at: keep any Image that loads it ahead of time the same)
    readonly property size decodeSize: Qt.size(1600, 1000)
    visible: Config.hyprBlur.enabled && wallpaper !== ""

    // Preview pixels per unit of win/screen
    readonly property real k: width / Math.max(0.0001, win.width)
    // A real window to show it behind: users pass a 1×1 stand-in while there's nothing to show
    // (the window switcher, for a card without a preview), and that made k this item's whole
    // width, laying the wallpaper out hundreds of times the screen's size, too big to draw
    // (in any units: a real window is at most a few dozen times smaller than its screen)
    readonly property bool drawn: visible && win.width > 0 && win.height > 0
        && screen.width / win.width < 64 && screen.height / win.height < 64
    layer.enabled: drawn                    // keeps the wallpaper to this item's bounds
    layer.effect: MultiEffect { maskEnabled: true; maskSource: wbMask }

    Image {
        id: wbImg
        visible: false
        x: -wb.win.x * wb.k
        y: -wb.win.y * wb.k
        // Nothing to show: no size at all, as the blur builds its images from this item's size
        // even while it's hidden. And never more than 16 times this item, whatever order the
        // values arrive in: for a moment drawn could still be true with a stand-in window,
        // laying the wallpaper out hundreds of times the screen's size, too big to draw
        width: wb.drawn ? Math.min(wb.screen.width * wb.k, wb.width * 16) : 0
        height: wb.drawn ? Math.min(wb.screen.height * wb.k, wb.height * 16) : 0
        source: wb.drawn ? wb.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        // One size for every WallBlur (decodeSize), so the wallpaper is decoded once and shared
        // through the image cache: sized by each window, every preview decoded it again as it
        // appeared, and the blur came in half a second after the window
        sourceSize: wb.decodeSize
        asynchronous: true
    }
    MultiEffect {
        // Only once the picture has loaded: before then there's nothing to blur, and a blur of
        // an image still loading logs a warning ("not assigned a valid texture provider")
        readonly property bool ready: wb.drawn && wbImg.status === Image.Ready
        visible: ready
        anchors.fill: wbImg
        source: ready ? wbImg : null
        blurEnabled: true
        blur: 1
        blurMax: Math.max(4, Math.min(64, Math.round(Config.hyprBlur.size * Math.pow(2, Config.hyprBlur.passes) * wb.pixelScale)))
        contrast: Config.hyprBlur.contrast - 1
        saturation: Config.hyprBlur.vibrancy
    }
    Item {
        id: wbMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: wb.radius }
    }
}
