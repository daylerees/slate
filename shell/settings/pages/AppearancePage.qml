import QtQuick
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    id: appearancePane
    spacing: 4
    PageTitle { text: "Appearance" }
    // The look's own pages, first: what's on them now, and a button to go there
    GroupLabel { text: "Wallpaper, icons and apps" }
    Group {
        SettingRow {
            label: "Wallpaper"
            detail: "Your desktop picture, from your own folder or Slate's, and changing it by itself"
            Button { label: "Open"; onClicked: win.goTo("wallpaper", "") }
        }
        Separator {}
        SettingRow {
            label: "Icons"
            detail: "The icon theme, folder colors, the shape of app icons, and more icon styles to add"
            Button { label: "Open"; onClicked: win.goTo("icons", "") }
        }
        Separator {}
        SettingRow {
            label: "App Theming"
            readonly property int count: (Config.s.themedApps || []).length
            detail: "Terminals, editors, GTK, Qt and more following Slate's colors and accent · "
                + (count === 0 ? "none switched on" : count + (count === 1 ? " app" : " apps") + " themed")
            Button { label: "Open"; onClicked: win.goTo("apptheming", "") }
        }
    }
    GroupLabel { text: "Preset" }
    // ---- Presets: theme, colour and glass in one go (asks first) --------------------
    Group {
        DropdownSetting {
            label: "Preset"
            detail: "A quick way to a finished look, if you'd rather not fine-tune every setting: sets the theme, colors, glass and folder colors below in one go. Your wallpaper and other settings stay as they are"
            // Reads "Custom" while the settings don't match a preset; that's not something to
            // pick, so it isn't in the list
            readonly property var match: win.themePresets.find(p => win.presetActive(p)) ?? null
            options: win.themePresets.map(p => ({ value: p.name, label: p.name }))
            noneLabel: "Custom"
            value: match ? match.name : ""
            onPicked: v => {
                const p = win.themePresets.find(x => x.name === v);
                if (!p || win.presetActive(p)) return;
                win.askQuestion({
                    title: "Apply " + p.name + "?",
                    body: "This gives you a fresh look: it changes the theme, colors, glass and folder colors. "
                        + "Your wallpaper stays as it is, and so does everything else.",
                    button: "Apply", code: 0xEB01,
                    run: () => win.applyPreset(p)
                });
            }
        }
    }
    GroupLabel { text: "Theme & color" }
    Group {
        SettingRow {
            label: "Theme"
            detail: {
                if (Config.themeMode !== "auto") return "Dark is the default; light flips the bar, panels and windows to light backgrounds with dark text";
                const h = Config.lightHours(new Date());
                return "Auto: light from " + Config.clockText(h.from) + " to " + Config.clockText(h.to)
                    + (Config.s.locationName !== "" ? " (sunrise to sunset in " + Config.s.locationName + ")" : " (set a location below to follow sunrise and sunset)");
            }
            // Three-way switch: Dark | Light | Auto
            SegmentedChoice {
                options: [{ value: "dark", label: "Dark", icon: 0xEAF8 }, { value: "light", label: "Light", icon: 0xEB30 }, { value: "auto", label: "Auto", icon: 0xF4A3 }]
                value: Config.themeMode
                onPicked: v => win.pickThemeMode(v)
            }
        }
        Separator {}
        DropdownSetting {
            label: "Color"
            settingKey: "colourStyle"
            detail: Config.colourful ? "More variety of color: soft pastels, like each Settings page in its own color"
                : "The accent color and grays throughout"
            options: [{ value: "monotone", label: "Monotone" }, { value: "colourful", label: "Colorful" }]
            value: Config.s.colourStyle || "colourful"
            onPicked: v => Config.s.colourStyle = v
        }
        Separator {}
        SettingRow {
            label: "Accent color from wallpaper"
            settingKey: "accentFromWallpaper"
            detail: "Highlights (switches, sliders, selected items, the active workspace dot) use a bright color picked from the wallpaper. Off: the color chosen below"
            Row {
                spacing: 12
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: Config.corner(12)
                    color: Config.wallpaperAccent ? Config.fromWallpaper(Config.wallpaperAccent) : "transparent"
                    border.width: 1; border.color: win.ring
                }
                SettingToggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.s.accentFromWallpaper; onToggled: v => Config.s.accentFromWallpaper = v }
            }
        }
        Separator {}
        SettingRow {
            // Only for the wallpaper's colour
            needsMet: Config.s.accentFromWallpaper
            needs: "Needs Accent color from wallpaper to be on"
            needsPage: "appearance"; needsLabel: "Accent color from wallpaper"
            label: "Accent boldness"
            settingKey: "accentBoldness"
            detail: "How vivid the wallpaper's color is: from soft, as picked, to bold. Text on it stays readable"
            ValueSlider {
                per: 100
                from: 0; to: 100; stepSize: 5; suffix: "%"
                value: Math.round((Config.s.accentBoldness || 0) * 100)
                onMoved: v => Config.s.accentBoldness = v / 100
            }
        }
        Separator {}
        Column {
            width: parent.width
            // Only for a colour of your own
            SettingRow {
                needsMet: !Config.s.accentFromWallpaper
                needs: "Needs Accent color from wallpaper to be off"
                needsPage: "appearance"; needsLabel: "Accent color from wallpaper"
                label: "Accent color"
                settingKey: "accent"
                detail: "Used for highlights across the bar, dock, launcher and panels"
                Row {
                    spacing: 8
                    Repeater {
                        model: ["#8fb3e8", "#7fc4c0", "#9ad3a6", "#e8c48f", "#e8a6b5", "#b9a6e8", "#eef1f5"]
                        delegate: Rectangle {
                            required property string modelData
                            width: 24; height: 24; radius: Config.corner(12)
                            color: Config.accentShade(modelData)      // as it'll look (deeper in light mode)
                            border.width: Config.s.accent.toLowerCase() === modelData ? 2 : 0
                            border.color: win.text
                            scale: swHover.hovered ? 1.12 : 1
                            Behavior on scale { NumberAnimation { duration: Config.ms(100) } }
                            HoverHandler { id: swHover }
                            ClickTap { onTapped: Config.s.accent = parent.modelData }
                        }
                    }
                }
            }
            Separator {}
            SettingRow {
                id: customRow
                needsMet: !Config.s.accentFromWallpaper
                needs: "Needs Accent color from wallpaper to be off"
                needsPage: "appearance"; needsLabel: "Accent color from wallpaper"
                label: "Custom color"
                settingKey: "accent"
                detail: "Slide to pick a shade, or type a hex code"
                readonly property color current: Config.s.accent
                Row {
                    spacing: 12
                    // Hue slider: keeps the theme's soft lightness, changes the hue
                    Item {
                        id: hue
                        anchors.verticalCenter: parent.verticalCenter
                        width: 200; height: 24
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 10; radius: Config.corner(5)
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0/6; color: Config.accentShade(Qt.hsla(0/6, 0.65, 0.74, 1)) }
                                GradientStop { position: 1/6; color: Config.accentShade(Qt.hsla(1/6, 0.65, 0.74, 1)) }
                                GradientStop { position: 2/6; color: Config.accentShade(Qt.hsla(2/6, 0.65, 0.74, 1)) }
                                GradientStop { position: 3/6; color: Config.accentShade(Qt.hsla(3/6, 0.65, 0.74, 1)) }
                                GradientStop { position: 4/6; color: Config.accentShade(Qt.hsla(4/6, 0.65, 0.74, 1)) }
                                GradientStop { position: 5/6; color: Config.accentShade(Qt.hsla(5/6, 0.65, 0.74, 1)) }
                                GradientStop { position: 6/6; color: Config.accentShade(Qt.hsla(0.999, 0.65, 0.74, 1)) }
                            }
                        }
                        Rectangle {
                            width: 16; height: 16; radius: Config.corner(8)
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, customRow.current.hslHue) * (parent.width - width)
                            color: Config.accentShade(customRow.current)
                            border.width: 2; border.color: win.text
                        }
                        MouseArea {
                            // Keep the drag once it's started here, as the other sliders do: the
                            // scrolling page around it took over when the pointer drifted up or down
                            preventStealing: true
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor      // (a hand over it, as over what's clicked)
                            function set(mx) {
                                const h = Math.max(0, Math.min(0.999, mx / width));
                                const c = Qt.hsla(h, 0.65, 0.74, 1);
                                const hex = v => ("0" + Math.round(v * 255).toString(16)).slice(-2);
                                Config.s.accent = "#" + hex(c.r) + hex(c.g) + hex(c.b);
                            }
                            onPressed: m => set(m.x)
                            onPositionChanged: m => { if (pressed) set(m.x); }
                        }
                    }
                    TextField {
                        id: hexInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: 92
                        text: Config.s.accent
                        input.maximumLength: 7
                        input.validator: RegularExpressionValidator { regularExpression: /#?[0-9A-Fa-f]{0,6}/ }
                        function apply() {
                            let t = text.trim();
                            if (!t.startsWith("#")) t = "#" + t;
                            if (/^#[0-9A-Fa-f]{6}$/.test(t)) Config.s.accent = t.toLowerCase();
                            else text = Config.s.accent;
                        }
                        onAccepted: { apply(); input.focus = false; }
                        onFinished: apply()
                    }
                }
            }
        }
        Separator {}
        SettingRow {
            label: "Background tint from wallpaper"
            settingKey: "toneFromWallpaper"
            detail: "The bar, panels and window backgrounds keep their brightness but take on the wallpaper's overall hue. Off: neutral slate"
            Row {
                spacing: 12
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: Config.corner(12)
                    color: Config.wallpaperTone ? Qt.hsla(Qt.lighter(Config.wallpaperTone, 1).hslHue, 0.3, 0.2, 1) : "transparent"
                    border.width: 1; border.color: win.ring
                }
                SettingToggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.s.toneFromWallpaper; onToggled: v => Config.s.toneFromWallpaper = v }
            }
        }
        Separator {}
        SettingRow {
            needsMet: Config.s.toneFromWallpaper
            needs: "Needs Background tint from wallpaper to be on"
            needsPage: "appearance"; needsLabel: "Background tint from wallpaper"
            label: "Tint boldness"
            settingKey: "toneBoldness"
            detail: "How much of the wallpaper's color the backgrounds take, in light and dark mode. 50% is the standard amount"
            ValueSlider {
                per: 100
                from: 0; to: 100; stepSize: 5; suffix: "%"
                value: Math.round((Config.s.toneBoldness ?? 0.8) * 100)
                onMoved: v => Config.s.toneBoldness = v / 100
            }
        }
    }
    GroupLabel { text: "Glass" }
    Group {
        ToggleSetting {
            label: "Glass"
            detail: "The bar, dock, panels, menus, the launcher and Settings turn see-through, with what's behind them blurred"
            key: "glass"
            needsMet: !Config.s.reduceTransparency && !Config.s.highContrast
            needs: Config.s.highContrast ? "Needs High contrast to be off" : "Needs Reduce transparency to be off"
            needsPage: "accessibility"; needsLabel: Config.s.highContrast ? "High contrast" : "Reduce transparency"
        }
        Separator { visible: Config.s.glass }
        SettingRow {
            visible: Config.s.glass
            label: "Opacity"
            settingKey: "glassOpacity"
            detail: "How much of their color the surfaces keep: lower is clearer glass"
            ValueSlider { per: 100; from: 30; to: 95; stepSize: 5; suffix: "%"; value: Math.round(Config.s.glassOpacity * 100); onMoved: v => Config.s.glassOpacity = v / 100 }
        }
        Separator { visible: Config.s.glass }
        SettingRow {
            visible: Config.s.glass
            label: "Blur"
            settingKey: "glassBlur"
            detail: Config.s.glassBlur > 0 ? "How strongly what's behind is blurred (Hyprland's blur, so see-through windows use it too)"
                : "Hyprland's own blur (size " + Config.hyprBlur.size + "); drag to make it stronger or softer"
            ValueSlider { from: 0; to: 20; stepSize: 1; value: Config.s.glassBlur; onMoved: v => Config.s.glassBlur = v }
        }
        Separator { visible: Config.s.glass }
        SettingRow {
            visible: Config.s.glass
            label: "Gloss"
            settingKey: "glassGloss"
            detail: "A glossy sheen on the bar's containers, hover highlights and tooltips. 0% for none"
            // (the setting runs 0 to 2; the slider shows that as 0–100%, so 50% is the sheen as
            // Slate first had it at full, and 100% twice that)
            ValueSlider { per: 50; from: 0; to: 100; stepSize: 5; suffix: "%"; value: Math.round(Config.glossAmount * 50); onMoved: v => Config.s.glassGloss = v / 50 }
        }
        Separator { visible: Config.s.glass }
        SettingRow {
            visible: Config.s.glass
            label: "Gloss color"
            settingKey: "glassGlossTint"
            detail: "How much color the sheen takes from what it's on: the wallpaper's color on glass, a selection's own. 0% for plain white"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 5; suffix: "%"; value: Math.round(Config.glossTint * 100); onMoved: v => Config.s.glassGlossTint = v / 100 }
        }
    }
    GroupLabel { text: "Blur" }
    Group {
        SettingRow {
            label: "Fast blur"
            settingKey: "fastBlur"
            detail: Config.s.fastBlur ? "See-through windows and glass blur just the wallpaper, not the windows under them: far less work, so everything stays smooth"
                : "See-through windows and glass blur whatever's under them, windows included. Heavier: animations and the pointer can slow down"
            SettingToggle { checked: Config.s.fastBlur; onToggled: v => Config.s.fastBlur = v }
        }
        Separator {}
        DropdownSetting {
            label: "Blur quality"
            settingKey: "blurPasses"
            detail: "Smoother blur takes more passes, and asks a little more of your computer"
            options: [{ value: 0, label: "Hyprland's own" }, { value: 1, label: "Low (1 pass)" }, { value: 2, label: "Medium (2 passes)" },
                      { value: 3, label: "High (3 passes)" }, { value: 4, label: "Highest (4 passes)" }]
            value: Config.s.blurPasses
            onPicked: v => Config.s.blurPasses = v
        }
    }
    GroupLabel { text: "Style" }
    Group {
        ToggleSetting {
            label: "Rounded screen corners"
            detail: "Round off the corners of the screen and curve the bar into the screen edges"
            key: "roundedScreenCorners"
        }
        Separator {}
        ToggleSetting {
            label: "Rounded UI elements"
            detail: "Off, everything goes hard-edged and square: the bar's containers and panels, the dock, menus, buttons, switches and your windows. App icons and workspace dots keep the shapes chosen for them"
            key: "roundedElements"
        }
    }
    // ---- Shadows: one look for every shadow, with a preview that shows it as it changes
    GroupLabel { text: "Shadows" }
    Group {
        // A sample of what Slate raises (a card, and a pill like the OSD's) on the window's
        // well, each with Slate's own shadow: the sliders below change it, and every
        // shadow on screen with it, as they move
        Item {
            width: parent.width
            height: 150
            Rectangle {
                id: shadowStage
                anchors { fill: parent; margins: 8 }
                radius: Config.corner(10)
                // Seen on a dark background (the window's own) or a light one, to compare:
                // the cards and their text follow, as they'd be in a light app
                property bool light: false
                readonly property color cardColour: light ? "#f7f8fa" : win.card
                readonly property color inkColour: light ? "#2a313c" : win.text
                readonly property color dimColour: light ? "#8b94a3" : win.dim
                color: light ? "#dfe3e8" : win.well
                Behavior on color { ColorAnimation { duration: Config.ms(150) } }
                clip: true
                Rectangle {
                    id: sampleCard
                    width: Math.min(200, parent.width * 0.45); height: 86
                    x: parent.width * 0.5 - width - 14; y: (parent.height - height) / 2
                    radius: Config.corner(14)
                    color: shadowStage.cardColour
                    Behavior on color { ColorAnimation { duration: Config.ms(150) } }
                    Shadow {}
                    Column {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Rectangle { width: sampleCard.width * 0.55; height: 9; radius: Config.corner(4.5); color: shadowStage.inkColour; opacity: 0.85 }
                        Rectangle { width: sampleCard.width * 0.7; height: 7; radius: Config.corner(3.5); color: shadowStage.dimColour; opacity: 0.6 }
                        Rectangle { width: sampleCard.width * 0.4; height: 7; radius: Config.corner(3.5); color: shadowStage.dimColour; opacity: 0.6 }
                    }
                }
                Rectangle {
                    width: Math.min(150, parent.width * 0.32); height: 40
                    x: parent.width * 0.5 + 18; y: (parent.height - height) / 2
                    radius: Config.corner(20)
                    color: shadowStage.cardColour
                    Behavior on color { ColorAnimation { duration: Config.ms(150) } }
                    Shadow {}
                    Rectangle {
                        anchors { left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        height: 6; radius: Config.corner(3)
                        color: win.control
                        Rectangle { width: parent.width * 0.6; height: parent.height; radius: parent.radius; color: win.accent }
                    }
                }
                Text {
                    visible: !Config.shadowsOn
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                    text: Config.gameMode ? "Shadows are off while game mode is on" : "Shadows are off"
                    color: shadowStage.dimColour; font.family: win.font; font.pixelSize: Config.text(12)
                }
                // Dark or light behind them: two small pills in the corner, the one showing lit
                Row {
                    anchors { top: parent.top; right: parent.right; margins: 8 }
                    spacing: 4
                    Repeater {
                        model: [{ label: "Dark", light: false }, { label: "Light", light: true }]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool on: shadowStage.light === modelData.light
                            width: pillText.implicitWidth + 18; height: 24
                            radius: Config.corner(12)
                            // The chosen one fades in; the muted hover is there at once (HoverFill)
                            color: on ? win.accent : Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0)
                            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                            HoverFill { base: Qt.rgba(0, 0, 0, shadowStage.light ? 0.08 : 0.25); hovered: pillHover.hovered; gone: parent.on; radius: parent.radius }
                            Text {
                                id: pillText
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                color: parent.on ? win.accentText : shadowStage.inkColour
                                font.family: win.font; font.pixelSize: Config.text(11); font.weight: Font.Medium
                            }
                            HoverHandler { id: pillHover }
                            ClickTap { onTapped: shadowStage.light = parent.modelData.light }
                        }
                    }
                }
            }
        }
        Separator {}
        ToggleSetting {
            label: "Shadows"
            detail: Config.gameMode ? "Off while game mode is on" : "A shadow under everything raised: panels, menus, the launcher, notifications and floating windows. Off, everything sits flat"
            key: "shadows"
        }
        // How they look, for every shadow alike (Config.qml: shadowStrength, shadowReach…)
        Separator { visible: Config.s.shadows }
        SettingRow {
            visible: Config.s.shadows
            label: "Darkness"
            settingKey: "shadowDarkness"
            detail: Config.glass && Config.s.shadowDarkness * (Config.s.lightMode ? 0.5 : 1) > Config.shadowStrength + 0.005
                ? "How dark they are. With glass on they stay a little lighter than this, so the glass doesn't blur them"
                : "How dark they are at their darkest (half as dark in light mode)"
            ValueSlider { per: 100; from: 10; to: 100; stepSize: 5; suffix: "%"; value: Math.round(Config.s.shadowDarkness * 100); onMoved: v => Config.s.shadowDarkness = v / 100 }
        }
        Separator { visible: Config.s.shadows }
        SettingRow {
            visible: Config.s.shadows
            label: "Softness"
            settingKey: "shadowSoftness"
            detail: "How gently their edge fades away. 0 is a crisp edge"
            ValueSlider { from: 0; to: 24; stepSize: 1; suffix: " px"; value: Config.s.shadowSoftness; onMoved: v => Config.s.shadowSoftness = v }
        }
        Separator { visible: Config.s.shadows }
        SettingRow {
            visible: Config.s.shadows
            label: "Spread"
            settingKey: "shadowSpread"
            detail: "How far their full darkness reaches past the edge, before it fades"
            ValueSlider { from: 0; to: 10; stepSize: 1; suffix: " px"; value: Config.s.shadowSpread; onMoved: v => Config.s.shadowSpread = v }
        }
        Separator { visible: Config.s.shadows }
        SettingRow {
            visible: Config.s.shadows
            label: "Distance"
            settingKey: "shadowDistance"
            detail: "How far they sit from what casts them. 0 is all round, like a glow"
            ValueSlider { from: 0; to: 16; stepSize: 1; suffix: " px"; value: Config.s.shadowDistance; onMoved: v => Config.s.shadowDistance = v }
        }
        Separator { visible: Config.s.shadows }
        SettingRow {
            visible: Config.s.shadows
            label: "Direction"
            settingKey: "shadowDirection"
            detail: "Which way they fall: 0° is straight down, 90° to the left, 180° up and 270° to the right. Panels from the bar always fall away from it"
            ValueSlider { from: 0; to: 345; stepSize: 15; suffix: "°"; value: Config.s.shadowDirection; onMoved: v => Config.s.shadowDirection = Math.round(v) }
        }
    }
    GroupLabel { text: "Fonts" }
    Group {
        FontSetting {
            label: "Interface font"
            detail: "Used across the bar, panels, launcher, switchers, notifications and this window"
            key: "fontFamily"
        }
        Separator {}
        FontSetting {
            label: "Code font"
            detail: "Monospaced font for code: Slate uses it, and your other apps can too, with the switch below"
            key: "codeFontFamily"
            monoOnly: true
        }
        Separator {}
        // Off until chosen (the Welcome window offers it): the code font as every app's
        // "monospace", each change recorded and put back when it's switched off
        // (scripts/apply-theme.py, as the app "code-font")
        ToggleSetting {
            label: "Code font in your apps"
            detail: "Makes the code font the monospaced font of your other apps too: terminals, editors and anything else that asks for one. Switch it off and Slate puts their settings back as they were"
            key: "codeFontInApps"
        }
    }
    GroupLabel { text: "Size" }
    Group {
        SettingRow {
            label: "Interface size"
            settingKey: "uiScale"
            detail: "Scales Slate only (the bar, dock, panels, launcher, title bars and this window), on every display, on top of each display's Scale. "
                + "Apps stay as they are: to make everything larger or smaller, apps included, change Scale in Displays instead. Changing it restarts Slate"
            ValueSlider {
                per: 100
                from: 75; to: 150; stepSize: 5; suffix: "%"
                value: Math.round(Config.s.uiScale * 100)
                onMoved: v => Config.s.uiScale = v / 100
                onReleased: scaleAsk.restart()
            }
            // Once you let go, ask before restarting; Cancel goes back to the size in use
            Timer {
                id: scaleAsk
                interval: 150
                onTriggered: {
                    if (Math.abs(Config.s.uiScale - Config.uiScale) < 0.001) return;
                    win.askQuestion({
                        title: "Restart Slate?",
                        body: "Interface size changes to " + Math.round(Config.s.uiScale * 100) + "% when Slate restarts. "
                            + "Your apps and windows stay open. The bar, dock and Settings step away for a moment, "
                            + "then Settings opens again right here.",
                        button: "Restart",
                        run: () => Config.uiScaleEdited(),
                        cancel: () => Config.s.uiScale = Config.uiScale
                    });
                }
            }
        }
    }
    GroupLabel { text: "Motion" }
    Group {
        DropdownSetting {
            label: "Animations"
            settingKey: "animations"
            needsMet: !Config.s.reduceMotion
            needs: "Needs Reduce motion to be off"
            needsPage: "accessibility"; needsLabel: "Reduce motion"
            detail: "Windows opening, closing and moving, switching workspaces, and Slate's own: panels opening, the bar's groups sliding open, fades and highlights. Faster halves them; Off makes them instant"
            options: [{ value: "normal", label: "Normal" }, { value: "fast", label: "Faster" }, { value: "off", label: "Off" }]
            value: Config.s.animations !== "" ? Config.s.animations : "normal"
            onPicked: v => Config.s.animations = v
        }
    }
}
