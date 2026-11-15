// Holds back what's slow or reaches outside Slate while the wallpaper switcher is just looking:
// borders, App Theming, folder colours, title bar buttons and the login screen's sync each ask
// heldBack(their timer) before running, and are started again once when the switcher closes.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    // While the wallpaper switcher shows wallpapers (Config.wallpaperSwitching), the theme follows
    // each one in Slate alone: what's slow or reaches outside Slate (App theming, folder colours,
    // title bar buttons, which can reload Hyprland, window borders, the login screen) is held,
    // and done once when it closes, for the wallpaper kept (or not at all, if nothing changed)
    property var heldUpdates: []
    function heldBack(timer) {
        if (!Config.wallpaperSwitching) return false;
        if (!heldUpdates.includes(timer)) heldUpdates = heldUpdates.concat([timer]);
        return true;
    }
    Connections {
        target: Config
        function onWallpaperSwitchingChanged() {
            if (Config.wallpaperSwitching) return;
            const held = root.heldUpdates;
            root.heldUpdates = [];
            for (const t of held) t.restart();
        }
    }
}
