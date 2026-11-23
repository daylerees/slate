import QtQuick
import ".."

// The switch on a Settings row: Toggle.qml in this window's colours
Toggle {
    readonly property var win: SettingsHost.win
    hoverFill: true; fillBase: win.control
    ringColor: win.accent
    knobOn: win.accentText; knobOff: win.text
    // (a screen reader: named for its row, "Glass", unless it's given a name of its own)
    property string name: ""
    readonly property string rowLabel: {
        for (let p = parent; p; p = p.parent) if (p.settingKey !== undefined && p.label !== undefined) return p.label;
        return "";
    }
    Accessible.name: name !== "" ? name : rowLabel
}
