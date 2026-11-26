import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import ".."

// ---- Icons (its own page, from Appearance): the icon theme, folder colours, app icons ----
Column {
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "Icons" }
    GroupLabel { text: "Icon theme" }
    Group {
        // The icon theme: every app's icons, and Slate's own tiles (scripts/icon-themes.py
        // lists them; shell.qml sets the one chosen for GTK, Qt and KDE apps)
        DropdownSetting {
            id: iconThemeSet
            // (SettingsLookups.qml: read once, kept for the next time the page opens)
            readonly property var themes: SettingsLookups.iconThemes
            function look() { SettingsLookups.refreshThemes("icons"); }
            Component.onCompleted: SettingsLookups.wantThemes("icons")
            label: "Icons"
            settingKey: "iconTheme"
            detail: Config.s.iconTheme !== "" && !themes.some(t => t.id === Config.s.iconTheme) && themes.length > 0
                ? "The icon theme chosen here isn't installed any more, so apps use this computer's own. Choose another whenever you like"
                : "The icons in your apps, and on Slate's dock, launcher and bar. Apps already open pick them up as they can; Slate redraws its own in a moment"
            // ("This computer's": the theme it had before one was chosen here, put back)
            // The default: the theme this computer had before one was chosen here (put back
            // when it's picked), listed by its name, and not again among the rest
            readonly property string own: Config.s.iconThemeBefore || Config.gtkIconTheme
            readonly property var ownTheme: themes.find(t => t.id === own) ?? null
            options: [{ value: "", label: (ownTheme ? ownTheme.name : own !== "" ? own : "This computer's") + " (default)" }]
                .concat(themes.filter(t => t.id !== own).map(t => ({ value: t.id, label: t.name })))
            value: Config.s.iconTheme !== own && themes.some(t => t.id === Config.s.iconTheme) ? Config.s.iconTheme : ""
            onPicked: v => {
                // (the first choice remembers what this computer had, to go back to)
                if (Config.s.iconTheme === "" && v !== "" && Config.s.iconThemeBefore === "") Config.s.iconThemeBefore = Config.gtkIconTheme;
                Config.s.iconTheme = v;
            }
        }
        Separator {}
        // Folder colour for file managers: Papirus's coloured folders (scripts/folder-colour.py)
        Column {
            id: folderSet
            width: parent.width
            property var info: ({ supported: true, base: "", colours: [] })
            Process {
                id: folderList
                running: true
                command: [Quickshell.shellPath("scripts/folder-colour.py"), "--list"]
                stdout: StdioCollector { onStreamFinished: { try { folderSet.info = JSON.parse(text); } catch (e) {} } }
            }
            // (looked at again once a new icon theme is in: it decides whether there are coloured folders)
            Connections { target: Config.s; function onIconThemeChanged() { folderRelist.restart(); } }
            Timer { id: folderRelist; interval: 2500; onTriggered: { folderList.running = false; folderList.running = true; } }
            readonly property var names: ({ adwaita: "Adwaita blue", bluegrey: "Blue gray", breeze: "Breeze blue",
                darkcyan: "Dark cyan", deeporange: "Deep orange", palebrown: "Pale brown", paleorange: "Pale orange" })
            function nice(n) { return names[n] || (n.charAt(0).toUpperCase() + n.slice(1)); }
            readonly property var colours: folderSet.info.colours || []
            function hexOf(name) { const c = colours.find(x => x.name === name); return c ? c.hex : ""; }
            // Auto: the Papirus colour closest to the wallpaper's, picked as folder-colour.py
            // does (nearest()): by hue for colourful ones, else a grey
            readonly property string autoHex: {
                const a = Config.wallpaperAccent ? Qt.color(Config.wallpaperAccent) : null;
                if (!a || colours.length === 0) return hexOf("blue") || "#5294e2";
                const greys = ["black", "grey", "white", "bluegrey"];
                const hue = c => Math.max(0, c.hslHue);
                const grey = a.hslSaturation < 0.18;
                let best = "", d = 1e9;
                for (const c of colours) {
                    if (c.name === "yaru" || greys.includes(c.name) !== grey) continue;
                    const k = Qt.color(c.hex);
                    const dh0 = Math.abs(hue(k) - hue(a)), dh = Math.min(dh0, 1 - dh0);
                    const e = dh * 4 + Math.abs(k.hslLightness - a.hslLightness) * 0.25 + Math.abs(k.hslSaturation - a.hslSaturation) * 0.15;
                    if (e < d) { d = e; best = c.hex; }
                }
                return best || hexOf("blue") || "#5294e2";
            }
            SettingRow {
                visible: !folderSet.info.supported
                label: "Folder color"
                detail: "Folders in Nautilus, Dolphin and other file managers. Needs icons with folders in colors, like Papirus, Kora or Nordzy (yours are " + folderSet.info.base + ")"
            }
            DropdownSetting {
                visible: folderSet.info.supported
                label: "Folder color"
                settingKey: "folderColour"
                detail: "Folders in Nautilus, Dolphin and other file managers" + (Config.s.folderColour === "auto" ? ", in the color closest to the wallpaper's" : "")
                options: [{ value: "auto", label: "From the wallpaper", folder: folderSet.autoHex },
                          { value: "default", label: "Theme's own", folder: folderSet.hexOf("blue") || "#5294e2" }]
                    .concat(folderSet.colours.map(c => ({ value: c.name, label: folderSet.nice(c.name), folder: c.hex })))
                value: Config.s.folderColour === "" ? "default" : Config.s.folderColour
                onPicked: v => Config.s.folderColour = v
            }
        }
    }
    GroupLabel { text: "App icons" }
    Group {
        id: iconGroup
        // One of your apps drawn in each shape, filled and whole (scripts/appicon.py --preview)
        readonly property string previewDir: Quickshell.env("HOME") + "/.cache/slate/tiles/preview"
        property int previewVersion: 0
        // (a first look, counted while it draws: a picture of the page taken sooner showed the
        // tiles before their colour, on a busy computer)
        FirstLook {
            running: true
            command: [Config.tileScript, "--preview", iconGroup.previewDir, "96"]
            onExited: { iconGroup.previewVersion++; previewColourFile.reload(); }
        }
        // The previewed icon's main colour, so its tile shows Tiles in the icon's colour too (read
        // at once as the preview's done, so it's there by the time the page counts as looked)
        FileView { id: previewColourFile; path: iconGroup.previewDir + "/colour.txt"; printErrors: false; blockLoading: true }
        readonly property var previewShade: Config.iconTileShadeOf(previewColourFile.text().trim())
        SettingRow {
            label: "Shape"
            settingKey: "iconShape"
            defaultText: "Tile"
            detail: "For app icons in the dock, launcher, switcher, bar and notifications"
        }
        Flow {
            width: parent.width - 32; x: 16
            spacing: 8
            bottomPadding: 14
            Repeater {
                model: [{ value: "tile", label: "Tile" }, { value: "squircle", label: "Squircle" }, { value: "circle", label: "Circle" },
                        { value: "square", label: "Square" }, { value: "original", label: "Original" }]
                delegate: Rectangle {
                    id: shapeCard
                    required property var modelData
                    readonly property bool on: Config.s.iconShape === modelData.value
                    width: 92; height: 96; radius: Config.corner(12)
                    color: on ? win.accent : "transparent"
                    HoverFill { base: win.well; hovered: shapeHover.hovered; gone: on; radius: parent.radius }
                    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                    // Shown as every App icons setting has it: the shape, Fill the shape, Tiles
                    // in the icon's colour, and Tint app icons (and its strength); with glass,
                    // see-through tiles and the sheen, as in the dock
                    Image {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
                        width: 48; height: 48
                        sourceSize: Qt.size(96, 96)
                        cache: false
                        source: iconGroup.previewVersion > 0
                            ? "file://" + iconGroup.previewDir + "/" + shapeCard.modelData.value + (Config.s.iconFill ? "-fill" : "-whole") + ".png?v=" + iconGroup.previewVersion
                            : ""
                        layer.enabled: Config.iconTint > 0; layer.effect: IconTint {}
                        IconPlate {
                            anchors.fill: parent; z: -1; shape: shapeCard.modelData.value
                            color: iconGroup.previewShade ?? Config.iconPlateColor
                            shaded: iconGroup.previewShade !== null
                        }
                        // Glass: the sheen the dock puts on its icons, rounded to this shape
                        Gloss {
                            glassHint: true
                            visible: Config.glassGloss && shapeCard.modelData.value !== "original"
                            radius: { const v = shapeCard.modelData.value, w = parent.width;
                                      return v === "circle" ? w / 2 : v === "square" ? 0 : v === "squircle" ? w * 0.3 : w * 0.225; }
                        }
                    }
                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                        text: shapeCard.modelData.label
                        color: shapeCard.on ? win.accentText : win.dim
                        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                        font.family: win.font; font.pixelSize: Config.text(12); font.weight: Font.Medium
                    }
                    HoverHandler { id: shapeHover }
                    ClickTap { onTapped: Config.s.iconShape = shapeCard.modelData.value }
                    // By keyboard: a stop for Tab, Enter or Space does what a click does, with the ring while it has the keyboard
                    activeFocusOnTab: visible && enabled
                    Keys.onPressed: e => { if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { Config.s.iconShape = shapeCard.modelData.value; e.accepted = true; } }
                    Accessible.role: Accessible.Button
                    Accessible.name: shapeCard.modelData.label
                    FocusRing { round: 10 }
                }
            }
        }
        Separator {}
        SettingRow {
            label: "Fill the shape"
            settingKey: "iconFill"
            detail: Config.s.iconShape === "original"
                ? "Trim icons' empty margins and theme shadows so they're all the same size. Off: exactly as the apps ship them"
                : "Crop each icon's own border and shadow and grow it to fill the shape, on its main color. Off: the whole icon, smaller, on a plain tile"
            SettingToggle { checked: Config.s.iconFill; onToggled: v => Config.s.iconFill = v }
        }
        Separator {}
        SettingRow {
            // Only for icons on a tile: filled icons and original ones have none
            needsMet: !Config.s.iconFill && Config.s.iconShape !== "original"
            needs: Config.s.iconShape === "original" ? "Needs a Shape other than Original" : "Needs Fill the shape to be off"
            needsPage: "icons"; needsLabel: Config.s.iconShape === "original" ? "Shape" : "Fill the shape"
            label: "Tiles in the icon's color"
            settingKey: "iconTileColour"
            detail: "The tile behind each icon takes a deep shade of the icon's own main color, rather than the theme's. Gray and white icons get a plain gray tile"
            SettingToggle { checked: Config.s.iconTileColour; onToggled: v => Config.s.iconTileColour = v }
        }
        Separator {}
        ToggleSetting {
            label: "Tint app icons"
            detail: "Color app icons in the dock, launcher, switcher, bar and notifications with the accent color"
            key: "tintIcons"
        }
        Separator { visible: Config.s.tintIcons }
        SettingRow {
            visible: Config.s.tintIcons
            label: "Tint strength"
            settingKey: "iconTintStrength"
            detail: "A light wash of color, up to icons drawn entirely in the accent"
            ValueSlider { from: 20; to: 100; stepSize: 5; suffix: "%"; value: Config.s.iconTintStrength; onMoved: v => Config.s.iconTintStrength = v }
        }
    }
    GroupLabel { text: "More icon styles" }
    ThemePacks { kind: "icons"; chooseIn: "Icon theme"; onInstalled: iconThemeSet.look() }
}
