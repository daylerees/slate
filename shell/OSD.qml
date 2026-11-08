// On-screen indicator for volume, microphone, screen brightness and keyboard
// backlight: a pill near the bottom of the screen with an icon, a level bar and
// the percentage. Fades away after a moment.
//
// Volume and mic: shown whenever they change, from anywhere (keys, apps, the bar).
// Brightness: the screen doesn't announce changes, so the keys go through here:
//   slate ipc call osd brightness up|down
//   slate ipc call osd keyboard up|down
// Volume keys:  slate ipc call osd volume up|down|mute   and   osd mic mute
// Media keys:   slate ipc call media toggle|next|previous   (the playing player, else the first)
// Workspaces (Super+Left/Right):  slate ipc call osd workspace
//   a larger copy of the bar's workspace dots, with the accent marker gliding across

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

PanelWindow {
    id: osd
    required property var bar
    property var popouts: null

    // ---- What's showing ------------------------------------------------------
    property int icon: 0xEB51
    property real value: 0            // 0..1
    property string label: ""         // shown instead of a percentage (e.g. "Muted")
    property bool dimmed: false       // muted: grey bar
    property bool shown: false
    property string mode: "level"     // "level" (volume, brightness…) or "workspace"

    function show(icon, value, label, dimmed) {
        screen = Config.focusedScreen;     // open on the focused screen
        osd.mode = "level";
        osd.icon = icon;
        osd.value = Math.max(0, Math.min(1, value));
        osd.label = label || "";
        osd.dimmed = !!dimmed;
        shown = true;
        hideTimer.restart();
    }
    Timer { id: hideTimer; interval: 1400; onTriggered: osd.shown = false }

    function showWorkspace() {
        screen = Config.focusedScreen;     // open on the focused screen
        const fresh = !(shown && mode === "workspace");
        mode = "workspace";
        if (fresh) ws.prime();
        shown = true;
        hideTimer.restart();
    }

    // ---- Volume & microphone (watch the audio system) -------------------------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [osd.sink, osd.source] }
    property bool ready: false        // ignore the values reported at start-up
    Timer { running: true; interval: 1500; onTriggered: osd.ready = true }

    function showVolume() {
        if (!ready || !sink || !sink.audio) return;
        // The volume panel has its own slider; don't double up
        if (popouts && popouts.current === "volume") return;
        const v = sink.audio.volume, m = sink.audio.muted;
        show(m || v === 0 ? 0xF1C3 : v > 0.66 ? 0xEB51 : v > 0.33 ? 0xEB4F : 0xEB50, v, m ? "Muted" : "", m);
    }
    function showMic() {
        if (!ready || !source || !source.audio) return;
        const m = source.audio.muted;
        show(m ? 0xED16 : 0xEAF0, source.audio.volume, m ? "Mic off" : "Mic on", m);
    }
    Connections {
        target: osd.sink ? osd.sink.audio : null
        function onVolumeChanged() { osd.showVolume(); }
        function onMutedChanged() { osd.showVolume(); }
    }
    Connections {
        target: osd.source ? osd.source.audio : null
        function onMutedChanged() { osd.showMic(); }
    }

    // A short tick on volume key presses, at the new volume (Settings → General → Sound).
    // Held keys repeat fast, so tick at most every 70 ms.
    property real lastTick: 0
    function tick() {
        if (!Config.s.volumeSound || Date.now() - lastTick < 70) return;
        lastTick = Date.now();
        // At Settings → Sound → Sound effects volume (0 = none)
        const v = Math.max(0, Math.min(100, Config.s.soundEffectsVolume)) / 100;
        if (v <= 0) return;
        Quickshell.execDetached(["sh", "-c", "pw-play --volume=\"$1\" \"$0\" 2>/dev/null || paplay --volume=\"$2\" \"$0\"",
            Quickshell.shellPath("sounds/volume-tick.wav"), v.toFixed(2), String(Math.round(v * 65536))]);
    }

    // ---- Brightness (screen and keyboard) -------------------------------------
    // brightnessctl -m prints:  device,class,current,percent%,max
    Process {
        id: bright
        property bool keyboard: false
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("\n").pop().split(",");
                const pct = parseInt(parts[3]) / 100;
                if (isNaN(pct)) return;
                if (bright.keyboard) osd.show(0xEBD6, pct, pct === 0 ? "Off" : "");
                else osd.show(pct < 0.3 ? 0xF237 : 0xEB30, pct, "");
            }
        }
    }
    function brightness(dir, keyboard) {
        const args = ["brightnessctl", "-m"];
        if (keyboard) args.push("-d", "*kbd_backlight*");
        else args.push("-c", "backlight", "-n1");      // never go fully black
        if (dir === "up") args.push("set", keyboard ? "+1" : "5%+");
        else if (dir === "down") args.push("set", keyboard ? "1-" : "5%-");
        bright.keyboard = keyboard;
        bright.command = args;
        bright.running = true;
    }

    IpcHandler {
        target: "osd"
        function volume(action: string): void {
            const a = osd.sink ? osd.sink.audio : null;
            if (!a) return;
            if (action === "mute") a.muted = !a.muted;
            else {
                a.muted = false;
                a.volume = Math.max(0, Math.min(1, Math.round((a.volume + (action === "up" ? 0.05 : -0.05)) * 20) / 20));
                osd.tick();
            }
            osd.showVolume();
        }
        function mic(action: string): void {
            const a = osd.source ? osd.source.audio : null;
            if (a && action === "mute") a.muted = !a.muted;
        }
        function brightness(action: string): void { osd.brightness(action, false); }
        function keyboard(action: string): void { osd.brightness(action, true); }
        function workspace(): void { osd.showWorkspace(); }
    }

    // ---- Media keys -----------------------------------------------------------
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    IpcHandler {
        target: "media"
        function toggle(): void { const p = osd.player; if (p && p.canTogglePlaying) p.togglePlaying(); }
        function next(): void { const p = osd.player; if (p && p.canGoNext) p.next(); }
        function previous(): void { const p = osd.player; if (p && p.canGoPrevious) p.previous(); }
    }

    // ---- Window --------------------------------------------------------------
    property real fade: shown ? 1 : 0
    Behavior on fade { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    visible: fade > 0
    anchors.bottom: true
    // Clear of the dock (or the bar, when either is at the bottom)
    margins.bottom: Config.dockEdge === "bottom" ? 96 : Config.barAtBottom ? osd.bar.barHeight + 28 : 48
    implicitWidth: Math.max(340, pill.width + 40)
    implicitHeight: 90
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "slate-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}                   // never blocks the pointer

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: 16 + (1 - osd.fade) * 12
        width: osd.mode === "workspace" ? ws.width + 40 : 300
        height: 52; radius: 26
        color: osd.bar.barColor
        opacity: osd.fade
        // Glass: a thin light rim
        border.width: Config.glassShine ? 1 : 0
        border.color: Config.glassEdge
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: !Config.glass; shadowColor: "#000000"; shadowOpacity: 0.4
            shadowBlur: 0.8; shadowVerticalOffset: 4; blurMax: 32
        }

        Text {
            id: osdIcon
            visible: osd.mode === "level"
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
            text: String.fromCodePoint(osd.icon)
            color: osd.dimmed ? osd.bar.errorColor : osd.bar.textColor
            font.family: osd.bar.iconFont; font.pixelSize: 20
        }
        // Level bar
        Rectangle {
            id: track
            visible: osd.mode === "level"
            anchors { left: osdIcon.right; leftMargin: 14; right: osdText.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
            height: 6; radius: 3
            color: osd.bar.capsuleColor
            Rectangle {
                width: Math.max(height, track.width * osd.value)
                height: parent.height; radius: 3
                color: osd.dimmed ? Config.tint("#4f5866") : osd.bar.accent
                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
        }
        Text {
            id: osdText
            visible: osd.mode === "level"
            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
            width: 52
            horizontalAlignment: Text.AlignRight
            text: osd.label || Math.round(osd.value * 100) + "%"
            color: osd.dimmed ? osd.bar.errorColor : osd.bar.textColor
            font.family: osd.bar.fontFamily; font.pixelSize: 13; font.weight: Font.Medium
        }

        // ---- Workspaces: the bar's dots, larger --------------------------------
        Item {
            id: ws
            visible: osd.mode === "workspace"
            anchors.centerIn: parent
            readonly property real dot: 20
            readonly property real gap: 10
            readonly property var spaces: Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
            readonly property int activeIndex: Math.max(0, spaces.findIndex(w => Hyprland.focusedWorkspace && w.id === Hyprland.focusedWorkspace.id))
            readonly property real step: dot + gap
            width: Math.max(dot, spaces.length * step - gap)
            height: dot

            // The accent marker glides to the active dot (WorkspaceMarker)
            property int prevIndex: 0
            property int lastIndex: 0
            property real changedAt: 0
            onActiveIndexChanged: {
                prevIndex = lastIndex; lastIndex = activeIndex; changedAt = Date.now();
                wsMarker.go(activeIndex, osd.visible && osd.mode === "workspace");
            }
            // Opening: start from the workspace we just left, so the move is seen
            function prime() {
                wsMarker.jump(Date.now() - changedAt < 500 ? prevIndex : activeIndex);
                wsMarker.go(activeIndex, true);
            }

            Row {
                spacing: ws.gap
                Repeater {
                    model: ws.spaces
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool occupied: (modelData.toplevels?.values?.length ?? 0) > 0
                        width: ws.dot; height: ws.dot; radius: Config.dotRadius(ws.dot)
                        color: occupied ? Config.tint("#aeb6c2") : Config.tint("#4f5866")
                    }
                }
            }
            WorkspaceMarker {
                id: wsMarker
                anchors.fill: parent
                dot: ws.dot; step: ws.step
                animate: false            // moves are started above
                color: osd.bar.accent
            }
        }
    }
}
