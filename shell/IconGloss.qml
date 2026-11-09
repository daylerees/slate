// The sheen on an app icon's tile with glass (Settings → Appearance → Glass → Gloss), the same
// wherever icons show: the dock, launcher, switchers, notifications, the bar. Put it inside the
// icon's Image, after its IconPlate:  IconGloss {}
// Not on icons shown as they come (no tile to follow).

import QtQuick

Gloss {
    glassHint: true
    tall: false             // the same crisp sheen at any size (the dock's magnify, big tiles)
    visible: Config.glassGloss && Config.s.iconShape !== "original"
    radius: Config.iconCornerFor(width)
}
