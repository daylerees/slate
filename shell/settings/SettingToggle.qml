import QtQuick
import ".."

// The switch on a Settings row: Toggle.qml in this window's colours
Toggle {
    readonly property var win: SettingsHost.win
    hoverFill: true; fillBase: win.control
    ringColor: win.accent
    knobOn: win.accentText; knobOff: win.text
}
