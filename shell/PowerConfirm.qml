// Confirmation dialog in the middle of the screen over a dimmed desktop: for log out /
// restart / shut down, and for anything else that needs a yes first (deleting a space…).
// Keyboard: Left/Right or Tab pick a button (the action is picked first), Enter or Space
// presses it, Escape or a click outside cancels. Restart also has a switch to reopen your
// apps afterwards (Settings → Power): Up or Tab reaches it, Enter or Space flips it.
// Open with powerConfirm.ask("<logout|reboot|shutdown>"), or from anywhere with:
//   slate ipc call power confirm shutdown
// For other questions:
//   powerConfirm.confirmWith({ title: "Delete “Work”?", body: "…", button: "Delete",
//                              code: 0xEB41, danger: true }, () => { … })
// A question can also have a switch to go further (option: { label, detail }; its answer is
// passed to onConfirm), and something to run if it's cancelled (onCancel).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    // ---- Look --------------------------------------------------------------
    readonly property color cardColor: Config.surface(Config.tint("#0f1216"))     // same as the top bar
    readonly property color buttonColor: Config.tint("#1d222a")   // bar capsules
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property color dimTextColor: Config.tint("#8b94a3")
    readonly property color accent: Config.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color danger: Config.tint("#f28b8b")
    readonly property string fontFamily: Config.s.fontFamily
    readonly property int fadeMs: 180

    // ---- Actions -----------------------------------------------------------
    readonly property var actions: ({
        logout:   { title: "Log out?",   body: "Your apps will close and you'll be back at the login screen. See you soon.", button: "Log out",   code: 0xEBA8, danger: false },
        reboot:   { title: "Restart?",   body: "Your apps will close and your computer will restart. Back in a moment.",          button: "Restart",   code: 0xEB13, danger: false },
        shutdown: { title: "Shut down?", body: "Your apps will close and your computer will turn off. See you next time.",         button: "Shut down", code: 0xEB0D, danger: true }
    })

    property string action: ""                 // action being asked about ("custom": confirmWith)
    property bool shown: false
    property var custom: null                  // confirmWith: what to show, and what to run
    property var customAction: null
    property var customCancel: null
    property bool customOption: false          // the question's own switch (custom.option), off to start
    readonly property var info: action === "custom" && custom ? custom : (actions[action] ?? actions.shutdown)

    property int focusedButton: 1          // 0 = Cancel, 1 = the action, 2 = the reopen switch
    readonly property bool hasReopen: action === "reboot"
    // The switch row: Restart's "reopen my apps", or a question's own option
    readonly property bool hasOption: hasReopen || (action === "custom" && !!custom && !!custom.option)
    readonly property bool optionOn: hasReopen ? Config.s.reopenAppsAfterRestart : customOption
    function flipOption() {
        if (hasReopen) Config.s.reopenAppsAfterRestart = !Config.s.reopenAppsAfterRestart;
        else customOption = !customOption;
    }
    readonly property var focusOrder: hasOption ? [2, 0, 1] : [0, 1]   // Tab order, top to bottom
    function ask(name) {
        if (!actions[name]) return;
        open(name);
    }
    // A question can also ask for a line of text (naming a workspace): spec.input is
    // { text, placeholder, maxLength }; the field has the keyboard, Enter confirms, and onConfirm
    // gets what was typed as its second argument. It opens without the attention sound: you
    // asked for it, Slate isn't asking you.
    readonly property bool hasInput: action === "custom" && !!custom && !!custom.input
    property alias inputText: field.text
    // Any other question: spec is { title, body, button, code, danger, option?, cancelLabel?, input?, id? }; onConfirm runs on
    // yes (given the option's answer), onCancel (if any) on no
    // A question asked while another is showing waits its turn (it used to replace it, and the
    // first was never answered)
    property var waiting: []
    onShownChanged: if (!shown && waiting.length > 0) nextQuestion.restart()
    Timer {
        id: nextQuestion
        interval: root.fadeMs + 80           // once this one has faded out, so it's clearly a new one
        onTriggered: {
            if (root.shown) return;          // something else came up first: after that, then
            if (root.waiting.length === 0) return;
            const q = root.waiting[0];
            root.waiting = root.waiting.slice(1);
            root.confirmWith(q.spec, q.onConfirm, q.onCancel);
        }
    }
    function confirmWith(spec, onConfirm, onCancel) {
        if (shown) { waiting = waiting.concat([{ spec: spec, onConfirm: onConfirm, onCancel: onCancel }]); return; }
        custom = spec;
        customAction = onConfirm;
        customCancel = onCancel || null;
        customOption = false;
        field.text = spec.input ? String(spec.input.text || "") : "";
        open("custom");
        focusedButton = spec.input ? 1 : 0;      // Cancel first: Enter alone doesn't delete things
        if (spec.input) Qt.callLater(() => { field.forceActiveFocus(); field.selectAll(); });
    }
    // Take a question back before it's answered (spec.id), whether it's showing or waiting its
    // turn: neither its onConfirm nor its onCancel runs. For questions asked on something
    // else's behalf that has stopped waiting (AssistantGate.qml)
    function withdraw(id) {
        if (!id) return;
        waiting = waiting.filter(q => !(q.spec && q.spec.id === id));
        if (shown && action === "custom" && custom && custom.id === id) {
            customAction = null; customCancel = null;
            shown = false;
        }
    }
    function open(name) {
        screen = Config.focusedScreen;     // open on the focused screen
        action = name;
        focusedButton = 1;
        shown = true;
        if (!hasInput) Config.attention();
        Qt.callLater(() => keys.forceActiveFocus());
    }
    function press() {
        if (focusedButton === 2) flipOption();
        else if (focusedButton === 0) cancel();
        else confirm();
    }
    function step(d) {
        const i = focusOrder.indexOf(focusedButton);
        focusedButton = focusOrder[(i + d + focusOrder.length) % focusOrder.length];
    }
    function cancel() {
        if (!shown) return;
        shown = false;
        const c = action === "custom" ? customCancel : null;
        customAction = null; customCancel = null;
        if (c) c();
    }
    function confirm() {
        if (!shown) return;
        shown = false;
        if (action === "custom") {
            const f = customAction, opt = customOption, typed = field.text;
            customAction = null; customCancel = null;
            if (f) f(opt, typed);
            return;
        }
        Config.sessionAction(action);
    }

    IpcHandler {
        target: "power"
        function confirm(action: string): void { root.ask(action); }
        function cancel(): void { root.cancel(); }
    }

    // ---- Window ------------------------------------------------------------
    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(root.fadeMs); easing.type: Easing.OutCubic } }

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
                case Qt.Key_Up: if (root.hasOption) root.focusedButton = 2; break;
                case Qt.Key_Down: if (root.focusedButton === 2) root.focusedButton = 1; break;
                case Qt.Key_Tab: root.step(1); break;
                case Qt.Key_Backtab: root.step(-1); break;
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

                // A line of text to type (spec.input), like the Spaces panel's name field
                Rectangle {
                    visible: root.hasInput
                    width: parent.width; height: 38; radius: 10
                    color: root.buttonColor
                    Gloss { radius: parent.radius }   // glass: a sheen, as on the bar's containers
                    border.width: field.activeFocus ? 1 : 0
                    border.color: root.accent
                    TextInput {
                        id: field
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: root.textColor
                        selectionColor: root.accent; selectedTextColor: root.accentText
                        font.family: root.fontFamily; font.pixelSize: 14
                        maximumLength: root.hasInput && root.custom.input.maxLength ? root.custom.input.maxLength : 200
                        selectByMouse: true
                        onAccepted: root.confirm()
                        Keys.onEscapePressed: root.cancel()
                        // Tab: on to the buttons
                        Keys.onTabPressed: { root.focusedButton = 0; keys.forceActiveFocus(); }
                    }
                    Text {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: Text.AlignVCenter
                        visible: field.text === "" && root.hasInput
                        text: root.hasInput ? root.custom.input.placeholder || "" : ""
                        color: root.dimTextColor
                        font.family: root.fontFamily; font.pixelSize: 14
                        elide: Text.ElideRight
                    }
                }
                Item { width: 1; height: 16; visible: root.hasInput }

                // Restart: reopen your apps afterwards; or the question's own option
                Rectangle {
                    id: reopen
                    visible: root.hasOption
                    width: parent.width
                    height: reopenText.implicitHeight + 24
                    radius: 12
                    readonly property bool on: root.optionOn
                    color: reopenHover.hovered ? Config.hoverOn(root.buttonColor) : root.buttonColor
                    Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                    Gloss { radius: parent.radius; opacity: reopenHover.hovered ? 1 : 0 }
                    HoverHandler { id: reopenHover; onHoveredChanged: if (hovered) root.focusedButton = 2 }
                    ClickTap { onTapped: root.flipOption() }
                    // Keyboard focus ring, as on the buttons
                    Rectangle {
                        anchors { fill: parent; margins: -4 }
                        radius: parent.radius + 4
                        color: "transparent"
                        border.width: 2; border.color: root.textColor
                        opacity: root.focusedButton === 2 ? 0.35 : 0
                        Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
                    }
                    Column {
                        id: reopenText
                        anchors { left: parent.left; leftMargin: 14; right: reopenSwitch.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text {
                            width: parent.width
                            text: root.hasReopen ? "Reopen my apps afterwards" : root.custom && root.custom.option ? root.custom.option.label : ""
                            color: root.textColor
                            font.family: root.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            visible: text !== ""
                            text: root.hasReopen ? "On the same workspaces, just where you left them"
                                : root.custom && root.custom.option ? root.custom.option.detail || "" : ""
                            color: root.dimTextColor
                            font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
                        }
                    }
                    Rectangle {
                        id: reopenSwitch
                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        width: 42; height: 24; radius: 12
                        color: reopen.on ? root.accent : Config.tint("#2a313c")
                        Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                        Rectangle {
                            width: 18; height: 18; radius: 9
                            anchors.verticalCenter: parent.verticalCenter
                            x: reopen.on ? parent.width - width - 3 : 3
                            color: reopen.on ? root.accentText : root.textColor
                            Behavior on x { NumberAnimation { duration: Config.ms(140); easing.type: Easing.OutCubic } }
                        }
                    }
                }
                Item { width: 1; height: 16; visible: root.hasOption }

                // Buttons
                Row {
                    width: parent.width
                    spacing: 10
                    DialogButton {
                        width: (parent.width - parent.spacing) / 2
                        label: (root.action === "custom" && root.custom && root.custom.cancelLabel) || "Cancel"
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
        color: primary ? (hh.hovered ? Qt.lighter(base, 1.08) : base) : (hh.hovered ? Config.hoverOn(base) : base)
        Gloss { radius: parent.radius; opacity: (hh.hovered) ? 1 : 0 }   // glass: a sheen while hovered (fading with the colour)
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        HoverHandler { id: hh; onHoveredChanged: if (hovered) root.focusedButton = btn.primary ? 1 : 0 }
        // Keyboard focus ring, just outside the button
        Rectangle {
            anchors { fill: parent; margins: -4 }
            radius: parent.radius + 4
            color: "transparent"
            border.width: 2
            border.color: btn.primary ? btn.base : root.textColor
            opacity: btn.focused ? (btn.primary ? 0.55 : 0.35) : 0
            Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
        }
        ClickTap { onTapped: btn.clicked() }
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
