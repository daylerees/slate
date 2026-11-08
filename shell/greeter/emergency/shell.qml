// Emergency login screen: run-greeter.sh starts this only if the Slate login screen (and
// the last copy that worked) both fail to load, so there's always a way to log in.
// Deliberately plain and self-contained: no Slate files, settings, fonts or scripts, only
// Quickshell's own types, so the things that can break the real one can't break this.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

ShellRoot {
    id: root
    readonly property string dir: Quickshell.env("SLATE_GREETER_DATA") || "/var/lib/slate-greeter"
    readonly property string stateDir: "/var/cache/slate-greeter"
    readonly property bool checking: Quickshell.env("SLATE_GREETER_CHECK") === "1"

    // ---- Who logs in: the synced user, else the first normal account ---------------
    property string user: ""
    FileView {
        path: root.dir + "/user.json"
        printErrors: false
        onLoaded: { try { const u = JSON.parse(text()); if (u.user) root.user = u.user; } catch (e) {} }
    }
    Process {
        running: true
        command: ["sh", "-c", "getent passwd | awk -F: '$3>=1000 && $3<60000 && $7 !~ /nologin|false/ {print $1; exit}'"]
        stdout: StdioCollector { onStreamFinished: if (!root.user) root.user = text.trim() }
    }

    // ---- Sessions (from /usr/share/wayland-sessions), last one remembered -----------
    property var sessions: []
    property int sessionIndex: 0
    Process {
        running: true
        command: ["sh", "-c", "for f in /usr/share/wayland-sessions/*.desktop; do printf '%s\\t%s\\t%s\\t%s\\n' \"$(basename \"$f\" .desktop)\" \"$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-)\" \"$(grep -m1 '^Exec=' \"$f\" | cut -d= -f2-)\" \"$(grep -m1 '^DesktopNames=' \"$f\" | cut -d= -f2-)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.sessions = text.trim().split("\n").filter(l => l).map(l => {
                    const p = l.split("\t");
                    return { id: p[0], name: p[1], exec: p[2], desktops: p[3] || p[1] };
                });
                const i = root.sessions.findIndex(s => s.id === (lastSession.text() || "").trim());
                if (i >= 0) root.sessionIndex = i;
            }
        }
    }
    FileView { id: lastSession; path: root.stateDir + "/last-session"; blockLoading: true; printErrors: false }

    // ---- Logging in through greetd ----------------------------------------------------
    property bool busy: false
    property string message: ""
    property bool messageIsError: false
    property string pending: ""
    signal failed()

    function submit(name, password) {
        if (!Greetd.available) { fail("Not running under greetd"); return; }
        if (!name) { fail("Type your user name"); return; }
        busy = true; message = ""; messageIsError = false;
        pending = password;
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        Greetd.createSession(name);
    }
    function fail(text) {
        busy = false; pending = "";
        message = text; messageIsError = true;
        root.failed();
    }
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
            if (responseRequired) { Greetd.respond(root.pending); root.pending = ""; }
            else if (error) { root.message = message; root.messageIsError = true; }
        }
        function onAuthFailure(message) { root.fail(root.messageIsError && root.message ? root.message : "Wrong user name or password"); }
        function onReadyToLaunch() {
            const s = root.sessions[root.sessionIndex];
            if (!s) { root.fail("No session to start"); return; }
            lastSession.setText(s.id + "\n");
            root.message = "Starting " + s.name + "…"; root.messageIsError = false;
            Greetd.launch(root.splitExec(s.exec),
                ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + s.id, "XDG_CURRENT_DESKTOP=" + s.desktops], true);
        }
        function onError(error) { root.fail("Login error: " + error); }
    }

    function power(action) { Quickshell.execDetached(["systemctl", action]); }

    // ---- The window (Window.qml; not loaded in check mode, which has no display) ------
    readonly property Component windowComponent: checking ? null : Qt.createComponent("Window.qml")
    Variants {
        model: root.checking ? [] : [Quickshell.screens[0]].filter(s => s).map(s => ({ screen: s, greeter: root }))
        delegate: root.windowComponent
    }

    // Check mode (slate-greeter-install): build the login box without a window, exit 0 if it loaded
    Component { id: checkBox; Box { width: 1280; height: 800; greeter: root } }
    property var checked: null
    Component.onCompleted: if (checking) checked = checkBox.createObject(null)
    Timer {
        running: root.checking
        interval: 500
        onTriggered: Qt.exit(root.checked ? 0 : 3)
    }
}
