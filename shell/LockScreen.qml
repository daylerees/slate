// Slate lock screen: a real Wayland session lock (covers every monitor) showing
// LoginScreen.qml, with the password checked through PAM.
//
//   slate ipc call lock lock              lock now
//   slate ipc call lock preview lock      try the lock screen in a normal overlay:
//   slate ipc call lock preview login     checks your real password but never locks,
//                                               and the power menu only says what it would do

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

Scope {
    id: root

    // ---- Shared state for every screen ----------------------------------------
    property bool busy: false
    property string message: ""
    property bool messageIsError: false
    signal failed(string text)
    signal opened()

    readonly property string user: Quickshell.env("USER")
    readonly property string avatar: Config.avatarPath + "?v=" + Config.avatarVersion   // version: reload after a change
    property string displayName: user
    Process {
        running: true
        command: ["getent", "passwd", root.user]
        stdout: StdioCollector { onStreamFinished: { const n = (text.split(":")[4] || "").split(",")[0]; if (n) root.displayName = n; } }
    }

    // Sessions for the login preview (the real login screen reads these itself)
    property var sessions: []
    Process {
        running: true
        // (the session files in every standard data folder: XDG_DATA_DIRS, as NixOS keeps them
        // outside /usr/share; the first of each name wins)
        command: ["sh", "-c", "IFS=:; seen=; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do for f in \"$d\"/wayland-sessions/*.desktop; do [ -f \"$f\" ] || continue; n=$(basename \"$f\" .desktop); case \" $seen \" in *\" $n \"*) continue ;; esac; seen=\"$seen $n\"; printf '%s\\t%s\\n' \"$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-)\" \"$(grep -m1 '^Exec=' \"$f\" | cut -d= -f2-)\"; done; done"]
        stdout: StdioCollector {
            // Slate first: the preview shows the first session, as the login screen would
            // show the one you use
            onStreamFinished: root.sessions = text.trim().split("\n").filter(l => l).map(l => { const p = l.split("\t"); return { name: p[0], exec: p[1] }; })
                .sort((a, b) => (b.name === "Slate") - (a.name === "Slate"))
        }
    }

    // ---- Password check ----------------------------------------------------------
    PamContext {
        id: pam
        property string pending: ""
        onResponseRequiredChanged: if (responseRequired && pending !== "") { respond(pending); pending = ""; }
        onCompleted: result => {
            pending = "";
            if (result === PamResult.Success) root.succeeded();
            else root.checkLockout(true);     // wrong password, or locked out?
            root.forget();
        }
        onError: err => { pending = ""; root.fail("Slate couldn't check your password. Please try again"); root.forget(); }
    }
    function check(password) {
        if (lockedOut) return;            // trying while locked out only extends it
        if (pam.active) pam.abort();
        busy = true; message = ""; messageIsError = false;
        pam.pending = password;
        pam.start();
    }
    // Drop our copies of the typed password and let the JS engine reclaim them
    function forget() { pam.pending = ""; Qt.callLater(gc); }

    // ---- Lockout (pam_faillock: 3 wrong passwords within 15 min → 10 min lockout) ----
    readonly property int failDeny: 3
    readonly property int failInterval: 900
    readonly property int unlockTime: 600
    property real lockedUntil: 0          // ms timestamp
    property real now: Date.now()
    readonly property bool lockedOut: lockedUntil > now
    Timer { interval: 1000; repeat: true; running: root.lockedUntil > 0; onTriggered: root.tickLockout() }
    function tickLockout() {
        now = Date.now();
        if (lockedUntil > 0 && now >= lockedUntil) {
            lockedUntil = 0; message = ""; messageIsError = false;
        } else if (lockedUntil > 0) {
            const s = Math.ceil((lockedUntil - now) / 1000);
            message = "Too many tries · you can try again in " + Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
            messageIsError = true;
        }
    }
    property bool afterFailure: false
    function checkLockout(failed) {
        afterFailure = failed;
        faillock.running = true;
    }
    Process {
        id: faillock
        // faillock is in /usr/sbin on Debian and openSUSE, which users often don't have on PATH
        command: ["sh", "-c", "PATH=\"$PATH:/usr/sbin:/sbin\" exec faillock --user \"$0\"", root.user]
        stdout: StdioCollector {
            onStreamFinished: {
                // Lines: "2026-11-07 16:40:01 TTY  /dev/tty1  V"  (V = counts)
                const times = text.split("\n").map(l => l.match(/^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})\s.*\sV\s*$/))
                    .filter(m => m).map(m => new Date(m[1] + "T" + m[2]).getTime());
                const t = Date.now();
                const latest = times.length ? Math.max(...times) : 0;
                const recent = times.filter(x => latest - x <= root.failInterval * 1000).length;
                const live = times.filter(x => t - x <= root.failInterval * 1000).length;
                root.now = t;
                if (recent >= root.failDeny && latest + root.unlockTime * 1000 > t) {
                    root.lockedUntil = latest + root.unlockTime * 1000;
                    root.busy = false;
                    root.tickLockout();
                    if (root.afterFailure) root.failed(root.message);
                } else if (root.afterFailure) {
                    const left = root.failDeny - live;
                    root.fail(left > 0 && left < root.failDeny ? "That password didn't match · " + left + (left === 1 ? " try" : " tries") + " left" : "That password didn't match");
                }
                root.afterFailure = false;
            }
        }
    }
    function fail(text) {
        busy = false; message = text; messageIsError = true;
        root.failed(text);
    }
    function succeeded() {
        busy = false;
        lockedUntil = 0;
        if (previewing) {
            message = "Welcome back"; messageIsError = false;
            previewCloseTimer.restart();
        } else {
            root.unlock();
        }
    }

    // ---- Power -------------------------------------------------------------------
    function power(action) {
        const names = { suspend: "suspend", hibernate: "hibernate", reboot: "restart", poweroff: "shut down", logout: "log out" };
        if (previewing) {                 // never act from the preview
            message = "Preview: would " + names[action]; messageIsError = false;
            return;
        }
        if (action === "logout" || action === "reboot" || action === "poweroff") Config.sessionAction(action);
        else Quickshell.execDetached([Quickshell.shellPath("bin/slate-init"), action]);     // systemctl, or loginctl without systemd
    }

    function startFresh() {
        busy = false; message = ""; messageIsError = false;
        root.opened();
        checkLockout(false);              // still locked out from earlier?
    }

    // ---- The real lock -------------------------------------------------------------
    WlSessionLock {
        id: sessionLock
        locked: false
        onLockedChanged: if (locked) root.startFresh()
        WlSessionLockSurface {
            // See-through only while fading (then Hyprland draws the desktop underneath: xray);
            // otherwise solid, so nothing beneath can ever show
            color: Qt.rgba(0.059, 0.071, 0.086, root.lockFade)
            LoginScreen {
                id: lockScreen
                anchors.fill: parent
                opacity: root.lockFade
                mode: "lock"
                wallpaper: Config.wallpaper
                avatar: root.avatar
                displayName: root.displayName
                busy: root.busy
                message: root.message
                messageIsError: root.messageIsError
                lockedOut: root.lockedOut
                showPowerMenu: Config.s.lockScreenPowerMenu
                onSubmitted: pw => root.check(pw)
                onPowerAction: a => root.power(a)
                Connections { target: root; function onFailed(t) { lockScreen.fail(t); } function onOpened() { lockScreen.reset(); } }
            }
        }
    }

    // ---- Lock before sleep, and "lock session" requests ----------------------------
    // Watch logind. While "lock before sleep" is on, also hold a short delay on
    // sleep so the lock screen is up before the machine suspends; let go once locked.
    // Whether the screen is locked, kept here rather than bound to sessionLock.locked: Quickshell
    // doesn't announce the change when Slate lets the lock go, so a binding stayed true after
    // unlocking, and everything going by it (hot corners, the screensaver, the idle lock) stood
    // down for good. Set by setLocked(), and kept in step with any change Quickshell does announce
    property bool locked: false
    function setLocked(on) {
        sessionLock.locked = on;
        if (locked === on) return;
        locked = on;
        if (!on) released();
    }
    // The lock let go: the fade's state back to rest, xray off
    function released() {
        fadeIn.stop(); fadeOut.stop(); fadeInGuard.stop(); unlockGuard.stop();
        unlocking = false;
        lockFade = 1;
        xray(false);
    }

    // ---- Fading in and out --------------------------------------------------------
    // The lock always engages at once: input goes to it from the first moment. The fade is
    // only how it looks. Hyprland normally draws nothing beneath a lock; for the length of a
    // fade Slate turns on its session_lock_xray, so the lock screen crossfades over the live
    // desktop, then turns it straight off again. On the way out, xray goes on only once your
    // password has been accepted, and the lock is held until the fade has finished, so input
    // stays with it throughout. No fades for locks before sleep, or with animations off (or in
    // game mode). Even if xray were left on, the lock screen at rest is opaque.
    property real lockFade: 1                 // the lock screen's opacity
    property bool unlocking: false
    function xray(on) {
        const cmd = `hl.config({ misc = { session_lock_xray = ${on ? "true" : "false"} } })`;
        if (on) { xrayOn.command = ["hyprctl", "eval", cmd]; xrayOn.running = true; }
        else Quickshell.execDetached(["hyprctl", "eval", cmd]);
    }
    // What to do once xray is on: fade in (locking) or out (unlocking)
    Process {
        id: xrayOn
        onExited: {
            if (root.unlocking) fadeOut.restart();
            else fadeIn.restart();
        }
    }
    NumberAnimation { id: fadeIn; target: root; property: "lockFade"; to: 1; duration: Config.ms(300); easing.type: Easing.OutCubic
        onFinished: root.xray(false) }
    NumberAnimation { id: fadeOut; target: root; property: "lockFade"; to: 0; duration: Config.ms(300); easing.type: Easing.InCubic
        onFinished: root.setLocked(false) }
    // fade: false for locks before sleep (and anything else that mustn't wait on a look)
    function lockNow(fade) {
        if (locked) return;
        fadeOut.stop(); unlocking = false;
        if (fade !== false && Config.animate) {
            lockFade = 0;
            xray(true);                       // the fade starts once it's on (xrayOn)
            fadeInGuard.restart();
        } else {
            fadeIn.stop();
            lockFade = 1;
        }
        setLocked(true);                      // at once, whatever the fade
    }
    function unlock() {
        if (!locked || unlocking) return;
        fadeIn.stop();
        if (Config.animate) {
            unlocking = true;
            lockFade = 1;
            xray(true);                       // only now, after the password: then fade out
            unlockGuard.restart();
        } else {
            setLocked(false);
        }
    }
    // Safety nets, should a fade never start or finish (hyprctl stuck, say): the lock screen
    // shows anyway, so you're never typing into a blank screen; and after your password, the
    // lock lets go anyway, so you can't be left stuck behind it
    Timer { id: fadeInGuard; interval: 1000; onTriggered: if (root.locked && !root.unlocking && root.lockFade < 1 && !fadeIn.running) root.lockFade = 1 }
    Timer { id: unlockGuard; interval: 1500; onTriggered: if (root.unlocking) root.setLocked(false) }
    // Never left on: off when Slate starts, and whenever the lock is let go
    Component.onCompleted: xray(false)
    Connections {
        target: sessionLock
        // A change Quickshell does announce (the compositor ending the lock, say): follow it
        function onLockedChanged() {
            if (root.locked === sessionLock.locked) return;
            root.locked = sessionLock.locked;
            if (!root.locked) root.released();
        }
    }
    Process {
        id: logind
        running: true
        // setpriv --pdeathsig: these exit if Slate itself goes away (restart, reload),
        // so no stray watcher is left holding up sleep. slate-init inhibit: systemd-inhibit, or
        // elogind's without systemd (the login1 signals below are the same from either)
        command: ["setpriv", "--pdeathsig", "TERM"].concat(Config.s.lockBeforeSleep
            ? [Quickshell.shellPath("bin/slate-init"), "inhibit", "--what=sleep", "--mode=delay", "--who=Slate", "--why=Lock the screen before sleep",
               "setpriv", "--pdeathsig", "TERM"]
            : []).concat(["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"])
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("PrepareForSleep (true")) {
                    if (Config.s.lockBeforeSleep) { root.sleepPending = true; root.lockNow(false); sleepFallback.restart(); root.releaseIfSecure(); }
                } else if (line.includes("org.freedesktop.login1.Session.Lock ")) {
                    root.lockNow();
                }
            }
        }
        // Restarts itself (after waking, or when the setting changes)
        onRunningChanged: if (!running) rewatch.restart()
    }
    // Let sleep go ahead (stopping the watcher releases the delay) once Hyprland
    // confirms the lock covers every screen, or after 4 s at most (logind's own limit is 5)
    property bool sleepPending: false
    function releaseIfSecure() { if (sleepPending && sessionLock.secure) releaseSleep.restart(); }
    Connections { target: sessionLock; function onSecureChanged() { root.releaseIfSecure(); root.suspendIfSecure(); } }
    Timer { id: releaseSleep; interval: 150; onTriggered: { sleepFallback.stop(); root.sleepPending = false; logind.running = false; } }
    Timer { id: sleepFallback; interval: 4000; onTriggered: { root.sleepPending = false; logind.running = false; } }

    // Slate's own idle suspend: lock first, then suspend once the lock is up
    property bool suspendPending: false
    function suspendIfSecure() {
        if (suspendPending && sessionLock.secure) { suspendPending = false; Quickshell.execDetached([Quickshell.shellPath("bin/slate-init"), "suspend"]); }
    }
    // Start watching again a moment later; this runs after waking up
    Timer { id: rewatch; interval: 3000; onTriggered: logind.running = true }
    Connections {
        target: Config.s
        function onLockBeforeSleepChanged() { logind.running = false; }
    }

    // ---- Idle: lock, screen off, suspend ----------------------------------------------
    IdleMonitor {
        enabled: Config.s.idleLockMinutes > 0 && !root.locked
        timeout: Config.s.idleLockMinutes * 60
        respectInhibitors: Config.s.idleRespectInhibitors
        onIsIdleChanged: if (isIdle) root.lockNow()
    }
    IdleMonitor {
        enabled: Config.s.idleScreenOffMinutes > 0
        timeout: Config.s.idleScreenOffMinutes * 60
        respectInhibitors: Config.s.idleRespectInhibitors
        onIsIdleChanged: Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.dpms({ action = "${isIdle ? "off" : "on"}" })`])
    }
    IdleMonitor {
        enabled: Config.s.idleSuspendMinutes > 0 && Config.canSuspend
        timeout: Config.s.idleSuspendMinutes * 60
        respectInhibitors: Config.s.idleRespectInhibitors
        onIsIdleChanged: {
            if (!isIdle) return;
            if (Config.s.lockBeforeSleep) { root.suspendPending = true; root.lockNow(false); root.suspendIfSecure(); }
            else Quickshell.execDetached([Quickshell.shellPath("bin/slate-init"), "suspend"]);
        }
    }

    // ---- Preview (an ordinary overlay; nothing is locked) ---------------------------
    property bool previewing: false
    property string previewMode: "lock"
    Timer { id: previewCloseTimer; interval: 900; onTriggered: root.previewing = false }

    PanelWindow {
        visible: root.previewing
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "slate-lock-preview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.previewing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "#0f1216"
        LoginScreen {
            id: previewScreen
            // Hidden along with its window: a hidden window doesn't hide what's in it, so its Caps
            // Lock check (a process every 250 ms) ran for the whole session while no preview showed
            visible: root.previewing
            anchors.fill: parent
            mode: root.previewMode
            wallpaper: Config.wallpaper
            avatar: root.avatar
            displayName: root.displayName
            sessions: root.sessions
            busy: root.busy
            message: root.message
            messageIsError: root.messageIsError
            lockedOut: root.lockedOut
            showPowerMenu: root.previewMode === "login" || Config.s.lockScreenPowerMenu
            onSubmitted: pw => root.check(pw)
            onPowerAction: a => root.power(a)
            Connections { target: root; function onFailed(t) { previewScreen.fail(t); } function onOpened() { previewScreen.reset(); } }
        }
        // Way out of the preview
        Rectangle {
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 20 }
            width: previewLabel.implicitWidth + 28; height: 34; radius: Config.corner(17)
            color: Config.tint("#0f1216")
            Text {
                id: previewLabel
                anchors.centerIn: parent
                text: "Preview · click here to close"
                color: Config.tint("#eef1f5")
                font.family: Config.s.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
            }
            TapHandler { onTapped: root.previewing = false }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lockNow(); }
        function preview(mode: string): void {
            root.previewMode = mode === "login" ? "login" : "lock";
            root.previewing = true;
            root.startFresh();
        }
        function closePreview(): void { root.previewing = false; }
    }
}
