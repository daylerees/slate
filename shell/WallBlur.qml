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
    visible: Config.hyprBlur.enabled && wallpaper !== ""

    // Preview pixels per unit of win/screen
    readonly property real k: width / Math.max(0.0001, win.width)
    layer.enabled: true                     // keeps the wallpaper to this item's bounds
    layer.effect: MultiEffect { maskEnabled: true; maskSource: wbMask }

    Image {
        id: wbImg
        visible: false
        x: -wb.win.x * wb.k
        y: -wb.win.y * wb.k
        width: wb.screen.width * wb.k
        height: wb.screen.height * wb.k
        source: wb.visible ? wb.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.min(1600, width), Math.min(1000, height))
        asynchronous: true
    }
    MultiEffect {
        anchors.fill: wbImg
        source: wbImg
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
