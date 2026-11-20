// One screen of the login screen: greeter/shell.qml makes one per screen, the login box
// on the first and just the wallpaper on the others. In its own file because a window
// can't be loaded without a display, and the installer's check (no display) loads
// shell.qml to make sure the login screen works before installing it.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: win
    required property var modelData            // { screen, greeter: shell.qml's root }
    readonly property var greeter: modelData.greeter
    readonly property bool primary: modelData.screen === Quickshell.screens[0]
    screen: modelData.screen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "slate-greeter"
    WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "#0f1216"
    LoginScreen {
        id: screen
        anchors.fill: parent
        mode: "login"
        visible: true
        wallpaper: win.greeter.haveWallpaper ? win.greeter.wallpaper : ""
        avatar: win.greeter.avatar
        displayName: win.greeter.displayName
        people: win.greeter.people
        personIndex: win.greeter.personIndex
        onPersonPicked: i => {
            // (a question from the last attempt belongs to the last person: ended first)
            if (win.greeter.asking || win.greeter.auto) win.greeter.cancelAsking();
            win.greeter.personChosen = true; win.greeter.personIndex = i;
        }
        sessions: win.greeter.sessions
        sessionIndex: win.greeter.sessionIndex
        onSessionIndexChanged: win.greeter.sessionIndex = sessionIndex
        busy: win.greeter.busy
        message: win.greeter.message
        messageIsError: win.greeter.messageIsError
        showPowerMenu: true
        interactive: win.primary
        iconFontSource: "file://" + win.greeter.dir + "/fonts/tabler.ttf"
        onSubmitted: pw => win.greeter.submit(pw)
        hint: win.greeter.hint
        onActivity: win.greeter.activity()
        onPowerAction: a => win.greeter.power(a)
        onCancelled: win.greeter.cancelAsking()
        Connections {
            target: win.greeter
            function onFailed(t) { screen.fail(t); }
            function onAsked(q, v) { screen.ask(q, v); }
            function onNoted(t, e) { screen.note(t, e); }
        }
    }
}
