// The Slate lock / login screen, shared by the lock screen (LockScreen.qml) and
// the login screen (greetd). Wallpaper behind; avatar, name and a password frame in
// the middle; session switcher bottom-left (login only); power menu bottom-right.
//
// It only draws and collects input. Whoever uses it checks the password:
// listen for submitted(password) and call fail(message) or leave on success.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

Item {
    id: ls
    property string mode: "lock"          // "lock" or "login"
    property string wallpaper: ""         // image path; plain slate until it loads
    property string avatar: ""            // image path
    property string displayName: ""
    property var sessions: []             // login: [{ name, exec }]
    property var people: []               // login: everyone who can log in, [{ user, name }]
    property int personIndex: 0           // ...and who's chosen (personPicked: chosen here)
    signal personPicked(int index)
    property int sessionIndex: 0
    property bool busy: false             // checking the password
    property string message: ""
    property bool messageIsError: false
    property bool lockedOut: false        // too many wrong passwords: input disabled
    property bool showPowerMenu: true
    property bool interactive: true       // false: background only (extra monitors)
    // The on-screen keyboard's keys, shown (its button, bottom right: always on the login screen,
    // on the lock screen with Settings → Accessibility → On-screen keyboard on)
    property bool keysShown: false

    // A second question from the login (a one-time code, say): PAM's own words, shown above the
    // field, and the next thing typed answers it. answerVisible: PAM wants it shown as it's typed
    property bool asking: false
    property bool answerVisible: false
    // What another way in (a face, a finger, a key) is waiting for, in Slate's words: a quiet
    // line under the field while nothing else is said there ("Looking for your face…")
    property string hint: ""
    // Someone's here: the pointer moved, or a key was pressed before anything was typed (the
    // lock screen looks for a face again then, if it had stopped)
    signal activity()
    signal submitted(string password)
    signal cancelled()                     // Escape while it asks: back to a fresh password
    signal powerAction(string action)      // suspend, hibernate, reboot, poweroff, logout

    function fail(text) {
        busy = false; asking = false;
        message = text || "That password didn't match";
        messageIsError = true;
        password.text = "";
        shake.restart();
        password.forceActiveFocus();
    }
    function ask(question, visible) {
        busy = false; asking = true; answerVisible = visible;
        message = question; messageIsError = false;
        password.text = "";
        password.forceActiveFocus();
    }
    // A note or complaint from PAM while it checks (no question in it)
    function note(text, isError) { message = text; messageIsError = isError; }
    function reset() {
        busy = false; asking = false; message = ""; messageIsError = false;
        password.text = ""; menu = "";
        password.forceActiveFocus();
    }
    function submit() {
        if (busy || lockedOut || password.text === "") return;
        busy = true; asking = false; message = ""; messageIsError = false;
        const pw = password.text;
        password.text = "";               // don't keep it in the field while it's checked
        ls.submitted(pw);
    }

    // ---- Look ------------------------------------------------------------------
    // (easing from one look to another, on the login screen, when someone else is chosen: the
    // colours below, and how much glass, shadow and roundness, which everything here draws with)
    property real glassOn: Config.glass ? 1 : 0
    Behavior on glassOn { NumberAnimation { duration: Config.ms(450); easing.type: Easing.InOutQuad } }
    property real shadowOn: Config.shadowsOn ? 1 : 0
    Behavior on shadowOn { NumberAnimation { duration: Config.ms(450); easing.type: Easing.InOutQuad } }
    property real roundness: Config.s.roundedElements ? 1 : 0
    Behavior on roundness { NumberAnimation { duration: Config.ms(450); easing.type: Easing.InOutQuad } }
    function corner(r) { return r * roundness; }       // (Config.corner, eased)
    property color accent: Config.accent
    Behavior on accent { ColorAnimation { duration: Config.ms(450) } }
    property color accentText: Config.palette.accentText
    Behavior on accentText { ColorAnimation { duration: Config.ms(450) } }
    property color frame: Config.palette.base
    Behavior on frame { ColorAnimation { duration: Config.ms(450) } }
    property color field: Config.palette.card
    Behavior on field { ColorAnimation { duration: Config.ms(450) } }
    property color text: Config.palette.text
    Behavior on text { ColorAnimation { duration: Config.ms(450) } }
    property color dim: Config.palette.dim
    Behavior on dim { ColorAnimation { duration: Config.ms(450) } }
    readonly property color error: Config.palette.danger
    readonly property string font: Config.s.fontFamily
    property url iconFontSource: "file://" + Quickshell.shellPath("fonts/tabler.ttf")   // the greeter passes its own copy
    FontLoader { id: tabler; source: ls.iconFontSource }
    function glyph(c) { return String.fromCodePoint(c); }

    // ---- Caps lock (keyboard LED) ----------------------------------------------
    // Not read in tests: the container sees the host's LEDs, so the screenshots would
    // change with the Caps Lock key of whoever runs them.
    property bool capsLock: false
    // (false: whoever holds this screen reads the light, once for every screen, and sets capsLock:
    // the lock screen, with a screen of this for each monitor; asked through capsCheckWanted)
    property bool readsCaps: true
    signal capsCheckWanted()
    Process {
        id: capsRead
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: ls.capsLock = text.split("\n").some(l => parseInt(l) > 0) }
    }
    // Read once as the screen shows, again just after any key goes down or up in the password
    // field (that's when the light changes), and slowly in between, for a Caps Lock pressed
    // where the field can't see it. (It used to start a shell four times a second while locked)
    function readCaps() {
        if (!readsCaps) { capsCheckWanted(); return; }
        if (!Config.testMode && !capsRead.running) capsRead.running = true;
    }
    Timer { id: capsSoon; interval: 60; onTriggered: ls.readCaps() }       // (the light follows the key a moment later)
    Timer { interval: 4000; running: ls.visible && ls.readsCaps && !Config.testMode; repeat: true; triggeredOnStart: true; onTriggered: ls.readCaps() }

    // ---- Background: plain slate, then the wallpaper once it's there -----------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Config.palette.divider }
            GradientStop { position: 1.0; color: Config.palette.base }
        }
    }
    // The wallpaper, crossfading when it changes (the login screen, choosing someone with a look
    // of their own): the new one loads behind, then fades in as the old one fades out
    component PicLayer: RoundImage {
        id: picLayer
        property bool on: false
        anchors.fill: parent
        radius: ls.corner(width / 2)
        fallback: true      // no account picture: the themed person icon
        fontSource: ls.iconFontSource
        asynchronous: true
        opacity: on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(450); easing.type: Easing.InOutQuad } }
        onStatusChanged: if (status !== Image.Loading && picLayer !== pic.front && source.toString() === pic.want) pic.swap()
    }
    component WallLayer: Image {
        id: layer
        property bool shown: false
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: shown && status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Config.ms(450); easing.type: Easing.InOutQuad } }
        onStatusChanged: if (status === Image.Ready && layer !== wall.front && source.toString() === wall.want) wall.swap()
    }
    Item {
        id: wall
        // A few pixels past each edge: some wallpapers have a stray light/dark
        // row or column at the very edge
        anchors { fill: parent; margins: -4 }
        readonly property string want: ls.wallpaper ? "file://" + ls.wallpaper : ""
        property Item front: wallA
        readonly property Item back: front === wallA ? wallB : wallA
        function show() {
            if (want === "") { wallA.shown = false; wallB.shown = false; return; }
            if (front.source.toString() === want) { front.shown = true; return; }
            back.source = want;
            if (back.status === Image.Ready) swap();      // (already loaded: no signal comes)
        }
        function swap() { const b = back; b.shown = true; front.shown = false; front = b; }
        onWantChanged: show()
        Component.onCompleted: show()
        WallLayer { id: wallA }
        WallLayer { id: wallB }
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
    // (the pointer moving anywhere: someone's here. It takes no clicks, so nothing under it changes)
    HoverHandler { onPointChanged: if (ls.interactive) ls.activity() }

    // ---- Middle: avatar, name, password ---------------------------------------
    Column {
        id: centre
        visible: ls.interactive
        anchors.centerIn: parent
        // (lifted by half of what the avatar's border added, so the password frame stays put)
        anchors.verticalCenterOffset: -34
        spacing: 18

        // Round avatar with a border (8 px round a 124 px picture): the border is the accent
        // (avatarRing, below), over the glass, which shows through it
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 140; height: 140; radius: ls.corner(70)
            color: Qt.alpha(ls.frame, 1 - ls.glassOn)
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: ls.shadowOn > 0; shadowColor: "#000000"; shadowOpacity: 0.45 * ls.shadowOn; shadowBlur: Config.shadowEffectBlur; shadowHorizontalOffset: Config.shadowDX; shadowVerticalOffset: Config.shadowDY; blurMax: 32 }
            GlassFill { screen: ls; shown: ls.glassOn; wallpaper: ls.wallpaper; fill: Config.surface(ls.frame); radius: parent.radius }
            Rectangle {
                anchors { fill: parent; margins: 8 }
                radius: ls.corner(width / 2)
                color: Config.raised(ls.field)
            }
            // The picture's border: the accent, with a light catch along 45° from the top left, as
            // on the window borders' sheen: lighter there, the accent itself towards the bottom
            // right, laid over the glass partly see-through. As round as the picture is. (A thin
            // ring inside a glass border once: the author wanted the border itself in the accent)
            Shape {
                id: avatarRing
                readonly property real line: 8
                // (partly see-through: the frosted glass, or the frame without glass, shows through)
                readonly property real see: 0.6
                readonly property color lit: Qt.alpha(Qt.tint(ls.accent, Qt.rgba(1, 1, 1, 0.5)), see)
                readonly property color soft: Qt.alpha(Qt.tint(ls.accent, Qt.rgba(1, 1, 1, 0.15)), see)
                readonly property color base: Qt.alpha(ls.accent, see)
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    strokeColor: "transparent"
                    fillRule: ShapePath.OddEvenFill
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0
                        x2: avatarRing.width; y2: avatarRing.height
                        GradientStop { position: 0; color: avatarRing.lit }
                        GradientStop { position: 0.45; color: avatarRing.soft }
                        GradientStop { position: 1; color: avatarRing.base }
                    }
                    PathRectangle {
                        width: avatarRing.width; height: avatarRing.height
                        radius: ls.corner(avatarRing.width / 2)
                    }
                    PathRectangle {
                        x: avatarRing.line; y: avatarRing.line
                        width: avatarRing.width - avatarRing.line * 2; height: avatarRing.height - avatarRing.line * 2
                        radius: ls.corner((avatarRing.width - avatarRing.line * 2) / 2)
                    }
                }
            }
            // The picture, crossfading when someone else is chosen (as the wallpaper does)
            Item {
                id: pic
                anchors { fill: parent; margins: 8 }
                readonly property string want: ls.avatar ? "file://" + ls.avatar : ""
                property Item front: picA
                readonly property Item back: front === picA ? picB : picA
                function show() {
                    if (front.source.toString() === want) { front.on = true; return; }
                    back.source = want;
                    if (back.status !== Image.Loading) swap();
                }
                function swap() { const b = back; b.on = true; front.on = false; front = b; }
                onWantChanged: show()
                Component.onCompleted: show()
                PicLayer { id: picA }
                PicLayer { id: picB }
            }
        }

        // Password frame
        Rectangle {
            id: box
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360
            height: boxCol.implicitHeight + 28
            radius: ls.corner(18)
            color: Qt.alpha(ls.frame, 1 - ls.glassOn)
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: ls.shadowOn > 0; shadowColor: "#000000"; shadowOpacity: 0.4 * ls.shadowOn; shadowBlur: Config.shadowEffectBlur; shadowHorizontalOffset: Config.shadowDX; shadowVerticalOffset: Config.shadowDY; blurMax: 32 }
            GlassFill { screen: ls; shown: ls.glassOn; wallpaper: ls.wallpaper; fill: Config.surface(ls.frame); radius: box.radius }
            transform: Translate { id: shakeX }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: shakeX; property: "x"; to: -12; duration: Config.ms(50) }
                NumberAnimation { target: shakeX; property: "x"; to: 10; duration: Config.ms(70) }
                NumberAnimation { target: shakeX; property: "x"; to: -6; duration: Config.ms(60) }
                NumberAnimation { target: shakeX; property: "x"; to: 0; duration: Config.ms(60) }
            }

            Column {
                id: boxCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                // Password field with a go button
                Rectangle {
                    width: parent.width; height: 46; radius: ls.corner(12)
                    color: Config.raised(ls.field)
                    // (flat, with glass too: an outline while it has the keyboard)
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
                        // (a screen reader: the password box; what's typed is never read out)
                        Accessible.role: Accessible.EditableText
                        Accessible.name: ls.asking ? "Answer" : "Password"
                        Accessible.passwordEdit: echoMode === TextInput.Password
                        anchors { left: lockIcon.right; leftMargin: 10; right: goBtn.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        echoMode: ls.asking && ls.answerVisible ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "●"
                        color: ls.text
                        selectionColor: ls.accent
                        font.family: ls.font; font.pixelSize: 15; font.letterSpacing: 2
                        enabled: !ls.busy && !ls.lockedOut
                        focus: true
                        clip: true
                        onAccepted: ls.submit()
                        onTextChanged: if (text !== "" && ls.messageIsError) { ls.message = ""; ls.messageIsError = false; }
                        Keys.onEscapePressed: { if (ls.menu !== "") ls.menu = ""; else if (ls.asking) { text = ""; ls.asking = false; ls.message = ""; ls.cancelled(); } else text = ""; }
                        Keys.onPressed: event => { capsSoon.restart(); if (text === "") ls.activity(); event.accepted = false; }
                        Keys.onReleased: event => { capsSoon.restart(); event.accepted = false; }
                    }
                    Text {
                        visible: password.text === "" && !ls.busy
                        anchors { left: password.left; verticalCenter: parent.verticalCenter }
                        text: ls.asking ? "Answer" : "Password"
                        color: ls.dim
                        font.family: ls.font; font.pixelSize: 14
                    }
                    Rectangle {
                        id: goBtn
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        width: 34; height: 34; radius: ls.corner(9)
                        color: password.text !== "" ? ls.accent : "transparent"
                        Behavior on color { ColorAnimation { duration: Config.ms(120) } }
                        // The arrow, and the spinner in its place while the password's checked: two
                        // items, so the arrow is never the one that was turned (as one, it came back
                        // at whatever angle the spinner had stopped at)
                        Text {
                            anchors.centerIn: parent
                            visible: !ls.busy
                            text: ls.glyph(0xEA1F)
                            color: password.text !== "" ? ls.accentText : ls.dim
                            font.family: tabler.name; font.pixelSize: 17
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: ls.busy
                            text: ls.glyph(0xF226)
                            color: password.text !== "" ? ls.accentText : ls.dim
                            font.family: tabler.name; font.pixelSize: 17
                            RotationAnimation on rotation { running: ls.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                        }
                        TapHandler { onTapped: ls.submit() }
                    }
                }

                // Caps lock / error / status line. Errors sit on a soft red strip; long
                // ones (PAM's own messages on the login screen) wrap inside the frame.
                Rectangle {
                    id: note
                    readonly property bool isError: ls.messageIsError && ls.message !== ""
                    readonly property bool caps: ls.message === "" && ls.capsLock
                    readonly property bool hinting: ls.message === "" && !ls.capsLock && ls.hint !== ""
                    width: parent.width
                    // Only an error's strip needs room round it: a plain line (Caps Lock, a status)
                    // takes its own height, so the frame's edge is as close under it as above the field
                    height: isError ? Math.max(30, noteRow.implicitHeight + 12) : noteRow.implicitHeight
                    radius: ls.corner(10)
                    visible: ls.capsLock || ls.message !== "" || ls.hint !== ""
                    color: isError ? Qt.rgba(ls.error.r, ls.error.g, ls.error.b, 0.14) : "transparent"
                    Row {
                        id: noteRow
                        anchors.centerIn: parent
                        spacing: 7
                        Text {
                            id: noteIcon
                            anchors.top: noteText.top
                            anchors.topMargin: Math.round((noteText.font.pixelSize * 1.35 - font.pixelSize) / 2)
                            visible: note.isError || note.caps
                            text: ls.glyph(note.isError ? 0xEA05 : 0xEFEF)
                            color: note.isError ? ls.error : ls.accent
                            font.family: tabler.name; font.pixelSize: 15
                        }
                        Text {
                            id: noteText
                            // PAM messages can carry their own line breaks; let them wrap to fit instead
                            textFormat: Text.PlainText      // PAM's words, not ours: never markup
                            text: ls.message !== "" ? ls.message.replace(/\s+/g, " ").trim() : note.caps ? "Caps Lock is on" : ls.hint
                            width: Math.min(implicitWidth, note.width - 24 - (noteIcon.visible ? noteIcon.width + noteRow.spacing : 0))
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            lineHeight: 1.35; lineHeightMode: Text.ProportionalHeight
                            // (left once it needs more than one line, going by its words measured
                            // apart: by its own line count or width, its alignment fed back into its
                            // layout, a binding loop, or worse, a layout that never settled)
                            horizontalAlignment: noteWords.advanceWidth > note.width - 24 - (noteIcon.visible ? noteIcon.width + noteRow.spacing : 0)
                                ? Text.AlignLeft : Text.AlignHCenter
                            TextMetrics { id: noteWords; font: noteText.font; text: noteText.text }
                            color: note.isError ? ls.error : ls.message !== "" || note.hinting ? ls.dim : ls.accent
                            font.family: ls.font; font.pixelSize: 13; font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }

    // ---- Corner menus ------------------------------------------------------------
    property string menu: ""              // "", "person", "session" or "power"

    component Pill: Rectangle {
        id: pill
        property int icon
        property string label: ""
        property bool active: false
        property string name: ""                // what a screen reader calls it (else its label)
        signal clicked()
        Accessible.role: Accessible.Button
        Accessible.name: name !== "" ? name : label.replace(/\s*▴$/, "")
        Accessible.onPressAction: clicked()
        height: 44
        width: label ? pillRow.implicitWidth + 30 : 44
        radius: ls.corner(22)
        readonly property color fill: active ? ls.accent : pillHover.hovered ? Config.hoverOn(ls.frame) : ls.frame
        // The active color fades in and out; the hover comes and goes at once (CONVENTIONS, the
        // muted hover): laid over it, below
        readonly property color base: active ? ls.accent : ls.frame
        color: Qt.alpha(base, 1 - ls.glassOn)
        Behavior on color { ColorAnimation { duration: Config.ms(100) } }
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: ls.shadowOn > 0; shadowColor: "#000000"; shadowOpacity: 0.35 * ls.shadowOn; shadowBlur: Config.shadowEffectBlur; shadowHorizontalOffset: Config.shadowDX; shadowVerticalOffset: Config.shadowDY; blurMax: 32 }
        GlassFill { screen: ls; shown: ls.glassOn; wallpaper: ls.wallpaper; fill: pill.active ? pill.fill : Config.surface(pill.fill); radius: pill.radius }
        Rectangle {
            anchors.fill: parent
            radius: pill.radius
            visible: !Config.glass && !pill.active && pillHover.hovered
            color: Config.hoverOn(ls.frame)
        }
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 8
            Text { anchors.verticalCenter: parent.verticalCenter; text: ls.glyph(pill.icon); color: pill.active ? ls.accentText : ls.text; font.family: tabler.name; font.pixelSize: 18 }
            Text { visible: pill.label !== ""; anchors.verticalCenter: parent.verticalCenter; text: pill.label; textFormat: Text.PlainText; color: pill.active ? ls.accentText : ls.text; font.family: ls.font; font.pixelSize: 13; font.weight: Font.Medium }
        }
        HoverHandler { id: pillHover }
        TapHandler { onTapped: pill.clicked() }
    }
    // A menu that opens upwards from a corner button
    component Menu: Rectangle {
        id: m
        property var items: []             // [{ id, label, icon, current }]
        signal chosen(var item)
        width: 220
        height: menuCol.implicitHeight + 12
        radius: ls.corner(16)
        color: Qt.alpha(ls.frame, 1 - ls.glassOn)
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: ls.shadowOn > 0; shadowColor: "#000000"; shadowOpacity: 0.4 * ls.shadowOn; shadowBlur: Config.shadowEffectBlur; shadowHorizontalOffset: Config.shadowDX; shadowVerticalOffset: Config.shadowDY; blurMax: 32 }
        GlassFill { screen: ls; shown: ls.glassOn; wallpaper: ls.wallpaper; fill: Config.surface(ls.frame); radius: m.radius }
        Column {
            id: menuCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 6
            Repeater {
                model: m.items
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width; height: 40; radius: ls.corner(10)
                    color: modelData.current ? ls.accent : itemHover.hovered ? Config.hover : "transparent"
                    Row {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Text { anchors.verticalCenter: parent.verticalCenter; text: ls.glyph(parent.parent.modelData.icon); color: parent.parent.modelData.current ? ls.accentText : (parent.parent.modelData.danger ? ls.error : ls.text); font.family: tabler.name; font.pixelSize: 16 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: parent.parent.modelData.label; textFormat: Text.PlainText; color: parent.parent.modelData.current ? ls.accentText : ls.text; font.family: ls.font; font.pixelSize: 13; font.weight: Font.Medium }
                    }
                    HoverHandler { id: itemHover }
                    TapHandler { onTapped: m.chosen(parent.modelData) }
                }
            }
        }
    }

    // Bottom middle: who's logging in, when there's more than one person (login screen only)
    Pill {
        id: personBtn
        visible: ls.interactive && ls.mode === "login" && ls.people.length > 1
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 }
        icon: 0xEB4D
        label: ls.people.length > 1 ? (ls.people[Math.min(ls.personIndex, ls.people.length - 1)].name || "") + "  ▴" : ""
        active: ls.menu === "person"
        onClicked: ls.menu = ls.menu === "person" ? "" : "person"
    }
    Menu {
        visible: ls.menu === "person" && personBtn.visible
        anchors { horizontalCenter: personBtn.horizontalCenter; bottom: personBtn.top; bottomMargin: 10 }
        width: Math.max(220, personBtn.width)
        items: ls.people.map((p, i) => ({ id: i, label: p.name, icon: 0xEB4D, current: i === ls.personIndex }))
        onChosen: item => {
            ls.menu = "";
            if (item.id !== ls.personIndex) { password.text = ""; ls.reset(); ls.personPicked(item.id); }
            password.forceActiveFocus();
        }
    }
    // Bottom-left: which session (login screen only)
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

    // Bottom right, beside power: the on-screen keyboard, typing into the password box (nothing
    // else can show over the lock screen, so its keys are here, as on the desktop: OnScreenKeys)
    Pill {
        id: keysBtn
        visible: ls.interactive && (ls.mode === "login" || Config.s.onScreenKeyboard)
        anchors { right: powerBtn.visible ? powerBtn.left : parent.right; rightMargin: powerBtn.visible ? 10 : 28; bottom: parent.bottom; bottomMargin: 28 }
        icon: 0xEBD6
        name: "On-screen keyboard"
        active: ls.keysShown
        onClicked: { ls.keysShown = !ls.keysShown; password.forceActiveFocus(); }
    }
    OnScreenKeys {
        visible: ls.keysShown && keysBtn.visible
        anchors.horizontalCenter: parent.horizontalCenter
        // Just under the password frame, never lower than clear of the buttons along the bottom
        // (a short screen: then over the space below the frame as far as it goes)
        y: { box.y; box.height; ls.height; height;
             return Math.min(box.mapToItem(ls, 0, box.height).y + 16, ls.height - height - 90); }
        sounds: false                       // (the lock and login screens stay silent)
        keySize: 40                         // (a little smaller here: room under the password frame)
        color: ls.frame
        keyFill: Config.hoverOn(ls.frame)
        keyText: ls.text
        accentText: ls.accentText
        fontFamily: ls.font
        onTyped: t => { if (!ls.lockedOut && !ls.busy) password.insert(password.cursorPosition, t); }
        onKey: name => {
            if (ls.lockedOut || ls.busy) return;
            const at = password.cursorPosition;
            if (name === "BackSpace" && at > 0) password.remove(at - 1, at);
            else if (name === "Return") ls.submit();
            else if (name === "Left") password.cursorPosition = Math.max(0, at - 1);
            else if (name === "Right") password.cursorPosition = Math.min(password.length, at + 1);
        }
        onHide: ls.keysShown = false
    }

    // Bottom-right: power
    Pill {
        id: powerBtn
        name: "Power"
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
