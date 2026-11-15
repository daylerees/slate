pragma Singleton

// The Settings window, handed to the building blocks and pages in this folder. They're files of
// their own, so they can't see the window's ids the way they could when they were all inside
// SettingsWindow.qml; each one that needs the window declares `readonly property var win:
// SettingsHost.win` and goes on writing win.dim, win.accent, win.goTo… as before. The window
// sets this as it's built (there's only ever the one).
import QtQuick

QtObject {
    property var win: null
}
