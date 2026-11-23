import QtQuick
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "Spaces" }
    IntroText { text: "Save the apps on some workspaces, and where their windows sit, as a space; then bring them all back on new workspaces in one click from the Spaces button on the menu bar." }
    GroupLabel { text: "Menu Bar" }
    Group {
        ToggleSetting {
            label: "Color the window's icon"
            detail: "When the focused window came from a space, its icon on the menu bar sits on the space's color"
            key: "spaceBarTint"
        }
    }
    GroupLabel { text: "Windows from a space" }
    Group {
        ToggleSetting {
            label: "Top border"
            detail: "A thin line in the space's color along the top of each window"
            key: "spaceBorders"
        }
        Separator {}
        ToggleSetting {
            label: "Corner badge"
            detail: "The space's icon in the window's top left corner; it moves to the other corner when the pointer comes near"
            key: "spaceBadges"
        }
        Separator {}
        ToggleSetting {
            label: "Badges in the switchers"
            detail: "The space's icon on its windows in the window switcher (Super+Tab) and the workspace overview (Super+Down)"
            key: "spaceSwitcherBadges"
        }
    }
}
