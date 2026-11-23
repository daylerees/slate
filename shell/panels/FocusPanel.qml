import QtQuick
import qs

// The focus timer (Timers.qml; Settings → Timers): a Pomodoro. The round's countdown and its
// ring, which round this is, and Start / Pause, Skip and Reset
Column {
    required property var pop
    id: focusView
    width: 300
    spacing: 10
    readonly property string phaseName: ({ idle: "Ready to focus", focus: "Focusing", break: "Short break", long: "Long break" })[Timers.phase] || ""
    PanelTitle {
        text: "Focus Timer"
        Switch {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            checked: Config.s.focusTimer
            onToggled: Config.s.focusTimer = !Config.s.focusTimer
        }
    }
    Item {
        visible: Timers.focusOn
        width: parent.width; height: 132
        TimerRing {
            anchors.centerIn: parent
            size: 120
            progress: Timers.phase === "idle" ? 1 : Timers.focusProgress
            colour: Timers.phase === "focus" ? Config.statusColour("focus", pop.accent) : pop.accent
            trackColour: pop.card
            Column {
                anchors.centerIn: parent
                spacing: 2
                Icon { anchors.horizontalCenter: parent.horizontalCenter; code: Timers.phase === "break" || Timers.phase === "long" ? 0xEAFB : 0xEA70; font.pixelSize: 20; color: pop.text }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Timers.phase === "idle" ? Config.s.focusMinutes + ":00" : Timers.clock(Timers.focusLeft)
                    font.pixelSize: Config.text(18)
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
        text: !Timers.focusOn ? "Focus for " + Config.s.focusMinutes + " minutes, then take a short break; a longer one after every " + Config.s.focusRounds + " rounds"
            : focusView.phaseName + (Timers.paused ? " (paused)" : "") + " · round " + (Timers.round + (Timers.phase === "focus" || Timers.phase === "idle" ? 1 : 0)) + " of " + Config.s.focusRounds
              + (Timers.roundsToday > 0 ? " · " + Timers.roundsToday + " today" : "")
              + (Config.s.focusQuiet && Timers.phase === "focus" ? ". Do Not Disturb is on while you focus" : "")
    }
    Row {
        visible: Timers.focusOn
        width: parent.width
        spacing: 8
        Repeater {
            model: [
                { id: "toggle", label: Timers.phase === "idle" ? "Start" : Timers.paused ? "Resume" : "Pause",
                  code: Timers.phase === "idle" || Timers.paused ? 0xF691 : 0xF690 },
                { id: "skip", label: Timers.phase === "focus" ? "Break" : "Skip", code: 0xF694, off: Timers.phase === "idle" },
                { id: "reset", label: "Reset", code: 0xEB13, off: Timers.phase === "idle" && Timers.round === 0 }
            ]
            delegate: RowButton {
                required property var modelData
                width: (focusView.width - 16) / 3
                enabled: !modelData.off
                opacity: enabled ? 1 : 0.4
                selected: modelData.id === "toggle" && Timers.phase === "idle"
                onClicked: modelData.id === "toggle" ? Timers.toggleFocus() : modelData.id === "skip" ? Timers.nextPhase() : Timers.resetFocus()
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; code: modelData.code; font.pixelSize: 14; color: parent.parent.fg }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: modelData.label; font.weight: Font.Normal; color: parent.parent.fg }
                }
            }
        }
    }
    Divider {}
    LinkRow { code: 0xEB20; text: "Timer settings"; onClicked: pop.openSettingsPage("timers") }
}
