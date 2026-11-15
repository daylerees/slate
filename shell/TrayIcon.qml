import QtQuick
import Quickshell
import qs

// A tray icon's picture, as the bar draws it: in the bar's text colour (or its own colours, in
// the Colourful look), and grown until what's drawn fills the same space as the other icons'.
// Fills the item it's put in (the tray's delegate in Bar.qml).
Item {
    id: root
    anchors.fill: parent
    required property var win               // the bar it's on
    required property string iconSrc        // the app's icon, as the tray gives it
    // Icon drawn in high-contrast black and white (light parts white,
    // dark/coloured parts black) to match the rest of the bar; in the
    // Colourful look, in its own colours, unless Settings → Menu Bar →
    // Monochrome tray icons asks for one colour there too
    readonly property bool mono: !Config.colourful || Config.s.barTrayMono
    // Apps draw their icons with more or less empty space round them
    // (Spotify's is mostly margin), so each is measured once (trayMeasure)
    // and grown until what's drawn fills the same space as the others
    Item {
        id: trayBox
        anchors.centerIn: parent
        width: 18; height: 18
        clip: true
        property real grow: 1          // 1 … 1.6
        property point mid: Qt.point(0.5, 0.5)   // the drawing's centre, 0 … 1
        // An app can name its icon by a folder (image://icon/<name>?path=<folder>,
        // as Spotify does). The icon lookup doesn't always find it there, and then
        // hands back a broken-image pattern (no error to catch): so the file itself,
        // from that folder, first; the lookup only if there's no such file
        readonly property string iconUrl: iconSrc
        readonly property string fileUrl: {
            const m = /^image:\/\/icon\/([^?]+)\?path=(.+)$/.exec(iconUrl);
            return m ? "file://" + decodeURIComponent(m[2]) + "/" + m[1] + ".png" : "";
        }
        property bool useLookup: false
        onIconUrlChanged: useLookup = false
        Image {
            id: trayIcon
            width: 18 * trayBox.grow; height: width
            x: 9 - trayBox.mid.x * width
            y: 9 - trayBox.mid.y * height
            source: trayBox.fileUrl !== "" && !trayBox.useLookup ? trayBox.fileUrl : trayBox.iconUrl
            sourceSize: Qt.size(36, 36)
            smooth: true; mipmap: true
            onStatusChanged: {
                if (status === Image.Error && !trayBox.useLookup && trayBox.fileUrl !== "") trayBox.useLookup = true;
                else if (status === Image.Ready) trayMeasure.fetch();
            }
        }
        layer.enabled: root.mono
        layer.effect: ShaderEffect {
            property real threshold: 0.45      // brighter than this takes the text colour
            property color tint: win.textColor
            fragmentShader: Qt.resolvedUrl("shaders/mono.frag.qsb")
        }
    }
    // Measured from the icon as drawn (a picture of trayIcon, taken once it's
    // loaded and at its own size), so what's measured is what shows
    Canvas {
        id: trayMeasure
        width: 32; height: 32
        opacity: 0                     // (in the scene, unseen: hidden, it never gets a context)
        renderStrategy: Canvas.Immediate
        property string src: ""
        property int tries: 0
        function fetch() {
            if (trayIcon.status !== Image.Ready || trayBox.grow !== 1) {
                if (trayIcon.status === Image.Ready && trayBox.grow !== 1) { trayBox.grow = 1; trayBox.mid = Qt.point(0.5, 0.5); }
                if (trayIcon.status !== Image.Ready) return;
            }
            // (not yet on screen as the bar first builds: try again in a moment)
            if (!trayIcon.Window.window || !trayIcon.visible) { trayGrabLater.restart(); return; }
            if (Config.testMode) win.trayTest.measured++;
            trayIcon.grabToImage(r => {
                if (trayMeasure.src) trayMeasure.unloadImage(trayMeasure.src);
                trayMeasure.src = r.url;
                trayMeasure.tries = 0;
                trayMeasure.loadImage(r.url);
                if (!trayMeasure.measure()) trayRetry.restart();
            }, Qt.size(32, 32));
        }
        onAvailableChanged: measure()
        onImageLoaded: measure()
        Timer { id: trayGrabLater; interval: 300; onTriggered: trayMeasure.fetch() }
        Timer {
            id: trayRetry
            interval: 250; repeat: true
            onTriggered: if (trayMeasure.measure() || ++trayMeasure.tries > 24) stop()
        }
        // true once measured (or there's nothing to measure)
        function measure() {
            if (!src || isImageError(src)) return true;
            if (!available || !isImageLoaded(src)) return false;
            const ctx = getContext("2d");
            if (!ctx) return false;
            ctx.clearRect(0, 0, 32, 32);
            ctx.drawImage(src, 0, 0, 32, 32);
            const d = ctx.getImageData(0, 0, 32, 32).data;
            let x0 = 32, y0 = 32, x1 = -1, y1 = -1;
            for (let y = 0; y < 32; y++)
                for (let x = 0; x < 32; x++)
                    if (d[(y * 32 + x) * 4 + 3] > 24) {
                        if (x < x0) x0 = x; if (x > x1) x1 = x;
                        if (y < y0) y0 = y; if (y > y1) y1 = y;
                    }
            if (x1 < 0) return false;          // (not drawn yet)
            // Most icons fill about nine tenths of their square: grow the
            // rest to match (those that nearly do stay as they are, at most 1.6 times)
            // (by its longer side, so a wide or tall icon still fits)
            const fill = Math.max(x1 - x0 + 1, y1 - y0 + 1) / 32;
            const g = Math.max(1, Math.min(1.6, 0.9 / fill));
            trayBox.grow = g < 1.08 ? 1 : g;
            trayBox.mid = trayBox.grow === 1 ? Qt.point(0.5, 0.5)
                : Qt.point((x0 + x1 + 1) / 64, (y0 + y1 + 1) / 64);
            trayRetry.stop();
            return true;
        }
    }
}
