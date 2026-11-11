// Choosing your account picture (Settings → General → Change picture, or the control centre's
// picture): a window of its own, with places down the side (Pictures, Downloads, Desktop…),
// folders to browse, a grid of your images, and a round preview of the one you've picked, as
// it'll look. Config.setAvatar() does the rest (scripts/set-avatar.sh).
//   AvatarPicker { id: picker; bar: … }   then   picker.open()
// Hyprland floats and centres it by its title (session/hypr/config/windowrules.lua).

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

FloatingWindow {
    id: pk
    required property var bar

    title: "Choose a picture"
    visible: false
    // 860×580, or less on a small screen (as Settings fits itself)
    readonly property var fitScreen: Config.focusedScreen
    implicitWidth: Math.round(fitScreen ? Math.min(860, fitScreen.width * 0.9) : 860)
    implicitHeight: Math.round(fitScreen ? Math.min(580, (fitScreen.height - 60) * 0.9) : 580)
    minimumSize: Qt.size(Math.min(620, implicitWidth), Math.min(420, implicitHeight))
    color: bar.barColor

    // ---- Look (as Settings) --------------------------------------------------
    readonly property color text: bar.textColor
    readonly property color dim: Config.tint("#8b94a3")
    readonly property color accent: bar.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color panel: Config.tint("#151920")
    readonly property string font: bar.fontFamily
    readonly property string iconFont: bar.iconFont
    function glyph(c) { return String.fromCodePoint(c); }
    readonly property string home: Quickshell.env("HOME")
    function nicePath(p) { return p === home ? "Home" : p.startsWith(home + "/") ? "~" + p.slice(home.length) : p; }

    // ---- Where it is, and what's picked -----------------------------------------
    property string folder: home + "/Pictures"
    property string chosen: ""             // the picked image's path
    function open() {
        chosen = "";
        placesRun.running = true;
        visible = true;
        grid.forceActiveFocus();
    }
    function go(path) {
        if (!path) return;
        folder = path;
        chosen = "";
        grid.currentIndex = -1;
        grid.positionViewAtBeginning();
    }
    function up() {
        if (folder === "/") return;
        const i = folder.lastIndexOf("/");
        go(i <= 0 ? "/" : folder.slice(0, i));
    }
    function use() {
        if (!chosen) return;
        Config.setAvatar(chosen);
        visible = false;
    }
    function activate(i) {
        if (i < 0 || i >= files.count) return;
        if (files.get(i, "fileIsDir")) go(files.get(i, "filePath"));
        else { chosen = files.get(i, "filePath"); use(); }
    }

    // ---- Places: your picture folders and the usual ones, where they exist ------
    property var places: []
    Process {
        id: placesRun
        // label<TAB>path for each that exists (XDG folders where set, else the usual names)
        command: ["sh", "-c", [
            'ud() { p=$(xdg-user-dir "$1" 2>/dev/null); [ -n "$p" ] && [ "$p" != "$HOME" ] && echo "$p" || echo "$HOME/$2"; }',
            'pics=$(ud PICTURES Pictures)',
            'for e in "Pictures	$pics" "Camera	$pics/Camera" "Screenshots	$pics/Screenshots" "Wallpapers	$pics/Wallpapers" "Wallpapers	$1" ' +
                '"Downloads	$(ud DOWNLOAD Downloads)" "Desktop	$(ud DESKTOP Desktop)" "Documents	$(ud DOCUMENTS Documents)" "Home	$HOME"; do',
            '  d=${e#*	}; [ -n "$d" ] && [ -d "$d" ] && printf "%s\\n" "$e"',
            'done'
        ].join("\n"), "sh", Config.s.wallpaperFolder || ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, list = [];
                for (const l of text.split("\n")) {
                    const t = l.indexOf("\t");
                    if (t < 0) continue;
                    const p = { label: l.slice(0, t), path: l.slice(t + 1) };
                    if (seen[p.path]) continue;
                    seen[p.path] = true;
                    list.push(p);
                }
                pk.places = list;
            }
        }
    }

    FolderListModel {
        id: files
        folder: "file://" + pk.folder
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.JPG", "*.JPEG", "*.PNG", "*.WEBP"]
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
        sortField: FolderListModel.Time    // newest first
    }

    Shortcut { sequences: [StandardKey.Cancel]; onActivated: pk.visible = false }
    Shortcut { sequences: ["Backspace", "Alt+Up"]; onActivated: pk.up() }

    // ---- Places, down the side ---------------------------------------------------
    Rectangle {
        id: side
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: 190
        color: "transparent"
        Column {
            anchors { fill: parent; margins: 14; topMargin: 18 }
            spacing: 4
            Text {
                text: "Choose a picture"
                color: pk.text; font.family: pk.font; font.pixelSize: 17; font.weight: Font.Medium
                bottomPadding: 12; leftPadding: 6
            }
            Repeater {
                model: pk.places
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: pk.folder === modelData.path
                    width: parent.width; height: 36; radius: 9
                    color: on ? Config.raised(Config.tint("#1d222a")) : placeHover.hovered ? Config.hover : "transparent"
                    Gloss { radius: parent.radius; opacity: (on || placeHover.hovered) ? 1 : 0 }
                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: pk.glyph(({ Pictures: 0xEB0A, Camera: 0xEA54, Screenshots: 0xF201, Wallpapers: 0xEB0A, Downloads: 0xEA96,
                                              Desktop: 0xEA89, Documents: 0xEAA2, Home: 0xEAC1 })[parent.parent.modelData.label] || 0xEAAD)
                            color: parent.parent.on ? pk.accent : pk.dim
                            font.family: pk.iconFont; font.pixelSize: 16
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.parent.modelData.label
                            color: pk.text; font.family: pk.font; font.pixelSize: 13; font.weight: Font.Medium
                        }
                    }
                    HoverHandler { id: placeHover }
                    ClickTap { onTapped: pk.go(parent.modelData.path) }
                }
            }
        }
    }

    // ---- The folder: where you are, then its folders and images ---------------------
    Rectangle {
        id: main
        anchors { top: parent.top; bottom: parent.bottom; left: side.right; right: preview.left; topMargin: 10; bottomMargin: 10 }
        radius: 14
        color: pk.panel
        // Up, and where you are
        Item {
            id: crumbs
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 10 }
            height: 34
            Rectangle {
                id: upBtn
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: 34; height: 34; radius: 17
                opacity: pk.folder === "/" ? 0.35 : 1
                color: upHover.hovered ? Config.hover : "transparent"
                Text { anchors.centerIn: parent; text: pk.glyph(0xEA19); color: upHover.hovered ? pk.text : pk.dim; font.family: pk.iconFont; font.pixelSize: 18 }
                HoverHandler { id: upHover }
                ClickTap { onTapped: pk.up() }
            }
            Text {
                anchors { left: upBtn.right; leftMargin: 8; right: parent.right; verticalCenter: parent.verticalCenter }
                text: pk.nicePath(pk.folder)
                color: pk.text; font.family: pk.font; font.pixelSize: 13; font.weight: Font.Medium
                elide: Text.ElideMiddle
            }
        }
        Text {
            visible: files.status === FolderListModel.Ready && files.count === 0
            anchors.centerIn: parent
            text: "No pictures or folders here. Try another place on the left"
            color: pk.dim; font.family: pk.font; font.pixelSize: 13
        }
        GridView {
            id: grid
            anchors { top: crumbs.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; margins: 10; topMargin: 6; rightMargin: 2 }
            clip: true
            focus: true
            currentIndex: -1
            boundsBehavior: Flickable.StopAtBounds
            readonly property int cols: Math.max(1, Math.floor((width - 10) / 132))
            cellWidth: Math.floor((width - 10) / cols)
            cellHeight: cellWidth + 22
            model: files
            SmoothWheel { flick: grid }
            keyNavigationEnabled: true
            onCurrentIndexChanged: if (currentIndex >= 0 && !files.get(currentIndex, "fileIsDir")) pk.chosen = files.get(currentIndex, "filePath")
            Keys.onReturnPressed: pk.activate(currentIndex)
            Keys.onEnterPressed: pk.activate(currentIndex)
            delegate: Item {
                id: cell
                required property int index
                required property string filePath
                required property string fileName
                required property bool fileIsDir
                readonly property bool picked: !fileIsDir && pk.chosen === filePath
                width: grid.cellWidth; height: grid.cellHeight
                Rectangle {
                    id: frame
                    anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 4 }
                    width: parent.width - 12; height: width
                    radius: 12
                    color: cell.fileIsDir ? (cellHover.hovered ? Config.hover : "transparent") : Config.raised(Config.tint("#1d222a"))
                    border.width: cell.picked ? 2 : 0
                    border.color: pk.accent
                    // Folders: a folder icon
                    Text {
                        visible: cell.fileIsDir
                        anchors.centerIn: parent
                        text: pk.glyph(0xEAAD)
                        color: cellHover.hovered ? pk.text : pk.dim
                        font.family: pk.iconFont; font.pixelSize: Math.round(parent.width * 0.5)
                    }
                    // Images: the picture, cropped square, rounded
                    Item {
                        visible: !cell.fileIsDir
                        anchors { fill: parent; margins: cell.picked ? 4 : 0 }
                        Behavior on anchors.margins { NumberAnimation { duration: Config.ms(100) } }
                        layer.enabled: true
                        layer.effect: MultiEffect { maskEnabled: true; maskSource: thumbMask }
                        Image {
                            anchors.fill: parent
                            source: cell.fileIsDir ? "" : "file://" + cell.filePath
                            sourceSize: Qt.size(240, 240)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
                        }
                        Item {
                            id: thumbMask
                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            Rectangle { anchors.fill: parent; radius: cell.picked ? 9 : 12 }
                        }
                    }
                    // Pointed at: a light wash over a picture
                    Rectangle {
                        visible: !cell.fileIsDir
                        anchors.fill: parent; radius: parent.radius
                        color: "white"
                        opacity: cellHover.hovered && !cell.picked ? 0.08 : 0
                        Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
                    }
                }
                Text {
                    anchors { top: frame.bottom; topMargin: 4; left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6 }
                    horizontalAlignment: Text.AlignHCenter
                    text: cell.fileName
                    color: cell.picked ? pk.text : pk.dim
                    font.family: pk.font; font.pixelSize: 11; font.weight: cell.picked ? Font.Medium : Font.Normal
                    elide: Text.ElideMiddle
                }
                HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                // Folder: open it. Picture: pick it (twice: use it)
                ClickTap {
                    onTapped: {
                        grid.currentIndex = cell.index;
                        if (cell.fileIsDir) pk.go(cell.filePath);
                        else pk.chosen = cell.filePath;
                    }
                    onDoubleTapped: if (!cell.fileIsDir) { pk.chosen = cell.filePath; pk.use(); }
                }
            }
        }
        ThinScrollbar {
            flick: grid
            color: pk.text
            anchors { top: grid.top; bottom: grid.bottom; right: parent.right; rightMargin: 2 }
        }
    }

    // ---- The picked picture, as it'll look, and the buttons -------------------------
    Item {
        id: preview
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 230
        Column {
            anchors { top: parent.top; topMargin: 44; horizontalCenter: parent.horizontalCenter }
            spacing: 14
            // Round, as your account picture shows
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 156; height: 156; radius: 78
                color: Config.raised(Config.tint("#1d222a"))
                Gloss { radius: parent.radius }   // glass: a sheen, as on the bar's containers
                border.width: 1; border.color: Config.tint("#2a313c")
                Text {
                    visible: pk.chosen === ""
                    anchors.centerIn: parent
                    text: pk.glyph(0xEF68)          // user
                    color: pk.dim; font.family: pk.iconFont; font.pixelSize: 64
                }
                RoundImage {
                    visible: pk.chosen !== ""
                    anchors { fill: parent; margins: 3 }
                    radius: width / 2
                    source: pk.chosen ? "file://" + pk.chosen : ""
                }
            }
            Text {
                width: 190
                horizontalAlignment: Text.AlignHCenter
                text: pk.chosen ? pk.chosen.slice(pk.chosen.lastIndexOf("/") + 1) : "Pick a picture"
                color: pk.chosen ? pk.text : pk.dim
                font.family: pk.font; font.pixelSize: 12; font.weight: Font.Medium
                elide: Text.ElideMiddle
            }
            Text {
                width: 190
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "Shown on the lock and login screens and in the control centre. It's cropped to a circle from the middle."
                color: pk.dim; font.family: pk.font; font.pixelSize: 11
            }
        }
        Row {
            anchors { bottom: parent.bottom; bottomMargin: 18; horizontalCenter: parent.horizontalCenter }
            spacing: 8
            Rectangle {
                width: cancelText.implicitWidth + 28; height: 34; radius: 9
                color: cancelHover.hovered ? Config.hoverOn(Config.raised(Config.tint("#2a313c"))) : Config.raised(Config.tint("#2a313c"))
                Text { id: cancelText; anchors.centerIn: parent; text: "Cancel"; color: pk.text; font.family: pk.font; font.pixelSize: 12; font.weight: Font.Medium }
                HoverHandler { id: cancelHover }
                ClickTap { onTapped: pk.visible = false }
            }
            Rectangle {
                width: useText.implicitWidth + 28; height: 34; radius: 9
                opacity: pk.chosen ? 1 : 0.45
                color: useHover.hovered && pk.chosen ? Qt.lighter(pk.accent, 1.08) : pk.accent
                Text { id: useText; anchors.centerIn: parent; text: "Use picture"; color: pk.accentText; font.family: pk.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                HoverHandler { id: useHover }
                ClickTap { onTapped: pk.use() }
            }
        }
    }
}
