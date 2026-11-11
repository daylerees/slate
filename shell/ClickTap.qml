import QtQuick

// A TapHandler that also plays Slate's click (Settings → Sound → Click sound, off by default).
// Use it for things you press: buttons, menu items, switches, tiles.
// (The pointer becomes a hand over whatever it's on, Config.handCursor. A tap
// handler can't change the pointer itself except while pressed, so it gives its item a hover
// handler that does)
TapHandler {
    id: tap
    onTapped: Config.click()
    Component.onCompleted: {
        if (!Config.handCursor || !parent) return;
        const h = Config.handHover.createObject(parent);
        if (h) h.enabled = Qt.binding(() => tap.enabled);
    }
}
