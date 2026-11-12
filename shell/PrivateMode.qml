// Private Mode: nothing on this computer listens, watches or records while it's on.
//   - every microphone muted, and kept muted (new ones too); back as they were after
//   - the camera off for every app (bin/slate-private-camera, a small helper added to the system
//     once, the first time Private Mode is turned on: it asks first, and it's opt in)
//   - Nova and assistants off (Config.assistantOn)
//   - screenshots off (scripts/screenshot.sh reads the mark below), and screen sharing and
//     recording through the desktop portal stopped (apps that capture the screen directly,
//     like grim or wf-recorder, are beyond Slate: Hyprland only lets that change on a restart)
// On/off from the control centre and the launcher (Config.setPrivateMode), and
//   slate ipc call private toggle | on | off

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Scope {
    id: root
    property var confirm: null             // Slate's question window (PowerConfirm.qml)
    readonly property bool on: Config.s.privateMode

    // Where the camera helper lives once it's added (bin/slate-private-camera install), and the
    // mark that tells Slate's own scripts Private Mode is on (screenshot.sh)
    readonly property string helper: "/usr/local/libexec/slate-private-camera"
    readonly property string mark: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/slate-private"
    readonly property string icon: Quickshell.shellPath("assets/icon/icon-64.png")
    property bool helperThere: false

    Connections { target: Config; function onPrivateModeAsked(on) { root.set(on); } }
    IpcHandler {
        target: "private"
        function toggle(): void { root.set(!Config.s.privateMode); }
        function on(): void { root.set(true); }
        function off(): void { root.set(false); }
    }

    // ---- Turning it on and off ------------------------------------------------------------
    // The first time, while the camera helper isn't there, Slate asks: what Private Mode does,
    // and that turning the camera off needs the helper added (your password, once). Turning it
    // on is the yes; Cancel leaves it off
    function set(want) {
        if (!want) { Config.s.privateMode = false; return; }
        if (Config.s.privateMode) return;
        if (helperThere || !confirm || Config.testMode) { Config.s.privateMode = true; return; }
        confirm.confirmWith({
            title: "Turn on Private Mode?",
            body: "While it's on, your microphones are muted, your camera is off for every app, Nova and assistants are off, "
                + "and screenshots and screen sharing are stopped. Turn it off and everything comes back as it was.\n\n"
                + "To turn the camera off for every app, Slate adds a small helper to your system, this once: it asks for your "
                + "password now, and never again. It can only switch the camera off and on.\n\n"
                + "Apps already using the camera or microphone keep them until they let go, and apps that capture the screen "
                + "directly (like grim or wf-recorder) aren't stopped.",
            long: true, button: "Set up and turn on", code: 0xF227, danger: false
        }, () => setup.running = true);
    }
    Process {
        id: setup
        command: ["pkexec", Quickshell.shellPath("bin/slate-private-camera"), "install"]
        stdout: StdioCollector {}
        stderr: StdioCollector { id: setupErr }
        onExited: code => {
            look.running = true;
            if (code === 0) {
                root.helperThere = true;
                Quickshell.execDetached(["notify-send", "--app-name=Slate", "--icon=" + root.icon, "--hint=string:x-slate-page:control",
                    "Private Mode is ready", "Slate can now turn your camera off whenever Private Mode is on. It's on now."]);
            } else {
                const why = code === 3
                    ? "On NixOS the system is set by your configuration, so Slate can't add it. Private Mode is on without turning the camera off."
                    : code === 126 || code === 127
                    ? "It wasn't added, so Private Mode is on without turning the camera off. You can try again by turning Private Mode off and on."
                    : "Something went wrong adding it, so Private Mode is on without turning the camera off. You can try again by turning Private Mode off and on.";
                Quickshell.execDetached(["notify-send", "--app-name=Slate", "--icon=" + root.icon, "--hint=string:x-slate-page:control",
                    "Slate couldn't set up the camera helper", why]);
            }
            Config.s.privateMode = true;
        }
    }
    // Is the helper there? (looked at as Slate starts, and after setting it up)
    Process {
        id: look
        running: !Config.testMode
        command: ["test", "-x", root.helper]
        onExited: code => root.helperThere = code === 0
    }

    // What's turned off and back on, when it changes (and as Slate starts, when it's on)
    onOnChanged: apply()
    Component.onCompleted: if (!Config.testMode) Qt.callLater(apply)
    function apply() {
        if (on) micsOff(); else micsBack();
        if (Config.testMode) return;
        // The mark for Slate's scripts, the portal's screen sharing, and the camera
        Quickshell.execDetached(["sh", "-c", on ? ': > "$0"' : 'rm -f "$0"', mark]);
        Quickshell.execDetached([Quickshell.shellPath("scripts/private-capture.sh"), on ? "off" : "on"]);
        if (on) camera(true);
        else Quickshell.execDetached(["sh", "-c", '[ -x "$0" ] && exec pkexec "$0" on', helper]);
    }
    function camera(off) {
        Quickshell.execDetached(["sh", "-c", '[ -x "$0" ] && exec pkexec "$0" "$1"', helper, off ? "off" : "on"]);
    }
    // A camera plugged in while it's on is covered by the helper's rule; screen sharing that
    // starts its portal again (without systemd to hold it stopped) is stopped again
    Timer {
        running: root.on && !Config.testMode
        interval: 3000; repeat: true
        onTriggered: Quickshell.execDetached([Quickshell.shellPath("scripts/private-capture.sh"), "keep"])
    }

    // ---- Microphones ------------------------------------------------------------------------
    // Every microphone (and line in): muted, and muted again if anything unmutes it, while it's
    // on. Those that weren't muted before are remembered by name (Config.s.privateRestore), so
    // only they come back
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    PwObjectTracker { objects: root.sources }
    function micsOff() {
        const kept = Config.s.privateRestore && Config.s.privateRestore.length !== undefined ? Array.from(Config.s.privateRestore) : [];
        const was = [];
        for (const n of sources) {
            if (!n.audio || n.audio.muted) continue;
            if (kept.indexOf(n.name) < 0 && was.indexOf(n.name) < 0) was.push(n.name);
            n.audio.muted = true;
        }
        if (was.length > 0) Config.s.privateRestore = kept.concat(was);
    }
    function micsBack() {
        const was = Config.s.privateRestore && Config.s.privateRestore.length !== undefined ? Array.from(Config.s.privateRestore) : [];
        for (const n of sources) if (n.audio && was.indexOf(n.name) >= 0) n.audio.muted = false;
        if (was.length > 0) Config.s.privateRestore = [];
    }
    // (new microphones, and any unmuted while it's on: muted again straight away)
    onSourcesChanged: if (on) keepMuted.restart()
    Timer { id: keepMuted; interval: 50; onTriggered: root.micsOff() }
    Instantiator {
        model: root.sources
        delegate: Connections {
            required property var modelData
            target: modelData.audio
            function onMutedChanged() { if (root.on && modelData.audio && !modelData.audio.muted) keepMuted.restart(); }
        }
    }
}
