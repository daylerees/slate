// Slate login screen (greeter). Runs as the "greeter" user inside a small
// Hyprland started by greetd. Uses the same LoginScreen.qml as the lock screen.
//
//   Code (root-owned, installed by: sudo slate-greeter-install):
//     /usr/local/share/slate-greeter   this file and the others listed in greeter/files,
//                                      settings.json -> data/settings.json, version
//     /usr/local/share/slate-greeter.good   the last copy someone logged in with
//   Appearance (yours, kept in sync by Slate via slate-greeter-sync; data only, no code):
//     /var/lib/slate-greeter           settings.json wallpaper avatar user.json fonts/
//   Greeter's own writable state (last session):  /var/cache/slate-greeter

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

ShellRoot {
    id: root
    readonly property string dir: Quickshell.env("SLATE_GREETER_DATA") || "/var/lib/slate-greeter"   // appearance data
    readonly property string stateDir: "/var/cache/slate-greeter"
    // Check mode (slate-greeter-install runs it before installing): build the login screen
    // without a window, then exit 0 if it loaded, so a broken copy is never installed
    readonly property bool checking: Quickshell.env("SLATE_GREETER_CHECK") === "1"

    // ---- Who logs in ----------------------------------------------------------------
    // Everyone who can log in (people: { user, name }), and the one chosen: the last
    // person to log in here, else the one whose desktop Slate last synced from (user.json), else
    // the first. Pictures: the synced person's own copy, else AccountsService's (readable by all)
    property var people: []
    property int personIndex: 0
    readonly property var person: people[personIndex] || null
    readonly property string user: person ? person.user : syncedUser
    readonly property string displayName: person ? person.name : syncedName
    readonly property string avatar: !person || person.user === syncedUser ? dir + "/avatar" : "/var/lib/AccountsService/icons/" + person.user
    property bool personChosen: false      // picked on the screen: kept, whatever loads after
    property string syncedUser: ""
    property string syncedName: ""
    property string defaultSession: ""     // the session the synced person was using
    FileView {
        path: root.dir + "/user.json"
        onLoaded: {
            try {
                const u = JSON.parse(text());
                root.syncedUser = u.user || ""; root.syncedName = u.name || u.user || "";
                root.defaultSession = u.session || "";
                root.pickRemembered();
            } catch (e) {}
            root.pickPerson();
            root.userKnown();
        }
    }
    FileView { id: lastUser; path: root.stateDir + "/last-user"; onLoaded: root.pickPerson() }
    // People with a normal account (the same rule as accounts.py's list: a uid from 1000 to
    // 59999 and a shell to log in with), in the order they were added
    Process {
        running: true
        // (the tests hand it a passwd file of their own, under the test switch only)
        command: ["sh", "-c", "{ if [ \"$SLATE_GREETER_TEST\" = 1 ] && [ -n \"$SLATE_GREETER_PASSWD\" ]; then cat \"$SLATE_GREETER_PASSWD\"; else getent passwd; fi; } | awk -F: '$3>=1000 && $3<60000 && $7 !~ /nologin|false/ {print $1\"\\t\"$5}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.people = text.trim().split("\n").filter(l => l).slice(0, 30).map(l => {
                    const p = l.split("\t");
                    const name = (p[1] || "").split(",")[0] || p[0];
                    return { user: p[0], name: name };
                });
                root.pickPerson();
                root.searched = true;
                root.userKnown();
            }
        }
    }
    function pickPerson() {
        if (people.length === 0 || personChosen) return;
        for (const u of [(lastUser.text() || "").trim(), syncedUser]) {
            const i = people.findIndex(p => p.user === u);
            if (u && i >= 0) { personIndex = i; return; }
        }
        personIndex = 0;
    }

    // ---- Wallpaper drives the accent / tint, as on the desktop -----------------
    readonly property string wallpaper: root.dir + "/wallpaper"
    property bool haveWallpaper: false
    Process {
        running: true
        command: ["test", "-s", root.wallpaper]
        onExited: code => { root.haveWallpaper = code === 0; if (code === 0) Config.wallpaper = root.wallpaper; }
    }

    // ---- Sessions (wayland-sessions in the standard data folders), last one remembered ----
    property var sessions: []
    property int sessionIndex: 0
    Process {
        running: true
        // (every standard data folder: XDG_DATA_DIRS, as NixOS keeps them outside /usr/share;
        // the first of each name wins)
        command: ["sh", "-c", "IFS=:; seen=; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do for f in \"$d\"/wayland-sessions/*.desktop; do [ -f \"$f\" ] || continue; n=$(basename \"$f\" .desktop); case \" $seen \" in *\" $n \"*) continue ;; esac; seen=\"$seen $n\"; printf '%s\\t%s\\t%s\\t%s\\n' \"$n\" \"$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-)\" \"$(grep -m1 '^Exec=' \"$f\" | cut -d= -f2-)\" \"$(grep -m1 '^DesktopNames=' \"$f\" | cut -d= -f2-)\"; done; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.sessions = text.trim().split("\n").filter(l => l).map(l => {
                    const p = l.split("\t");
                    return { id: p[0], name: p[1], exec: p[2], desktops: p[3] || p[1] };
                });
                root.pickRemembered();
            }
        }
    }
    FileView {
        id: lastSession
        path: root.stateDir + "/last-session"
        onLoaded: root.pickRemembered()
    }
    // Last session picked here, else the one you were using, else the first
    function pickRemembered() {
        for (const id of [(lastSession.text() || "").trim(), defaultSession]) {
            const i = sessions.findIndex(s => s.id === id);
            if (id && i >= 0) { sessionIndex = i; return; }
        }
    }

    // ---- Logging in through greetd ------------------------------------------------
    property bool busy: false
    property string message: ""
    property bool messageIsError: false
    property string pending: ""
    signal failed(string text)
    // greetd asked a second question after the password (a one-time code, say): the screen shows
    // it, and the next thing typed is the answer, not a new attempt
    property bool asking: false
    signal asked(string question, bool visible)
    signal noted(string text, bool isError)
    // Escape on the question: end the attempt, back to a fresh password
    function cancelAsking() {
        asking = false; busy = false; pending = ""; message = ""; messageIsError = false;
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        Qt.callLater(gc);
    }

    // A password typed before the account is known (the lookups above are still running, say on a
    // busy computer): kept, and tried the moment the account is known, rather than asking greetd
    // to start a session for nobody
    property bool searched: false
    property string waiting: ""
    property bool hasWaiting: false
    function userKnown() {
        if (!hasWaiting || (!user && !searched)) return;
        const w = waiting; waiting = ""; hasWaiting = false;
        if (!user) { fail("Slate couldn't find your account to log in to. Restart your computer and try again"); return; }
        submit(w);
    }

    function submit(password) {
        if (asking && Greetd.state !== GreetdState.Inactive) {
            asking = false; busy = true; message = ""; messageIsError = false;
            Greetd.respond(password);
            return;
        }
        if (!Greetd.available) { fail("Slate couldn't reach the login service (greetd). Restart your computer and try again"); return; }
        busy = true; message = ""; messageIsError = false;
        if (!user) { waiting = password; hasWaiting = true; return; }
        pending = password;
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        Greetd.createSession(user);
    }
    function fail(text) {
        busy = false; pending = ""; asking = false;
        message = text; messageIsError = true;
        root.failed(text);
        Qt.callLater(gc);
    }
    // Split an Exec line into arguments (handles simple quoting, drops %f-style codes)
    function splitExec(exec) {
        const out = []; let cur = "", q = null;
        for (const ch of exec) {
            if (q) { if (ch === q) q = null; else cur += ch; }
            else if (ch === '"' || ch === "'") q = ch;
            else if (ch === " ") { if (cur) { out.push(cur); cur = ""; } }
            else cur += ch;
        }
        if (cur) out.push(cur);
        return out.filter(a => !/^%[a-zA-Z]$/.test(a));
    }
    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                if (root.pending !== "") {
                    Greetd.respond(root.pending);
                    root.pending = "";
                } else {
                    // A question after the password: show it, wait for the answer
                    root.busy = false; root.asking = true;
                    root.message = message; root.messageIsError = false;
                    root.asked(message, echoResponse);
                }
            } else if (message !== "") {
                root.message = message; root.messageIsError = error;   // e.g. faillock's "account locked"
                root.noted(message, error);
            }
        }
        function onAuthFailure(message) {
            // (Quickshell has already ended the attempt with greetd)
            root.fail(root.messageIsError && root.message ? root.message : "That password didn't match");
        }
        function onReadyToLaunch() {
            const s = root.sessions[root.sessionIndex];
            if (!s) { root.fail("Slate couldn't find a session to start"); return; }
            lastSession.setText(s.id + "\n");
            lastUser.setText(root.user + "\n");
            // This version works: the installer keeps it as the fallback (.good)
            const v = version.text().trim();
            if (v) proven.setText(v + "\n");
            root.message = "Starting " + s.name + "…"; root.messageIsError = false;
            Qt.callLater(gc);
            Greetd.launch(root.splitExec(s.exec),
                ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + s.id, "XDG_CURRENT_DESKTOP=" + s.desktops], true);
        }
        // greetd's own problems. After a wrong password Quickshell cancels the attempt that
        // greetd has already ended, and greetd answers "Connection refused": no attempt is under
        // way by then, so it's only logged (shown, it replaced "That password didn't match")
        function onError(error) {
            if (!root.busy) { console.info("slate-greeter: greetd after the attempt ended: " + error); return; }
            console.warn("slate-greeter: greetd: " + error);
            root.fail("Slate couldn't reach the login service. Try again, or restart your computer if it keeps happening.");
        }
    }

    // Which version this is (written by the installer), and the last one that logged someone in
    FileView { id: version; path: Quickshell.shellPath("version"); blockLoading: true; printErrors: false }
    FileView { id: proven; path: root.stateDir + "/proven"; blockWrites: true; printErrors: false }

    // ---- Power ------------------------------------------------------------------
    function power(action) {
        // systemctl with systemd; loginctl (elogind) without
        Quickshell.execDetached(["sh", "-c", 'if [ -d /run/systemd/system ]; then exec systemctl "$0"; else exec loginctl "$0"; fi', action]);
    }

    // ---- Screens: the login box on the first screen, wallpaper on the others -----
    // (LoginWindow.qml; not loaded in check mode, which has no display)
    readonly property Component windowComponent: checking ? null : Qt.createComponent("LoginWindow.qml")
    Variants {
        model: root.checking ? [] : Quickshell.screens.map(s => ({ screen: s, greeter: root }))
        delegate: root.windowComponent
    }
    // If the window can't load there'd be no login screen at all: exit with an error so
    // run-greeter.sh falls back to the last copy that worked
    function checkWindow() {
        if (windowComponent.status !== Component.Error) return;
        console.error("slate-greeter: LoginWindow.qml failed to load: " + windowComponent.errorString());
        Qt.exit(4);
    }

    // Check mode: the same login screen, with no window
    Component { id: checkScreen; LoginScreen { mode: "login"; width: 1280; height: 800 } }
    property var checked: null
    Component.onCompleted: if (checking) checked = checkScreen.createObject(null); else checkWindow()
    Timer {
        running: root.checking
        interval: 1500      // let it settle, so errors while it starts up are logged too
        onTriggered: {
            console.info(root.checked ? "slate-greeter-check: ok" : "slate-greeter-check: LoginScreen failed to load");
            Qt.exit(root.checked ? 0 : 3);
        }
    }

    // Testing outside greetd (fake greetd socket): qs -p <dir> ipc call greeter submit <password>
    IpcHandler {
        target: "greeter"
        enabled: Quickshell.env("SLATE_GREETER_TEST") === "1"
        function submit(password: string): void { root.submit(password); }
        function message(): string { return root.message; }
        function asking(): string { return root.asking ? "yes" : "no"; }
        function cancel(): void { root.cancelAsking(); }
        // Who's listed and who's chosen, and choosing, as the person menu does
        function people(): string { return JSON.stringify(root.people.map(p => p.user)); }
        function user(): string { return root.user; }
        function pick(i: int): void { if (root.asking) root.cancelAsking(); root.personChosen = true; root.personIndex = i; }
    }
}
