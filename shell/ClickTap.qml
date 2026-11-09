import QtQuick

// A TapHandler that also plays Slate's click (Settings → Sound → Click sound, off by default).
// Use it for things you press: buttons, menu items, switches, tiles.
TapHandler {
    onTapped: Config.click()
}
