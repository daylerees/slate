import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Qt.labs.folderlistmodel
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "Dock" }
    GroupLabel { text: "Position & behavior" }
    Group {
        SettingRow {
            label: "Position"
            settingKey: "dockPosition"
            defaultText: { const d = Config.defaultOf("dockPosition"); return d.charAt(0).toUpperCase() + d.slice(1); }
            detail: "Click an edge. The menu bar is at the " + Config.s.barPosition + "; if you pick its edge, it moves to the opposite one"
            EdgePicker { accent: win.accent; bar: false; edge: Config.s.dockPosition; onPicked: e => Config.moveDock(e) }
        }
        Separator {}
        ToggleSetting {
            label: "Auto-hide"
            detail: "Hide the dock while the workspace has tiled windows (floating ones leave it open, except in floating windows mode); push the pointer to the dock's edge to show it"
            key: "dockAutoHide"
        }
        Separator {}
        ToggleSetting {
            label: "Window previews"
            detail: "Rest the pointer on an app with windows open to see them; click one to go to it (titles only, in game mode)"
            key: "dockPreviews"
        }
        Separator { visible: Config.s.dockPreviews }
        SettingRow {
            visible: Config.s.dockPreviews
            label: "Previews appear after"
            settingKey: "dockPreviewDelay"
            detail: "How long to rest on an app before its windows show. Instant shows them as soon as the pointer arrives"
            ValueSlider { from: 0; to: 3; stepSize: 0.1; decimals: 1; suffix: " s"; zeroText: "Instant"; value: Config.s.dockPreviewDelay; onMoved: v => Config.s.dockPreviewDelay = v }
        }
        Separator {}
        ToggleSetting {
            label: "Badges and progress"
            detail: "An app's unread count on its icon (what it says itself, or its unread notifications), and how far a download or copy has got"
            key: "dockBadges"
        }
        Separator {}
        ToggleSetting {
            label: "Divider"
            detail: "A line after the Apps button and media controls, between the pinned apps and the others running, and before the Waste Basket"
            key: "dockDivider"
        }
        Separator {}
        ToggleSetting {
            label: "Apps button"
            detail: "At the start of the dock: opens the launcher; right-click for Settings"
            key: "dockShowLauncher"
        }
        Separator {}
        ToggleSetting {
            label: "Media controls"
            detail: "After the Apps button while something's playing: its album art (click it to go to the app) with Previous, Play/Pause and Next beside it (over the art on a side dock); right-click for them all"
            key: "dockShowMedia"
        }
        Separator { visible: Config.s.dockShowMedia }
        SettingRow {
            visible: Config.s.dockShowMedia
            label: "Album art"
            settingKey: "dockMediaArt"
            detail: "The track's artwork beside the controls; off, just the controls"
            SettingToggle { checked: Config.s.dockMediaArt; onToggled: v => Config.s.dockMediaArt = v }
        }
        Separator {}
        ToggleSetting {
            label: "Downloads"
            detail: "Before the Waste Basket: click for your newest downloads, right-click to open the folder"
            key: "dockShowDownloads"
        }
        Separator {}
        ToggleSetting {
            label: "Waste Basket"
            detail: "At the end of the dock, filled when there's something in it: click to open it, right-click to empty it"
            key: "dockShowTrash"
        }
    }
    GroupLabel { text: "Icons" }
    Group {
        SettingRow {
            label: "Icon size"
            settingKey: "dockIconSize"
            detail: "When the dock gets too long for your screen, Slate makes the icons smaller, then puts apps you haven't pinned in More."
            ValueSlider { from: 28; to: 64; stepSize: 1; suffix: " px"; value: Config.s.dockIconSize; onMoved: v => Config.s.dockIconSize = v }
        }
        Separator {}
        DropdownSetting {
            label: "Hover effect"
            settingKey: "dockHoverEffect"
            detail: ({
                tilt: "With the pointer on the dock, the icons turn in 3D towards it, and the ones near it straighten up to face you (the one under it lifts a little)",
                both: "With the pointer on the dock, the icons turn in 3D towards it, and the ones near it straighten up and grow",
                fade: "The icons away from the pointer fade, so the ones near it stand out; all clear again when it leaves",
                fademagnify: "The icons near the pointer grow, and the ones away from it fade",
                glow: "The icon under the pointer gets a ring and a soft glow round it, in its own color",
                glowmagnify: "The icons near the pointer grow, and the one under it gets a ring and a soft glow in its own color",
                raise: "The icon under the pointer lifts up a little; the others stay where they are",
                none: "The icons stay as they are"
            })[Config.s.dockHoverEffect] ?? "The icons near the pointer grow, the one under it most"
            options: [{ value: "magnify", label: "Magnify" }, { value: "tilt", label: "Tilt" },
                      { value: "both", label: "Magnify and tilt" }, { value: "fade", label: "Fade" },
                      { value: "fademagnify", label: "Fade and magnify" }, { value: "glow", label: "Glow" },
                      { value: "glowmagnify", label: "Glow and magnify" }, { value: "raise", label: "Raise" },
                      { value: "none", label: "None" }]
            value: ["tilt", "both", "fade", "fademagnify", "glow", "glowmagnify", "raise", "none"].includes(Config.s.dockHoverEffect) ? Config.s.dockHoverEffect : "magnify"
            onPicked: v => Config.s.dockHoverEffect = v
        }
        // Under the effect they belong to: magnifying's size, and how far either reaches
        Separator { visible: !["tilt", "fade", "glow", "raise", "none"].includes(Config.s.dockHoverEffect) }
        SettingRow {
            visible: !["tilt", "fade", "glow", "raise", "none"].includes(Config.s.dockHoverEffect)
            label: "Magnification"
            settingKey: "dockMagnification"
            detail: "How large the icon under the pointer grows"
            ValueSlider { from: 1; to: 2.5; stepSize: 0.05; decimals: 2; suffix: "×"; value: Config.s.dockMagnification; onMoved: v => Config.s.dockMagnification = v }
        }
        Separator { visible: Config.s.dockHoverEffect !== "none" && Config.s.dockHoverEffect !== "raise" }
        SettingRow {
            visible: Config.s.dockHoverEffect !== "none" && Config.s.dockHoverEffect !== "raise"
            label: "Magnification spread"
            settingKey: "dockSpread"
            detail: "How many neighboring icons rise in the arc (or turn, with tilt, or stay clear, with fade)"
            ValueSlider { from: 1; to: 5; stepSize: 0.5; decimals: 1; value: Config.s.dockSpread; onMoved: v => Config.s.dockSpread = v }
        }
    }
    // (only with glass on: Appearance → Glass)
    GroupLabel { visible: Config.s.glass; text: "Glass" }
    Group {
        visible: Config.s.glass
        ToggleSetting {
            label: "Blur"
            detail: "What's behind the dock is blurred, like frosted glass. Off, you see straight through it"
            key: "dockBlur"
        }
        Separator {}
        SettingRow {
            label: "Background opacity"
            settingKey: "dockOpacity"
            detail: "How solid the dock's background is: 100% can't be seen through, lower is clearer"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round((Config.s.dockOpacity < 0 ? Config.dockGlassOpacity : Config.s.dockOpacity) * 100); onMoved: v => Config.s.dockOpacity = v / 100 }
        }
        Separator {}
        SettingRow {
            label: "Tile opacity"
            settingKey: "dockTileOpacity"
            detail: "The tiles behind the dock's icons and its buttons: 100% is solid, lower lets the dock show through them"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.s.dockTileOpacity * 100); onMoved: v => Config.s.dockTileOpacity = v / 100 }
        }
        Separator {}
        SettingRow {
            label: "Icon opacity"
            settingKey: "dockIconOpacity"
            detail: "The icons, and what's drawn on the dock's own buttons: 100% is solid, at 0% they're gone"
            ValueSlider { per: 100; from: 0; to: 100; stepSize: 1; suffix: "%"; value: Math.round(Config.s.dockIconOpacity * 100); onMoved: v => Config.s.dockIconOpacity = v / 100 }
        }
    }
}
