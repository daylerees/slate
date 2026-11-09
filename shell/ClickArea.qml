import QtQuick

// A MouseArea that also plays Slate's click (Settings → Sound → Click sound, off by default).
// Use it for things you press; areas that only catch clicks outside a panel stay MouseAreas.
MouseArea {
    onClicked: Config.click()
}
