import QtQuick
import ".."

// An item in a list setting (a keyboard layout, a startup app), with a way to remove it
SettingRow {
    id: listItemRow
    property bool removable: true
    signal removed()
    Button {
        visible: listItemRow.removable
        icon: 0xEB41
        label: "Remove"
        destructive: true
        compactLabel: true
        onClicked: listItemRow.removed()
    }
}
