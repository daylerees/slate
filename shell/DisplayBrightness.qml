pragma Singleton

// Brightness, for every display Slate can set it on (Settings → Displays → Brightness, the
// brightness keys through OSD.qml, and the `brightness` IPC Nova uses):
//
//  - The built-in screen's backlight, with brightnessctl. Every change goes through one place
//    here, the keys' (step), the osd IPC's and the slider's (setScreen), and each one reaches
//    Automatic brightness (AutoBrightness.manual) to be learned rather than fought. The slider
//    follows the keys, and Automatic brightness, while Settings is open.
//  - A monitor's own brightness control (VCP 0x10, over DDC/CI) with ddcutil, which is optional
//    and slow (a tenth of a second to a second a call, and it can fail): read once as the
//    Displays page opens (scripts/display-brightness.py, which also says which of ddcutil's
//    displays is which output), and set only once a slider's drag rests and when it's let go,
//    one call at a time. Nothing waits on it.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // Each display, by Hyprland's name (DP-1): { kind: "backlight" | "ddc" | "none", percent,
    // bus, max, why } (scripts/display-brightness.py says what each means)
    property var displays: ({})
    property string ddcutil: ""        // "ok", "missing" or "access", once looked
    property bool checked: false
    property int checks: 0             // (how many times it's looked, for the tests)
    readonly property bool checking: lister.running
    // The built-in screen, where there's one Slate can set ("" otherwise)
    readonly property string builtIn: {
        for (const n in displays) if (displays[n].kind === "backlight") return n;
        return "";
    }

    // A change to show (OSD.qml): 0..1, the keyboard's light or the screen's
    signal adjusted(real fraction, bool keyboard)

    // ---- Looking ------------------------------------------------------------------------
    // What each display has, and how bright it is (Settings → Displays, as it opens or a
    // display comes or goes). Slider changes made meanwhile are kept
    function refresh() {
        if (Config.isLoginScreen || lister.running) return;
        lister.seen = {};
        touched = {};
        lister.running = true;
    }
    property var touched: ({})
    function take(line) {
        let e;
        try { e = JSON.parse(line); } catch (err) { return; }
        if (e.done) {
            const kept = {};
            for (const n in displays) if (lister.seen[n]) kept[n] = displays[n];
            displays = kept;
            ddcutil = e.ddcutil || "";
            checked = true;
            checks++;
            for (const n in later) setNow(n, later[n], true);
            later = {};
        } else if (e.display) {
            lister.seen[e.display] = true;
            const d = { kind: e.kind, percent: e.percent, bus: e.bus, max: e.max, why: e.why || "" };
            if (touched[e.display] && displays[e.display]) d.percent = displays[e.display].percent;
            // (part way through easing to the room: where Automatic brightness is taking it)
            else if (e.kind === "backlight" && AutoBrightness.now && typeof AutoBrightness.now.screen === "number")
                d.percent = AutoBrightness.now.screen;
            const all = Object.assign({}, displays);
            all[e.display] = d;
            displays = all;
        }
    }
    Process {
        id: lister
        property var seen: ({})
        command: [Quickshell.shellPath("scripts/display-brightness.py")]
        stdout: SplitParser { onRead: line => root.take(line) }
    }
    // How bright a display is now, as the slider shows it
    function note(name, percent) {
        if (!name || !displays[name] || isNaN(percent)) return;
        const all = Object.assign({}, displays);
        all[name] = Object.assign({}, all[name], { percent: Math.round(percent) });
        displays = all;
    }

    // ---- Setting ------------------------------------------------------------------------
    // From a slider (Settings): shown at once, set as the drag goes (the backlight, quick) or
    // once it rests (a monitor). False for a display Slate can't set
    function set(name, percent) {
        const d = displays[name];
        if (!d || (d.kind !== "backlight" && d.kind !== "ddc")) return false;
        percent = Math.round(Math.max(d.kind === "backlight" ? 1 : 0, Math.min(100, percent)));
        touched[name] = true;
        note(name, percent);
        if (d.kind === "backlight") setScreen(percent, false);
        else {
            wanted[name] = percent;
            rest.restart();
        }
        return true;
    }
    // The slider let go: what it's on now, straight away
    function settle() {
        rest.stop();
        flush();
    }
    // Straight away (the IPC): show says whether the on-screen indicator shows it
    function setNow(name, percent, show) {
        const d = displays[name];
        if (!d) return false;
        if (d.kind === "backlight") {
            setScreen(percent, show);
            return true;
        }
        if (!set(name, percent)) return false;
        settle();
        return true;
    }

    // The built-in screen and the keyboard's light, with brightnessctl -m (device,class,current,percent%,max)
    // The brightness keys: a step up or down
    function step(dir, keyboard) {
        const args = ["brightnessctl", "-m"];
        if (keyboard) args.push("-d", "*kbd_backlight*");
        else args.push("-c", "backlight", "-n1");      // never go fully black
        if (dir === "up") args.push("set", keyboard ? "+1" : "5%+");
        else if (dir === "down") args.push("set", keyboard ? "1-" : "5%-");
        backlight(args, keyboard, true);
    }
    // The screen to a percentage, never fully black (the osd IPC and Nova show it; the slider doesn't)
    function setScreen(percent, show) {
        backlight(["brightnessctl", "-m", "-c", "backlight", "-n1", "set", Math.round(Math.max(1, Math.min(100, percent))) + "%"], false, show);
    }
    // One call at a time: one asked for meanwhile waits, and only the latest
    function backlight(args, keyboard, show) {
        const job = { args: args, keyboard: keyboard, show: show };
        if (bright.running) { bright.next = job; return; }
        bright.job = job;
        bright.command = args;
        bright.running = true;
    }
    Process {
        id: bright
        property var job: null
        property var next: null
        stdout: StdioCollector { onStreamFinished: root.heard(text, bright.job) }
        onRunningChanged: if (!running && next) Qt.callLater(() => {
            const j = bright.next;
            bright.next = null;
            if (j) root.backlight(j.args, j.keyboard, j.show);
        })
    }
    function heard(text, job) {
        const pct = parseInt(text.trim().split("\n").pop().split(",")[3]) / 100;
        if (isNaN(pct) || !job) return;
        if (job.show) adjusted(pct, job.keyboard);
        // (your choice for this light, for Automatic brightness to learn rather than undo)
        AutoBrightness.manual(job.keyboard ? "keyboard" : "screen", pct * 100);
        // (the slider follows: unless another change is on its way, which it already shows)
        if (!job.keyboard && !bright.next) note(builtIn, pct * 100);
    }
    // ...and as Automatic brightness takes it somewhere
    Connections {
        target: AutoBrightness
        function onNowChanged() {
            const n = AutoBrightness.now;
            if (n && n.screen !== null && n.screen !== undefined && !bright.running) root.note(root.builtIn, n.screen);
        }
    }

    // A monitor, with ddcutil: the latest value for each, once the slider rests
    property var wanted: ({})
    property var queue: ({})
    Timer { id: rest; interval: 400; onTriggered: root.flush() }
    function flush() {
        for (const n in wanted) queue[n] = wanted[n];
        wanted = {};
        pump();
    }
    function pump() {
        if (ddc.running) return;
        const n = Object.keys(queue)[0];
        if (n === undefined) return;
        const d = displays[n], pct = queue[n];
        delete queue[n];
        if (!d || d.kind !== "ddc") { pump(); return; }
        ddc.command = ["ddcutil", "--bus", String(d.bus), "--noverify", "setvcp", "10", String(Math.round(pct * (d.max || 100) / 100))];
        ddc.running = true;
    }
    Process {
        id: ddc
        onRunningChanged: if (!running) Qt.callLater(root.pump)
    }

    // A display to set later, once Slate's looked (the IPC, before Settings has opened)
    property var later: ({})
    IpcHandler {
        target: "brightness"
        // Each display Slate can set, and how bright it is: {"checked": true, "displays": {"eDP-1": 52,
        // "DP-1": 70}}. The first call looks (ddcutil takes a second or two), so says checked: false
        function list(): string {
            if (!root.checked) root.refresh();
            const out = {};
            for (const n in root.displays) {
                const d = root.displays[n];
                if (d.kind === "backlight" || d.kind === "ddc") out[n] = d.percent;
            }
            return JSON.stringify({ checked: root.checked, displays: out });
        }
        // One display to a percentage: "ok", "later" (once Slate's looked) or "no" (it can't)
        function set(display: string, percent: int): string {
            if (root.setNow(display, percent, true)) return "ok";
            if (!root.checked) {
                root.later[display] = percent;
                root.refresh();
                return "later";
            }
            return "no";
        }
    }

    function testState() {
        return { displays: displays, checked: checked, checks: checks, checking: checking, ddcutil: ddcutil, builtIn: builtIn };
    }
}
