import QtQuick

// A window drawn as its shape: an outline on a soft fill, for the switcher and the overview
// when live previews are off (or in game mode). The caller sizes it and puts the app's tile in it.
Rectangle {
    radius: Config.corner(8)
    color: Qt.rgba(0.07, 0.08, 0.1, 0.72)
    border.width: 1.5
    border.color: Qt.rgba(1, 1, 1, 0.35)
}
