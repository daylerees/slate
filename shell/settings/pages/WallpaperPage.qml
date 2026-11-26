import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../.."
import ".."

// ---- Wallpaper (its own page, from Appearance and the desktop's menu) ----------------
Column {
    readonly property var win: SettingsHost.win
    id: wallpaperPane
    spacing: 4
    readonly property string folder: Config.s.wallpaperFolder || (Quickshell.env("HOME") + "/Pictures")
    function setWallpaper(path) { Config.s.wallpaper = path; }
    // Choosing another wallpaper folder (a small folder browser under the Folder row)
    property bool choosingFolder: false
    property string browseDir: ""
    function chooseFolder() { browseDir = folder; choosingFolder = true; }

    PageTitle { text: "Wallpaper" }
    GroupLabel { text: "Your pictures" }
    Group {
        SettingRow {
            label: "Folder"
            detail: wallpaperPane.folder.replace(Quickshell.env("HOME"), "~")
            Row {
                spacing: 8
                Button { icon: 0xFAF7; label: "Open"; onClicked: Quickshell.execDetached(["xdg-open", wallpaperPane.folder]) }
                Button { icon: 0xEAAD; label: "Change…"; onClicked: wallpaperPane.choosingFolder ? wallpaperPane.choosingFolder = false : wallpaperPane.chooseFolder() }
                Button { icon: 0xF000; label: "Random"; primary: true; onClicked: { const all = wallpaperPane.shown.concat(wallpaperPane.slateShown); if (all.length > 0) wallpaperPane.setWallpaper(all[Math.floor(Math.random() * all.length)]); } }
            }
        }
        // Folder browser: go into a folder, then use it
        Column {
            visible: wallpaperPane.choosingFolder
            width: parent.width - 32; x: 16
            spacing: 8
            bottomPadding: 14
            Row {
                width: parent.width
                spacing: 6
                Button {
                    id: upBtn
                    icon: 0xEA25; label: "Up"
                    enabled: wallpaperPane.browseDir !== "/"
                    onClicked: if (wallpaperPane.browseDir !== "/") wallpaperPane.browseDir = wallpaperPane.browseDir.replace(/\/[^\/]*$/, "") || "/"
                }
                Button { id: homeBtn; icon: 0xEAC1; label: "Home"; onClicked: wallpaperPane.browseDir = Quickshell.env("HOME") }
                Text {
                    width: parent.width - upBtn.width - homeBtn.width - 12
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 6
                    textFormat: Text.PlainText        // never markup: a folder's name
                    text: wallpaperPane.browseDir.replace(Quickshell.env("HOME"), "~")
                    color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium
                    elide: Text.ElideMiddle
                }
            }
            Rectangle {
                width: parent.width; height: 220
                radius: Config.corner(8)
                color: win.well
                ListView {
                    id: dirList
                    anchors { fill: parent; margins: 4 }
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    SmoothWheel { flick: dirList }
                    model: FolderListModel {
                        id: dirModel
                        folder: wallpaperPane.choosingFolder ? "file://" + wallpaperPane.browseDir : ""
                        showFiles: false
                        showDirs: true
                        showDotAndDotDot: false
                        showHidden: false
                        sortField: FolderListModel.Name
                    }
                    delegate: Rectangle {
                        required property string fileName
                        required property string filePath
                        width: dirList.width - (dirList.contentHeight > dirList.height ? 12 : 0); height: 32; radius: Config.corner(6)
                        color: dirHover.hovered ? Config.hover : "transparent"
                        Text {
                            id: dirIcon
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: Config.glyph(0xEAAD)
                            color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 16
                        }
                        Text {
                            anchors { left: dirIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            textFormat: Text.PlainText        // never markup: a file's name
                            text: parent.fileName
                            color: win.text; font.family: win.font; font.pixelSize: Config.text(13)
                            elide: Text.ElideRight
                        }
                        HoverHandler { id: dirHover }
                        ClickTap { onTapped: wallpaperPane.browseDir = parent.filePath }
                        // By keyboard: a stop for Tab, Enter or Space does what a click does, with the ring while it has the keyboard
                        activeFocusOnTab: visible && enabled
                        Keys.onPressed: e => { if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { wallpaperPane.browseDir = filePath; e.accepted = true; } }
                        Accessible.role: Accessible.Button
                        Accessible.name: fileName
                        FocusRing { round: 10 }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: dirList.count === 0
                    text: "No folders in here"
                    color: win.dim; font.family: win.font; font.pixelSize: Config.text(12)
                }
                ScrollShade {
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    z: 3; cornerRadius: 8
                    distance: dirList.contentY - dirList.originY
                }
                ScrollShade {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    z: 3; atBottom: true; cornerRadius: 8
                    distance: dirList.originY + dirList.contentHeight - dirList.height - dirList.contentY
                }
                ThinScrollbar {
                    z: 3; flick: dirList; color: win.text
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right; topMargin: 4; bottomMargin: 4; rightMargin: 2 }
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button { label: "Cancel"; onClicked: wallpaperPane.choosingFolder = false }
                Button {
                    label: "Use this folder"; primary: true
                    onClicked: {
                        const home = Quickshell.env("HOME") + "/Pictures";
                        Config.s.wallpaperFolder = wallpaperPane.browseDir === home ? "" : wallpaperPane.browseDir;
                        wallpaperPane.choosingFolder = false;
                    }
                }
            }
        }
        Separator {}
        DropdownSetting {
            label: "Change wallpaper"
            settingKey: "wallpaperChange"
            detail: (Config.s.wallpaperChange === "off"
                    ? "Keep the one you pick"
                    : "Switch to another image from this folder" + (Config.s.wallpaperShowSlate ? " or Slate's own" : "") + ", in a shuffled order")
                + (Config.s.wallpaperChange !== "off" && !Config.s.accentFromWallpaper && !Config.s.toneFromWallpaper
                    ? ". Turn on the accent or tint from the wallpaper (above) for the theme to change with it" : "")
            options: [
                { value: "off", label: "Never" },
                { value: "login", label: "At each login" },
                { value: "15", label: "Every 15 minutes" },
                { value: "30", label: "Every 30 minutes" },
                { value: "60", label: "Every hour" },
                { value: "180", label: "Every 3 hours" },
                { value: "1440", label: "Every day" }
            ]
            value: Config.s.wallpaperChange
            onPicked: v => Config.s.wallpaperChange = v
        }
        Separator {}
        ToggleSetting {
            label: "Slate's wallpapers"
            detail: "Show the wallpapers that come with Slate below your own, and include them in Random and when the wallpaper changes by itself"
            key: "wallpaperShowSlate"
        }
        Separator {}
        ToggleSetting {
            label: "Hide small images"
            detail: "Leave out pictures too small to be wallpapers, like icons, avatars and small screenshots"
            key: "wallpaperHideSmall"
        }
        Separator { visible: Config.s.wallpaperHideSmall }
        DropdownSetting {
            visible: Config.s.wallpaperHideSmall
            label: "Smallest size"
            settingKey: "wallpaperMinSize"
            detail: "Images narrower or shorter than this are hidden"
            options: [{ value: "320x240", label: "320 × 240" }, { value: "640x480", label: "640 × 480" }, { value: "800x600", label: "800 × 600" }, { value: "1024x768", label: "1024 × 768" }, { value: "1280x720", label: "1280 × 720" }, { value: "1920x1080", label: "1920 × 1080" }, { value: "2560x1440", label: "2560 × 1440" }]
            value: Config.s.wallpaperMinSize
            onPicked: v => Config.s.wallpaperMinSize = v
        }
    }
    // ---- Hiding small images: each image's size, read from its file (scripts/image-sizes.py)
    property var sizes: ({})
    readonly property var minSize: Config.s.wallpaperMinSize.split("x").map(Number)
    function tooSmall(name) {
        const sz = sizes[name];
        return Config.s.wallpaperHideSmall && !!sz && (sz[0] < minSize[0] || sz[1] < minSize[1]);
    }
    Process {
        id: sizeReader
        command: [Quickshell.shellPath("scripts/image-sizes.py"), wallpaperPane.folder]
        stdout: StdioCollector { onStreamFinished: { try { wallpaperPane.sizes = JSON.parse(text); } catch (e) {} } }
    }
    // Read the sizes when the page opens and when the folder's contents change. Both happen
    // together as the page opens (the folder's listing arrives just after), so they're
    // gathered into one read rather than starting the script and stopping it straight away.
    Timer { id: sizesSoon; interval: 250; onTriggered: { sizeReader.running = false; sizeReader.running = true; } }
    Connections { target: wallFiles; function onCountChanged() { sizesSoon.restart(); } }
    Component.onCompleted: sizesSoon.restart()
    readonly property var shown: {
        const out = [];
        for (let i = 0; i < wallFiles.count; i++) {
            const n = wallFiles.get(i, "fileName");
            if (!tooSmall(n)) out.push(wallFiles.get(i, "filePath"));
        }
        return out;
    }
    readonly property int hidden: wallFiles.count - shown.length

    GroupLabel {
        text: wallpaperPane.shown.length + (wallpaperPane.shown.length === 1 ? " image" : " images")
            + (wallpaperPane.hidden > 0 ? " · " + wallpaperPane.hidden + " small " + (wallpaperPane.hidden === 1 ? "one" : "ones") + " hidden" : "")
    }
    FolderListModel {
        id: wallFiles
        folder: "file://" + wallpaperPane.folder
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.JPG", "*.JPEG", "*.PNG"]
        showDirs: false
        sortField: FolderListModel.Name
    }
    Text {
        visible: wallFiles.count === 0
        text: "No pictures in this folder yet. Pop some in, or choose another folder above"
        color: win.dim; font.family: win.font; font.pixelSize: Config.text(13)
        leftPadding: 4
    }
    // Thumbnails; click one to use it
    Grid {
        id: wallGrid
        width: parent.width
        columns: 3
        spacing: 12
        readonly property real tileW: (width - spacing * (columns - 1)) / columns
        Repeater {
            model: wallFiles
            delegate: WallTile {
                tileW: wallGrid.tileW
                small: wallpaperPane.tooSmall(fileName)
                onPicked: wallpaperPane.setWallpaper(filePath)
            }
        }
    }
    // The wallpapers that come with Slate (shell/wallpapers, made by tools/make-wallpapers.py),
    // below your own: Settings → Wallpaper → Slate's wallpapers switches them off
    FolderListModel {
        id: slateFiles
        folder: Config.s.wallpaperShowSlate ? "file://" + Quickshell.shellPath("wallpapers") : ""
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Name
    }
    // (for the tests: the folders still being read count as loading, their tiles to come)
    Binding {
        target: win; property: "wallsListing"
        value: wallFiles.status === FolderListModel.Loading || slateFiles.status === FolderListModel.Loading
    }
    readonly property var slateShown: {
        const out = [];
        if (Config.s.wallpaperShowSlate) for (let i = 0; i < slateFiles.count; i++) out.push(slateFiles.get(i, "filePath"));
        return out;
    }
    GroupLabel { visible: wallpaperPane.slateShown.length > 0; text: "From Slate" }
    Grid {
        id: slateGrid
        visible: wallpaperPane.slateShown.length > 0
        width: parent.width
        columns: 3
        spacing: 12
        readonly property real tileW: (width - spacing * (columns - 1)) / columns
        Repeater {
            model: Config.s.wallpaperShowSlate ? slateFiles : null
            delegate: WallTile {
                tileW: slateGrid.tileW
                title: Config.wallpaperName(filePath)     // ("slate-ember.png" → "Ember")
                onPicked: wallpaperPane.setWallpaper(filePath)
            }
        }
    }
}
