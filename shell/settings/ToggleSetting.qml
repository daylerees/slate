import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// A setting that's a plain switch for one of Slate's settings: key is its name in
// SettingsData (ToggleSetting { label: "…"; detail: "…"; key: "barShowApps" })
SettingRow {
    id: toggleRow
    property string key
    settingKey: key
    SettingToggle { checked: Config.s[toggleRow.key]; onToggled: v => Config.s[toggleRow.key] = v }
}
