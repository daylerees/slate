// Clipboard history (Super+V) and emoji picker (Super+.), styled like the launcher.
//   slate ipc call picker clipboard     open clipboard history
//   slate ipc call picker emoji         open the emoji picker
//   slate ipc call picker toggle <clipboard|emoji>
//   slate ipc call picker close
//
// Clipboard: history is kept by scripts/clipstore.py (fed by wl-paste --watch, started
// in shell.qml) in ~/.local/state/slate/clipboard/. Enter or click copies an entry
// back; Delete forgets it.
// Emoji: data/emoji.json; Enter or click copies it. Recently used come first
// (~/.local/state/slate/emoji.json).

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    // ---- Look (same as the launcher) ---------------------------------------
    readonly property real panelWidth: 560
    readonly property real panelHeight: 520
    readonly property real rowHeight: 52
    readonly property real imageRowHeight: 92
    // As tall as what's listed needs (never taller than panelHeight), like the launcher: the
    // search box, margins and footer (118), then the list's or grid's own height, at least a row
    readonly property real fittedHeight: Math.min(panelHeight, 118 + Math.max(rowHeight, view().contentHeight))
    readonly property int columns: 10            // emoji grid
    readonly property int fadeMs: 200
    readonly property real dropDistance: 18
    readonly property int slideMs: 140
    readonly property color barColor: Config.surface(Config.tint("#0f1216"))
    readonly property color fieldColor: Config.raised(Config.tint("#1d222a"))
    readonly property color selectColor: Config.tint("#262c35")
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property color dimTextColor: Config.tint("#8b94a3")
    readonly property color accent: Config.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property string fontFamily: Config.s.fontFamily
    readonly property string emojiFont: "Noto Color Emoji"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/slate"
    readonly property string clipDir: stateDir + "/clipboard"
    readonly property string clipScript: Quickshell.shellPath("scripts/clipstore.py")

    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }
    readonly property string iconFont: tabler.name

    // ---- Open / close ------------------------------------------------------
    property string mode: "clipboard"      // "clipboard" or "emoji"
    property bool shown: false
    // Typed in (or an entry deleted) since opening: only then does it animate its height (not
    // while its list is still loading as it opens, which made it grow in steps)
    property bool typed: false
    property bool slideHighlight: false
    property var lastPointer: null
    function open(m) {
        screen = Config.focusedScreen;     // open on the focused screen
        mode = m;
        lastPointer = null;
        slideHighlight = false;
        Qt.callLater(() => root.slideHighlight = true);
        search.text = "";
        typed = false;
        if (m === "clipboard") clipFile.reload();
        view().currentIndex = 0;
        view().positionViewAtBeginning();
        shown = true;
    }
    function close() { shown = false; }
    function toggle(m) { if (shown && mode === m) close(); else open(m); }
    function view() { return mode === "emoji" ? grid : list; }

    IpcHandler {
        target: "picker"
        function clipboard(): void { root.open("clipboard"); }
        function emoji(): void { root.open("emoji"); }
        function toggle(mode: string): void { root.toggle(mode === "emoji" ? "emoji" : "clipboard"); }
        function close(): void { root.close(); }
    }

    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutCubic } }

    visible: shown || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ---- Clipboard ---------------------------------------------------------
    property var clips: []
    FileView {
        id: clipFile
        path: root.clipDir + "/index.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.clips = JSON.parse(text()).entries || []; } catch (e) { root.clips = []; } }
        onLoadFailed: root.clips = []
    }
    readonly property var clipResults: {
        const q = search.text.trim().toLowerCase();
        if (q === "") return clips;
        return clips.filter(e => e.kind === "image" ? "image picture screenshot".includes(q) : e.text.toLowerCase().includes(q));
    }
    function clipRun(args) { Quickshell.execDetached(["python3", clipScript].concat(args)); }
    function copyClip(e) {
        if (!e) return;
        clipRun(["copy", e.id]);
        close();
    }
    function deleteClip(e) {
        if (!e) return;
        const i = list.currentIndex;
        typed = true;                                   // shrinks smoothly
        clips = clips.filter(c => c.id !== e.id);      // at once; the file catches up
        list.currentIndex = Math.min(i, list.count - 1);
        clipRun(["delete", e.id]);
    }
    function clearClips() { typed = true; clips = []; clipRun(["clear"]); }

    function preview(text) { return text.replace(/\s+/g, " ").trim(); }
    function ago(t) {
        const s = Math.max(0, Math.floor(Date.now() / 1000 - t));
        if (s < 60) return "Just now";
        if (s < 3600) return Math.floor(s / 60) + " min ago";
        if (s < 86400) return Math.floor(s / 3600) + " h ago";
        const d = Math.floor(s / 86400);
        return d === 1 ? "Yesterday" : d + " days ago";
    }
    function clipDetail(e) {
        if (e.kind === "image") return "Image" + (e.w ? " · " + e.w + " × " + e.h : "") + " · " + ago(e.time);
        const lines = e.text.replace(/\s+$/, "").split("\n").length;
        return (lines > 1 ? lines + " lines · " : e.text.length > 60 ? e.text.length + " characters · " : "") + ago(e.time);
    }

    // ---- Emoji -------------------------------------------------------------
    // data/emoji.json: [[emoji, name, keywords, category], ...]
    property var emojis: []
    FileView {
        path: Quickshell.shellPath("data/emoji.json")
        blockLoading: true
        onLoaded: { try { root.emojis = JSON.parse(text()); } catch (e) {} }
    }
    property var recent: []
    FileView {
        id: recentFile
        path: root.stateDir + "/emoji.json"
        blockLoading: true
        printErrors: false
        onLoaded: { try { root.recent = JSON.parse(text()).recent || []; } catch (e) {} }
    }
    readonly property var emojiResults: {
        const q = search.text.trim().toLowerCase();
        if (q === "") {
            const first = recent.map(r => emojis.find(e => e[0] === r)).filter(e => e);
            const seen = new Set(recent);
            return first.concat(emojis.filter(e => !seen.has(e[0])));
        }
        const rank = e => {
            const n = e[1].toLowerCase();
            if (n.startsWith(q)) return 0;
            if (n.split(/[\s\-_:]+/).some(w => w.startsWith(q))) return 1;
            if (n.includes(q)) return 2;
            if (e[2].toLowerCase().split(" ").some(w => w.startsWith(q))) return 3;
            if ((e[2] + " " + e[3]).toLowerCase().includes(q)) return 4;
            return -1;
        };
        const r = recent;
        return emojis.map(e => ({ e: e, s: rank(e) })).filter(x => x.s >= 0)
            .sort((a, b) => a.s - b.s || (r.indexOf(b.e[0]) >= 0) - (r.indexOf(a.e[0]) >= 0))
            .map(x => x.e);
    }
    function copyEmoji(e) {
        if (!e) return;
        Quickshell.execDetached(["wl-copy", e[0]]);
        recent = [e[0]].concat(recent.filter(r => r !== e[0])).slice(0, columns * 2);
        recentFile.setText(JSON.stringify({ recent: recent }));
        close();
    }

    // ---- Panel -------------------------------------------------------------
    MouseArea { anchors.fill: parent; enabled: root.shown; onClicked: root.close() }

    Rectangle {
        id: panel
        width: root.panelWidth
        // Shrinks and grows with what's listed, smoothly; the top stays where a full-height
        // panel's would be, so the search box doesn't move
        height: root.fittedHeight
        Behavior on height { enabled: root.shown && root.typed; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - root.panelHeight) / 2)
        radius: 18
        color: root.barColor
        opacity: root.fade
        scale: 0.98 + 0.02 * root.fade
        // Glass: a thin light rim
        border.width: Config.glassShine ? 1 : 0
        border.color: Config.glassEdge
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: !Config.glass
            shadowColor: "#000000"
            shadowOpacity: 0.45
            shadowBlur: 1.0
            shadowVerticalOffset: 8
            blurMax: 48
        }
        transform: Translate { y: -root.dropDistance * (1 - root.fade) }

        MouseArea { anchors.fill: parent }    // clicks inside don't close it

        // ---- Search box ----------------------------------------------------
        Rectangle {
            id: field
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
            height: 44
            radius: 10
            color: root.fieldColor

            Text {
                id: fieldIcon
                anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
                text: String.fromCodePoint(root.mode === "emoji" ? 0xEAF7 : 0xEA6F)    // mood-smile / clipboard
                color: root.dimTextColor
                font.family: root.iconFont
                font.pixelSize: 19
            }
            Text {
                anchors { left: fieldIcon.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: root.mode === "emoji" ? "Search emoji" : "Search clipboard history"
                color: root.dimTextColor
                font.family: root.fontFamily
                font.pixelSize: 15
                font.weight: Font.Medium
                visible: search.text === ""
            }
            TextInput {
                id: search
                anchors { left: fieldIcon.right; right: parent.right; leftMargin: 10; rightMargin: 14; verticalCenter: parent.verticalCenter }
                color: root.textColor
                selectionColor: root.accent
                selectedTextColor: root.barColor
                font.family: root.fontFamily
                font.pixelSize: 15
                font.weight: Font.Medium
                focus: root.shown
                clip: true
                onTextChanged: { root.view().currentIndex = 0; if (root.shown) root.typed = true; }

                Keys.onPressed: event => {
                    const v = root.view();
                    const n = v.count, i = v.currentIndex;
                    const emoji = root.mode === "emoji";
                    const step = emoji ? root.columns : 1;
                    const page = emoji ? root.columns * 4 : 6;
                    switch (event.key) {
                    case Qt.Key_Escape: root.close(); break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        if (emoji) root.copyEmoji(root.emojiResults[i]); else root.copyClip(root.clipResults[i]);
                        break;
                    case Qt.Key_Delete:
                        if (emoji) return;
                        root.deleteClip(root.clipResults[i]);
                        break;
                    case Qt.Key_Left:
                        if (!emoji) return;              // move the text cursor
                        v.currentIndex = Math.max(0, i - 1); break;
                    case Qt.Key_Right:
                        if (!emoji) return;
                        v.currentIndex = Math.min(n - 1, i + 1); break;
                    case Qt.Key_Down: v.currentIndex = Math.min(n - 1, i + step); break;
                    case Qt.Key_Up: v.currentIndex = Math.max(0, i - step); break;
                    case Qt.Key_Tab: v.currentIndex = Math.min(n - 1, i + 1); break;
                    case Qt.Key_Backtab: v.currentIndex = Math.max(0, i - 1); break;
                    case Qt.Key_PageDown: v.currentIndex = Math.min(n - 1, i + page); break;
                    case Qt.Key_PageUp: v.currentIndex = Math.max(0, i - page); break;
                    default: return;
                    }
                    event.accepted = true;
                }
            }
        }

        // Keep the selection on screen: scroll just enough when it moves past an edge
        function follow(v, anim) {
            const it = v.currentItem;
            if (!it) return;
            let to = v.contentY;
            if (it.y < v.contentY) to = it.y;
            else if (it.y + it.height > v.contentY + v.height) to = it.y + it.height - v.height;
            if (to === v.contentY) return;
            anim.stop();
            if (root.slideHighlight) { anim.to = to; anim.start(); } else v.contentY = to;
        }

        // ---- Clipboard list ------------------------------------------------
        ListView {
            id: list
            visible: root.mode === "clipboard"
            anchors { top: field.bottom; left: parent.left; right: parent.right; bottom: footer.top; margins: 14; bottomMargin: 6; rightMargin: 22 }
            clip: true
            model: root.mode === "clipboard" ? root.clipResults : []
            SmoothWheel { flick: list }
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: false
            highlight: Rectangle {
                width: list.width
                height: list.currentItem ? list.currentItem.height : root.rowHeight
                radius: 10
                color: root.selectColor
                y: list.currentItem ? list.currentItem.y : 0
                Behavior on y { enabled: root.slideHighlight; NumberAnimation { duration: root.slideMs; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: root.slideHighlight; NumberAnimation { duration: root.slideMs; easing.type: Easing.OutCubic } }
            }
            NumberAnimation { id: listScroll; target: list; property: "contentY"; duration: root.slideMs; easing.type: Easing.OutCubic }
            onCurrentIndexChanged: panel.follow(list, listScroll)

            delegate: Item {
                id: clipRow
                required property var modelData
                required property int index
                readonly property bool image: modelData.kind === "image"
                width: ListView.view.width
                height: image ? root.imageRowHeight : root.rowHeight

                // Kind of entry, or the picture itself
                Rectangle {
                    id: badge
                    visible: !clipRow.image
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    width: 36; height: 36; radius: 9
                    color: root.fieldColor
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(/^https?:\/\/\S+$/.test(clipRow.modelData.text || "") ? 0xEADE : 0xEA09)   // link / text
                        color: root.dimTextColor
                        font.family: root.iconFont
                        font.pixelSize: 18
                    }
                }
                RoundImage {
                    id: thumb
                    visible: clipRow.image
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    readonly property real ratio: clipRow.modelData.w && clipRow.modelData.h ? clipRow.modelData.w / clipRow.modelData.h : 1.5
                    height: root.imageRowHeight - 16
                    width: Math.min(160, Math.max(48, height * ratio))
                    radius: 8
                    source: clipRow.image ? "file://" + root.clipDir + "/" + clipRow.modelData.file : ""
                }

                Column {
                    anchors { left: clipRow.image ? thumb.right : badge.right; leftMargin: 12; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Text {
                        width: parent.width
                        visible: !clipRow.image
                        text: clipRow.image ? "" : root.preview(clipRow.modelData.text).slice(0, 300)
                        color: root.textColor
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        width: parent.width
                        text: root.clipDetail(clipRow.modelData)
                        color: root.dimTextColor
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: m => {
                        const g = mapToItem(null, m.x, m.y);
                        const last = root.lastPointer;
                        root.lastPointer = Qt.point(g.x, g.y);
                        if (!last || Math.abs(g.x - last.x) + Math.abs(g.y - last.y) < 2) return;
                        if (list.currentIndex !== clipRow.index) list.currentIndex = clipRow.index;
                    }
                    onClicked: root.copyClip(clipRow.modelData)
                }
            }
        }

        // ---- Emoji grid ----------------------------------------------------
        GridView {
            id: grid
            visible: root.mode === "emoji"
            anchors { top: field.bottom; left: parent.left; right: parent.right; bottom: footer.top; margins: 14; bottomMargin: 6; rightMargin: 22 }
            clip: true
            cellWidth: Math.floor(width / root.columns)
            cellHeight: cellWidth
            model: root.mode === "emoji" ? root.emojiResults : []
            SmoothWheel { flick: grid }
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: false
            highlight: Rectangle {
                width: grid.cellWidth; height: grid.cellHeight
                radius: 10
                color: root.selectColor
                x: grid.currentItem ? grid.currentItem.x : 0
                y: grid.currentItem ? grid.currentItem.y : 0
                Behavior on x { enabled: root.slideHighlight; NumberAnimation { duration: root.slideMs; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: root.slideHighlight; NumberAnimation { duration: root.slideMs; easing.type: Easing.OutCubic } }
            }
            NumberAnimation { id: gridScroll; target: grid; property: "contentY"; duration: root.slideMs; easing.type: Easing.OutCubic }
            onCurrentIndexChanged: panel.follow(grid, gridScroll)

            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                width: grid.cellWidth; height: grid.cellHeight
                Text {
                    anchors.centerIn: parent
                    text: cell.modelData[0]
                    font.family: root.emojiFont
                    font.pixelSize: 26
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: m => {
                        const g = mapToItem(null, m.x, m.y);
                        const last = root.lastPointer;
                        root.lastPointer = Qt.point(g.x, g.y);
                        if (!last || Math.abs(g.x - last.x) + Math.abs(g.y - last.y) < 2) return;
                        if (grid.currentIndex !== cell.index) grid.currentIndex = cell.index;
                    }
                    onClicked: root.copyEmoji(cell.modelData)
                }
            }
        }

        // Scrollbar (ThinScrollbar, as everywhere), only when the view overflows
        ThinScrollbar {
            flick: root.view()
            color: root.textColor
            anchors { top: list.top; bottom: list.bottom; left: list.right; leftMargin: 2 }
        }

        Text {
            anchors.centerIn: list
            visible: root.view().count === 0
            text: root.mode === "emoji" ? "No emoji match"
                : search.text !== "" ? "Nothing matches"
                : !Config.s.clipboardHistory ? "Clipboard history is off (Settings → General)"
                : "Nothing copied yet"
            color: root.dimTextColor
            font.family: root.fontFamily
            font.pixelSize: 14
        }

        // ---- Footer: what's selected / keys, and Clear all -----------------
        Item {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 24; rightMargin: 14; bottomMargin: 10 }
            height: 30
            Text {
                anchors { left: parent.left; right: clearBtn.visible ? clearBtn.left : parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                readonly property var sel: root.mode === "emoji" ? root.emojiResults[grid.currentIndex] : null
                text: root.mode === "emoji"
                    ? (sel ? sel[1].charAt(0).toUpperCase() + sel[1].slice(1) + "  ·  Enter to copy" : "")
                    : "Enter to copy  ·  Delete to remove"
                color: root.dimTextColor
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Rectangle {
                id: clearBtn
                visible: root.mode === "clipboard" && root.clips.length > 0
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: clearLabel.implicitWidth + 24; height: 28; radius: 8
                color: clearHover.hovered ? Config.hoverOn(root.fieldColor) : root.fieldColor
                Behavior on color { ColorAnimation { duration: 100 } }
                HoverHandler { id: clearHover }
                TapHandler { onTapped: root.clearClips() }
                Text {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: "Clear all"
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }
        }
    }
}
