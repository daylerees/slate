import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "Windows" }
    GroupLabel { text: "Layout & borders" }
    Group {
        // Hyprland's layouts, and floating
        // The default: a workspace can have its own from the menu bar's workspace indicator
        DropdownSetting {
            label: "Default window mode"
            settingKey: "windowMode"
            detail: ({
                floating: "Windows open floating and centered, like a traditional desktop. Move them by their title bar or with Super+drag; Super+Alt+Space tiles one",
                master: "One main window on the left, the rest stacked beside it. Super+J makes the focused window the main one; Super+Alt+Space floats one",
                scrolling: "Windows sit in columns on a strip that scrolls sideways as you move between them. Super+J changes a column's width; Super+Alt+Space floats one",
                monocle: "One window at a time, filling the screen; the others wait behind it. Super+J or Super+Alt+Left/Right switch between them",
                solo: "Every window fills a workspace of its own: a new one opens on the next free workspace. Move between them as between workspaces"
            })[Config.windowMode] ?? "Windows tile side by side. Super+J splits the other way, Super+drag moves one, Super+Alt+Space floats it"
            // (and that it's only the default)
            + ". For new workspaces: each can have its own, from the button beside the workspace dots on the menu bar"
            options: Config.windowModes
            value: Config.windowMode
            // With windows open in another mode (the old default, or a workspace's own):
            // shift every workspace to the new one, or leave those in use as they are?
            // (asked in Slate's confirmation window; closing it leaves them)
            onPicked: v => {
                if (v === Config.windowMode) return;
                const n = Config.workspacesNotIn(v).length;
                if (n === 0) { Config.setDefaultMode(v, true); return; }
                const to = Config.windowModes.find(m => m.value === v);
                win.askQuestion({
                    title: "Tidy up open windows?",
                    body: "New workspaces will use " + to.label + ". " + (n === 1 ? "One workspace has" : n + " workspaces have")
                        + " windows open in another mode: tidy up, moving every workspace to " + to.label
                        + " now, or leave " + (n === 1 ? "it as it is" : "them as they are") + "? Left alone, "
                        + (n === 1 ? "it keeps its" : "each keeps its") + " current mode until you change it from the menu bar.",
                    button: "Tidy up", cancelLabel: "Leave " + (n === 1 ? "it" : "them"), code: to.icon,
                    run: () => Config.setDefaultMode(v, true),
                    cancel: () => Config.setDefaultMode(v, false)
                });
            }
        }
        // Floating windows' title bars: Slate's own (the default: nothing to build), or
        // Hyprbars, the optional plugin (Config.hyprbars…, HyprbarsWatch.qml). Always shown:
        // any workspace can be floating (the menu bar's workspace indicator), whatever the default
        Separator {}
        DropdownSetting {
            label: "Title bars"
            settingKey: "titleBarStyle"
            detail: Config.slateTitleBars
                ? "Slate Bars: Slate draws a title bar on the floating window in front, with nothing to install or rebuild. It fades out while a window moves, resizes or maximizes. Drag it to move the window; double-click to maximize"
                : "From the Hyprbars plugin, on every floating window and moving with it. It has to be rebuilt after every Hyprland update; until then Slate Bars are used"
            options: [{ value: "slate", label: "Slate Bars" },
                      { value: "hyprbars", label: Config.hyprbarsState === "stale" ? "Hyprbars (needs rebuilding)" : "Hyprbars (optional)" }]
            value: Config.slateTitleBars ? "slate" : "hyprbars"
            // Hyprbars has risks, and may need building: Slate asks first, and switches once
            // it's loaded. While it's being built or waiting for a reload, it can't be picked
            onPicked: v => {
                if (v === "slate") { Config.s.titleBarStyle = "slate"; return; }
                if (Config.hyprbarsState === "building") return;
                Config.hyprbarsChoose();
            }
        }
        Separator {}
        SettingRow {
            id: hyprbarsRow
            readonly property string state: Config.hyprbarsState
            readonly property string forNew: Config.hyprbars.installed || "the new Hyprland"
            label: "Hyprbars"
            detail: state === "building" ? "Being built for Hyprland " + (Config.hyprbars.stateFor || forNew) + "…"
                : state === "loaded" ? (
                    !Config.hyprlandUpdated ? (Config.slateTitleBars ? "Built and loaded. Choose it above to use it" : "In use")
                    : Config.hyprbars.next === "yes" ? "Hyprland was updated: rebuilt for it, and ready after your next restart"
                    : Config.hyprbars.state === "failed" ? "Hyprland was updated, and Hyprbars couldn't be rebuilt for it: " + (Config.hyprbars.error || "the build failed")
                    : "Hyprland was updated. Rebuild now, and it's ready after your next restart")
                : state === "ready" ? "Built. Reload Hyprland to load it; your windows stay open"
                : state === "stale" ? "Needs rebuilding: it was built for another version of Hyprland, so it can't load. Slate Bars are used until it's rebuilt"
                : state === "failed" ? "Couldn't be built: " + (Config.hyprbars.error || "the build failed")
                : state === "unreleased" ? "Waiting for a Hyprbars release for your Hyprland"
                : state === "removed" ? "Removed. Fully gone after your next restart"
                : state === "system" ? "The one from your system's package doesn't match this Hyprland. Update that package, or build Slate's own"
                : "Optional title bars from a Hyprland plugin, on every floating window. Slate builds it on this computer, and it needs rebuilding after every Hyprland update"
            Row {
                spacing: 8
                Button {
                    visible: hyprbarsRow.state === "ready"
                    label: "Reload"; icon: 0xEB13
                    onClicked: Config.hyprbarsReload()
                }
                Button {
                    visible: hyprbarsRow.state === "stale" || hyprbarsRow.state === "failed" || hyprbarsRow.state === "system"
                        || (hyprbarsRow.state === "loaded" && Config.hyprlandUpdated && Config.hyprbars.next !== "yes")
                    label: hyprbarsRow.state === "failed" ? "Retry" : hyprbarsRow.state === "system" ? "Build" : "Rebuild"
                    onClicked: Config.hyprbarsRebuild()
                }
                Button {
                    // (no release yet: only with a yes is the newest, unreleased code built)
                    visible: hyprbarsRow.state === "unreleased"
                    label: "Build the unreleased version"
                    onClicked: Config.hyprbarsBuildUnreleased()
                }
                Button {
                    visible: hyprbarsRow.state === "none" || hyprbarsRow.state === "removed"
                    label: "Build"
                    onClicked: Config.hyprbarsChoose()
                }
                Button {
                    visible: Config.hyprbars.any === "yes" && hyprbarsRow.state !== "building"
                    label: "Remove"
                    destructive: true
                    onClicked: Config.hyprbarsRemove()
                }
            }
        }
        // (always too: for whichever workspaces float)
        Separator {}
        DropdownSetting {
            label: "Title bar buttons"
            settingKey: "titleButtons"
            detail: "Which side of a floating window's title bar the close and maximize buttons sit on"
            options: [{ value: "left", label: "Left" }, { value: "right", label: "Right" }]
            value: Config.s.titleButtons
            onPicked: v => Config.s.titleButtons = v
        }
        // (hidden with Slate's title bars, which always use a click: Config.clickToFocus)
        Separator { visible: !Config.clickToFocus }
        SettingRow {
            id: focusRow
            visible: !Config.clickToFocus
            label: "Focus follows the pointer"
            settingKey: "focusFollowsMouse"
            detail: "Windows take the keyboard as the pointer moves over them. Off: click a window to use it (scrolling still reaches the one under the pointer)"
            property int current: 1
            Process {
                running: true
                command: [Quickshell.shellPath("scripts/hypr-options.py"), "input:follow_mouse"]
                stdout: StdioCollector { onStreamFinished: { try { focusRow.current = JSON.parse(text)["input:follow_mouse"]; } catch (e) {} } }
            }
            SettingToggle {
                checked: Config.s.focusFollowsMouse !== "" ? Config.s.focusFollowsMouse === "on" : focusRow.current === 1
                onToggled: v => Config.s.focusFollowsMouse = v ? "on" : "off"
            }
        }
        Separator {}
        SettingRow {
            label: "Window borders"
            settingKey: "windowBorderSize"
            detail: "Around each window when a workspace has more than one (a lone window has none), and round Slate's own windows with glass. 0 turns them off"
            ValueSlider { from: 0; to: 12; stepSize: 1; suffix: " px"; value: Config.s.windowBorderSize; onMoved: v => Config.s.windowBorderSize = v }
        }
        Separator {}
        SettingRow {
            label: "Window spacing"
            settingKey: "windowGap"
            detail: "The gap between windows on a workspace with more than one (the screen edges get a little more). 0 puts them edge to edge"
            ValueSlider { from: 0; to: 32; stepSize: 2; suffix: " px"; value: Config.s.windowGap; onMoved: v => Config.s.windowGap = v }
        }
        Separator {}
        SettingRow {
            label: "Space around a lone window"
            settingKey: "soloWindowGap"
            detail: "Padding around a window that's alone on its workspace, which then keeps its rounded corners. 0 lets it fill the screen up to the bar. Maximized and full-screen apps always fill it"
            ValueSlider { from: 0; to: 32; stepSize: 2; suffix: " px"; value: Config.s.soloWindowGap; onMoved: v => Config.s.soloWindowGap = v }
        }
        Separator {}
        SettingRow {
            label: "Dim inactive windows"
            settingKey: "inactiveDim"
            detail: "Darken the windows you're not using, so the focused one stands out (Settings itself never dims). 0 turns it off"
            ValueSlider { from: 0; to: 80; stepSize: 5; suffix: "%"; value: Config.s.inactiveDim; onMoved: v => Config.s.inactiveDim = v }
        }
    }
    GroupLabel { text: "Drop-down terminal" }
    Group {
        SettingRow {
            label: "Height"
            settingKey: "dropdownHeight"
            detail: "Super+` brings a terminal down from the top of the screen over whatever you're doing, and puts it away again. "
                + "What's running in it keeps going while it's hidden"
            ValueSlider { from: 20; to: 90; stepSize: 5; suffix: "%"; value: Config.s.dropdownHeight; onMoved: v => Config.s.dropdownHeight = v }
        }
    }
    GroupLabel { text: "Window switcher (Super+Tab)" }
    Group {
        // What each window's card shows (switcherPreviews and switcherAppIcons), as the
        // overview's Windows show
        DropdownSetting {
            label: "Windows show"
            detail: !Config.s.switcherPreviews ? "Each window's outline with its app icon; nothing is captured, which is lighter"
                : Config.s.switcherAppIcons ? "Each window's contents, with a small app icon on the corner"
                : "Each window's contents, live"
            options: [{ value: "previews", label: "Live previews" }, { value: "icons", label: "App icons" }, { value: "both", label: "Both" }]
            value: !Config.s.switcherPreviews ? "icons" : Config.s.switcherAppIcons ? "both" : "previews"
            onPicked: v => {
                Config.s.switcherPreviews = v !== "icons";
                if (v !== "icons") Config.s.switcherAppIcons = v === "both";
            }
        }
        Separator {}
        DropdownSetting {
            label: "Moving between windows"
            settingKey: "switcherMoveAnimation"
            detail: ({
                hop: "The windows hop along to the next one",
                wheel: "The windows sit round the outside of a wheel that turns to bring the next one to the top",
                tilt: "The chosen window faces you and the others are turned away in 3D on either side",
                orbit: "The windows ride round a ring in 3D, the chosen one at the front and the rest smaller towards the back",
                deck: "The windows sit in a pile with the chosen one on top; moving on deals it away and the next one rises",
                fan: "The windows spread like a hand of cards, the chosen one lifted out of it",
                instant: "The selection jumps straight to the next window"
            })[Config.s.switcherMoveAnimation] ?? "The row of windows slides along, keeping the chosen one in the middle"
            options: [{ value: "slide", label: "Slide" }, { value: "hop", label: "Hop" }, { value: "wheel", label: "Wheel" },
                      { value: "tilt", label: "Tilt" }, { value: "orbit", label: "Orbit" }, { value: "deck", label: "Deck" },
                      { value: "fan", label: "Fan" }, { value: "instant", label: "Instant" }]
            value: ["hop", "wheel", "tilt", "orbit", "deck", "fan", "instant"].includes(Config.s.switcherMoveAnimation) ? Config.s.switcherMoveAnimation : "slide"
            onPicked: v => Config.s.switcherMoveAnimation = v
        }
        Separator {}
        DropdownSetting {
            label: "Going to the window"
            settingKey: "switcherPickAnimation"
            detail: ({
                workspace: "A window on another workspace is switched to with your workspace animation (Workspaces → Workspace switching)",
                instant: "Straight to the window, and the switcher goes at once"
            })[Config.s.switcherPickAnimation] ?? "A window on another workspace fades in over the one you're on"
            options: [{ value: "crossfade", label: "Crossfade" }, { value: "workspace", label: "Workspace animation" }, { value: "instant", label: "Instant" }]
            value: Config.s.switcherPickAnimation
            onPicked: v => Config.s.switcherPickAnimation = v
        }

    }
}
