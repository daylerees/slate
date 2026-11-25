import QtQuick
import qs

// A row's icon that turns dark on the active color: color: <row>.fg, cross-fading as RowLabel does
Icon {
    Behavior on color { ColorAnimation { duration: Config.ms(120) } }
}
