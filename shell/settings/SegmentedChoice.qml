import QtQuick
import ".."

// A choice of two or three side by side in one well (Theme: Dark | Light | Auto), the chosen one
// filled with the accent, which slides to a new choice. Each option: { value, label }, with an
// icon (a Tabler code point) or a dot ("circle" or "square": the workspace dots' shape) before
// its label.
//   SegmentedChoice { options: [...]; value: Config.s.launcherLayout; onPicked: v => Config.s.launcherLayout = v }
Rectangle {
    id: choice
    readonly property var win: SettingsHost.win
    property var options: []
    property var value
    property int iconSize: 14
    signal picked(var value)
    readonly property int segment: 92
    readonly property int at: Math.max(0, options.findIndex(o => o.value === value))
    width: options.length * segment; height: 34; radius: Config.corner(9)
    color: win.well
    Rectangle {
        width: choice.segment - 6; height: parent.height - 6; radius: Config.corner(7)
        y: 3; x: 3 + choice.at * choice.segment
        color: choice.win.accent
        Behavior on x { NumberAnimation { duration: Config.ms(160); easing.type: Easing.OutCubic } }
    }
    Row {
        anchors.fill: parent
        Repeater {
            model: choice.options
            delegate: Item {
                id: opt
                required property var modelData
                readonly property bool on: choice.value === modelData.value
                readonly property color ink: on ? choice.win.accentText : choice.win.dim
                width: choice.segment; height: 34
                Rectangle {
                    anchors { fill: parent; margins: 3 }
                    radius: Config.corner(7)
                    color: choice.win.accent
                    opacity: !opt.on && optHover.hovered ? Config.hoverStrength : 0
                }
                HoverHandler { id: optHover }
                Row {
                    anchors.centerIn: parent
                    spacing: opt.modelData.dot ? 7 : 6
                    Text {
                        visible: !!opt.modelData.icon
                        anchors.verticalCenter: parent.verticalCenter
                        text: opt.modelData.icon ? Config.glyph(opt.modelData.icon) : ""
                        color: opt.ink; font.family: Config.iconFont; font.pixelSize: choice.iconSize
                    }
                    Rectangle {
                        visible: !!opt.modelData.dot
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 10
                        radius: opt.modelData.dot === "square" ? 10 * 0.28 : 5
                        color: opt.ink
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: opt.modelData.label; color: opt.ink
                        font.family: choice.win.font; font.pixelSize: Config.text(12); font.weight: Font.Medium
                    }
                }
                ClickTap { onTapped: choice.picked(opt.modelData.value) }
            }
        }
    }
}
