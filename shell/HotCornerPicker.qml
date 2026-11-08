// Settings → Hot corners: a small screen with what each corner does, as an icon and name
// (in the accent when it does something). Click a corner to choose it; the page's action
// list below then sets it.

import QtQuick

Rectangle {
    id: hp
    property string selected: "TopLeft"          // TopLeft, TopRight, BottomLeft or BottomRight
    property var actions: []                     // [{ value, label }]
    property color accent: Config.accent
    property color textColor: "white"
    property color dimColor: "grey"
    property string fontFamily: ""
    property string iconFont: ""
    signal picked(string corner)

    readonly property var icons: ({ lock: 0xEAE2, launcher: 0xEB1C, overview: 0xEDBA, control: 0xEA03,
        notifications: 0xEA35, screenoff: 0xEA89 })
    function labelFor(v) { const a = actions.find(x => x.value === v); return a ? a.label : v; }

    width: 420; height: 230; radius: 14
    color: Config.tint("#151920")
    border.width: 1; border.color: Config.tint("#323a46")

    Repeater {
        model: [{ key: "TopLeft", name: "Top left" }, { key: "TopRight", name: "Top right" },
                { key: "BottomLeft", name: "Bottom left" }, { key: "BottomRight", name: "Bottom right" }]
        delegate: Rectangle {
            id: corner
            required property var modelData
            required property int index
            readonly property string action: Config.s["hotCorner" + modelData.key] || "none"
            readonly property bool on: action !== "none"
            readonly property bool current: hp.selected === modelData.key
            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index >= 2
            width: 150; height: 60; radius: 10
            x: atRight ? hp.width - width - 10 : 10
            y: atBottom ? hp.height - height - 10 : 10
            // Rounded like the screen on the corner it sits in
            topLeftRadius: !atRight && !atBottom ? hp.radius - 4 : 6
            topRightRadius: atRight && !atBottom ? hp.radius - 4 : 6
            bottomLeftRadius: !atRight && atBottom ? hp.radius - 4 : 6
            bottomRightRadius: atRight && atBottom ? hp.radius - 4 : 6
            color: cornerHover.hovered ? Config.hoverOn(Config.tint("#262c35")) : Config.tint("#262c35")
            border.width: current ? 2 : 0
            border.color: hp.accent
            Behavior on color { ColorAnimation { duration: 100 } }

            Row {
                anchors { verticalCenter: parent.verticalCenter; left: corner.atRight ? undefined : parent.left; right: corner.atRight ? parent.right : undefined; leftMargin: 12; rightMargin: 12 }
                layoutDirection: corner.atRight ? Qt.RightToLeft : Qt.LeftToRight
                spacing: 10
                Rectangle {
                    width: 32; height: 32; radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: corner.on ? Qt.rgba(hp.accent.r, hp.accent.g, hp.accent.b, 0.18) : Config.tint("#1d222a")
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(corner.on ? (hp.icons[corner.action] || 0xF7A0) : 0xF7A0)
                        color: corner.on ? hp.accent : hp.dimColor
                        opacity: corner.on ? 1 : 0.6
                        font.family: hp.iconFont; font.pixelSize: 17
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        anchors.right: corner.atRight ? parent.right : undefined
                        text: corner.modelData.name
                        color: hp.dimColor
                        font.family: hp.fontFamily; font.pixelSize: 11
                    }
                    Text {
                        anchors.right: corner.atRight ? parent.right : undefined
                        width: Math.min(implicitWidth, 92)
                        horizontalAlignment: corner.atRight ? Text.AlignRight : Text.AlignLeft
                        text: hp.labelFor(corner.action)
                        color: corner.on ? hp.textColor : hp.dimColor
                        font.family: hp.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                }
            }
            HoverHandler { id: cornerHover }
            TapHandler { onTapped: hp.picked(corner.modelData.key) }
        }
    }

    // The middle: what to do
    Text {
        anchors.centerIn: parent
        text: "Click a corner, then pick\nwhat it does below"
        horizontalAlignment: Text.AlignHCenter
        color: hp.dimColor
        opacity: 0.7
        font.family: hp.fontFamily; font.pixelSize: 12
    }
}
