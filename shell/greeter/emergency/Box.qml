// The emergency login screen's contents (see shell.qml): user name, password, session
// and power buttons, in plain QtQuick so nothing beyond Quickshell is needed

import QtQuick

Rectangle {
    id: box
    required property var greeter
    color: "#0f1216"

    readonly property color text: "#eef1f5"
    readonly property color dim: "#8b94a3"
    readonly property color field: "#1d222a"
    readonly property color accent: "#7aa2f7"

    function login() { if (!greeter.busy) greeter.submit(userField.text.trim(), passField.text); }
    Connections { target: box.greeter; function onFailed() { passField.text = ""; passField.forceActiveFocus(); } }

    component Field: Rectangle {
        property alias input: input
        property string placeholder: ""
        width: 320; height: 44; radius: 8
        color: box.field
        border.width: input.activeFocus ? 2 : 1
        border.color: input.activeFocus ? box.accent : "#2a313c"
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            verticalAlignment: TextInput.AlignVCenter
            color: box.text
            font.pixelSize: 16
            clip: true
            enabled: !box.greeter.busy
            onAccepted: box.login()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !parent.text && !parent.activeFocus
                text: parent.parent.placeholder
                color: box.dim
                font.pixelSize: 16
            }
        }
    }

    component Link: Text {
        signal clicked()
        color: area.containsMouse ? box.text : box.dim
        font.pixelSize: 14
        MouseArea { id: area; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: parent.clicked() }
    }

    Column {
        anchors.centerIn: parent
        spacing: 14

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Log in"
            color: box.text
            font.pixelSize: 26
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 320
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "Slate's login screen couldn't start, so this basic one is standing in. "
                + "Log in as usual, then update the login screen from Settings → Security."
            color: box.dim
            font.pixelSize: 13
        }
        Field {
            id: userBox
            placeholder: "User name"
        }
        Field {
            id: passBox
            placeholder: "Password"
            Component.onCompleted: input.echoMode = TextInput.Password
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            text: box.greeter.message.replace(/\s+/g, " ").trim()
            width: Math.min(implicitWidth, 320)   // long PAM messages wrap instead of running off
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: box.greeter.messageIsError ? "#f28b8b" : box.dim
            font.pixelSize: 14
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 320; height: 44; radius: 8
            color: loginArea.containsMouse ? Qt.lighter(box.accent, 1.1) : box.accent
            opacity: box.greeter.busy ? 0.6 : 1
            Text { anchors.centerIn: parent; text: box.greeter.busy ? "Logging in…" : "Log in"; color: "#12151a"; font.pixelSize: 16 }
            MouseArea { id: loginArea; anchors.fill: parent; hoverEnabled: true; onClicked: box.login() }
        }
        Link {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property var session: box.greeter.sessions[box.greeter.sessionIndex]
            text: "Session: " + (session ? session.name : "none found") + (box.greeter.sessions.length > 1 ? "  ›" : "")
            onClicked: if (box.greeter.sessions.length) box.greeter.sessionIndex = (box.greeter.sessionIndex + 1) % box.greeter.sessions.length
        }
    }

    Row {
        anchors { right: parent.right; bottom: parent.bottom; margins: 24 }
        spacing: 24
        Link { text: "Restart"; onClicked: box.greeter.power("reboot") }
        Link { text: "Shut down"; onClicked: box.greeter.power("poweroff") }
    }

    readonly property alias userField: userBox.input
    readonly property alias passField: passBox.input
    // Fill in the user name once it's known (unless one's been typed), then go to the password
    function fillUser() {
        if (userField.text || !greeter.user) return;
        userField.text = greeter.user;
        passField.forceActiveFocus();
    }
    Connections { target: box.greeter; function onUserChanged() { box.fillUser(); } }
    Component.onCompleted: { userField.forceActiveFocus(); fillUser(); }
}
