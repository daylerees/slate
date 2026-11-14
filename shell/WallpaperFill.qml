// A wallpaper filling its parent (cropped to fit), as the desktop draws it: changing it
// cross-fades from the old image to the new one, and Slate's own wallpapers (shell/wallpapers)
// are drawn through shaders/dither.frag so their smooth colour doesn't band. The desktop
// (Wallpaper.qml) and the wallpaper switcher (WallpaperSwitcher.qml) use it.
//   WallpaperFill { anchors.fill: parent; path: Config.wallpaper; pixelRatio: screen.devicePixelRatio }

import QtQuick
import Quickshell

Item {
    id: fill
    property string path: ""                 // the image (a file path)
    property real pixelRatio: 1              // the screen's: the image is decoded at its size
    // The wallpapers that come with Slate
    readonly property string ownFolder: Quickshell.shellPath("wallpapers")
    // (the image showing, once it's in: the tests' and the switcher's)
    readonly property bool ready: images[front].status === Image.Ready && images[front].source.toString() === wanted

    // Two images take turns: the new one loads hidden, then fades in over the old
    property int front: 0
    readonly property var images: [imgA, imgB]
    readonly property string wanted: path ? "file://" + path : ""
    onWantedChanged: {
        // (none: both let go, to free their memory)
        if (wanted === "") { retire.stop(); imgA.source = ""; imgB.source = ""; imgA.opacity = 0; imgB.opacity = 0; return; }
        const back = images[1 - front];
        if (images[front].source.toString() === wanted) return;
        back.opacity = 0;
        back.source = wanted;
    }

    component Layer: Image {
        id: layer
        // A few pixels past each edge: some wallpapers have a stray light or dark row or
        // column at the very edge, which would show as a line along the screen edge
        anchors { fill: parent; margins: -4 }
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        // One of Slate's own (shell/wallpapers): smooth colour, which bands when it's
        // scaled to the screen's size and rounded to its colours. So it's kept whole,
        // and Smooth (below) scales and rounds it with care instead of this drawing it
        readonly property bool own: source.toString().indexOf("file://" + fill.ownFolder + "/") === 0
        visible: !own
        sourceSize.width: own ? 0 : fill.width * fill.pixelRatio
        sourceSize.height: own ? 0 : fill.height * fill.pixelRatio
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(600); easing.type: Easing.InOutQuad } }
        onStatusChanged: {
            if (status !== Image.Ready || source.toString() !== fill.wanted) return;
            const i = fill.images.indexOf(layer);
            if (i === fill.front && opacity === 1) return;
            z = 1; fill.images[1 - i].z = 0;
            opacity = 1;
            fill.front = i;
            retire.restart();
        }
    }
    Layer { id: imgA; Component.onCompleted: source = fill.wanted }
    Layer { id: imgB }
    // Slate's own wallpapers, drawn from the whole picture (shaders/dither.frag): cropped
    // to fill the screen as the image itself would be, fading with it
    component Smooth: ShaderEffect {
        id: fx
        property Image from
        property variant source: from
        anchors.fill: from
        z: from.z
        opacity: from.opacity
        visible: from.own && from.status === Image.Ready && opacity > 0
        readonly property real fit: from.implicitWidth > 0 && from.implicitHeight > 0
            ? Math.max(width / from.implicitWidth, height / from.implicitHeight) : 1
        readonly property real shownW: Math.min(1, width / Math.max(1, from.implicitWidth * fit))
        readonly property real shownH: Math.min(1, height / Math.max(1, from.implicitHeight * fit))
        property vector4d crop: Qt.vector4d((1 - shownW) / 2, (1 - shownH) / 2, shownW, shownH)
        fragmentShader: Qt.resolvedUrl("shaders/dither.frag.qsb")
    }
    Smooth { from: imgA }
    Smooth { from: imgB }
    // Once the new image is in, drop the old one to free its memory
    Timer {
        id: retire
        interval: 700
        onTriggered: { const old = fill.images[1 - fill.front]; old.opacity = 0; old.source = ""; }
    }
}
