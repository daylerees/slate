// Night light: warms the screen colours with a Hyprland screen shader (no extra tools).
// On/off from the control centre; strength from Config.s.nightLightTemperature (kelvin).
//   slate ipc call nightlight toggle | on | off

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root
    readonly property bool on: Config.s.nightLight
    readonly property int kelvin: Math.max(1000, Math.min(6500, Config.s.nightLightTemperature))
    readonly property string shaderPath: Quickshell.env("HOME") + "/.cache/slate/nightlight.frag"

    IpcHandler {
        target: "nightlight"
        function toggle(): void { Config.s.nightLight = !Config.s.nightLight; }
        function on(): void { Config.s.nightLight = true; }
        function off(): void { Config.s.nightLight = false; }
    }

    // White point of a colour temperature, as RGB multipliers (Tanner Helland's fit)
    function whitePoint(k) {
        const t = k / 100;
        const r = t <= 66 ? 255 : 329.698727446 * Math.pow(t - 60, -0.1332047592);
        const g = t <= 66 ? 99.4708025861 * Math.log(t) - 161.1195681661 : 288.1221695283 * Math.pow(t - 60, -0.0755148492);
        const b = t >= 66 ? 255 : t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
        return [r, g, b].map(v => Math.max(0, Math.min(255, v)) / 255);
    }
    readonly property string shader: {
        const w = whitePoint(kelvin).map(v => v.toFixed(4));
        return "#version 300 es\n"
            + "precision highp float;\n"
            + "in vec2 v_texcoord;\n"
            + "uniform sampler2D tex;\n"
            + "out vec4 fragColor;\n"
            + "void main() {\n"
            + "    vec4 c = texture(tex, v_texcoord);\n"
            + `    fragColor = vec4(c.rgb * vec3(${w[0]}, ${w[1]}, ${w[2]}), c.a);\n`
            + "}\n";
    }

    FileView { id: shaderFile; path: root.shaderPath; atomicWrites: true; printErrors: false }
    function apply() {
        if (on) {
            Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.cache/slate"]);
            shaderFile.setText(shader);
            Quickshell.execDetached(["hyprctl", "eval", `hl.config({ decoration = { screen_shader = "${shaderPath}" } })`]);
        } else {
            Quickshell.execDetached(["hyprctl", "eval", `hl.config({ decoration = { screen_shader = "" } })`]);
        }
    }
    onOnChanged: applyLater.restart()
    onShaderChanged: if (on) applyLater.restart()
    Timer { id: applyLater; interval: 200; running: true; onTriggered: root.apply() }
    // ---- Schedule ------------------------------------------------------------------
    // "sun": sunset to sunrise at Settings' location; "custom": nightLightFrom to nightLightTo.
    // It switches at those times; turning it on or off by hand lasts until the next switch.
    readonly property string schedule: Config.s.nightLightSchedule
    property var lastScheduled: null       // what the schedule last asked for
    function minutes(text) {
        const m = /^(\d{1,2}):(\d{2})$/.exec(text || "");
        return m ? parseInt(m[1]) * 60 + parseInt(m[2]) : 0;
    }
    function scheduledOn(now) {
        const t = now.getHours() * 60 + now.getMinutes();
        let from, to;
        if (schedule === "sun") { const st = Config.sunTimes(now); from = st.set; to = st.rise; }
        else { from = minutes(Config.s.nightLightFrom); to = minutes(Config.s.nightLightTo); }
        return from <= to ? (t >= from && t < to) : (t >= from || t < to);   // may wrap past midnight
    }
    function checkSchedule() {
        if (schedule !== "sun" && schedule !== "custom") return;
        if (schedule === "sun" && Config.s.locationName === "") return;   // needs a location
        const want = scheduledOn(new Date());
        if (want !== lastScheduled) {
            lastScheduled = want;
            if (Config.s.nightLight !== want) Config.s.nightLight = want;
        }
    }
    // Changing the schedule applies it straight away
    onScheduleChanged: { lastScheduled = null; checkSchedule(); }
    Connections {
        target: Config.s
        function onNightLightFromChanged() { root.lastScheduled = null; root.checkSchedule(); }
        function onNightLightToChanged() { root.lastScheduled = null; root.checkSchedule(); }
    }
    Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.checkSchedule() }

    // A config reload resets the shader; put it back
    Connections {
        target: Config
        function onHyprConfigReloaded() { applyLater.restart(); }
    }
}
