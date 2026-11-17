import QtQuick
import Quickshell
import "../.."
import ".."

// Settings → Timers: the drink reminder and the focus timer (Timers.qml), each on the menu bar,
// the dock or both, with their panels (panels/DrinkPanel.qml, FocusPanel.qml)
Column {
    id: timersPage
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "Timers" }
    IntroText {
        text: "Gentle timers for your day: a reminder to drink some water, and a focus timer that keeps you to short, steady rounds with breaks between. Each can sit on the menu bar, the dock or both."
    }
    readonly property var places: [{ value: "bar", label: "Menu bar" }, { value: "dock", label: "Dock" }, { value: "both", label: "Both" }]

    GroupLabel { text: "Drink reminder" }
    Group {
        ToggleSetting {
            label: "Drink reminder"
            detail: "A gentle notification when it's time for a drink. Press \"I've had a drink\" (on the notification, in its panel or on the dock) to start the next wait"
            key: "drinkReminder"
        }
        Separator {}
        SettingRow {
            label: "Every"
            settingKey: "drinkMinutes"
            needsMet: Config.s.drinkReminder
            needs: "Needs Drink reminder to be on"
            needsPage: "timers"; needsLabel: "Drink reminder"
            ValueSlider { from: 15; to: 120; stepSize: 5; suffix: " min"; value: Config.s.drinkMinutes; onMoved: v => Config.s.drinkMinutes = v }
        }
        Separator {}
        DropdownSetting {
            label: "Show on"
            // (the menu bar's switch for it and the dock's, as one choice)
            needsMet: Config.s.drinkReminder
            needs: "Needs Drink reminder to be on"
            needsPage: "timers"; needsLabel: "Drink reminder"
            options: timersPage.places
            value: Config.s.barShowDrink && Config.s.dockShowDrink ? "both" : Config.s.dockShowDrink ? "dock" : "bar"
            onPicked: v => { Config.s.barShowDrink = v !== "dock"; Config.s.dockShowDrink = v !== "bar"; }
        }
    }

    GroupLabel { text: "Focus timer" }
    Group {
        ToggleSetting {
            label: "Focus timer"
            detail: "Focus for a while, then take a short break; a longer one after a few rounds. Start it from its panel or the dock"
            key: "focusTimer"
        }
        Separator {}
        SettingRow {
            label: "Focus for"
            settingKey: "focusMinutes"
            needsMet: Config.s.focusTimer
            needs: "Needs Focus timer to be on"
            needsPage: "timers"; needsLabel: "Focus timer"
            ValueSlider { from: 5; to: 90; stepSize: 5; suffix: " min"; value: Config.s.focusMinutes; onMoved: v => Config.s.focusMinutes = v }
        }
        Separator {}
        SettingRow {
            label: "Short break"
            settingKey: "focusBreakMinutes"
            needsMet: Config.s.focusTimer
            needs: "Needs Focus timer to be on"
            needsPage: "timers"; needsLabel: "Focus timer"
            ValueSlider { from: 1; to: 30; stepSize: 1; suffix: " min"; value: Config.s.focusBreakMinutes; onMoved: v => Config.s.focusBreakMinutes = v }
        }
        Separator {}
        SettingRow {
            label: "Long break"
            settingKey: "focusLongBreakMinutes"
            needsMet: Config.s.focusTimer
            needs: "Needs Focus timer to be on"
            needsPage: "timers"; needsLabel: "Focus timer"
            ValueSlider { from: 5; to: 60; stepSize: 5; suffix: " min"; value: Config.s.focusLongBreakMinutes; onMoved: v => Config.s.focusLongBreakMinutes = v }
        }
        Separator {}
        SettingRow {
            label: "Rounds before a long break"
            settingKey: "focusRounds"
            needsMet: Config.s.focusTimer
            needs: "Needs Focus timer to be on"
            needsPage: "timers"; needsLabel: "Focus timer"
            ValueSlider { from: 2; to: 8; stepSize: 1; value: Config.s.focusRounds; onMoved: v => Config.s.focusRounds = v }
        }
        Separator {}
        ToggleSetting {
            label: "Do Not Disturb while focusing"
            detail: "Notifications wait quietly in the list until your break"
            key: "focusQuiet"
            needsMet: Config.s.focusTimer
            needs: "Needs Focus timer to be on"
            needsPage: "timers"; needsLabel: "Focus timer"
        }
        Separator {}
        DropdownSetting {
            label: "Show on"
            // (the menu bar's switch for it and the dock's, as one choice)
            needsMet: Config.s.focusTimer
            needs: "Needs Focus timer to be on"
            needsPage: "timers"; needsLabel: "Focus timer"
            options: timersPage.places
            value: Config.s.barShowFocus && Config.s.dockShowFocus ? "both" : Config.s.dockShowFocus ? "dock" : "bar"
            onPicked: v => { Config.s.barShowFocus = v !== "dock"; Config.s.dockShowFocus = v !== "bar"; }
        }
    }
}
