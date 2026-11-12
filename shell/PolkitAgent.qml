// Polkit authentication agent: when an app asks for admin rights (pkexec, Settings,
// package managers…), a card in the middle of the screen asks for your password.
// Same look as the power confirmation (PowerConfirm.qml).
// Enter submits; Escape or a click outside cancels. A wrong password shakes the card
// and polkit asks again.
//
// Preview the look without a real request (the password isn't checked):
//   slate ipc call polkit preview        (and: polkit previewWrong, polkit close)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit

PanelWindow {
    id: root

    // ---- Look --------------------------------------------------------------
    readonly property color cardColor: Config.surface(Config.tint("#0f1216"))     // same as the top bar
    readonly property color fieldColor: Config.raised(Config.tint("#1d222a"))    // bar capsules
    readonly property color textColor: Config.tint("#eef1f5")
    readonly property color dimTextColor: Config.tint("#8b94a3")
    readonly property color accent: Config.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color danger: Config.tint("#f28b8b")
    readonly property string fontFamily: Config.s.fontFamily
    readonly property int fadeMs: 180

    // ---- The agent ---------------------------------------------------------
    PolkitAgent { id: agent }
    readonly property var flow: agent.flow

    // Preview: fake request for checking the look (ipc call polkit preview)
    property bool previewing: false
    property var previewIdentities: [{ displayName: "You", string: Quickshell.env("USER"), isGroup: false }]

    readonly property bool shown: previewing || (flow !== null && !flow.isCompleted)
    readonly property string message: previewing ? "Authentication is needed to run `/usr/bin/true' as the super user" : (flow ? flow.message : "")
    readonly property var identities: previewing ? previewIdentities : (flow ? flow.identities : [])
    readonly property var selected: previewing ? previewIdentities[0] : (flow ? flow.selectedIdentity : null)
    readonly property bool echo: !previewing && flow ? flow.responseVisible : false
    readonly property string prompt: {
        const p = (!previewing && flow ? flow.inputPrompt : "").replace(/:\s*$/, "").trim();
        return p === "" || /^password$/i.test(p) ? "Password" : p;
    }
    // Polkit's own notes (e.g. "Authentication failure"), unless we're showing ours
    readonly property string supplementary: !previewing && flow ? flow.supplementaryMessage : ""
    readonly property bool supplementaryIsError: !previewing && flow ? flow.supplementaryIsError : false

    property bool busy: false            // password sent, waiting for polkit
    property string error: ""            // our message after a wrong password

    function idName(i) { return i ? (i.displayName || i.string || "") : ""; }

    function submit() {
        if (!shown || busy || password.text === "") return;
        const pw = password.text;
        password.text = "";               // don't keep it in the field while it's checked
        error = "";
        if (previewing) { previewDone.restart(); busy = true; return; }
        busy = true;
        flow.submit(pw);
    }
    function cancel() {
        password.text = "";
        if (previewing) { previewing = false; return; }
        if (flow) flow.cancelAuthenticationRequest();
    }
    function wrong(msg) {
        busy = false;
        error = msg || "That password didn't match. Please try again";
        password.text = "";
        shake.restart();
        password.forceActiveFocus();
    }

    // A new request: start clean
    onFlowChanged: { busy = false; error = ""; password.text = ""; }
    // Ask on the focused screen
    onShownChanged: if (shown) { Config.attention(); screen = Config.focusedScreen; busy = false; error = ""; password.text = ""; Qt.callLater(() => password.forceActiveFocus()); }

    Connections {
        target: root.flow
        function onAuthenticationFailed() { root.wrong(); }
        // Polkit asks again (after a failure, or for a second piece of input)
        function onIsResponseRequiredChanged() { if (root.flow.isResponseRequired) { root.busy = false; password.forceActiveFocus(); } }
        function onSupplementaryMessageChanged() { if (root.flow.supplementaryIsError && root.flow.supplementaryMessage !== "") root.busy = false; }
    }

    Timer { id: previewDone; interval: 700; onTriggered: { root.busy = false; root.previewing = false; } }

    IpcHandler {
        target: "polkit"
        function preview(): void { root.previewing = true; }
        function previewWrong(): void { root.previewing = true; root.wrong(); }
        function close(): void { root.previewing = false; }
    }

    // ---- Window ------------------------------------------------------------
    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: Config.ms(root.fadeMs); easing.type: Easing.OutCubic } }

    visible: shown || fade > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-polkit"
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
        width: 400
        height: content.implicitHeight + 48
        radius: Config.corner(18)
        color: root.cardColor
        opacity: root.fade
        scale: 0.94 + 0.06 * root.fade
        Shadow {}      // raised: Slate's shadow, with glass too

        transform: Translate { id: shakeX }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: shakeX; property: "x"; to: -12; duration: Config.ms(50) }
            NumberAnimation { target: shakeX; property: "x"; to: 10; duration: Config.ms(70) }
            NumberAnimation { target: shakeX; property: "x"; to: -6; duration: Config.ms(60) }
            NumberAnimation { target: shakeX; property: "x"; to: 0; duration: Config.ms(60) }
        }

        MouseArea { anchors.fill: parent }    // swallow clicks inside the card

        FocusScope {
            anchors.fill: parent
            focus: root.shown
            Keys.onEscapePressed: root.cancel()

            Column {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 0

                // Icon
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 56; height: 56; radius: Config.corner(28)
                    color: root.fieldColor
                    Text {
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xEAE2)     // lock
                        color: root.accent
                        font.family: tabler.name
                        font.pixelSize: 26
                    }
                }
                Item { width: 1; height: 16 }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Your password, please"
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }
                Item { width: 1; height: 6 }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    text: root.message
                    color: root.dimTextColor
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Item { width: 1; height: 18 }

                // Who you're authenticating as: one line, or a choice when there are several
                Text {
                    visible: root.identities.length <= 1
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "As " + root.idName(root.selected)
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Flow {
                    visible: root.identities.length > 1
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: root.identities.length > 1 ? root.identities : []
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool current: root.selected === modelData
                            width: chipText.implicitWidth + 24; height: 30; radius: Config.corner(15)
                            color: current ? root.accent : chipHover.hovered ? Config.hoverOn(root.fieldColor) : root.fieldColor
                            Behavior on color { ColorAnimation { duration: Config.ms(100) } }
                            HoverHandler { id: chipHover }
                            ClickTap {
                                onTapped: {
                                    if (root.flow && !root.busy) root.flow.selectedIdentity = chip.modelData;
                                    password.forceActiveFocus();
                                }
                            }
                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: (chip.modelData.isGroup ? "Group " : "") + root.idName(chip.modelData)
                                color: chip.current ? root.accentText : root.textColor
                                font.family: root.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
                Item { width: 1; height: 10 }

                // Password field
                Rectangle {
                    width: parent.width; height: 44; radius: Config.corner(12)
                    color: root.fieldColor
                    border.width: password.activeFocus ? 1 : 0
                    border.color: root.error !== "" || root.supplementaryIsError ? root.danger : root.accent
                    TextInput {
                        id: password
                        anchors { left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16; verticalCenter: parent.verticalCenter }
                        focus: true
                        enabled: !root.busy
                        echoMode: root.echo ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        color: root.textColor
                        selectionColor: root.accent
                        selectedTextColor: root.accentText
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        clip: true
                        onAccepted: root.submit()
                        Keys.onEscapePressed: root.cancel()
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                        visible: password.text === ""
                        text: root.busy ? "Checking…" : root.prompt
                        color: root.dimTextColor
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }

                // Feedback: our wrong-password note, or polkit's own message
                Item { width: 1; height: (feedback.text !== "") ? 8 : 0 }
                Text {
                    id: feedback
                    visible: text !== ""
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: root.error !== "" ? root.error : root.supplementary
                    color: root.error !== "" || root.supplementaryIsError ? root.danger : root.dimTextColor
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
                Item { width: 1; height: 20 }

                // Buttons
                Row {
                    width: parent.width
                    spacing: 10
                    DialogButton {
                        width: (parent.width - parent.spacing) / 2
                        label: "Cancel"
                        onClicked: root.cancel()
                    }
                    DialogButton {
                        width: (parent.width - parent.spacing) / 2
                        label: root.busy ? "Checking…" : "Authenticate"
                        primary: true
                        dimmed: password.text === "" || root.busy
                        onClicked: root.submit()
                    }
                }
            }
        }
    }

    component DialogButton: Rectangle {
        id: btn
        property string label: ""
        property bool primary: false
        property bool dimmed: false
        signal clicked()
        height: 40
        radius: Config.corner(10)
        readonly property color base: primary ? root.accent : root.fieldColor
        color: primary ? base : (hh.hovered ? Config.hover : base)
        opacity: dimmed ? 0.55 : 1
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        Behavior on opacity { NumberAnimation { duration: Config.ms(100) } }
        HoverHandler { id: hh }
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
