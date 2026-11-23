import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Qt.labs.folderlistmodel
import "../.."
import ".."

Column {
    readonly property var win: SettingsHost.win
    spacing: 4
    PageTitle { text: "About Slate" }
    SlateLogo { size: 64; x: 4; textColor: win.text }
    Item { width: 1; height: 10 }
    IntroText { text: "Slate is a calm desktop for Linux with a premium feel: the bar, dock, launcher, window and workspace switchers, panels, notifications and these settings, all in one place. It runs on Quickshell and Hyprland, from ~/.config/slate." }
    // As in LICENSE
    Text {
        text: "© 2026 Dayle Rees · MIT License"
        color: win.dim; font.family: win.font; font.pixelSize: Config.text(12)
        leftPadding: 4; bottomPadding: 10
    }
    // What Slate is using right now, shown like the battery panel's meters: its memory (of
    // all the memory), how busy it keeps the processor, and the last minute of that as a
    // graph. Read from /proc every 2 s while Settings is open (Slate is one process)
    GroupLabel { text: "What Slate is using" }
    Group {
        id: usage
        property real mem: 0            // MB
        property real memTotal: 0       // MB
        property real cpu: -1           // % of the whole processor
        property var history: []        // the last minute of cpu readings
        property real lastTicks: -1
        property real lastTime: 0
        property int cores: 1
        // Shown values glide from one reading to the next
        property real memShown: memTotal > 0 ? mem / memTotal : 0
        property real cpuShown: Math.max(0, cpu) / 100
        Behavior on memShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
        Behavior on cpuShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
        function mb(v) { return v >= 1024 ? (v / 1024).toFixed(v >= 10240 ? 0 : 1) + " GB" : Math.round(v) + " MB"; }
        // Slate is the process reading these, so /proc/self is its own: three small files
        // read in place, with no process started for each reading. The core count never
        // changes, so it's asked once
        FileView { id: usageStatus; path: "/proc/self/status" }
        FileView { id: usageStat; path: "/proc/self/stat" }
        FileView { id: usageMeminfo; path: "/proc/meminfo" }
        Process {
            running: !Config.testMode
            command: ["nproc"]
            stdout: StdioCollector { onStreamFinished: usage.cores = Number(text.trim()) || 1 }
        }
        function read() {
            usageStatus.reload(); usageStat.reload(); usageMeminfo.reload();
            const rss = /^VmRSS:\s+(\d+)/m.exec(usageStatus.text());
            const total = /^MemTotal:\s+(\d+)/m.exec(usageMeminfo.text());
            // (the process's name is in brackets and can hold spaces: the fields count from its end)
            const stat = usageStat.text(), f = stat.slice(stat.lastIndexOf(")") + 2).split(" ");
            if (!rss || !total || f.length < 13) return;
            usage.mem = Number(rss[1]) / 1024;
            usage.memTotal = Number(total[1]) / 1024;
            const ticks = Number(f[11]) + Number(f[12]), now = Date.now();   // utime and stime: fields 14 and 15
            if (usage.lastTicks >= 0 && now > usage.lastTime) {
                usage.cpu = Math.max(0, (ticks - usage.lastTicks) / 100 / ((now - usage.lastTime) / 1000) / usage.cores * 100);
                usage.history = usage.history.concat([usage.cpu]).slice(-30);
            }
            usage.lastTicks = ticks; usage.lastTime = now;
        }
        Timer {
            interval: 2000; repeat: true; triggeredOnStart: true
            running: win.visible
            onTriggered: {
                // (in tests, the same every time: Slate's own use varies from run to run)
                if (Config.testMode) { usage.mem = 420; usage.cores = 8; usage.memTotal = 16384; usage.cpu = 3; usage.history = [2, 3, 4, 3, 2, 3]; return; }
                usage.read();
            }
        }
        Column {
            x: 16; width: parent.width - 32
            topPadding: 14; bottomPadding: 14
            spacing: 14
            // Meters, as in the battery panel
            Repeater {
                model: ["Memory", "Processor"]
                delegate: Column {
                    required property string modelData
                    readonly property bool isMem: modelData === "Memory"
                    readonly property real frac: isMem ? usage.memShown : usage.cpuShown
                    width: parent.width
                    spacing: 6
                    Item {
                        width: parent.width; height: meterName.height
                        Text { id: meterName; text: parent.parent.modelData; color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium }
                        Text {
                            anchors.right: parent.right
                            text: parent.parent.isMem ? (usage.mem > 0 ? usage.mb(usage.mem) + " of " + usage.mb(usage.memTotal) : "Checking…")
                                : (usage.cpu < 0 ? "Checking…" : usage.cpu.toFixed(1) + "% of " + usage.cores + " cores")
                            color: win.dim; font.family: win.font; font.pixelSize: Config.text(12)
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 6; radius: Config.corner(3)
                        color: win.divider
                        Rectangle {
                            width: Math.max(height, parent.width * Math.min(1, parent.parent.frac))
                            height: parent.height; radius: Config.corner(3)
                            color: parent.parent.frac > 0.8 ? win.danger : win.accent
                            Behavior on color { ColorAnimation { duration: Config.ms(300) } }
                        }
                    }
                }
            }
            // The processor over the last minute: scaled to its own peak, so the small
            // ups and downs show
            // Its room only once there's a graph to draw (two readings), so the card doesn't
            // sit with a gap under the meters while it waits
            Item {
                readonly property bool ready: usage.history.length >= 2
                width: parent.width; height: ready ? 64 : 0
                visible: height > 0
                clip: true
                Behavior on height { NumberAnimation { duration: Config.ms(200); easing.type: Easing.OutCubic } }
                readonly property real realPeak: usage.history.length ? Math.max(...usage.history) : 0
                readonly property real peak: Math.max(2, realPeak)     // the graph's top (at least 2%, so tiny wobbles stay small)
                Canvas {
                    id: spark
                    anchors.fill: parent
                    readonly property var data: usage.history
                    readonly property color line: win.accent
                    onDataChanged: requestPaint()
                    onLineChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const d = data, n = 30, w = width, h = height - 2, pk = parent.peak;
                        if (d.length < 2) return;
                        const x = i => w - (d.length - 1 - i) * (w / (n - 1));
                        const y = v => 1 + h - Math.min(1, v / pk) * (h - 2);
                        ctx.beginPath();
                        ctx.moveTo(x(0), y(d[0]));
                        for (let i = 1; i < d.length; i++) ctx.lineTo(x(i), y(d[i]));
                        ctx.lineWidth = 2;
                        ctx.strokeStyle = line;
                        ctx.lineJoin = "round";
                        ctx.stroke();
                        // Soft fill under the line
                        ctx.lineTo(x(d.length - 1), h + 1);
                        ctx.lineTo(x(0), h + 1);
                        ctx.closePath();
                        const g = ctx.createLinearGradient(0, 0, 0, h);
                        g.addColorStop(0, Qt.rgba(line.r, line.g, line.b, 0.28));
                        g.addColorStop(1, Qt.rgba(line.r, line.g, line.b, 0));
                        ctx.fillStyle = g;
                        ctx.fill();
                    }
                }
                Text {
                    anchors { left: parent.left; top: parent.top }
                    visible: usage.history.length >= 2
                    text: "Last minute · peak " + parent.realPeak.toFixed(1) + "%"
                    color: win.dim; font.family: win.font; font.pixelSize: Config.text(11)
                }
            }
        }
    }
    GroupLabel { text: "Tools" }
    Group {
        SettingRow {
            label: "Welcome"
            detail: "The friendly introduction from Slate's first start, with its recommended choices"
            Button {
                label: "Show the welcome"
                onClicked: { win.visible = false; Quickshell.execDetached([Quickshell.shellPath("bin/slate"), "ipc", "call", "welcome", "open"]); }
            }
        }
        Separator {}
        SettingRow {
            label: "Settings file"
            detail: "settings.json in ~/.config/slate"
            // (yours, in your Slate folder; xdg-open takes no "--", and the path starts with "/")
            Button { label: "Open file"; onClicked: Quickshell.execDetached(["xdg-open", Config.userDir + "/settings.json"]) }
        }
        Separator {}
        SettingRow {
            label: "Restart Slate"
            detail: "Reloads the bar, dock, launcher, switchers and notifications"
            Button { label: "Restart"; onClicked: Config.restartSlate() }
        }
    }
}
