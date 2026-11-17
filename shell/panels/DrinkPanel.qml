import QtQuick
import Quickshell
import qs

// The drink reminder (Timers.qml; Settings → Timers): when the next drink is due, how many today,
// and "I've had a drink", which starts the next wait
Column {
    required property var pop
    id: drinkView
    width: 300
    spacing: 10
    PanelTitle {
        text: "Drink Reminder"
        Switch {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            checked: Config.s.drinkReminder
            onToggled: Config.s.drinkReminder = !Config.s.drinkReminder
        }
    }
    // A big, calm countdown, and the ring it empties
    Item {
        visible: Timers.drinkOn
        width: parent.width; height: 132
        TimerRing {
            anchors.centerIn: parent
            size: 120
            progress: Timers.drinkProgress
            colour: Timers.drinkOverdue ? pop.accent : Config.statusColour("drink", pop.accent)
            trackColour: pop.card
            Column {
                anchors.centerIn: parent
                spacing: 2
                Icon { anchors.horizontalCenter: parent.horizontalCenter; code: 0xEA97; font.pixelSize: 22; color: Timers.drinkOverdue ? pop.accent : pop.text }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Timers.drinkOverdue ? "Now" : Timers.minutes(Timers.drinkLeft)
                    font.pixelSize: Config.text(15)
                }
            }
        }
    }
    Label {
        width: parent.width
        wrapMode: Text.Wrap
        color: pop.dim
        font.pixelSize: Config.text(12)
        font.weight: Font.Normal
        text: !Timers.drinkOn ? "A gentle reminder to drink some water every " + Config.s.drinkMinutes + " minutes"
            : Timers.drinkOverdue ? "Time for a drink. Press below once you've had one, and the next wait starts"
            : "Next drink in " + Timers.minutes(Timers.drinkLeft) + (Timers.drinksToday > 0
                ? ". " + Timers.drinksToday + (Timers.drinksToday === 1 ? " drink" : " drinks") + " today" : "")
    }
    RowButton {
        visible: Timers.drinkOn
        width: parent.width
        selected: Timers.drinkOverdue
        onClicked: Timers.drank()
        Icon {
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            code: 0xEA5E; font.pixelSize: 16; color: parent.fgDim
        }
        Label {
            anchors { left: parent.left; leftMargin: 36; verticalCenter: parent.verticalCenter }
            text: "I've had a drink"; font.weight: Font.Normal; color: parent.fg
        }
    }
    Divider {}
    LinkRow { code: 0xEB20; text: "Timer settings"; onClicked: pop.openSettingsPage("timers") }
}
