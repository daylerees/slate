import QtQuick
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "Control Center" }
    IntroText { text: "The control center has eight quick switches. Drag one onto another and the two change places; drag one across from More switches to put it in. You can change this at any time." }
    SwitchBoard {
        width: parent.width
        label: "Quick switches"
        all: Config.controlSwitchesHere
        chosen: Config.controlSwitches
        most: Config.controlSwitchesMost
        onPicked: ids => Config.s.controlSwitches = ids
        card: win.card; well: win.well; tile: win.control; outline: win.outline
        text: win.text; dim: win.dim
        accent: win.accent; accentText: win.accentText
        font: win.font; iconFont: win.bar.iconFont
    }
}
