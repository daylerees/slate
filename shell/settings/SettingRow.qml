import QtQuick
import ".."

// One setting: label + description on the left, a control on the right
Item {
    readonly property var win: SettingsHost.win
    id: settingRow
    property string label
    property string detail: ""
    default property alias control: controlSlot.data
    // Optional buttons under the description (below: [Button {…}, …]); takes no room when empty
    property alias below: belowSlot.data
    // ...and something on the right edge, level with them (belowRight: [Item {…}])
    property alias belowRight: belowRightSlot.data
    // The Slate setting this row changes (its name in SettingsData), for the mark that shows
    // it's been changed from its default; defaultText says what that default is, when the
    // row can't work it out (a switch: On/Off; a slider: its value, as the slider shows it)
    property string settingKey: ""
    property string defaultText: ""
    // A setting that only works while another one is on (or off): needsMet says whether it
    // is, and needs says which, in a short line under the description while it isn't
    // ("Needs Glass to be on"). Meanwhile the row greys out, but the line stays clickable
    // and goes to that setting (needsPage and needsLabel, as win.goTo takes them)
    property string needs: ""
    property bool needsMet: true
    property string needsPage: ""
    property string needsLabel: ""
    readonly property bool waiting: needs !== "" && !needsMet
    readonly property real waitOpacity: waiting ? 0.4 : 1
    readonly property bool changed: settingKey !== "" && Config.defaultOf(settingKey) !== undefined
        && !Config.sameValue(Config.s[settingKey], Config.defaultOf(settingKey))
    readonly property string defaultShown: {
        if (defaultText !== "") return defaultText;
        const d = settingKey !== "" ? Config.defaultOf(settingKey) : undefined;
        if (typeof d === "boolean") return d ? "On" : "Off";
        if (typeof d === "number") {
            const sl = controlSlot.children.length ? controlSlot.children[0] : null;
            if (sl && sl.suffix !== undefined) {
                // (as the slider would show it: a 0–1 setting on a percentage slider is 80%, not 1%)
                const v = d * (sl.per || 1);
                if (sl.zeroText && v <= sl.from) return sl.zeroText;
                return v.toFixed(sl.decimals || 0) + sl.suffix;
            }
            return String(d);
        }
        return d === undefined || d === "" ? "none" : String(d);
    }
    width: parent ? parent.width : 0
    height: Math.max(56, labels.implicitHeight + 24, controlSlot.height + 24)
    Column {
        id: labels
        anchors { left: parent.left; leftMargin: 16; right: controlSlot.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 2
        Text {
            id: labelText
            // (room left after the name for the changed-from-default dot)
            width: Math.min(implicitWidth, parent.width - (settingRow.changed ? 20 : 0))
            textFormat: Text.PlainText        // never markup: a row can be named after an app, a device or a download
            text: label; color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium; elide: Text.ElideRight
            opacity: settingRow.waitOpacity
            Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
        }
        Text {
            width: Math.min(parent.width, win.detailMeasure); visible: detail !== ""; textFormat: Text.PlainText; text: detail; color: win.dim; font.family: win.font; font.pixelSize: Config.text(12); wrapMode: Text.Wrap
            opacity: settingRow.waitOpacity
            Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
        }
        // What it's waiting for, and the way there: a quiet link, the muted hover under the pointer
        Item {
            id: needsLine
            objectName: "needsLine"
            visible: settingRow.waiting
            readonly property bool linked: settingRow.needsPage !== ""
            x: -6
            width: needsRow.implicitWidth + 12; height: needsRow.implicitHeight + 6
            Rectangle {
                anchors.fill: parent
                radius: Config.corner(6)
                color: needsLine.linked && needsHover.hovered ? Config.hover : "transparent"
            }
            Row {
                id: needsRow
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                spacing: 5
                Text {
                    width: Math.min(implicitWidth, labels.width - 24)
                    text: settingRow.needs; color: win.dim; font.family: win.font; font.pixelSize: Config.text(12); elide: Text.ElideRight
                }
                Text {
                    visible: needsLine.linked
                    anchors.verticalCenter: parent.verticalCenter
                    text: Config.glyph(0xEA1F)          // an arrow: it goes there
                    color: win.dim; font.family: win.bar.iconFont; font.pixelSize: 12
                }
            }
            HoverHandler { id: needsHover }
            ClickTap { enabled: needsLine.linked; onTapped: win.goTo(settingRow.needsPage, settingRow.needsLabel) }
        }
        Row {
            id: belowSlot
            spacing: 8
            topPadding: visibleChildren.length > 0 ? 8 : 0
            enabled: !settingRow.waiting
            opacity: settingRow.waitOpacity
            Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
        }
    }
    Item {
        id: belowRightSlot
        enabled: !settingRow.waiting
        opacity: settingRow.waitOpacity
        anchors { right: parent.right; rightMargin: 16 }
        y: labels.y + belowSlot.y + belowSlot.topPadding
        height: Math.max(0, belowSlot.height - belowSlot.topPadding)
        width: 0          // (what's in it is anchored to its right, the row's right edge)
    }
    // Changed from its default: a small dot after the name. Pointed at, it says what the
    // default is; clicked, it puts it back. (The row comes above its neighbours meanwhile, so
    // the bubble isn't drawn under them)
    z: dotHover.hovered ? 5 : 0
    Rectangle {
        id: changedDot
        visible: settingRow.changed
        x: labels.x + labelText.width + 8
        y: labels.y + labelText.height / 2 - height / 2
        width: 8; height: 8; radius: Config.corner(4)
        color: win.accent
        scale: dotHover.hovered ? 1.4 : 1
        Behavior on scale { NumberAnimation { duration: Config.ms(100) } }
        // Easier to point at than it looks: it reacts 10 px all round
        HoverHandler { id: dotHover; margin: 10; cursorShape: Qt.PointingHandCursor }
        ClickTap { margin: 10; onTapped: Config.resetKeys([settingRow.settingKey]) }
    }
    // (Slate's tooltip, Tooltip.qml; solid, as it lies over the page rather than the desktop)
    Tooltip {
        visible: changedDot.visible && dotHover.hovered
        z: 2
        solid: true
        x: changedDot.x + 18
        y: changedDot.y + changedDot.height / 2 - height / 2
        text: "Default: " + settingRow.defaultShown + "  ·  click to use it"
    }
    Item {
        id: controlSlot
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        width: childrenRect.width; height: childrenRect.height
        enabled: !settingRow.waiting
        opacity: settingRow.waitOpacity
        Behavior on opacity { NumberAnimation { duration: Config.ms(150) } }
    }
}
