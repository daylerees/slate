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
    GroupLabel { text: "Display" }
    Group {
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
