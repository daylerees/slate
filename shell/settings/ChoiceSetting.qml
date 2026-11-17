import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// A setting with a few named options: shows the current one; click to pick.
// options: [{ value, label }]
Column {
    readonly property var win: SettingsHost.win
    id: choiceSetting
    property string label
    property string detail: ""
    property var options: []
    property var value
    property bool open: false
    signal picked(var value)
    property string settingKey: ""          // (as SettingRow's: the changed-from-default mark)
    // (as SettingRow's: what it needs, when it can't be used)
    property string needs: ""
    property bool needsMet: true
    property string needsPage: ""
    property string needsLabel: ""
    width: parent ? parent.width : 0
    readonly property var current: options.find(o => o.value === value) ?? null
    SettingRow {
        label: choiceSetting.label
        detail: choiceSetting.detail
        settingKey: choiceSetting.settingKey
        needs: choiceSetting.needs; needsMet: choiceSetting.needsMet
        needsPage: choiceSetting.needsPage; needsLabel: choiceSetting.needsLabel
        defaultText: {
            const d = choiceSetting.settingKey !== "" ? Config.defaultOf(choiceSetting.settingKey) : undefined;
            const o = d === undefined ? null : choiceSetting.options.find(x => x.value === d);
            return o ? o.label : "";
        }
        Button {
            label: (choiceSetting.current ? choiceSetting.current.label : String(choiceSetting.value)) + (choiceSetting.open ? "  ▴" : "  ▾")
            primary: choiceSetting.open
            onClicked: choiceSetting.open = !choiceSetting.open
        }
    }
    Flow {
        visible: choiceSetting.open && choiceSetting.needsMet
        width: parent.width - 32; x: 16
        spacing: 6
        bottomPadding: 14
        Repeater {
            model: choiceSetting.options
            delegate: Rectangle {
                required property var modelData
                readonly property bool on: modelData.value === choiceSetting.value
                width: optText.implicitWidth + 26; height: 32; radius: Config.corner(8)
                color: on ? win.accent : "transparent"
                Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                HoverFill { base: win.control; hovered: optHover.hovered; gone: parent.on; radius: parent.radius }
                Text { id: optText; anchors.centerIn: parent; text: parent.modelData.label; color: parent.on ? win.accentText : win.text; font.family: win.font; font.pixelSize: Config.text(12); font.weight: Font.Medium }
                HoverHandler { id: optHover }
                ClickTap { onTapped: { choiceSetting.picked(parent.modelData.value); choiceSetting.open = false; } }
            }
        }
    }
}
