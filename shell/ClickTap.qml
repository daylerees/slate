import QtQuick

// A TapHandler that also plays Slate's click (Settings → Sound → Click sound, off by default).
// Use it for things you press: buttons, menu items, switches, tiles.
// (The pointer becomes a hand over whatever it's on, Config.handCursor. A tap
// handler can't change the pointer itself except while pressed, so it gives its item a hover
// handler that does)
TapHandler {
    id: tap
    // false: the click, but the pointer stays an arrow (menus, the dock: things that are all
    // pressable anyway, where a hand says nothing)
    property bool hand: true
    // false: no click of its own (something it starts plays it instead: Nova's microphone)
    property bool sound: true
    onTapped: if (sound) Config.click()
    Component.onCompleted: {
        if (!hand || !Config.handCursor || !parent) return;
        const h = Config.handHover.createObject(parent);
        if (h) h.enabled = Qt.binding(() => tap.enabled);
    }
}
