// The sheen on an app icon's tile with glass (Settings → Appearance → Glass → Gloss), the same
// wherever icons show: the dock, launcher, switchers, notifications, the bar. Put it inside the
// icon's Image, after its IconPlate:  IconGloss {}
// Not on icons shown as they come (no tile to follow).

import QtQuick

Gloss {
    glassHint: true
    // On a tile in the icon's own colour (Settings → Icons): a lighter tint of that tile, as on a
    // coloured fill (a plain white on a grey tile), rather than the wallpaper's colour, which
    // showed as the accent on grey tiles. The app, as IconPlate finds it: from the tile's file
    readonly property string app: {
        const src = parent && parent.source !== undefined ? String(parent.source) : "";
        if (src.indexOf("/tiles/") < 0) return "";
        return src.split("?")[0].split("/").pop().replace(/\.png$/, "");
    }
    hintFrom: Config.iconTileShade(app) ?? "transparent"
    tall: false             // the same crisp sheen at any size (the dock's magnify, big tiles)
    visible: Config.glassGloss && Config.s.iconShape !== "original"
    radius: Config.iconCornerFor(width)
}
