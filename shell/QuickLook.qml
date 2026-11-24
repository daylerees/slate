// Quick Look: a large preview of a file without opening an app ("slate-quicklook"). Space on a
// file in the launcher's results, the dock's Downloads or the Waste Basket (or Quick Look on
// one's right-click menu there) shows it here; Space or Escape (or a click outside) closes it,
// and Left/Right step to the file before or after it in the list it came from. Space in
// Nautilus and Nemo reaches it too (scripts/file-previewer.py, from shell.qml), and Dolphin's
// and Thunar's menus with Settings → Default Apps → Quick Look in Dolphin and Thunar.
//
//   quickLook.show(paths, index)     a list of files, starting at one of them
//   quickLook.show(urls, index, "", titles)   pictures on the web (https://: Slate Software's
//                                    screenshots), each with its title; shown as they are, no Open
//   slate ipc call quicklook open <path> / close
//
// What it shows, by kind (scripts/quicklook.py says which, and reads what's needed):
//   pictures   the picture, decoded near the size it's shown at
//   text       the first 200 KB, read-only (code in the code font, Settings → Appearance)
//   PDFs       the pages, drawn by poppler's pdftoppm (optional: without it, it says so)
//   video, songs  a player (QuickLookMedia.qml, Qt Multimedia: optional, likewise)
//   anything else  its icon, name, kind, size and date, with Open
// Open (or Enter) opens the file in its app, as a click on it in the launcher does.
// Built the first time it's wanted (shell.qml's LazyLoader).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    // ---- Look --------------------------------------------------------------
    readonly property color cardColor: Config.surface(Config.palette.base)     // as the launcher's
    readonly property color tileColor: Config.raised(Config.palette.card)      // bar capsules
    readonly property color textColor: Config.palette.text
    readonly property color dimTextColor: Config.palette.dim
    readonly property color accentText: Config.palette.accentText
    readonly property string fontFamily: Config.s.fontFamily
    readonly property string codeFont: String(Config.s.codeFontFamily || "monospace").replace(/[^\w .-]/g, "")
    readonly property int fadeMs: 160

    // ---- What it's showing -------------------------------------------------
    property var files: []                 // paths, in the order of the list it came from
    property int index: 0
    readonly property string path: files[index] || ""
    property bool shown: false
    signal opened()                        // a file was opened from here (the launcher closes)

    // From scripts/quicklook.py: the file's details, then what's in it
    property var info: null
    property string body: ""               // text
    property bool bodyCut: false
    property bool bodyCode: false
    property var pages: []                 // PDF pages, drawn
    property bool pagesDone: false
    property bool pagesMore: false
    property string missing: ""            // "pdftoppm": nothing to draw PDFs with
    property bool gone: false              // the file isn't there any more

    // Where the file came from: "" (Slate's own lists), or "nautilus" / "nemo" (Space there,
    // scripts/file-previewer.py): Left/Right then ask Nautilus to move its selection (stepOut)
    property string from: ""
    signal stepOut(int d)
    property var titles: []                // (pictures on the web: what each is called)
    // The picture being shown, in whichever of the two layers is current (layerA/layerB, below)
    property bool curA: true
    property string urlA: ""
    property string urlB: ""
    readonly property var picture: curA ? layerA : layerB
    readonly property string pictureUrl: kind === "image" && shown ? (web ? path : fileUrl(path)) : ""
    onPictureUrlChanged: {
        if (pictureUrl === "" || pictureUrl === (curA ? urlA : urlB)) return;
        if (curA) urlB = pictureUrl; else urlA = pictureUrl;
        curA = !curA;
    }
    // (the spinner only once a picture's taking a while: one already kept loads in a moment, and
    // just crossfades in)
    Timer { id: slowPicture; interval: 350 }
    // A picture on the web rather than a file here (only https: Flathub's screenshots)
    readonly property bool web: path.startsWith("https://")
    function show(list, at, source, names) {
        const l = (list || []).filter(p => typeof p === "string" && (p.startsWith("/") || p.startsWith("https://")));
        if (l.length === 0) return;
        titles = names || [];
        screen = Config.focusedScreen;
        from = source || "";
        files = l;
        index = Math.max(0, Math.min(l.length - 1, at || 0));
        shown = true;
        Qt.callLater(() => keys.forceActiveFocus());     // (the keys, again each time it opens)
        load();
    }
    function close() {
        if (!shown) return;
        shown = false;
        reader.running = false;
        if (mediaLoader.item) mediaLoader.item.stop();
    }
    function step(d) {
        if (files.length < 2) { if (from === "nautilus") stepOut(d); return; }
        index = (index + d + files.length) % files.length;
        load();
    }
    function load() {
        info = null; body = ""; bodyCut = false; bodyCode = false;
        pages = []; pagesDone = false; pagesMore = false; missing = ""; gone = false;
        reader.running = false;
        // On the web: a picture, nothing to read about it here
        if (web) { info = { kind: "image", name: titles[index] || "Screenshot", label: "Screenshot", web: true, width: 0, height: 0 }; return; }
        reader.command = ["python3", Quickshell.shellPath("scripts/quicklook.py"), path, Config.runtimeDir + "/slate/quicklook"];
        reader.running = true;
    }
    function openFile() {
        if (!path || web) return;
        Qt.openUrlExternally(fileUrl(path));
        close();
        opened();
    }
    // A path as a file:// URL, each part encoded: a name with # or ? in it is still that file
    function fileUrl(p) { return Config.fileUrl(p); }

    Process {
        id: reader
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.info) root.info = m.info;
                else if (m.text !== undefined) { root.body = m.text; root.bodyCut = !!m.cut; root.bodyCode = !!m.code; }
                else if (m.page) root.pages = root.pages.concat([m.page]);
                else if (m.pages !== undefined) { root.pagesDone = true; root.pagesMore = !!m.more; }
                else if (m.missing) root.missing = m.missing;
                else if (m.gone) root.gone = true;
            }
        }
    }

    // ---- Which view --------------------------------------------------------
    readonly property string kind: info ? info.kind : ""
    readonly property bool mediaKind: kind === "video" || kind === "audio"
    // Anything that can't be shown as itself falls back to its details, saying why if
    // something's missing that would show it
    readonly property bool imageFailed: kind === "image" && picture.status === Image.Error
    readonly property bool mediaMissing: mediaKind && mediaLoader.status === Loader.Error
    readonly property bool mediaFailed: mediaKind && !!mediaLoader.item && mediaLoader.item.failed
    readonly property bool pdfEmpty: kind === "pdf" && pagesDone && pages.length === 0
    // (the keys stay its own as one view gives way to the next: Qt let go of them as the views
    // changed, and Left, Right, Space and Escape stopped doing anything after the first step)
    onViewChanged: if (shown) keys.forceActiveFocus()
    readonly property string view: !info ? (gone ? "details" : "loading")
        : kind === "image" && !imageFailed ? "image"
        : kind === "text" ? "text"
        : kind === "pdf" && missing === "" && !pdfEmpty ? "pdf"
        : mediaKind && !mediaMissing && !mediaFailed ? kind
        : "details"
    readonly property string note: web && imageFailed ? "Slate couldn't load this screenshot. Check you're online, then try again."
        : gone ? "This file isn't there any more. It may have been moved or deleted."
        : missing === "pdftoppm" ? "To see PDFs here, install Poppler" + Packages.named("poppler") + "."
        : mediaMissing ? "To play videos and songs here, install Qt Multimedia" + Packages.named("qtmultimedia") + "."
        : imageFailed ? "Slate can't draw this kind of picture yet."
        : mediaFailed ? "Slate couldn't play this one."
        : pdfEmpty ? "Slate couldn't read the pages of this PDF."
        : ""

    function sizeText(n) {
        if (n < 1000) return n === 1 ? "1 byte" : n + " bytes";
        const units = ["KB", "MB", "GB", "TB"];
        let v = n / 1000, u = 0;
        while (v >= 1000 && u < units.length - 1) { v /= 1000; u++; }
        return (v < 10 ? v.toFixed(1) : Math.round(v)) + " " + units[u];
    }
    readonly property string name: info ? info.name : path.split("/").pop()
    // The kind and size, and what else is known (a picture's size, a PDF's pages)
    readonly property string details: {
        if (!info) return "";
        if (info.web) return info.label;
        const parts = [info.label];
        if (info.dir) { if (info.items !== null) parts.push(info.items === 1 ? "1 item" : info.items + " items"); }
        else parts.push(sizeText(info.size));
        if (kind === "image" && info.width > 0) parts.push(info.width + " × " + info.height);
        if (view === "pdf" && pagesDone)
            parts.push(pagesMore ? "first " + pages.length + " pages" : pages.length === 1 ? "1 page" : pages.length + " pages");
        return parts.join(" · ");
    }
    // (in the date format from Settings → Date & Time)
    readonly property string modified: info ? "Modified " + Config.dateText(new Date(info.modified * 1000), "full") : ""
    function glyph() {
        switch (kind) {
        case "folder": return 0xEAAD;
        case "image": return 0xEB0A;
        case "pdf": return 0xFB10;
        case "video": return 0xEAFA;
        case "audio": return 0xEAFC;
        case "text": return 0xEAA2;
        }
        const ext = (name.split(".").pop() || "").toLowerCase();
        if (["zip", "tar", "gz", "xz", "bz2", "zst", "7z", "rar", "deb", "rpm", "appimage", "iso"].includes(ext)) return 0xED4E;
        return 0xEAA4;
    }

    // ---- Size --------------------------------------------------------------
    // As big as the file wants, within most of the screen
    readonly property real dpr: screen && screen.devicePixelRatio > 0 ? screen.devicePixelRatio : 1
    readonly property real pad: 12
    readonly property real headHeight: 52
    readonly property real maxBodyW: Math.max(320, Math.min(width * 0.86, 1600) - pad * 2)
    readonly property real maxBodyH: Math.max(200, height * 0.84 - headHeight - pad)
    function fit(w, h) {
        if (!(w > 0 && h > 0)) return Qt.size(480, 320);
        const s = Math.min(1, maxBodyW / w, maxBodyH / h);
        return Qt.size(Math.max(120, Math.round(w * s)), Math.max(80, Math.round(h * s)));
    }
    readonly property size bodySize: {
        switch (view) {
        case "image": return picture.status === Image.Ready ? fit(picture.fullWidth, picture.fullHeight) : lastImage;
        // (as tall as the text, up to the room there is: a short note gets a small card)
        case "text": return Qt.size(Math.min(maxBodyW, 820), Math.min(maxBodyH, Math.max(160, Math.ceil(textHeight) + 4)));
        case "pdf": return Qt.size(Math.min(maxBodyW, 780), maxBodyH);
        case "video": {
            const n = mediaLoader.item ? mediaLoader.item.naturalSize : Qt.size(0, 0);
            return n.width > 0 ? fit(n.width, n.height) : fit(1280, 720);
        }
        case "audio": return Qt.size(420, 150);
        }
        return Qt.size(400, 0);
    }
    // (stepping from one picture to the next, the card keeps the last one's size until the
    // next is ready, rather than shrinking to nothing in between)
    property size lastImage: Qt.size(480, 320)
    // (the text's height, noted as it changes rather than bound: it depends on the width, which
    // the card's size sets)
    property real textHeight: 0
    function noteTextHeight() { textHeight = textFlick.contentHeight; }   // (a moment later: not while the card's size is being worked out)

    // ---- Window ------------------------------------------------------------
    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(root.fadeMs); easing.type: Easing.OutCubic } }
    visible: shown || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-quicklook"
    WlrLayershell.layer: WlrLayer.Overlay
    // The keyboard, taken a moment after it shows: opened from the launcher (which lets go of it as
    // this shows), taken in that same moment it went to the window behind instead, and keys were lost
    WlrLayershell.keyboardFocus: shown && keysReady ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    property bool keysReady: false
    onShownChanged: if (!shown) keysReady = false
    Timer { interval: 60; running: root.shown && !root.keysReady; onTriggered: { root.keysReady = true; keys.forceActiveFocus(); } }

    Connections {
        target: Config
        function onFocusedWorkspaceIdChanged() { root.close(); }
    }

    // Dimmed desktop; click it to close
    DialogBackdrop { fade: root.fade; active: root.shown; onDismissed: root.close() }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: root.shown
        Keys.onPressed: e => {
            switch (e.key) {
            case Qt.Key_Space: case Qt.Key_Escape: root.close(); break;
            case Qt.Key_Left: root.step(-1); break;
            case Qt.Key_Right: root.step(1); break;
            case Qt.Key_Return: case Qt.Key_Enter: root.openFile(); break;
            // (text: copy what's selected, or select it all)
            case Qt.Key_C: case Qt.Key_A:
                if (!(e.modifiers & Qt.ControlModifier) || root.view !== "text") return;
                if (e.key === Qt.Key_A) textEdit.selectAll(); else textEdit.copy();
                break;
            case Qt.Key_Up: case Qt.Key_Down: case Qt.Key_PageUp: case Qt.Key_PageDown: case Qt.Key_Home: case Qt.Key_End: {
                const f = root.view === "text" ? textFlick : root.view === "pdf" ? pdfFlick : null;
                if (!f) return;
                const most = Math.max(0, f.contentHeight - f.height);
                const by = { [Qt.Key_Up]: -60, [Qt.Key_Down]: 60, [Qt.Key_PageUp]: -f.height * 0.9, [Qt.Key_PageDown]: f.height * 0.9 }[e.key];
                f.contentY = e.key === Qt.Key_Home ? 0 : e.key === Qt.Key_End ? most : Math.max(0, Math.min(most, f.contentY + by));
                break;
            }
            default: return;
            }
            e.accepted = true;
        }
    }

    // ---- Card --------------------------------------------------------------
    Rectangle {
        id: card
        readonly property bool header: root.view !== "details" && root.view !== "loading"
        readonly property real wantW: card.header ? Math.max(400, root.bodySize.width + root.pad * 2) : 400
        readonly property real wantH: card.header ? root.headHeight + root.bodySize.height + root.pad : detailsCol.implicitHeight + 48
        width: Math.round(wantW)
        height: Math.round(wantH)
        // (grows or shrinks from one file to the next; at once when it first opens)
        property bool settled: false
        Behavior on width { enabled: card.settled; NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
        Behavior on height { enabled: card.settled; NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
        anchors.centerIn: parent
        radius: Config.corner(18)
        color: root.cardColor
        // Shown once there's something to show (the file's details: a moment after opening)
        opacity: root.fade * (root.view === "loading" ? 0 : 1)
        scale: 0.96 + 0.04 * root.fade
        Behavior on opacity { NumberAnimation { duration: Config.ms(120) } }
        WindowBorder { radius: parent.radius }   // glass: the window border (Config)
        Shadow {}                                // raised: Slate's shadow, with glass too
        MouseArea { anchors.fill: parent }       // clicks inside don't close it
        Timer { interval: 300; running: root.shown && root.view !== "loading"; onTriggered: card.settled = true }
        Connections { target: root; function onShownChanged() { if (!root.shown) card.settled = false; } }

        // ---- The header: name, details, where in the list, Open ----
        Item {
            id: head
            visible: card.header
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: root.headHeight
            Column {
                anchors { left: parent.left; leftMargin: 18; right: root.files.length > 1 ? counter.left : root.web ? closeButton.left : openButton.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 1
                Text {
                    id: headName
                    width: parent.width
                    textFormat: Text.PlainText        // never markup: a file's name
                    text: root.name
                    elide: Text.ElideMiddle
                    color: root.textColor
                    font.family: root.fontFamily; font.pixelSize: Config.text(14); font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.details
                    elide: Text.ElideRight
                    color: root.dimTextColor
                    font.family: root.fontFamily; font.pixelSize: Config.text(12); font.weight: Font.Medium
                }
            }
            // Where in the list, between arrows to the one before and after (as Left and Right)
            Row {
                id: counter
                visible: root.files.length > 1
                anchors { right: root.web ? closeButton.left : openButton.left; rightMargin: root.web ? 2 : 8; verticalCenter: parent.verticalCenter }
                spacing: 2
                HeadButton { id: prevButton; code: 0xEA60; onClicked: root.step(-1) }
                // (as wide as it can get for this list, its widest digits in both places, so the
                // arrows stay still as it counts)
                Text {
                    id: countText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.ceil(widest.advanceWidth) + 4
                    horizontalAlignment: Text.AlignHCenter
                    text: (root.index + 1) + " of " + root.files.length
                    color: root.dimTextColor
                    font.family: root.fontFamily; font.pixelSize: Config.text(12); font.weight: Font.Medium
                    TextMetrics {
                        id: widest
                        font: countText.font
                        text: { const n = String(root.files.length).replace(/./g, "8"); return n + " of " + n; }
                    }
                }
                HeadButton { id: nextButton; code: 0xEA61; onClicked: root.step(1) }
            }
            DialogButton {
                id: openButton
                visible: !root.web            // (a picture on the web: no file to open)
                anchors { right: closeButton.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                width: 76; height: 32
                label: "Open"
                primary: true
                fill: root.tileColor; textColor: root.textColor; accentText: root.accentText
                onClicked: root.openFile()
            }
            // Close, at the end (as Settings' close button: Escape, Space or a click outside too)
            HeadButton {
                id: closeButton
                anchors { right: parent.right; rightMargin: root.pad - 4; verticalCenter: parent.verticalCenter }
                code: 0xEB55
                onClicked: root.close()
            }
        }

        // ---- The body ----
        Item {
            id: bodyBox
            visible: card.header
            x: root.pad; y: root.headHeight
            width: card.width - root.pad * 2
            height: card.height - root.headHeight - root.pad
            clip: true

            // A picture, in two layers that take turns: the next loads in the other, then fades in
            // over this one, which fades out after it (a smooth crossfade: nothing is reloaded, and
            // the card never goes blank between two pictures)
            PictureLayer { id: layerA; current: root.curA; url: root.urlA }
            PictureLayer { id: layerB; current: !root.curA; url: root.urlB }
            // Loading (a screenshot from the web, a large picture): Slate's spinner
            Spinner {
                id: lookSpinner
                anchors.centerIn: parent
                readonly property bool wanted: root.view === "image" && picture.status === Image.Loading && !slowPicture.running
                opacity: wanted ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                size: 26
            }

            // Text: read-only, selectable, the first 200 KB
            Rectangle {
                anchors.fill: parent
                visible: root.view === "text"
                radius: Config.corner(10)
                color: root.tileColor
                Flickable {
                    id: textFlick
                    onContentHeightChanged: Qt.callLater(root.noteTextHeight)
                    anchors { fill: parent; margins: 2; rightMargin: textFlick.contentHeight > textFlick.height ? 16 : 2 }
                    contentWidth: width
                    contentHeight: textEdit.implicitHeight + (cutNote.visible ? cutNote.height + 8 : 0)
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    SmoothWheel { flick: textFlick }
                    TextEdit {
                        id: textEdit
                        width: textFlick.width
                        padding: 14
                        readOnly: true
                        selectByMouse: true
                        activeFocusOnPress: false           // (the keys stay Quick Look's: Space closes)
                        textFormat: TextEdit.PlainText      // never markup: what's in the file
                        wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                        text: root.view === "text" ? root.body : ""
                        color: root.textColor
                        selectionColor: Config.accent; selectedTextColor: root.accentText
                        font.family: root.bodyCode ? root.codeFont : root.fontFamily
                        font.pixelSize: Config.text(13)
                    }
                    Text {
                        id: cutNote
                        visible: root.bodyCut
                        anchors { top: textEdit.bottom; left: parent.left; leftMargin: 14 }
                        text: "That's the first 200 KB. Open it to see the rest."
                        color: root.dimTextColor
                        font.family: root.fontFamily; font.pixelSize: Config.text(12); font.weight: Font.Medium
                    }
                }
                ScrollShade { anchors { left: parent.left; right: parent.right; top: parent.top } z: 3; cornerRadius: 10
                              distance: textFlick.contentY }
                ScrollShade { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } z: 3; atBottom: true; cornerRadius: 10
                              distance: textFlick.contentHeight - textFlick.height - textFlick.contentY }
                ThinScrollbar { flick: textFlick; color: root.textColor
                                anchors { top: parent.top; bottom: parent.bottom; right: parent.right; topMargin: 6; bottomMargin: 6; rightMargin: 3 } }
            }

            // A PDF: its pages, one under another
            Item {
                anchors.fill: parent
                visible: root.view === "pdf"
                Flickable {
                    id: pdfFlick
                    anchors { fill: parent; rightMargin: pdfFlick.contentHeight > pdfFlick.height ? 16 : 0 }
                    contentWidth: width
                    contentHeight: pageCol.height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    SmoothWheel { flick: pdfFlick }
                    Column {
                        id: pageCol
                        width: pdfFlick.width
                        spacing: 10
                        Repeater {
                            model: root.view === "pdf" ? root.pages : []
                            delegate: Image {
                                required property string modelData
                                width: pageCol.width
                                height: status === Image.Ready && implicitWidth > 0 ? width * implicitHeight / implicitWidth : width * 1.414
                                source: root.fileUrl(modelData)
                                sourceSize.width: Math.round(pageCol.width * root.dpr)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: false
                            }
                        }
                        Text {
                            visible: root.pagesMore
                            width: pageCol.width
                            horizontalAlignment: Text.AlignHCenter
                            text: "Open it to see the rest of the pages."
                            color: root.dimTextColor
                            font.family: root.fontFamily; font.pixelSize: Config.text(12); font.weight: Font.Medium
                        }
                    }
                }
                ScrollShade { anchors { left: pdfFlick.left; right: pdfFlick.right; top: parent.top } z: 3; cornerRadius: 10
                              distance: pdfFlick.contentY }
                ScrollShade { anchors { left: pdfFlick.left; right: pdfFlick.right; bottom: parent.bottom } z: 3; atBottom: true; cornerRadius: 10
                              distance: pdfFlick.contentHeight - pdfFlick.height - pdfFlick.contentY }
                ThinScrollbar { flick: pdfFlick; color: root.textColor
                                anchors { top: parent.top; bottom: parent.bottom; right: parent.right } }
            }

            // A video or a song: Qt Multimedia's player (optional: loaded, never imported)
            Loader {
                id: mediaLoader
                anchors.fill: parent
                active: root.shown && root.mediaKind
                source: Qt.resolvedUrl("QuickLookMedia.qml")
                visible: root.view === "video" || root.view === "audio"
                onLoaded: {
                    item.textColor = Qt.binding(() => root.textColor);
                    item.dimColor = Qt.binding(() => root.dimTextColor);
                    item.tileColor = Qt.binding(() => root.tileColor);
                    item.fontFamily = Qt.binding(() => root.fontFamily);
                    item.iconFamily = Config.iconFont;
                    item.audio = Qt.binding(() => root.kind === "audio");
                    item.autoplay = !Config.testMode;          // (the tests' Slate stays quiet)
                    item.source = Qt.binding(() => root.mediaKind ? root.fileUrl(root.path) : "");
                }
            }
        }

        // ---- Anything else: its details, and Open ----
        Column {
            id: detailsCol
            visible: !card.header
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 0
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 88; height: 88
                radius: Config.corner(20)
                color: root.tileColor
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(root.glyph())
                    color: Config.accent
                    font.family: Config.iconFont; font.pixelSize: 40
                }
            }
            Item { width: 1; height: 16 }
            Text {
                id: detailsName
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText        // never markup: a file's name
                text: root.name
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 3
                elide: Text.ElideMiddle
                color: root.textColor
                font.family: root.fontFamily; font.pixelSize: Config.text(17); font.weight: Font.DemiBold
            }
            Item { width: 1; height: 6 }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: root.details
                wrapMode: Text.WordWrap
                color: root.dimTextColor
                font.family: root.fontFamily; font.pixelSize: Config.text(13); font.weight: Font.Medium
            }
            Text {
                width: parent.width
                visible: !!root.info
                horizontalAlignment: Text.AlignHCenter
                text: root.modified
                color: root.dimTextColor
                font.family: root.fontFamily; font.pixelSize: Config.text(13); font.weight: Font.Medium
            }
            Item { width: 1; height: 10; visible: root.note !== "" }
            Text {
                width: parent.width
                visible: root.note !== ""
                horizontalAlignment: Text.AlignHCenter
                text: root.note
                wrapMode: Text.WordWrap
                color: root.dimTextColor
                font.family: root.fontFamily; font.pixelSize: Config.text(12); font.weight: Font.Medium
            }
            Item { width: 1; height: 20 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                DialogButton {
                    width: 120
                    label: "Close"
                    fill: root.tileColor; textColor: root.textColor; accentText: root.accentText
                    onClicked: root.close()
                }
                DialogButton {
                    width: 120
                    visible: !root.gone && !root.web
                    label: "Open"
                    primary: true
                    fill: root.tileColor; textColor: root.textColor; accentText: root.accentText
                    onClicked: root.openFile()
                }
            }
        }
    }

    // ---- For the tests -------------------------------------------------------
    function testState() {
        return {
            open: shown, visible: visible, keysReady: keysReady, path: path, index: index, count: files.length, web: web, openShown: openButton.visible, closeShown: card.header ? closeButton.visible : root.view === "details",
            arrowsShown: card.header && counter.visible,
            arrows: counter.visible ? [Math.round(prevButton.mapToItem(card, 0, 0).x), Math.round(nextButton.mapToItem(card, 0, 0).x)] : [],
            kind: kind, view: view, note: note, details: details,
            // the name as each place shows it, and whether it's drawn as plain text
            name: card.header ? headName.text : detailsName.text,
            plain: (card.header ? headName.textFormat : detailsName.textFormat) === Text.PlainText,
            textLength: body.length, cut: bodyCut, code: bodyCode, pages: pages.length, pagesDone: pagesDone,
            card: [Math.round(card.width), Math.round(card.height)], opacity: Math.round(card.opacity * 100) / 100,
            image: picture.status === Image.Ready ? [Math.round(picture.fullWidth), Math.round(picture.fullHeight)] : null
        };
    }

    // A round icon button in the header (close, and the arrows), as Settings' close button
    component HeadButton: Rectangle {
        id: hb
        property int code: 0
        signal clicked()
        width: 34; height: 34; radius: Config.corner(17)
        color: hbHover.hovered ? Config.hover : "transparent"
        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(hb.code)
            color: hbHover.hovered ? root.textColor : root.dimTextColor
            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
            font.family: Config.iconFont; font.pixelSize: 18
        }
        HoverHandler { id: hbHover }
        ClickTap { onTapped: hb.clicked() }
    }

    // One of the picture's two layers (above): the current one fades in once it has loaded, on
    // top; the other keeps the picture before it until then, and fades out a little after
    component PictureLayer: Image {
        id: layer
        property bool current: false
        property string url: ""
        // How big it's shown: as decoded (never bigger than the file, nor than the room there
        // is), in Slate's units
        readonly property real fullWidth: implicitWidth / root.dpr
        readonly property real fullHeight: implicitHeight / root.dpr
        anchors.fill: parent
        visible: root.view === "image" && opacity > 0
        z: current ? 1 : 0
        source: url
        opacity: current ? (status === Image.Ready ? 1 : 0) : (root.picture.status === Image.Ready ? 0 : 1)
        Behavior on opacity {
            NumberAnimation { duration: Config.ms(layer.current ? 240 : 420); easing.type: Easing.InOutQuad }
        }
        // (the size it's shown at: Qt scales a picture up to sourceSize too, so it's the fitted
        // size, from the file's own, read by quicklook.py; the room there is when that isn't known)
        sourceSize: root.info && root.info.width > 0
            ? Qt.size(Math.round(root.fit(root.info.width / root.dpr, root.info.height / root.dpr).width * root.dpr),
                      Math.round(root.fit(root.info.width / root.dpr, root.info.height / root.dpr).height * root.dpr))
            : Qt.size(Math.round(root.maxBodyW * root.dpr), Math.round(root.maxBodyH * root.dpr))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: root.web               // (on the web: kept, so stepping back to it is instant)
        smooth: true; mipmap: true
        onStatusChanged: {
            if (!current) return;
            if (status === Image.Ready) root.lastImage = root.fit(fullWidth, fullHeight);
            if (status === Image.Loading) slowPicture.restart(); else slowPicture.stop();
        }
    }
}
