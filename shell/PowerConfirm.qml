// Confirmation dialog in the middle of the screen over a dimmed desktop: for log out /
// restart / shut down, and for anything else that needs a yes first (deleting a space…).
// Keyboard: Left/Right or Tab pick a button (the action is picked first), Enter or Space
// presses it, Escape or a click outside cancels.
// Open with powerConfirm.ask("<logout|reboot|shutdown>"), or from anywhere with:
//   slate ipc call power confirm shutdown
// For other questions:
//   powerConfirm.confirmWith({ title: "Delete “Work”?", body: "…", button: "Delete",
//                              code: 0xEB41, danger: true }, () => { … })

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    // ---- Look --------------------------------------------------------------
    readonly property color cardColor: Config.tint("#0f1216")     // same as the top bar
    readonly property color buttonColor: Config.tint("#1d222a")   // bar capsules
    readonly property color buttonHover: Config.tint("#262c35")
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property color dimTextColor: Config.tint("#8b94a3")
    readonly property color accent: Config.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color danger: Config.tint("#f28b8b")
    readonly property string fontFamily: Config.s.fontFamily
    readonly property int fadeMs: 180

    // ---- Actions -----------------------------------------------------------
    readonly property var actions: ({
        logout:   { title: "Log out?",   body: "Your apps will close and you'll return to the login screen.", button: "Log out",   code: 0xEBA8, danger: false },
        reboot:   { title: "Restart?",   body: "Your apps will close and the computer will restart.",          button: "Restart",   code: 0xEB13, danger: false },
        shutdown: { title: "Shut down?", body: "Your apps will close and the computer will turn off.",         button: "Shut down", code: 0xEB0D, danger: true }
    })

    property string action: ""                 // action being asked about ("custom": confirmWith)
    property bool shown: false
    property var custom: null                  // confirmWith: what to show, and what to run
    property var customAction: null
    readonly property var info: action === "custom" && custom ? custom : (actions[action] ?? actions.shutdown)

    property int focusedButton: 1          // 0 = Cancel, 1 = the action
    function ask(name) {
        if (!actions[name]) return;
        open(name);
    }
    // Any other question: spec is { title, body, button, code, danger }; onConfirm runs on yes
    function confirmWith(spec, onConfirm) {
        custom = spec;
        customAction = onConfirm;
        open("custom");
        focusedButton = 0;                 // Cancel first: Enter alone doesn't delete things
    }
    function open(name) {
        screen = Config.focusedScreen;     // open on the focused screen
        action = name;
        focusedButton = 1;
        shown = true;
        Qt.callLater(() => keys.forceActiveFocus());
    }
    function press() { if (focusedButton === 0) cancel(); else confirm(); }
    function cancel() { shown = false; customAction = null; }
    function confirm() {
        if (!shown) return;
        shown = false;
        if (action === "custom") {
            const f = customAction;
            customAction = null;
            if (f) f();
            return;
        }
        Quickshell.execDetached([Quickshell.shellPath("scripts/session.sh"), action]);
    }

    IpcHandler {
        target: "power"
        function confirm(action: string): void { root.ask(action); }
        function cancel(): void { root.cancel(); }
    }

    // ---- Window ------------------------------------------------------------
    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutCubic } }

    visible: shown || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-confirm"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    FontLoader { id: tabler; source: "file://" + Quickshell.shellPath("fonts/tabler.ttf") }

    // Dimmed desktop; click it to cancel
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.45 * root.fade
        MouseArea { anchors.fill: parent; enabled: root.shown; onClicked: root.cancel() }
    }

    // ---- Card --------------------------------------------------------------
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 380
        height: content.implicitHeight + 48
        radius: 18
        color: root.cardColor
        opacity: root.fade
        scale: 0.94 + 0.06 * root.fade

        MouseArea { anchors.fill: parent }    // swallow clicks inside the card

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: root.shown
            Keys.onPressed: e => {
                switch (e.key) {
                case Qt.Key_Escape: root.cancel(); break;
                case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: root.press(); break;
                case Qt.Key_Left: root.focusedButton = 0; break;
                case Qt.Key_Right: root.focusedButton = 1; break;
                case Qt.Key_Tab: case Qt.Key_Backtab: root.focusedButton = 1 - root.focusedButton; break;
                default: return;
                }
                e.accepted = true;
            }

            Column {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 0

                // Icon
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56; height: 56; radius: 28
                    color: root.buttonColor
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(root.info.code)
                        color: root.info.danger ? root.danger : root.accent
                        font.family: tabler.name
                        font.pixelSize: 26
                    }
                }
                Item { width: 1; height: 16 }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.info.title
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
                Item { width: 1; height: 6 }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.info.body
                    color: root.dimTextColor
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Item { width: 1; height: 22 }

                // Buttons
                Row {
                    width: parent.width
                    spacing: 10
                    DialogButton {
                        width: (parent.width - parent.spacing) / 2
                        label: "Cancel"
                        focused: root.focusedButton === 0
                        onClicked: root.cancel()
                    }
                    DialogButton {
                        width: (parent.width - parent.spacing) / 2
                        label: root.info.button
                        primary: true
                        focused: root.focusedButton === 1
                        onClicked: root.confirm()
                    }
                }
            }
        }
    }

    component DialogButton: Rectangle {
        id: btn
        property string label: ""
        property bool primary: false
        property bool focused: false
        signal clicked()
        height: 40
        radius: 10
        readonly property color base: primary ? (root.info.danger ? root.danger : root.accent) : root.buttonColor
        color: primary ? (hh.hovered ? Qt.lighter(base, 1.08) : base) : (hh.hovered ? root.buttonHover : base)
        Behavior on color { ColorAnimation { duration: 100 } }
        HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) root.focusedButton = btn.primary ? 1 : 0 }
        // Keyboard focus ring, just outside the button
        Rectangle {
            anchors { fill: parent; margins: -4 }
            radius: parent.radius + 4
            color: "transparent"
            border.width: 2
            border.color: btn.primary ? btn.base : root.textColor
            opacity: btn.focused ? (btn.primary ? 0.55 : 0.35) : 0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
        TapHandler { onTapped: btn.clicked() }
        Text {
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? root.accentText : root.textColor
            font.family: root.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }
}
