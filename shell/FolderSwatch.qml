// A small folder in a colour, the way Papirus draws its coloured folders: a darker back with
// its tab, and the colour in front. Settings → Icons → Folder colour.

import QtQuick

Item {
    id: fs
    property color colour: "#5294e2"
    width: 20; height: 16

    // Back, with the tab on its top left
    Rectangle {
        x: 0; y: 0
        width: fs.width * 0.45; height: fs.height * 0.4
        radius: 1.5
        color: Qt.darker(fs.colour, 1.35)
    }
    Rectangle {
        x: 0; y: fs.height * 0.14
        width: fs.width; height: fs.height * 0.86
        radius: 2
        color: Qt.darker(fs.colour, 1.35)
    }
    // Front
    Rectangle {
        x: 0; y: fs.height * 0.3
        width: fs.width; height: fs.height * 0.7
        radius: 2
        color: fs.colour
        // A faint light edge along its top
        Rectangle { width: parent.width; height: 1; color: Qt.lighter(fs.colour, 1.25); opacity: 0.7; x: 0; y: 0; radius: 1 }
    }
}
