pragma Singleton

// The bar panels' host: Popouts.qml sets `pop` to itself when it starts. The shared pieces in
// panels/ (Label, Icon, RowButton…) take their colours and fonts from it, because a file of
// its own can't see another file's ids the way the inline components they used to be could.
// There is one Popouts window, so one host.
import QtQuick

QtObject {
    property var pop: null
}
