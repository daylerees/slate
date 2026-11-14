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
    property int fadeMs: 600                 // the cross-fade from one image to the next
    // The wallpapers that come with Slate
    readonly property string ownFolder: Quickshell.shellPath("wallpapers")
    // (the image showing, once it's in: the tests' and the switcher's)
    readonly property bool ready: images[front].status === Image.Ready && images[front].source.toString() === wanted
    // (the picture actually in front, as a path: the tests')
    readonly property string showing: images[front].status === Image.Ready && images[front].opacity > 0
        ? images[front].source.toString().replace(/^file:\/\//, "") : ""

    // Two images take turns: the new one loads hidden, then fades in over the old
    property int front: 0
    readonly property var images: [imgA, imgB]
    readonly property string wanted: path ? "file://" + path : ""
    onWantedChanged: {
        // (none: both let go, to free their memory)
        if (wanted === "") { retire.stop(); imgA.source = ""; imgB.source = ""; imgA.opacity = 0; imgB.opacity = 0; return; }
        const back = images[1 - front];
        if (images[front].source.toString() === wanted) return;
        // Going straight back to the one just shown, before it's been let go: the spare still
        // has it, so setting it again changes nothing and it would never say it's loaded. It's
        // brought in now instead (otherwise the picture stayed on the one before)
        if (back.source.toString() === wanted && back.status === Image.Ready) { bringIn(back); return; }
        // (the spare's taken for this: the old picture's let-go, still to come, mustn't clear it
        // mid-load, or it never came in and the screen stayed on the one before)
        retire.stop();
        back.opacity = 0;
        back.source = wanted;
    }
    // The new picture is in: over the old one, fading in, and the old one let go once it's covered
    function bringIn(layer) {
        const i = images.indexOf(layer);
        if (i === front && layer.opacity === 1) return;
        layer.z = 1; images[1 - i].z = 0;
        layer.opacity = 1;
        front = i;
        retire.restart();
    }

    component Layer: Image {
        id: layer
        // A few pixels past each edge: some wallpapers have a stray light or dark row or
        // column at the very edge, which would show as a line along the screen edge
        anchors { fill: parent; margins: -4 }
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // (shared: the desktop and the wallpaper switcher's cover read each picture once between
        // them, and the cover has yours at once)
        cache: true
        smooth: true
        // One of Slate's own (shell/wallpapers): smooth colour, which bands when it's
        // scaled to the screen's size and rounded to its colours. So it's kept whole,
        // and Smooth (below) scales and rounds it with care instead of this drawing it
        readonly property bool own: source.toString().indexOf("file://" + fill.ownFolder + "/") === 0
        visible: !own
        sourceSize.width: own ? 0 : fill.width * fill.pixelRatio
        sourceSize.height: own ? 0 : fill.height * fill.pixelRatio
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(fill.fadeMs); easing.type: Easing.InOutQuad } }
        onStatusChanged: if (status === Image.Ready && source.toString() === fill.wanted) fill.bringIn(layer)
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
        interval: Config.ms(fill.fadeMs) + 100
        onTriggered: {
            const old = fill.images[1 - fill.front];
            if (old.source.toString() === fill.wanted) return;      // (the one coming in: kept)
            old.opacity = 0; old.source = "";
        }
    }
}
