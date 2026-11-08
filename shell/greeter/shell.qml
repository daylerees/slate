// Slate login screen (greeter). Runs as the "greeter" user inside a small
// Hyprland started by greetd. Uses the same LoginScreen.qml as the lock screen.
//
//   Code (root-owned, installed by: sudo slate-greeter-install):
//     /usr/local/share/slate-greeter   this file, LoginScreen.qml, Config.qml, RoundImage.qml,
//                                      scripts/, settings.json -> data/settings.json
//   Appearance (yours, kept in sync by Slate via slate-greeter-sync; data only, no code):
//     /var/lib/slate-greeter           settings.json wallpaper avatar user.json fonts/
//   Greeter's own writable state (last session):  /var/cache/slate-greeter

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

ShellRoot {
    id: root
    readonly property string dir: Quickshell.env("SLATE_GREETER_DATA") || "/var/lib/slate-greeter"   // appearance data
    readonly property string stateDir: "/var/cache/slate-greeter"

    // ---- Who logs in (written by the sync) -------------------------------------
    property string user: ""
    property string displayName: ""
    property string defaultSession: ""     // the session you were using when Slate last synced
    FileView {
        path: root.dir + "/user.json"
        onLoaded: {
            try {
                const u = JSON.parse(text());
                root.user = u.user || ""; root.displayName = u.name || u.user || "";
                root.defaultSession = u.session || "";
                root.pickRemembered();
            } catch (e) {}
        }
    }
    // Fallback: the first normal account on the system
    Process {
        running: true
        command: ["sh", "-c", "getent passwd | awk -F: '$3>=1000 && $3<60000 && $7 !~ /nologin|false/ {print $1\":\"$5; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(":");
                if (!root.user && p[0]) { root.user = p[0]; root.displayName = (p[1] || p[0]).split(",")[0]; }
            }
        }
    }

    // ---- Wallpaper drives the accent / tint, as on the desktop -----------------
    readonly property string wallpaper: root.dir + "/wallpaper"
    property bool haveWallpaper: false
    Process {
        running: true
        command: ["test", "-s", root.wallpaper]
        onExited: code => { root.haveWallpaper = code === 0; if (code === 0) Config.wallpaper = root.wallpaper; }
    }

    // ---- Sessions (from /usr/share/wayland-sessions), last one remembered -------
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

    function submit(password) {
        if (!Greetd.available) { fail("Not running under greetd"); return; }
        busy = true; message = ""; messageIsError = false;
        pending = password;
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        Greetd.createSession(user);
    }
    function fail(text) {
        busy = false; pending = "";
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
                Greetd.respond(root.pending);
                root.pending = "";
            } else if (error) {
                root.message = message; root.messageIsError = true;   // e.g. faillock's "account locked"
            }
        }
        function onAuthFailure(message) {
            // (Quickshell has already ended the attempt with greetd)
            root.fail(root.messageIsError && root.message ? root.message : "Wrong password");
        }
        function onReadyToLaunch() {
            const s = root.sessions[root.sessionIndex];
            if (!s) { root.fail("No session to start"); return; }
            lastSession.setText(s.id + "\n");
            root.message = "Starting " + s.name + "…"; root.messageIsError = false;
            Qt.callLater(gc);
            Greetd.launch(root.splitExec(s.exec),
                ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + s.id, "XDG_CURRENT_DESKTOP=" + s.desktops], true);
        }
        function onError(error) { root.fail("Login error: " + error); }
    }

    // ---- Power ------------------------------------------------------------------
    function power(action) { Quickshell.execDetached(["systemctl", action]); }

    // ---- Screens: the login box on the first screen, wallpaper on the others -----
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            readonly property bool primary: modelData === Quickshell.screens[0]
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "slate-greeter"
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "#0f1216"
            LoginScreen {
                id: screen
                anchors.fill: parent
                mode: "login"
                visible: true
                wallpaper: root.haveWallpaper ? root.wallpaper : ""
                avatar: root.dir + "/avatar"
                displayName: root.displayName
                sessions: root.sessions
                sessionIndex: root.sessionIndex
                onSessionIndexChanged: root.sessionIndex = sessionIndex
                busy: root.busy
                message: root.message
                messageIsError: root.messageIsError
                showPowerMenu: true
                interactive: win.primary
                iconFontSource: "file://" + root.dir + "/fonts/tabler.ttf"
                onSubmitted: pw => root.submit(pw)
                onPowerAction: a => root.power(a)
                Connections { target: root; function onFailed(t) { screen.fail(t); } }
            }
        }
    }

    // Testing outside greetd (fake greetd socket): qs -p <dir> ipc call greeter submit <password>
    IpcHandler {
        target: "greeter"
        enabled: Quickshell.env("SLATE_GREETER_TEST") === "1"
        function submit(password: string): void { root.submit(password); }
    }
}
