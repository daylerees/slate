// Displays: reads the monitors from Hyprland, applies changes live and saves them
// (Settings → Displays).
//
// Each monitor is saved by its description (make, model, serial), so its settings follow
// it from port to port. Saved to ~/.local/state/slate/displays.json, plus displays.lua,
// which Hyprland's config loads at startup (session/hypr/config/monitors.lua). Your own
// ~/.config/slate/hypr/hyprland.lua loads after it, so monitor rules there still win.
//
// Changes apply straight away but are only saved once kept: apply() remembers how things
// were, and revert() puts them back (Settings asks, and reverts by itself after a while).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    // Monitors as Hyprland reports them (hyprctl monitors all -j), refreshed by refresh()
    property var monitors: []
    // How things were before the last apply(), until it's kept or reverted
    property var before: null
    readonly property bool pending: before !== null

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/slate"

    function refresh() { query.running = true; }
    Process {
        id: query
        running: true
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.monitors = JSON.parse(text).sort((a, b) => a.x - b.x || a.y - b.y); } catch (e) {}
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].includes(event.name))
                refreshLater.restart();
        }
    }
    Timer { id: refreshLater; interval: 300; onTriggered: root.refresh() }

    // ---- Describing a monitor -----------------------------------------------
    // A monitor's settings as Slate keeps them
    function configOf(m) {
        // A monitor that's off has no size: use its best mode for when it's turned on
        const best = (m.availableModes || [])[0];
        const mode = m.width > 0 ? m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2)
            : best ? best.replace(/Hz$/, "").replace(/@([0-9.]+)$/, (_, hz) => "@" + Number(hz).toFixed(2)) : "1920x1080@60.00";
        return {
            mode: mode,
            x: m.x, y: m.y,
            scale: m.scale > 0 ? m.scale : 1,
            transform: m.transform,
            disabled: !!m.disabled
        };
    }
    // Its size on the layout (what windows and positions are measured in)
    function logicalSize(cfg) {
        const p = cfg.mode.split("@")[0].split("x").map(Number);
        let w = p[0] / cfg.scale, h = p[1] / cfg.scale;
        if (cfg.transform % 2 === 1) [w, h] = [h, w];
        return { w: Math.round(w), h: Math.round(h) };
    }
    // Resolutions and refresh rates: [{ value: "2560x1440@144.00", label: "2560 × 1440 · 144 Hz" }]
    function modeOptions(m) {
        const seen = {}, out = [];
        const add = s => {
            const v = s.replace(/Hz$/, "");
            const [res, hz] = v.split("@");
            const value = res + "@" + Number(hz).toFixed(2);
            if (seen[value]) return;
            seen[value] = true;
            const [w, h] = res.split("x");
            out.push({ value: value, label: w + " × " + h + " · " + Math.round(Number(hz)) + " Hz", w: Number(w), h: Number(h), hz: Number(hz) });
        };
        for (const s of (m.availableModes || [])) add(s);
        if (m.width > 0) add(configOf(m).mode);
        return out.sort((a, b) => b.w * b.h - a.w * a.h || b.hz - a.hz);
    }
    // Scales that give a whole-pixel layout size for this resolution (Hyprland needs that)
    function scaleOptions(mode, current) {
        const p = mode.split("@")[0].split("x").map(Number);
        const out = [];
        for (const s of [1, 1.25, 1.333333, 1.5, 1.6, 1.666667, 1.75, 2, 2.25, 2.5, 2.666667, 3]) {
            const fits = Math.abs(p[0] / s - Math.round(p[0] / s)) < 0.01 && Math.abs(p[1] / s - Math.round(p[1] / s)) < 0.01;
            const isCurrent = Math.abs(s - current) < 0.001;
            if (fits || isCurrent) out.push({ value: isCurrent ? current : s, label: Math.round(s * 100) + "%" });
        }
        return out;
    }
    readonly property var transformOptions: [
        { value: 0, label: "Normal" }, { value: 1, label: "90°" },
        { value: 2, label: "180°" }, { value: 3, label: "270°" }
    ]
    function displayName(m) {
        const d = (m.make || "") + " " + (m.model || "");
        return d.trim() !== "" ? d.trim() : m.name;
    }

    // ---- Applying ---------------------------------------------------------------
    function luaFor(desc, name, cfg) {
        const out = desc ? `desc:${desc}` : name;
        if (cfg.disabled) return `hl.monitor({ output = [==[${out}]==], disabled = true })`;
        return `hl.monitor({ output = [==[${out}]==], disabled = false, mode = "${cfg.mode}", position = "${Math.round(cfg.x)}x${Math.round(cfg.y)}", `
            + `scale = ${Number(cfg.scale).toFixed(6)}, transform = ${cfg.transform} })`;
    }
    // configs: { "<monitor name>": cfg } for every monitor (unchanged ones included)
    function apply(configs) {
        if (!before) {
            const b = {};
            for (const m of monitors) b[m.name] = configOf(m);
            before = b;
        }
        send(configs);
        revertTimer.restart();
    }
    function send(configs) {
        const lines = [];
        for (const m of monitors) if (configs[m.name]) lines.push(luaFor(m.description, m.name, configs[m.name]));
        if (lines.length === 0) return;
        Quickshell.execDetached(["hyprctl", "eval", lines.join("; ")]);
        refreshLater.restart();
    }
    function revert() {
        if (!before) return;
        send(before);
        before = null;
        revertTimer.stop();
    }
    function keep() {
        before = null;
        revertTimer.stop();
        save();
    }
    // Reverts by itself if the change isn't kept (a mode the screen can't show leaves
    // nothing to click)
    readonly property int revertSeconds: 15
    property int secondsLeft: revertSeconds
    Timer {
        id: revertTimer
        interval: 1000; repeat: true
        onRunningChanged: if (running) root.secondsLeft = root.revertSeconds
        onTriggered: {
            root.secondsLeft--;
            if (root.secondsLeft <= 0) root.revert();
        }
    }

    // ---- Saving -----------------------------------------------------------------
    function save() {
        Quickshell.execDetached(["mkdir", "-p", stateDir]);
        const saved = {}, lines = ["-- Written by Slate (Settings → Displays). Changes here are replaced when you change displays there."];
        for (const m of monitors) {
            const cfg = configOf(m);
            if (m.description) saved[m.description] = cfg;
            lines.push(luaFor(m.description, m.name, cfg));
        }
        jsonFile.setText(JSON.stringify(saved, null, 2) + "\n");
        luaFile.setText(lines.join("\n") + "\n");
    }
    FileView { id: jsonFile; path: root.stateDir + "/displays.json"; printErrors: false }
    FileView { id: luaFile; path: root.stateDir + "/displays.lua"; printErrors: false }

    // ---- Arranging ----------------------------------------------------------------
    // Put a monitor beside another: on the side nearest where it was dropped, lined up with
    // its top (or left) edge. Then the layout is shifted so it starts at 0,0.
    function placeBeside(configs, moving, dropX, dropY) {
        const me = configs[moving], meSize = logicalSize(me);
        const cx = dropX + meSize.w / 2, cy = dropY + meSize.h / 2;
        let best = null;
        for (const name in configs) {
            if (name === moving || configs[name].disabled) continue;
            const o = configs[name], s = logicalSize(o);
            const ocx = o.x + s.w / 2, ocy = o.y + s.h / 2;
            const d = Math.hypot(cx - ocx, cy - ocy);
            if (!best || d < best.d) best = { d: d, o: o, s: s, dx: cx - ocx, dy: cy - ocy };
        }
        if (!best) { me.x = 0; me.y = 0; return configs; }
        const o = best.o, s = best.s;
        // Which side: compare how far it was dragged across, relative to the shapes
        if (Math.abs(best.dx) / (s.w + meSize.w) >= Math.abs(best.dy) / (s.h + meSize.h)) {
            me.x = best.dx >= 0 ? o.x + s.w : o.x - meSize.w;
            me.y = Math.max(o.y - meSize.h + 1, Math.min(o.y + s.h - 1, Math.round(dropY)));
            if (Math.abs(me.y - o.y) < 80) me.y = o.y;                        // snap the tops level
            if (Math.abs(me.y + meSize.h - (o.y + s.h)) < 80) me.y = o.y + s.h - meSize.h;   // ...or the bottoms
        } else {
            me.y = best.dy >= 0 ? o.y + s.h : o.y - meSize.h;
            me.x = Math.max(o.x - meSize.w + 1, Math.min(o.x + s.w - 1, Math.round(dropX)));
            if (Math.abs(me.x - o.x) < 80) me.x = o.x;
            if (Math.abs(me.x + meSize.w - (o.x + s.w)) < 80) me.x = o.x + s.w - meSize.w;
            if (Math.abs((me.x + meSize.w / 2) - (o.x + s.w / 2)) < 80) me.x = Math.round(o.x + (s.w - meSize.w) / 2);   // ...or centred
        }
        return normalise(configs);
    }
    // Shift the layout so its top-left is 0,0
    function normalise(configs) {
        let minX = Infinity, minY = Infinity;
        for (const n in configs) if (!configs[n].disabled) { minX = Math.min(minX, configs[n].x); minY = Math.min(minY, configs[n].y); }
        if (!isFinite(minX)) return configs;
        for (const n in configs) { configs[n].x = Math.round(configs[n].x - minX); configs[n].y = Math.round(configs[n].y - minY); }
        return configs;
    }
    // Keep the others clear of a monitor that changed size (scale, mode or rotation): any
    // that touched its right or bottom edge move with that edge
    function reflow(configs, name, oldCfg) {
        const was = logicalSize(oldCfg), now = logicalSize(configs[name]);
        const c = configs[name];
        for (const n in configs) {
            if (n === name) continue;
            const o = configs[n];
            if (Math.abs(o.x - (c.x + was.w)) < 2) o.x = c.x + now.w;
            if (Math.abs(o.y - (c.y + was.h)) < 2) o.y = c.y + now.h;
        }
        return normalise(configs);
    }
    // Every monitor's current settings, to edit and pass to apply()
    function currentConfigs() {
        const c = {};
        for (const m of monitors) c[m.name] = configOf(m);
        return c;
    }
}
