import QtQuick
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "Workspaces" }
    GroupLabel { text: "Switching" }
    Group {
        DropdownSetting {
            label: "Workspace switching"
            settingKey: "workspaceAnimation"
            detail: Config.s.animations === "off" ? "Animations are off, so workspaces switch straight away"
                : ({ slidefade: "The new workspace slides in over the old one, which fades away underneath",
                     slidefadevert: "The new workspace slides in from above or below over the old one, which fades away",
                     slide: "Both slide along together, like turning pages",
                     slidevert: "Both slide up or down together",
                     crossfade: "The new workspace fades in over the old one",
                     none: "Straight to the new workspace, with no animation" })[Config.s.workspaceAnimation] || ""
            options: [{ value: "slidefade", label: "Slide Fade" }, { value: "slide", label: "Slide" },
                      { value: "crossfade", label: "Crossfade" }, { value: "slidefadevert", label: "Vertical Slide Fade" },
                      { value: "slidevert", label: "Vertical Slide" }, { value: "none", label: "None" }]
            value: Config.s.workspaceAnimation || "slidefade"
            onPicked: v => Config.s.workspaceAnimation = v
        }
        Separator {}
        ToggleSetting {
            label: "Name when switching"
            detail: "The indicator that shows as you go to the next or previous workspace (Super+Left / Right) names the one you land on, under its dots"
            key: "workspaceSwitchName"
        }
        Separator {}
        ToggleSetting {
            label: "Workspaces wrap around"
            detail: "Super+Left/Right and the overview go from the last workspace back to the first (and the other way); off, they stop at the ends, and the overview's row ends there too"
            key: "wrapWorkspaces"
        }
        Separator {}
        ToggleSetting {
            label: "Keep an empty workspace"
            detail: "Keeps an empty workspace after the last one in use, ready and waiting for a new window"
            key: "keepEmptyWorkspace"
        }
    }
    GroupLabel { text: "Look" }
    Group {
        SettingRow {
            label: "Workspace indicators"
            settingKey: "workspaceShape"
            detail: "The shape of the workspace dots on the bar, the window switcher, the overview and the on-screen display"
            // Two-way switch: Circles | Squares, each with a small preview
            SegmentedChoice {
                options: [{ value: "circle", label: "Circles", dot: "circle" }, { value: "square", label: "Squares", dot: "square" }]
                value: Config.s.workspaceShape
                onPicked: v => Config.s.workspaceShape = v
            }
        }
    }
    GroupLabel { text: "Workspace overview (Super+Down)" }
    Group {
        // What each window on the cards shows (overviewPreviews and overviewAppIcons): its
        // live picture, its outline with its app icon (nothing captured), or the picture
        // with the icon on it
        DropdownSetting {
            label: "Windows show"
            detail: !Config.s.overviewPreviews ? "Each window's outline with its app icon; nothing is captured, which is lighter"
                : Config.s.overviewAppIcons ? "Each window's contents, with its app icon in the middle"
                : "Each window's contents, live"
            options: [{ value: "previews", label: "Live previews" }, { value: "icons", label: "App icons" }, { value: "both", label: "Both" }]
            value: !Config.s.overviewPreviews ? "icons" : Config.s.overviewAppIcons ? "both" : "previews"
            onPicked: v => {
                Config.s.overviewPreviews = v !== "icons";
                if (v !== "icons") Config.s.overviewAppIcons = v === "both";
            }
        }
        Separator {}
        DropdownSetting {
            label: "Moving between workspaces"
            settingKey: "overviewMoveAnimation"
            detail: ({
                hop: "The cards hop along to the next one",
                wheel: "The cards sit round the outside of a wheel that turns to bring the next one to the top",
                tilt: "The chosen card faces you and the others are turned away in 3D on either side",
                orbit: "The cards ride round a ring in 3D, the chosen one at the front and the rest smaller towards the back",
                deck: "The cards sit in a pile with the chosen one on top; moving on deals it away and the next one rises",
                fan: "The cards spread like a hand of cards, the chosen one lifted out of it",
                grid: "Every workspace in a grid; the arrow keys move round it, and more rows than fit scroll",
                instant: "The selection jumps straight to the next workspace"
            })[Config.s.overviewMoveAnimation] ?? "The row of cards slides along, keeping the chosen one in the middle"
            options: [{ value: "slide", label: "Slide" }, { value: "hop", label: "Hop" }, { value: "wheel", label: "Wheel" },
                      { value: "tilt", label: "Tilt" }, { value: "orbit", label: "Orbit" }, { value: "deck", label: "Deck" },
                      { value: "fan", label: "Fan" }, { value: "grid", label: "Grid" }, { value: "instant", label: "Instant" }]
            value: ["hop", "wheel", "tilt", "orbit", "deck", "fan", "grid", "instant"].includes(Config.s.overviewMoveAnimation) ? Config.s.overviewMoveAnimation : "slide"
            onPicked: v => Config.s.overviewMoveAnimation = v
        }
        Separator {}
        // Under the movement it goes with: the cards' size, or for the grid how many go across
        SettingRow {
            visible: Config.s.overviewMoveAnimation !== "grid"
            label: "Card size"
            settingKey: "overviewCardWidth"
            ValueSlider { from: 480; to: 1000; stepSize: 8; suffix: " px"; value: Config.s.overviewCardWidth; onMoved: v => Config.s.overviewCardWidth = v }
        }
        SettingRow {
            visible: Config.s.overviewMoveAnimation === "grid"
            label: "Grid size"
            settingKey: "overviewGridSize"
            defaultText: { const d = Config.defaultOf("overviewGridSize"); return d + " × " + d; }
            detail: "How many workspaces go across, and down before it scrolls (fewer down on a small screen)"
            ValueSlider {
                from: 2; to: 9; stepSize: 1
                value: Config.s.overviewGridSize
                // (shown as 3 × 3 and so on)
                suffix: " × " + Math.round(value)
                onMoved: v => Config.s.overviewGridSize = Math.round(v)
            }
        }
        Separator {}
        DropdownSetting {
            label: "Going to the workspace"
            settingKey: "overviewPickAnimation"
            detail: ({
                fade: "The overview fades away to show the workspace",
                workspace: "The overview goes quickly and the workspace switches with your workspace animation (Workspace switching, above)",
                instant: "Straight to the workspace, and the overview goes at once"
            })[Config.s.overviewPickAnimation] ?? "The chosen card grows until it fills the screen and becomes the workspace"
            options: [{ value: "zoom", label: "Zoom" }, { value: "fade", label: "Fade" }, { value: "workspace", label: "Workspace animation" }, { value: "instant", label: "Instant" }]
            value: Config.s.overviewPickAnimation
            onPicked: v => Config.s.overviewPickAnimation = v
        }
    }
    GroupLabel { text: "Spaces" }
    Group {
        SettingRow {
            label: "Spaces"
            detail: "Save sets of workspaces with their apps and layout, and bring them back in one click"
            Button { label: "Open"; onClicked: win.goTo("spaces", "") }
        }
    }
}
