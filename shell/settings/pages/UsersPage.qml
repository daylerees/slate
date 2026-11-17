import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import ".."

// ---- Users: the people on this computer (AccountsService, through scripts/accounts.py) -------
// Everyone's listed; an administrator can add someone, change anyone's name, picture,
// password and account type, and remove an account (its home folder kept, or deleted if asked). Anyone can change
// their own name, picture and password. polkit asks for the password (PolkitAgent.qml).
Column {
    readonly property var win: SettingsHost.win
    id: usersPane
    spacing: 4
    readonly property string script: Quickshell.shellPath("scripts/accounts.py")
    // From accounts.py list: { service: "on"|"missing", me, admin, users: [...] }
    property var state: ({ service: "", me: -1, admin: false, users: [] })
    property string listText: ""
    function take(text) {
        win.rowMade("userLooks");
        if (text === listText) return;
        try { state = JSON.parse(text); listText = text; } catch (e) {}
    }
    readonly property bool admin: state.admin
    readonly property int adminCount: state.users.filter(u => u.admin).length
    property string note: ""               // how the last action went
    property int editing: -1               // the uid whose details are open
    property bool adding: false
    // Pictures keep their paths when they change: a number to load them again
    property int pictureVersion: 0

    function refresh() { listProc.running = false; listProc.running = true; }
    // Run one of accounts.py's actions (input: what it reads on stdin, the password), then show
    // how it went and look again. done(ok) runs after.
    property var done: null
    function act(args, doing, input, then) {
        if (actProc.running) return;
        note = doing;
        done = then || null;
        actProc.input = input || "";
        actProc.command = [script].concat(args);
        actProc.running = true;
    }
    FirstLook {
        id: listProc
        running: true
        command: [usersPane.script, "list"]
        stdout: StdioCollector { onStreamFinished: usersPane.take(win.pretendPolls.users ?? text) }
    }
    Process {
        id: actProc
        property string input: ""
        stdinEnabled: true
        onStarted: { if (input !== "") write(input + "\n"); input = ""; }
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim();
                const ok = line === "ok";
                usersPane.note = ok || line === "error canceled" ? ""
                    : line.startsWith("error ") ? line.slice(6) : line;
                usersPane.pictureVersion++;
                usersPane.refresh();
                const then = usersPane.done;
                usersPane.done = null;
                if (then) then(ok);
            }
        }
    }
    // (the tests' pretend accounts, in place of accounts.py list: look again when they change)
    Connections { target: win; enabled: Config.testMode; function onPretendPollsChanged() { usersPane.refresh(); } }
    // Your own picture is Config's (General shows it too): look again when it changes
    Connections { target: Config; function onAvatarVersionChanged() { usersPane.pictureVersion++; usersPane.refresh(); } }

    function describe(u) {
        const bits = [u.admin ? "Administrator" : "Standard", u.username];
        if (u.loggedIn && !u.me) bits.push("Logged in");
        return bits.join(" · ");
    }
    // A username from a full name, while one hasn't been typed: "Sam Lee" → "sam"
    function suggest(name) {
        const first = (name.trim().split(/\s+/)[0] || "").toLowerCase()
            .normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9_-]/g, "");
        return /^[a-z_]/.test(first) ? first.slice(0, 32) : "";
    }
    function taken(username) { return state.users.some(u => u.username === username); }

    // A text box on a row: FieldFrame round a TextInput
    component Field: FieldFrame {
        property alias text: input.text
        property alias input: input
        property string hint: ""
        property bool secret: false
        signal accepted()
        signal edited()          // typed into
        signal finished()        // Enter, or left
        field: input
        width: 220; height: 30
        TextInput {
            activeFocusOnTab: true          // Tab / Shift+Tab: the next or the box before
            id: input
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: win.text; selectionColor: win.accent
            font.family: win.font; font.pixelSize: Config.text(12)
            echoMode: parent.secret ? TextInput.Password : TextInput.Normal
            onAccepted: parent.accepted()
            onTextEdited: parent.edited()
            onEditingFinished: parent.finished()
        }
        Text {
            visible: input.text === "" && !input.activeFocus
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: parent.hint
            color: win.dim; font.family: win.font; font.pixelSize: Config.text(12)
        }
    }

    PageTitle { text: "Users" }
    IntroText { text: "The people who can log in to this computer, each with their own files, settings and password. Adding someone or changing their account asks for an administrator's password." }

    Text {
        visible: usersPane.note !== ""
        width: parent.width; leftPadding: 4; bottomPadding: 4
        textFormat: Text.PlainText        // never markup: it can quote what AccountsService said
        text: usersPane.note
        color: actProc.running ? win.dim : win.danger
        font.family: win.font; font.pixelSize: Config.text(12); wrapMode: Text.Wrap
    }

    GroupLabel { visible: usersPane.state.service === "missing"; text: "Accounts" }
    Group {
        visible: usersPane.state.service === "missing"
        SettingRow {
            label: "Slate can't see the accounts"
            detail: "Install AccountsService (the accountsservice package) to see and change the people on this computer"
        }
    }

    GroupLabel { visible: usersPane.state.service === "on"; text: "People" }
    Group {
        visible: usersPane.state.service === "on"
        Repeater {
            // A row for each account, by its uid, kept while the account is
            model: ScriptModel { values: usersPane.state.users.map(u => u.uid) }
            delegate: Column {
                id: userRow
                required property var modelData      // its account's uid
                required property int index
                readonly property var now: usersPane.state.users.find(u => u.uid === modelData)
                property var kept: ({})
                onNowChanged: if (now) kept = now
                Component.onCompleted: { if (now) kept = now; win.rowMade("users"); }
                readonly property var user: now ?? kept
                readonly property bool open: usersPane.editing === modelData
                readonly property bool canEdit: user.me || usersPane.admin
                property bool changingPassword: false
                onOpenChanged: if (!open) changingPassword = false
                width: parent.width

                Item {
                    width: parent.width; height: 64
                    Separator { visible: userRow.index > 0 }
                    RoundImage {
                        id: userPic
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        width: 40; height: 40; radius: Config.corner(width / 2)
                        fallback: true      // no picture: the themed person icon
                        source: userRow.user.picture ? "file://" + userRow.user.picture + "?v=" + usersPane.pictureVersion : ""
                    }
                    Column {
                        anchors { left: userPic.right; leftMargin: 12; right: userButtons.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        spacing: 2
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            textFormat: Text.PlainText        // never markup: someone's own name
                            text: userRow.user.name + (userRow.user.me ? " (you)" : "")
                            color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: usersPane.describe(userRow.user)
                            color: win.dim; font.family: win.font; font.pixelSize: Config.text(12)
                        }
                    }
                    Row {
                        id: userButtons
                        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Button {
                            visible: userRow.canEdit
                            label: userRow.open ? "Done" : "Edit"
                            onClicked: usersPane.editing = userRow.open ? -1 : userRow.modelData
                        }
                        Button {
                            visible: usersPane.admin && !userRow.user.me
                            label: "Remove"
                            destructive: true
                            onClicked: {
                                const u = userRow.user;
                                if (u.loggedIn) {
                                    usersPane.note = u.name + " is logged in right now. Once they log out, you can remove them";
                                    return;
                                }
                                win.ask = {
                                    title: "Remove " + u.name + "?",
                                    body: u.name + " won't be able to log in anymore. Their files stay in " + (u.home || "their home folder")
                                        + " unless you choose to delete them too. This asks for an administrator's password.",
                                    button: "Remove", destructive: true,
                                    option: { label: "Delete their files too", detail: "Everything in " + (u.home || "their home folder") + " goes, and can't be brought back" },
                                    run: deleteFiles => usersPane.act(["remove", String(u.uid), deleteFiles ? "delete" : "keep"],
                                        (deleteFiles ? "Removing " + u.name + " and their files…" : "Removing " + u.name + "…"))
                                };
                            }
                        }
                    }
                }

                // ---- Their details, while open
                Column {
                    visible: userRow.open
                    width: parent.width
                    Separator {}
                    SettingRow {
                        label: "Name"
                        detail: "How they're shown on the login screen and the lock screen"
                        Field {
                            id: nameField
                            hint: "Full name"
                            Component.onCompleted: text = userRow.user.name
                            onVisibleChanged: if (visible) text = userRow.user.name
                            onAccepted: input.focus = false
                            onFinished: {
                                const t = text.trim();
                                if (t !== "" && t !== userRow.user.name)
                                    usersPane.act(["name", String(userRow.user.uid), t], "Changing the name…");
                            }
                        }
                    }
                    Separator {}
                    SettingRow {
                        label: "Picture"
                        detail: "Shown on the login screen" + (userRow.user.me ? ", the lock screen and the control center" : "")
                        Button {
                            icon: 0xEB0A; label: "Change picture"
                            onClicked: {
                                if (userRow.user.me) { win.avatarPicking = true; return; }
                                const uid = String(userRow.user.uid), who = userRow.user.name;
                                win.pickPictureFor(who, path => usersPane.act(["picture", uid, path], "Changing " + who + "'s picture…"));
                            }
                        }
                    }
                    Separator { visible: usersPane.admin }
                    SettingRow {
                        visible: usersPane.admin
                        label: "Administrator"
                        detail: userRow.user.admin && usersPane.adminCount <= 1
                            ? "The only administrator. Make someone else one first to change this"
                            : "Administrators can add and remove people, install apps and change settings for the whole computer"
                        SettingToggle {
                            checked: userRow.user.admin
                            opacity: userRow.user.admin && usersPane.adminCount <= 1 ? 0.5 : 1
                            onToggled: v => {
                                if (!v && usersPane.adminCount <= 1) return;
                                usersPane.act(["type", String(userRow.user.uid), v ? "admin" : "standard"], v ? "Making them an administrator…" : "Making them a standard account…");
                            }
                        }
                    }
                    Separator {}
                    SettingRow {
                        // Yours: your current password, then the new one (passwd, in accounts.py
                        // own-password: AccountsService would ask for an administrator's).
                        // Someone else's: an administrator sets it
                        id: pwRow
                        readonly property bool mine: userRow.user.me
                        readonly property bool ready: (!mine || pw0.text !== "") && pw1.text !== "" && pw1.text === pw2.text
                        label: "Password"
                        detail: userRow.changingPassword
                            ? (pw1.text !== "" && pw2.text !== "" && pw1.text !== pw2.text ? "Those passwords don't match"
                                : mine ? "Your current password, then the new one twice" : "Type the new password twice, then Change")
                            : mine ? "The one you log in and unlock with" : "The one they log in with. Let them know what it is"
                        Row {
                            spacing: 8
                            Field { id: pw0; visible: userRow.changingPassword && pwRow.mine; width: 120; secret: true; hint: "Current"; onAccepted: pw1.input.forceActiveFocus() }
                            Field { id: pw1; visible: userRow.changingPassword; width: pwRow.mine ? 120 : 150; secret: true; hint: "New password"; onAccepted: pw2.input.forceActiveFocus() }
                            Field { id: pw2; visible: userRow.changingPassword; width: pwRow.mine ? 120 : 150; secret: true; hint: "Again"; onAccepted: setPw.clicked() }
                            Button {
                                id: setPw
                                label: userRow.changingPassword ? "Change" : "Change password"
                                primary: userRow.changingPassword
                                opacity: !userRow.changingPassword || pwRow.ready ? 1 : 0.5
                                onClicked: {
                                    if (!userRow.changingPassword) {
                                        pw0.text = ""; pw1.text = ""; pw2.text = "";
                                        userRow.changingPassword = true;
                                        (pwRow.mine ? pw0 : pw1).input.forceActiveFocus();
                                        return;
                                    }
                                    if (!pwRow.ready || actProc.running) return;
                                    const current = pw0.text, pw = pw1.text;
                                    pw0.text = ""; pw1.text = ""; pw2.text = "";
                                    if (pwRow.mine)
                                        usersPane.act(["own-password"], "Changing your password…", current + "\n" + pw,
                                            ok => { if (ok) userRow.changingPassword = false; });
                                    else
                                        usersPane.act(["password", String(userRow.user.uid)], "Changing the password…", pw,
                                            ok => { if (ok) userRow.changingPassword = false; });
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Adding someone (administrators)
    GroupLabel { visible: usersPane.state.service === "on"; text: "Add someone" }
    Group {
        id: addGroup
        visible: usersPane.state.service === "on"
        property bool usernameTyped: false
        readonly property string username: usernameTyped ? userField.text.trim() : usersPane.suggest(fullField.text)
        readonly property string problem: fullField.text.trim() === "" ? ""
            : !/^[a-z_][a-z0-9_-]{0,31}$/.test(username) ? "A username is lower case letters, numbers, - and _, starting with a letter"
            : usersPane.taken(username) ? "Someone already has that username. Try another"
            : pass1.text !== "" && pass2.text !== "" && pass1.text !== pass2.text ? "Those passwords don't match"
            : ""
        readonly property bool ready: fullField.text.trim() !== "" && problem === "" && pass1.text !== "" && pass1.text === pass2.text
        function reset() {
            fullField.text = ""; userField.text = ""; pass1.text = ""; pass2.text = "";
            usernameTyped = false; adminToggle.checked = false;
        }
        function add() {
            if (!ready || actProc.running) return;
            const name = fullField.text.trim(), pw = pass1.text;
            pass1.text = ""; pass2.text = "";
            usersPane.act(["add", username, name, adminToggle.checked ? "admin" : "standard"], "Adding " + name + "…", pw,
                ok => { if (ok) { usersPane.adding = false; addGroup.reset(); } });
        }
        SettingRow {
            visible: !usersPane.adding
            label: "Add someone"
            detail: usersPane.admin ? "A new account, with its own files, settings and password. Slate sets itself up for them the first time they log in"
                : "Only an administrator can add people to this computer"
            Button {
                visible: usersPane.admin
                icon: 0xEB0B; label: "Add"; primary: true
                onClicked: { addGroup.reset(); usersPane.adding = true; fullField.input.forceActiveFocus(); }
            }
        }
        SettingRow {
            visible: usersPane.adding
            label: "Full name"
            detail: "As it's shown on the login screen"
            Field { id: fullField; hint: "Sam Lee"; onAccepted: (addGroup.usernameTyped ? pass1 : userField).input.forceActiveFocus() }
        }
        Separator { visible: usersPane.adding }
        SettingRow {
            visible: usersPane.adding
            label: "Username"
            detail: "What they log in with, and the name of their home folder. It can't be changed later"
            Field {
                id: userField
                hint: addGroup.username || "sam"
                onAccepted: pass1.input.forceActiveFocus()
                onEdited: addGroup.usernameTyped = text !== ""
            }
        }
        Separator { visible: usersPane.adding }
        SettingRow {
            visible: usersPane.adding
            label: "Password"
            detail: "Type it twice. You can change it later, and so can they"
            Row {
                spacing: 8
                Field { id: pass1; width: 150; secret: true; hint: "Password"; onAccepted: pass2.input.forceActiveFocus() }
                Field { id: pass2; width: 150; secret: true; hint: "Again"; onAccepted: addGroup.add() }
            }
        }
        Separator { visible: usersPane.adding }
        SettingRow {
            visible: usersPane.adding
            label: "Administrator"
            detail: "Can add and remove people, install apps and change settings for the whole computer"
            SettingToggle { id: adminToggle; onToggled: v => checked = v }
        }
        Separator { visible: usersPane.adding }
        SettingRow {
            visible: usersPane.adding
            label: "Add " + (fullField.text.trim() || "them")
            detail: addGroup.problem !== "" ? addGroup.problem : "This asks for your password"
            Row {
                spacing: 8
                Button { label: "Cancel"; onClicked: { usersPane.adding = false; addGroup.reset(); } }
                Button {
                    label: "Add"; primary: true
                    opacity: addGroup.ready && !actProc.running ? 1 : 0.5
                    onClicked: addGroup.add()
                }
            }
        }
    }
}
