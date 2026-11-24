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
    readonly property string displayName: Config.fullName

    // Caps Lock, for the lock screen on every monitor: one reader for them all (each screen ran
    // its own every 4 seconds while locked). Read as it locks, just after a key in the password
    // field, and slowly in between. Not in tests (the container sees the host's light)
    property bool capsLock: false
    property int capsReads: 0                    // (the tests: how many times it has looked)
    Process {
        id: capsRead
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.capsLock = text.split("\n").some(l => parseInt(l) > 0) }
    }
    function readCaps() { if (!capsRead.running) { capsReads++; if (!Config.testMode) capsRead.running = true; } }
    Timer { interval: 4000; running: root.locked; repeat: true; triggeredOnStart: true; onTriggered: root.readCaps() }

    // Sessions for the login preview (the real login screen reads these itself): read the first
    // time the preview of the login screen is asked for, not at every start
    property var sessions: []
    Process {
        id: sessionsRead
        running: false
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
        // (tests: a PAM service of their own, with questions to ask; set only in test mode)
        config: Config.testMode && root.testPamService !== "" ? root.testPamService : "login"
        configDirectory: Config.testMode && root.testPamDir !== "" ? root.testPamDir : "/etc/pam.d"
        property string pending: ""
        // Every message PAM sends, the questions too. The first question is the password we
        // already hold; a question after it (a one-time code) is shown and waits for the
        // next thing typed, and a plain note or complaint is shown as it comes
        onPamMessage: {
            if (responseRequired) {
                if (pending !== "") { respond(pending); pending = ""; }
                else root.ask(message, responseVisible);
            } else if (message !== "") {
                root.message = message; root.messageIsError = messageIsError;
                root.noted(message, messageIsError);
            }
        }
        onCompleted: result => {
            if (result === PamResult.Error) return;   // (onError has it: it comes first)
            pending = ""; root.asking = false;
            if (result === PamResult.Success) root.succeeded();
            else root.checkLockout(true);     // wrong password, or locked out?
            root.forget();
        }
        // An error is followed by completed(Error), and both used to answer: "couldn't check"
        // first, then "didn't match" once faillock had been read, so for a moment (longer on a
        // busy computer) the wrong words showed. One answer now, from here. TryAuthFailed is PAM
        // saying no with a code other than a plain "wrong" (a module like pam_exec turning down a
        // second answer gives "System error"): it's a refusal, so it's told as one, tries left
        // and all. Only PAM not running at all (StartFailed, InternalError) is "couldn't check"
        onError: err => {
            pending = ""; root.asking = false;
            if (err === PamError.TryAuthFailed) root.checkLockout(true);
            else root.fail("Slate couldn't check your password. Please try again");
            root.forget();
        }
    }
    property string testPamService: ""
    property string testPamDir: ""

    // ---- Another way in: a face, a finger or a key ---------------------------------
    // A second PAM conversation, for a PAM service that has only those ways in and no
    // password (Slate's own, set up from Settings; none for anyone who hasn't): it starts on
    // its own as the lock screen shows, and again once someone's back after it gave up. What it
    // says it's waiting for shows under the field (hint). The password stays its own
    // conversation (pam above, `login`): typing one stops this, so neither ever waits on the
    // other. pam_faillock isn't in this service, so a face that isn't recognized never counts
    // towards the password's tries.
    property string testAutoService: ""
    property string testAutoDir: ""
    // Slate's own (bin/slate-unlock writes it, from Settings → Security): only the methods, each
    // marked "# slate-unlock: <method>". Watched, so turning one on or off counts at once
    property var unlockMethods: []
    property string testUnlockFile: ""   // (the tests: a slate-lock of their own, in a folder of theirs)
    readonly property string unlockFile: Config.testMode ? testUnlockFile : "/etc/pam.d/slate-lock"
    FileView {
        path: root.unlockFile
        watchChanges: true
        printErrors: false               // (it isn't there unless something's been set up)
        onFileChanged: reload()
        onLoaded: root.unlockMethods = text().split("\n").filter(l => l.startsWith("# slate-unlock: ")).map(l => l.slice(16).trim())
        onLoadFailed: root.unlockMethods = []
    }
    readonly property string autoService: Config.testMode && testAutoService !== "" ? testAutoService
        : unlockFile !== "" && unlockMethods.length > 0 ? "slate-lock" : ""
    property string hint: ""
    property real autoStartedAt: 0
    property bool autoGaveUp: false
    // What a known module says, in Slate's words; anything else as it said it (shown as plain text)
    function methodWords(text) {
        const t = String(text || "").trim();
        if (/face|facial|howdy/i.test(t)) return "Looking for your face… or type your password";
        if (/finger|swipe/i.test(t)) return "Touch the fingerprint reader, or type your password";
        if (/touch|u2f|fido|security key|token|device/i.test(t)) return "Touch your security key, or type your password";
        return t;
    }
    PamContext {
        id: autoPam
        config: root.autoService !== "" ? root.autoService : "login"
        configDirectory: Config.testMode && root.testAutoDir !== "" ? root.testAutoDir
            : Config.testMode && root.testUnlockFile !== "" ? root.testUnlockFile.replace(/\/[^\/]*$/, "") : "/etc/pam.d"
        onPamMessage: {
            // (a question is for a password or a code: this conversation never answers one,
            // the password has its own)
            if (responseRequired) { abort(); root.hint = ""; root.autoGaveUp = true; return; }
            if (message !== "" && !messageIsError) root.hint = root.methodWords(message);
        }
        onCompleted: result => {
            root.hint = "";
            if (result === PamResult.Success && !root.busy) { root.succeeded(); return; }
            root.autoGaveUp = true;
        }
        onError: err => { root.hint = ""; root.autoGaveUp = true; }
    }
    // Locked by you (Super+L, Lock now, the power menu, a hot corner, the lid): you're leaving,
    // and still in front of the camera, so a face would let you straight back in. It waits for
    // you to come back instead: a key or the pointer, a few seconds after locking (byYouFor), or
    // the computer waking from sleep. Locked by itself (idle, sleep, the screensaver), you're
    // away already, and it looks as the screen wakes
    property bool waitForYou: false
    property real lockedAt: 0
    readonly property int byYouFor: Config.testMode && testByYouFor >= 0 ? testByYouFor : 4000
    property int testByYouFor: -1
    Connections { target: Config; function onWoke() { if (root.locked && root.waitForYou) { root.waitForYou = false; root.startAuto(); } } }
    function startAuto() {
        if (waitForYou) { autoGaveUp = true; return; }      // (until you're back: activity)
        if (autoService === "" || autoPam.active || busy || asking || lockedOut) return;
        if (!locked && !(previewing && previewMode === "lock")) return;
        autoGaveUp = false;
        autoStartedAt = Date.now();
        autoPam.start();
    }
    function stopAuto() {
        if (autoPam.active) autoPam.abort();
        hint = "";
    }
    // Someone's back (the pointer, or a key before typing): look again if it had given up, not
    // more than once every few seconds
    function activity() {
        if (waitForYou) {
            if (Date.now() - lockedAt < byYouFor) return;
            waitForYou = false;
            startAuto();
            return;
        }
        if (autoGaveUp && Date.now() - autoStartedAt > 3000) startAuto();
    }
    // PAM asked a second question and waits for the answer (what's typed next goes to it)
    property bool asking: false
    signal asked(string question, bool visible)
    signal noted(string text, bool isError)
    function ask(question, visible) {
        busy = false; asking = true; message = question; messageIsError = false;
        asked(question, visible);
    }
    // Escape on a question: drop the attempt, back to a fresh password
    function cancelAsking() {
        asking = false; message = ""; messageIsError = false;
        if (pam.active) pam.abort();
        forget();
    }
    function check(password) {
        if (lockedOut) return;            // trying while locked out only extends it
        stopAuto();                       // (the password wins: the other way in stops)
        if (asking && pam.active) {       // the answer to PAM's question, not a new attempt
            asking = false; busy = true; message = ""; messageIsError = false;
            pam.respond(password);
            return;
        }
        if (pam.active) pam.abort();
        busy = true; message = ""; messageIsError = false;
        pam.pending = password;
        pam.start();
    }
    // Drop our copies of the typed password and let the JS engine reclaim them
    function forget() { pam.pending = ""; Qt.callLater(gc); }

    // ---- Lockout (pam_faillock: 3 wrong passwords within 15 min → 10 min lockout) ----
    // Those are pam_faillock's own defaults; a system that sets others in
    // /etc/security/faillock.conf gets its own numbers (readFaillockConf), so the tries left and
    // the countdown are the ones PAM really keeps. This is only what Slate shows and when it
    // stops sending tries: PAM does the locking out, whatever Slate reads here.
    //   failDeny 0:   PAM never locks the account, so neither does Slate
    //   unlockTime 0: it never unlocks by itself, only when an administrator runs
    //                 `faillock --user … --reset` (lockedUntil is then Infinity)
    property int failDeny: 3
    property int failInterval: 900
    property int unlockTime: 600
    // Tests: a faillock.conf of their own. Only ever looked at in test mode (the `lock` IPC's
    // faillockConf sets it, and only there too)
    property string testFaillockConf: ""
    FileView {
        path: Config.testMode && root.testFaillockConf !== "" ? root.testFaillockConf : "/etc/security/faillock.conf"
        printErrors: false                // it needn't exist: then the defaults stand
        onLoaded: root.readFaillockConf(text())
        onLoadFailed: root.readFaillockConf("")
    }
    // Lines like "deny = 5" (or "unlock_time = never"); "#" starts a comment. Anything missing,
    // or that isn't a number PAM would take, keeps pam_faillock's default
    function readFaillockConf(text) {
        const found = { deny: 3, fail_interval: 900, unlock_time: 600 };
        for (const line of String(text || "").split("\n")) {
            const m = line.replace(/#.*$/, "").trim().match(/^(deny|fail_interval|unlock_time)\s*=\s*(\d{1,9}|never)$/);
            if (!m) continue;
            if (m[2] === "never") { if (m[1] === "unlock_time") found.unlock_time = 0; }
            else if (m[1] !== "fail_interval" || Number(m[2]) > 0) found[m[1]] = Number(m[2]);
        }
        failDeny = found.deny; failInterval = found.fail_interval; unlockTime = found.unlock_time;
    }
    property real lockedUntil: 0          // ms timestamp (Infinity: until an administrator unlocks it)
    property real now: Date.now()
    readonly property bool lockedOut: lockedUntil > now
    Timer { interval: 1000; repeat: true; running: root.lockedUntil > 0; onTriggered: root.tickLockout() }
    function tickLockout() {
        now = Date.now();
        if (lockedUntil === Infinity) {
            // No countdown to show: nothing but an administrator ends this. Look again every few
            // seconds while a screen is up, so the field comes back once they have
            message = "Too many tries · an administrator needs to unlock this account";
            messageIsError = true;
            if ((locked || previewing) && !faillock.running && Math.floor(now / 1000) % 5 === 0) checkLockout(false);
        } else if (lockedUntil > 0 && now >= lockedUntil) {
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
                const never = root.unlockTime <= 0;      // (never unlocks by itself)
                if (root.failDeny > 0 && recent >= root.failDeny && (never || latest + root.unlockTime * 1000 > t)) {
                    root.lockedUntil = never ? Infinity : latest + root.unlockTime * 1000;
                    root.busy = false;
                    root.tickLockout();
                    if (root.afterFailure) { root.failuresShown++; root.failed(root.message); }
                } else {
                    // Unlocked by an administrator since Slate last looked: the field comes back
                    if (root.lockedUntil > 0) { root.lockedUntil = 0; root.message = ""; root.messageIsError = false; }
                    if (root.afterFailure) {
                        const left = root.failDeny - live;
                        root.fail(left > 0 && left < root.failDeny ? "That password didn't match · " + left + (left === 1 ? " try" : " tries") + " left" : "That password didn't match");
                    }
                }
                root.afterFailure = false;
            }
        }
    }
    // (tests: how many times a refusal has been shown, so one attempt can be seen to give one)
    property int failuresShown: 0
    function fail(text) {
        busy = false; message = text; messageIsError = true;
        failuresShown++;
        root.failed(text);
    }
    function succeeded() {
        busy = false;
        stopAuto();
        lockedUntil = 0;
        // (never the preview's ending while the screen is really locked: the lock comes first)
        if (previewing && !locked) {
            message = "Welcome back"; messageIsError = false;
            previewCloseTimer.restart();
        } else {
            root.unlock();
        }
    }

    // ---- Power -------------------------------------------------------------------
    function power(action) {
        const names = { suspend: "suspend", hibernate: "hibernate", reboot: "restart", poweroff: "shut down", logout: "log out" };
        if (previewing && !locked) {      // never act from the preview
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
        stopAuto();
        Qt.callLater(startAuto);          // (a face, a finger or a key, where one's set up)
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
                // (Caps Lock read once for every monitor's screen: root.capsLock)
                readsCaps: false
                capsLock: root.capsLock
                onCapsCheckWanted: root.readCaps()
                wallpaper: Config.wallpaper
                avatar: root.avatar
                displayName: root.displayName
                busy: root.busy
                message: root.message
                messageIsError: root.messageIsError
                hint: root.hint
                onActivity: root.activity()
                lockedOut: root.lockedOut
                showPowerMenu: Config.s.lockScreenPowerMenu
                onSubmitted: pw => root.check(pw)
                onPowerAction: a => root.power(a)
                Connections { target: root; function onFailed(t) { lockScreen.fail(t); } function onOpened() { lockScreen.reset(); }
                    function onAsked(q, v) { lockScreen.ask(q, v); } function onNoted(t, e) { lockScreen.note(t, e); } }
                onCancelled: root.cancelAsking()
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
    // fade: false for locks before sleep (and anything else that mustn't wait on a look);
    // byYou: you asked for it (waitForYou)
    function lockNow(fade, byYou) {
        // A real lock ends any preview: left open, the preview took the first right password
        // for itself ("Welcome back") and the lock stayed
        endPreview();
        if (locked) return;
        waitForYou = byYou === true;
        lockedAt = Date.now();
        // And any check of a password typed into the preview: one still running as the lock
        // comes up mustn't count as the lock's own password
        if (pam.active) { pam.abort(); forget(); }
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
        waitForYou = false;                   // (before woke(), which would start a look)
        Config.woke();                        // (after sleep it's this, more often than not)
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
                } else if (line.includes("PrepareForSleep (false")) {
                    Config.woke();
                } else if (line.includes("org.freedesktop.login1.Session.Lock ")) {
                    root.lockNow(undefined, true);       // (loginctl lock-session: asked for)
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
    // A player playing full screen holds them off (Config.mediaFullscreen), but not once the
    // screen is locked: a video behind the lock mustn't keep the screen on
    readonly property bool mediaHolds: Config.mediaFullscreen && !root.locked
    readonly property bool screenOffWatching: screenOffWatch.enabled    // (the tests read it)
    IdleMonitor {
        enabled: Config.s.idleLockMinutes > 0 && !root.locked && !Config.caffeine && !root.mediaHolds
        timeout: Config.s.idleLockMinutes * 60
        respectInhibitors: Config.s.idleRespectInhibitors
        onIsIdleChanged: if (isIdle) root.lockNow()
    }
    IdleMonitor {
        id: screenOffWatch
        enabled: Config.s.idleScreenOffMinutes > 0 && !Config.caffeine && !root.mediaHolds
        timeout: Config.s.idleScreenOffMinutes * 60
        respectInhibitors: Config.s.idleRespectInhibitors
        onIsIdleChanged: Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.dpms({ action = "${isIdle ? "off" : "on"}" })`])
    }
    IdleMonitor {
        enabled: Config.s.idleSuspendMinutes > 0 && Config.canSuspend && !Config.caffeine && !root.mediaHolds
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
    // Tests: Caps Lock as the preview shows it (the test session never reads the keyboard's light)
    property bool testCaps: false
    // ...and the login screen's people, as the preview shows them (the login screen lists the
    // computer's own; the tests' session has one): [{ user, name }]
    // ("user:Name;user:Name": Quickshell's IPC strips an argument's [ ], so not JSON)
    property string testPeopleText: ""
    readonly property var testPeople: testPeopleText.split(";").filter(p => p.indexOf(":") > 0)
        .map(p => ({ user: p.slice(0, p.indexOf(":")), name: p.slice(p.indexOf(":") + 1) }))
    Timer { id: previewCloseTimer; interval: 900; onTriggered: root.previewing = false }
    function endPreview() { previewCloseTimer.stop(); previewing = false; testCaps = false; testPeopleText = ""; if (!locked) stopAuto(); }

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
            // (the lock screen's preview tries the other way in too; the login screen's doesn't yet)
            hint: root.previewMode === "lock" ? root.hint : ""
            onActivity: if (root.previewMode === "lock") root.activity()
            lockedOut: root.lockedOut
            capsLock: root.testCaps
            people: root.previewMode === "login" ? root.testPeople : []
            showPowerMenu: root.previewMode === "login" || Config.s.lockScreenPowerMenu
            onSubmitted: pw => root.check(pw)
            onPowerAction: a => root.power(a)
            Connections { target: root; function onFailed(t) { previewScreen.fail(t); } function onOpened() { previewScreen.reset(); }
                function onAsked(q, v) { previewScreen.ask(q, v); } function onNoted(t, e) { previewScreen.note(t, e); } }
            onCancelled: root.cancelAsking()
        }
        // Way out of the preview
        Rectangle {
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 20 }
            width: previewLabel.implicitWidth + 28; height: 34; radius: Config.corner(17)
            color: Config.palette.base
            Text {
                id: previewLabel
                anchors.centerIn: parent
                text: "Preview · click here to close"
                color: Config.palette.text
                font.family: Config.s.fontFamily; font.pixelSize: Config.text(12); font.weight: Font.Medium
            }
            TapHandler { onTapped: root.previewing = false }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lockNow(undefined, true); }
        function preview(mode: string): void {
            if (root.locked) return;      // nothing to try out while it's really locked
            root.previewMode = mode === "login" ? "login" : "lock";
            if (root.previewMode === "login" && root.sessions.length === 0 && !sessionsRead.running) sessionsRead.running = true;
            root.previewing = true;
            root.startFresh();
        }
        function closePreview(): void { root.endPreview(); }
        function previewCaps(on: bool): void { if (Config.testMode) root.testCaps = on; }
        function previewPeople(people: string): void { if (Config.testMode) root.testPeopleText = people; }
        function previewMenu(name: string): void { if (Config.testMode) previewScreen.menu = name; }
        // (the tests: the on-screen keyboard's keys shown, as its button does)
        function previewKeys(on: bool): void { if (Config.testMode) previewScreen.keysShown = on; }
        // Tests: a faillock.conf of their own ("" for the system's), and a password as if typed
        // and Enter pressed. PAM checks it like any other, so it's no way past the lock
        function pamService(dir: string, name: string): void { if (Config.testMode) { root.testPamDir = dir; root.testPamService = name; } }
        // (and a service of theirs for another way in, as Slate's own would be: "" for none)
        function autoService(dir: string, name: string): void {
            if (!Config.testMode) return;
            root.stopAuto();              // (PAM won't take a new service while it's talking)
            root.autoGaveUp = false;
            root.testAutoDir = dir; root.testAutoService = name;
        }
        // (a slate-lock of the test's own, read as /etc/pam.d/slate-lock is: "" for none)
        function unlockFile(path: string): void {
            if (!Config.testMode) return;
            root.stopAuto();
            root.autoGaveUp = false;
            root.testUnlockFile = path;
        }
        // (someone's back, as the pointer moving does)
        function activity(): void { if (Config.testMode) root.activity(); }
        // (the tests: how long a lock you asked for waits before your coming back counts, and
        // a lock as idle makes it, not asked for)
        function byYouFor(ms: int): void { if (Config.testMode) root.testByYouFor = ms; }
        function lockAsIdle(): void { if (Config.testMode) root.lockNow(); }
        function cancel(): void { if (Config.testMode) root.cancelAsking(); }
        function faillockConf(path: string): void { if (Config.testMode) root.testFaillockConf = path; }
        function submit(password: string): void { if (Config.testMode) root.check(password); }
    }
}
