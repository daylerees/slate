// The Slate lock / login screen, shared by the lock screen (LockScreen.qml) and
// the login screen (greetd). Wallpaper behind; avatar, name and a password frame in
// the middle; session switcher bottom-left (login only); power menu bottom-right.
//
// It only draws and collects input. Whoever uses it checks the password:
// listen for submitted(password) and call fail(message) or leave on success.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

Item {
    id: ls
    property string mode: "lock"          // "lock" or "login"
    property string wallpaper: ""         // image path; plain slate until it loads
    property string avatar: ""            // image path
    property string displayName: ""
    property var sessions: []             // login: [{ name, exec }]
    property int sessionIndex: 0
    property bool busy: false             // checking the password
    property string message: ""
    property bool messageIsError: false
    property bool lockedOut: false        // too many wrong passwords: input disabled
    property bool showPowerMenu: true
    property bool interactive: true       // false: background only (extra monitors)

    signal submitted(string password)
    signal powerAction(string action)      // suspend, hibernate, reboot, poweroff, logout

    function fail(text) {
        busy = false;
        message = text || "Wrong password";
        messageIsError = true;
        password.text = "";
        shake.restart();
        password.forceActiveFocus();
    }
    function reset() {
        busy = false; message = ""; messageIsError = false;
        password.text = ""; menu = "";
        password.forceActiveFocus();
    }
    function submit() {
        if (busy || lockedOut || password.text === "") return;
        busy = true; message = ""; messageIsError = false;
        const pw = password.text;
        password.text = "";               // don't keep it in the field while it's checked
        ls.submitted(pw);
    }

    // ---- Look ------------------------------------------------------------------
    readonly property color accent: Config.accent
    readonly property color accentText: Config.tint("#12151a")
    readonly property color frame: Config.tint("#0f1216")
    readonly property color field: Config.tint("#1d222a")
    readonly property color hover: Config.tint("#262c35")
    readonly property color text: Config.tint("#eef1f5")
    readonly property color dim: Config.tint("#8b94a3")
    readonly property color error: Config.tint("#f28b8b")
    readonly property string font: Config.s.fontFamily
    property url iconFontSource: "file://" + Quickshell.shellPath("fonts/tabler.ttf")   // the greeter passes its own copy
    FontLoader { id: tabler; source: ls.iconFontSource }
    function glyph(c) { return String.fromCodePoint(c); }

    // ---- Caps lock (keyboard LED) ----------------------------------------------
    property bool capsLock: false
    Process {
        id: capsRead
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: ls.capsLock = text.split("\n").some(l => parseInt(l) > 0) }
    }
    Timer { interval: 250; running: ls.visible; repeat: true; triggeredOnStart: true; onTriggered: if (!capsRead.running) capsRead.running = true }

    // ---- Background: plain slate, then the wallpaper once it's there -----------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Config.tint("#262c35") }
            GradientStop { position: 1.0; color: Config.tint("#0f1216") }
        }
    }
    Image {
        // A few pixels past each edge: some wallpapers have a stray light/dark
        // row or column at the very edge
        anchors { fill: parent; margins: -4 }
        source: ls.wallpaper ? "file://" + ls.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }

    // Rounded screen corners, the same black squircles as the desktop (Bar.qml /
    // ScreenCorners.qml), since this screen covers those
    Repeater {
        model: 4                            // top-left, top-right, bottom-left, bottom-right
        Canvas {
            required property int index
            readonly property real rad: 17
            readonly property real squircle: 3.0
            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index >= 2
            z: 100
            visible: Config.s.roundedScreenCorners
            onVisibleChanged: if (visible) requestPaint()
            width: rad; height: rad
            x: atRight ? ls.width - rad : 0
            y: atBottom ? ls.height - rad : 0
            transform: Scale { xScale: atRight ? -1 : 1; yScale: atBottom ? -1 : 1; origin.x: rad / 2; origin.y: rad / 2 }
            onAvailableChanged: if (available) requestPaint()
            Component.onCompleted: requestPaint()
            onPaint: {
                const ctx = getContext("2d"), r = rad, n = squircle;
                ctx.reset();
                ctx.fillStyle = "#000000";
                ctx.beginPath();
                ctx.moveTo(0, 0);
                ctx.lineTo(r, 0);
                for (let i = 0; i <= 48; i++) {
                    const t = Math.PI / 2 * (1 - i / 48);
                    ctx.lineTo(r - r * Math.pow(Math.cos(t), 2 / n), r - r * Math.pow(Math.sin(t), 2 / n));
                }
                ctx.closePath();
                ctx.fill();
            }
        }
    }

    // Clicking the background closes an open menu and returns to the password
    MouseArea { anchors.fill: parent; onClicked: { ls.menu = ""; password.forceActiveFocus(); } }

    // ---- Middle: avatar, name, password ---------------------------------------
    Column {
        id: centre
        visible: ls.interactive
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -30
        spacing: 18

        // Round avatar with a border
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 132; height: 132; radius: 66
            color: ls.frame
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.45; shadowBlur: 0.9; shadowVerticalOffset: 6; blurMax: 40 }
            Rectangle {
                anchors { fill: parent; margins: 4 }
                radius: width / 2
                color: ls.field
                Text {
                    anchors.centerIn: parent
                    visible: avatarImg.status !== Image.Ready
                    text: ls.glyph(0xEB4D)
                    color: ls.dim
                    font.family: tabler.name; font.pixelSize: 56
                }
            }
            Image { id: avatarImg; source: ls.avatar ? "file://" + ls.avatar : ""; visible: false; asynchronous: true }
            RoundImage {
                anchors { fill: parent; margins: 4 }
                radius: width / 2
                visible: avatarImg.status === Image.Ready
                source: avatarImg.source
            }
        }

        // Password frame
        Rectangle {
            id: box
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360
            height: boxCol.implicitHeight + 28
            radius: 18
            color: ls.frame
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.4; shadowBlur: 0.9; shadowVerticalOffset: 6; blurMax: 40 }
            transform: Translate { id: shakeX }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeX; property: "x"; to: -12; duration: 50 }
                NumberAnimation { target: shakeX; property: "x"; to: 10; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: -6; duration: 60 }
                NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 60 }
            }

            Column {
                id: boxCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                // Password field with a go button
                Rectangle {
                    width: parent.width; height: 46; radius: 12
                    color: ls.field
                    border.width: password.activeFocus ? 1 : 0
                    border.color: ls.messageIsError ? ls.error : ls.accent
                    Text {
                        id: lockIcon
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        text: ls.glyph(0xEAE2)
                        color: ls.dim
                        font.family: tabler.name; font.pixelSize: 17
                    }
                    TextInput {
                        id: password
                        anchors { left: lockIcon.right; leftMargin: 10; right: goBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        color: ls.text
                        selectionColor: ls.accent
                        font.family: ls.font; font.pixelSize: 15; font.letterSpacing: 2
                        enabled: !ls.busy && !ls.lockedOut
                        focus: true
                        clip: true
                        onAccepted: ls.submit()
                        onTextChanged: if (text !== "" && ls.messageIsError) { ls.message = ""; ls.messageIsError = false; }
                        Keys.onEscapePressed: { if (ls.menu !== "") ls.menu = ""; else text = ""; }
                    }
                    Text {
                        visible: password.text === "" && !ls.busy
                        anchors { left: password.left; verticalCenter: parent.verticalCenter }
                        text: "Password"
                        color: ls.dim
                        font.family: ls.font; font.pixelSize: 14
                    }
                    Rectangle {
                        id: goBtn
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        width: 34; height: 34; radius: 9
                        color: password.text !== "" ? ls.accent : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: ls.glyph(ls.busy ? 0xF226 : 0xEA1F)
                            color: password.text !== "" ? ls.accentText : ls.dim
                            font.family: tabler.name; font.pixelSize: 17
                            RotationAnimation on rotation { running: ls.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                            onRotationChanged: if (!ls.busy) rotation = 0
                        }
                        TapHandler { onTapped: ls.submit() }
                    }
                }

                // Caps lock / error / status line
                Item {
                    width: parent.width
                    height: 18
                    visible: ls.capsLock || ls.message !== ""
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: ls.message === "" && ls.capsLock
                            text: ls.glyph(0xEFEF)
                            color: ls.accent
                            font.family: tabler.name; font.pixelSize: 14
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ls.message !== "" ? ls.message : "Caps Lock is on"
                            color: ls.messageIsError ? ls.error : ls.message !== "" ? ls.dim : ls.accent
                            font.family: ls.font; font.pixelSize: 12; font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }

    // ---- Corner menus ------------------------------------------------------------
    property string menu: ""              // "", "session" or "power"

    component Pill: Rectangle {
        id: pill
        property int icon
        property string label: ""
        property bool active: false
        signal clicked()
        height: 44
        width: label ? pillRow.implicitWidth + 30 : 44
        radius: 22
        color: active ? ls.accent : pillHover.hovered ? ls.hover : ls.frame
        Behavior on color { ColorAnimation { duration: 100 } }
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.35; shadowBlur: 0.7; shadowVerticalOffset: 4; blurMax: 32 }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: ls.glyph(pill.icon); color: pill.active ? ls.accentText : ls.text; font.family: tabler.name; font.pixelSize: 18 }
            Text { visible: pill.label !== ""; anchors.verticalCenter: parent.verticalCenter; text: pill.label; color: pill.active ? ls.accentText : ls.text; font.family: ls.font; font.pixelSize: 13; font.weight: Font.Medium }
        }
        HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pill.clicked() }
    }
    // A menu that opens upwards from a corner button
    component Menu: Rectangle {
        id: m
        property var items: []             // [{ id, label, icon, current }]
        signal chosen(var item)
        width: 220
        height: menuCol.implicitHeight + 12
        radius: 16
        color: ls.frame
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.4; shadowBlur: 0.9; shadowVerticalOffset: 6; blurMax: 40 }
        Column {
            id: menuCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 2
            Repeater {
                model: m.items
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width; height: 40; radius: 10
                    color: modelData.current ? ls.accent : itemHover.hovered ? ls.hover : "transparent"
                    Row {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Text { anchors.verticalCenter: parent.verticalCenter; text: ls.glyph(parent.parent.modelData.icon); color: parent.parent.modelData.current ? ls.accentText : (parent.parent.modelData.danger ? ls.error : ls.text); font.family: tabler.name; font.pixelSize: 16 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.label; color: parent.parent.modelData.current ? ls.accentText : ls.text; font.family: ls.font; font.pixelSize: 13; font.weight: Font.Medium }
                    }
                    HoverHandler { id: itemHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: m.chosen(parent.modelData) }
                }
            }
        }
    }

    // Bottom-left: session switcher (login screen only)
    Pill {
        id: sessionBtn
        visible: ls.interactive && ls.mode === "login" && ls.sessions.length > 0
        anchors { left: parent.left; bottom: parent.bottom; margins: 28 }
        icon: 0xEA89
        label: ls.sessions.length ? ls.sessions[Math.min(ls.sessionIndex, ls.sessions.length - 1)].name + "  ▴" : ""
        active: ls.menu === "session"
        onClicked: ls.menu = ls.menu === "session" ? "" : "session"
    }
    Menu {
        visible: ls.menu === "session"
        anchors { left: sessionBtn.left; bottom: sessionBtn.top; bottomMargin: 10 }
        width: Math.max(220, sessionBtn.width)
        items: ls.sessions.map((s, i) => ({ id: i, label: s.name, icon: 0xEA89, current: i === ls.sessionIndex }))
        onChosen: item => { ls.sessionIndex = item.id; ls.menu = ""; password.forceActiveFocus(); }
    }

    // Bottom-right: power
    Pill {
        id: powerBtn
        visible: ls.interactive && ls.showPowerMenu
        anchors { right: parent.right; bottom: parent.bottom; margins: 28 }
        icon: 0xEB0D
        active: ls.menu === "power"
        onClicked: ls.menu = ls.menu === "power" ? "" : "power"
    }
    Menu {
        visible: ls.menu === "power"
        anchors { right: powerBtn.right; bottom: powerBtn.top; bottomMargin: 10 }
        items: [
            { id: "suspend", label: "Suspend", icon: 0xF228 },
            { id: "hibernate", label: "Hibernate", icon: 0xEC0B },
            { id: "reboot", label: "Restart", icon: 0xEB13 },
            { id: "poweroff", label: "Shut down", icon: 0xEB0D, danger: true }
        ].concat(ls.mode === "lock" ? [{ id: "logout", label: "Log out", icon: 0xEBA8 }] : [])
        onChosen: item => { ls.menu = ""; ls.powerAction(item.id); }
    }
}
