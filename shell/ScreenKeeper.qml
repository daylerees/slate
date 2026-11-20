import QtQuick
import Quickshell

// Brings back a window that follows a screen (one window that moves, not one made per screen as
// the wallpaper is) after every screen has gone for a moment, as many monitors do going into
// standby. With no screen, Qt puts the window on a stand-in of its own, and once the real screen
// was back the window stayed there, unseen: the menu bar, the dock and the notifications were
// gone until Slate restarted. So the window is hidden while there's no screen (its `visible`
// takes `&& keeper.ready`) and shown again a moment after one returns, which makes it afresh on
// that screen. A window that places itself (rather than binding `screen`) gives `home`, the
// screen to go back to.
QtObject {
    id: keeper

    property var window: null
    property var home: null                 // function () → a screen, for a window whose screen is set in code
    // Whether there's a real screen (Qt's stand-in has no name)
    readonly property bool anyScreen: Quickshell.screens.some(s => s.name !== "")
    property bool ready: true
    property int returns: 0                 // (the tests: how many times it has come back)

    onAnyScreenChanged: {
        if (anyScreen) {
            settle.restart();
        } else {
            settle.stop();
            ready = false;
        }
    }

    // A moment for Hyprland to finish setting the screen up (a monitor waking can drop off and
    // come back again within a second or two), then the window is made again on it
    property Timer settle: Timer {
        interval: 400
        onTriggered: {
            if (keeper.home && keeper.window) {
                const s = keeper.window.screen;
                if (!s || !Quickshell.screens.includes(s)) keeper.window.screen = keeper.home();
            }
            if (!keeper.ready) keeper.returns++;
            keeper.ready = true;
        }
    }
}
