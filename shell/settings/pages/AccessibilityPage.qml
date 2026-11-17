import QtQuick
import Quickshell
import "../.."
import ".."

// Settings → Accessibility: what makes Slate easier to see and use, in one place. Each switch
// here overrides the look it touches (Glass, Animations…) without changing it, so switching it
// off again puts things back as you had them.
Column {
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "Accessibility" }
    IntroText {
        text: "Make Slate easier to see and use. These work on top of your other settings without changing them, so you can switch any of them off again and everything is as you had it."
    }
    GroupLabel { text: "Screen reader" }
    Group {
        ToggleSetting {
            label: "Screen reader"
            detail: !Config.orcaAvailable ? "Needs Orca, the screen reader (the orca package)"
                : "Orca reads out what's on the screen and what you're doing, in apps and in Slate. Super+Alt+S turns it on and off from anywhere"
            key: "screenReader"
        }
    }
    GroupLabel { text: "Zoom" }
    Group {
        ToggleSetting {
            label: "Zoom"
            detail: "Magnify the whole screen around the pointer. Super+Alt+Z turns it on and off; Super+Plus and Super+Minus, or Super+Alt with the scroll wheel, zoom in and out"
            key: "zoom"
        }
        Separator {}
        SettingRow {
            label: "Zoom level"
            settingKey: "zoomLevel"
            detail: "How far in it goes"
            ValueSlider { from: 1.25; to: 5; stepSize: 0.25; decimals: 2; suffix: "×"; value: Config.s.zoomLevel; onMoved: v => Config.s.zoomLevel = v }
        }
        Separator {}
        DropdownSetting {
            label: "Follow the pointer"
            settingKey: "zoomFollow"
            detail: "Smoothly moves the view when the pointer nears its edge; In the middle keeps the pointer centered, moving the view with it"
            options: [{ value: "smooth", label: "Smoothly" }, { value: "center", label: "In the middle" }]
            value: Config.s.zoomFollow
            onPicked: v => Config.s.zoomFollow = v
        }
    }
    GroupLabel { text: "Pointer and keyboard" }
    Group {
        ToggleSetting {
            label: "On-screen keyboard"
            detail: !Config.wtypeAvailable ? "Needs wtype to type into apps (the wtype package); on the lock screen it works without it"
                : "Keys at the bottom of the screen that type into the app you're in, and on the lock screen. Its ⌄ key puts it away; Super+Alt+K brings it back"
            key: "onScreenKeyboard"
        }
        Separator {}
        SettingRow {
            label: "Locate the pointer"
            detail: "Rings round the pointer for a moment, to find it. Press Super+Alt+P any time"
            Button { label: "Show me"; icon: 0xF1D4; onClicked: Config.slateCall("pointer", "locate") }
        }
        Separator {}
        ToggleSetting {
            label: "Trailing pointer"
            detail: "A short trail of fading dots behind the pointer as it moves, to keep track of it. Off in game mode"
            key: "pointerTrail"
        }
        Separator {}
        SettingRow {
            label: "Pointer size"
            detail: "A bigger pointer is easier to see: in Input, with the pointer's style"
            Button { label: "Input"; icon: 0xEA61; onClicked: win.goTo("input", "Pointer size") }
        }
        Separator {}
        SettingRow {
            label: "Key repeat"
            detail: "How long a key is held before it repeats, and how fast: in Input"
            Button { label: "Input"; icon: 0xEA61; onClicked: win.goTo("input", "Repeat delay") }
        }
    }
    GroupLabel { text: "Display" }
    Group {
        ToggleSetting {
            label: "High contrast"
            detail: "Text and icons stand out against darker (or, in light mode, lighter) surfaces, every surface has a clear edge, and windows a bright border. Apps themed in App Theming follow it"
            key: "highContrast"
        }
        Separator {}
        DropdownSetting {
            label: "Text size"
            settingKey: "textScale"
            detail: "Slate's text, without the rest growing (Interface size in Appearance grows everything). GTK apps follow it too when App Theming themes them"
            options: [{ value: 1, label: "Default" }, { value: 1.15, label: "Larger" }, { value: 1.3, label: "Largest" }]
            value: Config.textScale
            onPicked: v => Config.s.textScale = v
        }
        Separator {}
        ToggleSetting {
            label: "Reduce transparency"
            detail: "Solid surfaces everywhere: the bar, dock, panels, menus and windows, with nothing blurred or see-through behind them, whatever Glass is set to"
            key: "reduceTransparency"
        }
        Separator {}
        ToggleSetting {
            label: "Reduce motion"
            detail: "Nothing slides, grows or moves: windows and workspaces fade, and Slate's panels and menus appear at once, whatever Animations is set to"
            key: "reduceMotion"
        }
    }
}
