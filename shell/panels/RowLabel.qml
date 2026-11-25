import QtQuick
import qs

// A row's words that turn dark on the active color: color: <row>.fg, cross-fading as the row
// is chosen or let go of (CONVENTIONS: text on an active-color fill). Not the hover: that's
// the row's HoverFill, at once
Label {
    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
}
