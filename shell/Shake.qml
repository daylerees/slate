// A wrong password: the card shakes side to side, a short way and back (the lock and login
// screens' password frame, and the password prompt). Put on what shakes, and run it:
//   transform: Shake { id: shake }        shake.restart()
import QtQuick

Translate {
    id: tr
    function restart() { run.restart(); }
    readonly property SequentialAnimation run: SequentialAnimation {
        NumberAnimation { target: tr; property: "x"; to: -12; duration: Config.ms(50) }
        NumberAnimation { target: tr; property: "x"; to: 10; duration: Config.ms(70) }
        NumberAnimation { target: tr; property: "x"; to: -6; duration: Config.ms(60) }
        NumberAnimation { target: tr; property: "x"; to: 0; duration: Config.ms(60) }
    }
}
