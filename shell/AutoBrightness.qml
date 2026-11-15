pragma Singleton

// Automatic brightness (Settings → Displays → Automatic brightness): while the switch is on,
// scripts/auto-brightness.py holds the light sensor (iio-sensor-proxy, over D-Bus) and eases the
// screen, and the keyboard's light, to the room, learning from the changes you make. Nothing
// runs while it's off, or on a computer without a sensor (the script says so and stops); turning
// it off stops the script, which gives the sensor back.
//
// Your own changes reach it through manual() (DisplayBrightness.qml: the brightness keys, the
// `osd` IPC's brightnessSet, which Nova uses, and Settings → Displays → Brightness), so they're
// learned rather than fought.
//
// It keeps working in game mode: it draws nothing, a change is rare and slow, and a screen that
// stays readable as the room changes matters as much in a game.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // What this computer has: a sensor iio-sensor-proxy reads, a light sensor in the kernel
    // (whether or not iio-sensor-proxy is there to read it), a screen backlight, a keyboard one
    property bool sensor: false
    property bool hardware: false
    property bool backlight: false
    property bool keyboard: false
    property bool checked: false
    // The switch in Settings shows only where there's a sensor to follow
    readonly property bool shown: backlight && (sensor || hardware)
    readonly property bool on: Config.s.autoBrightness && !Config.isLoginScreen
    readonly property bool running: watcher.running
    // What it's doing now: { lux, screen, keyboard, paused, learned } (the script's last line)
    property var now: null

    // Look again at what this computer has (Settings → Displays, as it opens). While the
    // script runs, its first line has said already
    function refresh() {
        if (Config.isLoginScreen || watcher.running) return;
        checked = false;
        checker.running = false;
        checker.running = true;
    }
    // A change of yours: "screen" or "keyboard", to a percentage
    function manual(which, percent) {
        if (watcher.running && !isNaN(percent))
            watcher.write("manual " + which + " " + Math.round(percent) + "\n");
    }

    function take(line) {
        let e;
        try { e = JSON.parse(line); } catch (err) { return; }
        if (e.sensor !== undefined) {
            sensor = !!e.sensor; hardware = !!e.hardware; backlight = !!e.backlight; keyboard = !!e.keyboard;
            checked = true;
        } else now = e;
    }

    Process {
        id: checker
        command: [Quickshell.shellPath("scripts/auto-brightness.py"), "--check"]
        stdout: SplitParser { onRead: line => root.take(line) }
    }
    Process {
        id: watcher
        running: root.on
        stdinEnabled: true
        command: [Quickshell.shellPath("scripts/auto-brightness.py")]
        stdout: SplitParser { onRead: line => root.take(line) }
        onRunningChanged: if (!running) root.now = null
    }

    function testState() {
        return { sensor: sensor, hardware: hardware, backlight: backlight, keyboard: keyboard, checked: checked,
                 shown: shown, running: running, now: now };
    }
}
