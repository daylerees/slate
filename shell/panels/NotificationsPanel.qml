import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import QtQuick.Effects
import qs

// ---- Notifications -----------------------------------------------------
Column {
    required property var pop
    id: notifView
    width: 380
    spacing: 10
    readonly property var list: pop.notifs ? pop.notifs.history : []
    // (each by its key, for its row to find)
    readonly property var byKey: { const m = {}; for (const h of list) m[h.key] = h; return m; }
    readonly property var testList: nList

    PanelTitle {
        text: "Notifications"
        height: 28
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
            Label { anchors.verticalCenter: parent.verticalCenter; text: "Do Not Disturb"; color: pop.dim; font.pixelSize: Config.text(12) }
            Switch {
                anchors.verticalCenter: parent.verticalCenter
                checked: pop.notifs ? pop.notifs.quiet : false
                onToggled: if (pop.notifs) pop.notifs.setQuiet(!pop.notifs.quiet)
            }
            RowButton {
                visible: notifView.list.length > 0
                width: 30; height: 28
                danger: true
                onClicked: if (pop.notifs) pop.notifs.clearAll()
                Icon { anchors.centerIn: parent; code: 0xEB41; font.pixelSize: 16; color: pop.danger }
            }
        }
    }

    // (on by itself: why, and till when)
    Label {
        visible: !!pop.notifs && pop.notifs.quietWhy !== ""
        width: parent.width
        text: pop.notifs ? "Do Not Disturb is on " + pop.notifs.quietWhy : ""
        color: pop.dim; font.pixelSize: Config.text(12); font.weight: Font.Normal; wrapMode: Text.Wrap
    }
    Item {
        visible: notifView.list.length === 0
        width: parent.width; height: 120
        Column {
            anchors.centerIn: parent
            spacing: 8
            Icon { anchors.horizontalCenter: parent.horizontalCenter; code: 0xEA35; font.pixelSize: 26; color: pop.dim }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: "All caught up. Nothing new"; color: pop.dim }
        }
    }

    ListView {
        id: nList
        visible: notifView.list.length > 0
        width: parent.width
        // At most 480, less on a short screen (with room for the title row and the panel's
        // edges), so the panel never runs off the screen
        height: Math.min(contentHeight, 480, Math.max(160, pop.height - 160))
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        // A row for each notification, by its key, kept while the notification is: one
        // coming or going leaves the others as they are, where you'd scrolled to, and
        // the row that goes fades while the rest close up (remove and displaced, below).
        // Handed the history itself, a new list each time, every row was made again
        model: ScriptModel { values: notifView.list.map(h => h.key) }
        readonly property bool overflowing: contentHeight > height
        SmoothWheel { flick: nList }
        delegate: NotificationCard {
            required property var modelData      // its notification's key
            // What it shows: its notification, and still that as it fades away, once the
            // notification has gone from the history
            readonly property var now: notifView.byKey[modelData]
            property var kept: null
            onNowChanged: if (now) kept = now
            Component.onCompleted: { kept = now ?? null; pop.rowMade("notifications"); }
            width: nList.width - (nList.overflowing ? 18 : 0)   // room for the scrollbar and a gap before it
            bar: pop.bar
            inPanel: true
            entry: now ?? kept
            notif: pop.notifs ? (pop.notifs.live[modelData] ?? null) : null
            onActivated: { pop.notifs.activate(modelData); pop.close(); }
            onClosed: pop.notifs.remove(modelData)
            onAction: id => { pop.notifs.invokeAction(modelData, id); pop.close(); }
        }
        // One that arrives while the panel is open slides in a little from the side and
        // fades up as the rest make room (displaced). Not when Animations are off or in
        // game mode: it's simply there. (The rows the panel opens with aren't animated)
        add: Transition {
            enabled: Config.animate
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Config.ms(180) }
                NumberAnimation { property: "x"; from: 24; to: 0; duration: Config.ms(220); easing.type: Easing.OutCubic }
            }
        }
        remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Config.ms(150) } }
        displaced: Transition { NumberAnimation { property: "y"; duration: Config.ms(180); easing.type: Easing.OutCubic } }

        // Scrollbar (ThinScrollbar, as everywhere), only when the list overflows
        ThinScrollbar {
            parent: nList
            flick: nList
            color: pop.text
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        }

        // Shades at the top once scrolled down and at the bottom while there's more,
        // parented to the list itself (not its scrolling content) so they stay put
        ScrollShade { parent: nList; z: 3; width: nList.width; cornerRadius: 8; distance: nList.contentY - nList.originY }
        ScrollShade { parent: nList; z: 3; atBottom: true; y: nList.height - height; width: nList.width; cornerRadius: 8
                      distance: nList.originY + nList.contentHeight - nList.height - nList.contentY }
    }
}
