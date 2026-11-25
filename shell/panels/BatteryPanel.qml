import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs

// ---- Battery & power ---------------------------------------------------
Column {
    required property var pop
    id: bat
    width: 300
    spacing: 12
    readonly property var dev: UPower.displayDevice
    // (a computer with no battery: the panel is its power mode and system readings alone)
    readonly property bool has: !!dev && dev.isPresent
    readonly property real pct: dev && dev.ready ? dev.percentage : 0
    readonly property int st: dev ? dev.state : 0
    function duration(sec) {
        if (!sec || sec <= 0) return "";
        const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
        return h > 0 ? `${h} h ${m} min` : `${m} min`;
    }
    readonly property string stateText:
        st === UPowerDeviceState.Charging ? "Charging" + (duration(dev.timeToFull) ? " · full in " + duration(dev.timeToFull) : "")
        : st === UPowerDeviceState.FullyCharged ? "Fully charged"
        : st === UPowerDeviceState.Discharging ? "On battery" + (duration(dev.timeToEmpty) ? " · " + duration(dev.timeToEmpty) + " left" : "")
        : UPower.onBattery ? "On battery" : "Plugged in"

    Row {
        visible: bat.has
        spacing: 10
        Icon {
            code: UPower.onBattery ? 0xEA34 : 0xEA33
            font.pixelSize: 24
            anchors.verticalCenter: parent.verticalCenter
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Label { text: Math.round(bat.pct * 100) + "%"; font.pixelSize: Config.text(20) }
            Label { text: bat.stateText; color: pop.dim; font.pixelSize: Config.text(12) }
        }
    }
    // Charge bar
    Meter {
        visible: bat.has
        width: parent.width
        value: bat.pct; minFill: 0
        trackColour: pop.card
        colour: bat.pct < 0.15 && UPower.onBattery ? pop.danger : pop.accent
    }

    // The battery's health (how much of what it was made to hold it still holds), and
    // where charging stops if the laptop's set to stop short of full. Each only where
    // the battery says: not all do
    readonly property var cell: UPower.devices.values.find(d => d.isLaptopBattery) ?? null
    readonly property real health: cell && cell.healthSupported && cell.healthPercentage > 0 ? cell.healthPercentage : -1
    readonly property string cellName: cell && cell.nativePath ? String(cell.nativePath).split("/").pop() : ""
    FileView {
        id: limitFile
        path: bat.cellName !== "" ? "/sys/class/power_supply/" + bat.cellName + "/charge_control_end_threshold" : ""
        printErrors: false
        onLoaded: { const n = parseInt(text()); bat.limit = n > 0 && n < 100 ? n : -1; }
        onLoadFailed: bat.limit = -1
    }
    property int limit: -1
    Repeater {
        model: [{ label: "Battery health", value: bat.health >= 0 ? Math.round(bat.health) + "%" : "" },
                { label: "Charges up to", value: bat.limit > 0 ? bat.limit + "%" : "" }]
        delegate: Item {
            required property var modelData
            visible: modelData.value !== ""
            width: bat.width; height: factLabel.height
            Label { id: factLabel; text: parent.modelData.label; font.pixelSize: Config.text(12) }
            Label { anchors.right: parent.right; text: parent.modelData.value; color: pop.dim; font.pixelSize: Config.text(12) }
        }
    }

    Divider { visible: bat.has }
    Heading { text: "Power mode" }
    Row {
        width: parent.width
        spacing: 6
        Repeater {
            model: [
                { p: PowerProfile.PowerSaver, label: "Saver", code: 0xED4F },
                { p: PowerProfile.Balanced, label: "Balanced", code: 0xEBC2 },
                { p: PowerProfile.Performance, label: "Performance", code: 0xEC45 }
            ].filter(x => x.p !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)
            delegate: RowButton {
                id: profileButton
                required property var modelData
                width: (bat.width - 12) / 3
                height: 56
                selected: PowerProfiles.profile === modelData.p
                onClicked: PowerProfiles.profile = modelData.p
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    RowIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        code: profileButton.modelData.code
                        font.pixelSize: 18
                        color: profileButton.fg
                    }
                    RowLabel {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: profileButton.modelData.label
                        font.pixelSize: Config.text(12)
                        color: profileButton.fg
                    }
                }
            }
        }
    }

    // ---- System: CPU, memory, swap, the main drive and the graphics card, refreshed while the
    // panel is open (swap only when there is some; the graphics card only when it can say)
    Divider {}
    Heading { text: "System" }
    property real cpu: 0                 // 0..1
    property var lastCpu: null           // [busy, total] from the previous reading
    property real memUsed: 0
    property real memTotal: 0
    property real diskUsed: 0
    property real diskTotal: 0
    property real swapUsed: 0
    property real swapTotal: 0             // (0: no swap, and no row for it)
    property real gpu: pop.gpuLast         // 0..1, the busiest card awake
    property string gpuState: pop.gpuSeen  // "": no card can say (no row); "busy"; "asleep"
    // Asked every third reading (6 s: nvidia-smi is slow, and asking often kept a laptop's second
    // card from going back to sleep), and not again in this opening once nothing has answered
    property int gpuTick: 0
    property bool gpuNone: false
    property int gpuAsks: 0                // (the tests: how many times it asked)
    Process {
        id: gpuInfo
        command: [Quickshell.shellPath("scripts/gpu-busy.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l !== "");
                const busy = lines.filter(l => l.startsWith("busy ")).map(l => Number(l.slice(5)) / 100).filter(n => !isNaN(n));
                if (busy.length) { bat.gpu = Math.max(0, Math.min(1, Math.max(...busy))); bat.gpuState = "busy"; }
                else if (lines.includes("asleep")) { bat.gpu = 0; bat.gpuState = "asleep"; }
                else { bat.gpuState = ""; bat.gpuNone = true; }
                pop.gpuSeen = bat.gpuState; pop.gpuLast = bat.gpu;
            }
        }
    }
    FileView { id: statFile; path: "/proc/stat" }
    FileView { id: memFile; path: "/proc/meminfo" }
    Process {
        id: diskInfo
        command: ["df", "-B1", "--output=size,used", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n").pop().trim().split(/\s+/).map(Number);
                if (f.length === 2 && !isNaN(f[0])) { bat.diskTotal = f[0]; bat.diskUsed = f[1]; }
            }
        }
    }
    function sample() {
        if (bat.cellName !== "") limitFile.reload();
        // (in tests, the same readings every time: the test container sees the computer
        // running it, so its screenshots changed with what that was doing)
        if (Config.testMode) {
            cpu = 0.12; memTotal = 16 * 1024 ** 3; memUsed = 6.4 * 1024 ** 3; diskTotal = 512e9; diskUsed = 180e9;
            swapTotal = 8 * 1024 ** 3; swapUsed = 1.2 * 1024 ** 3; gpu = 0.23; gpuState = "busy";
            return;
        }
        statFile.reload(); memFile.reload();
        const c = (statFile.text().split("\n")[0] || "").trim().split(/\s+/).slice(1).map(Number);
        if (c.length >= 4) {
            const idle = c[3] + (c[4] || 0), total = c.reduce((a, b) => a + b, 0);
            if (lastCpu) {
                const dt = total - lastCpu[1], dbusy = (total - idle) - lastCpu[0];
                if (dt > 0) cpu = Math.max(0, Math.min(1, dbusy / dt));
            }
            lastCpu = [total - idle, total];
        }
        const mem = {};
        for (const line of memFile.text().split("\n")) {
            const mm = /^(\w+):\s+(\d+)/.exec(line);
            if (mm) mem[mm[1]] = Number(mm[2]) * 1024;
        }
        if (mem.MemTotal) { memTotal = mem.MemTotal; memUsed = mem.MemTotal - (mem.MemAvailable || mem.MemFree || 0); }
        swapTotal = mem.SwapTotal || 0;
        swapUsed = swapTotal ? swapTotal - (mem.SwapFree || 0) : 0;
        if (!gpuNone && gpuTick++ % 3 === 0 && !gpuInfo.running) { gpuAsks++; gpuInfo.running = true; }
        // (the drive's size and use barely move: asked on opening, then every 30 s)
        if (Date.now() - lastDisk > 30000 && !diskInfo.running) { lastDisk = Date.now(); diskInfo.running = true; }
    }
    property double lastDisk: 0
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: pop.shown && pop.displayed === "battery"
        // opened again: the drive read afresh, and the graphics card asked again
        onRunningChanged: if (running) { bat.lastDisk = 0; bat.gpuNone = false; bat.gpuTick = 0; }
        onTriggered: bat.sample()
    }
    // Shown values glide from one reading to the next (readings come every 2s)
    property real cpuShown: cpu
    property real memShown: memTotal ? memUsed / memTotal : 0
    property real diskShown: diskTotal ? diskUsed / diskTotal : 0
    property real swapShown: swapTotal ? swapUsed / swapTotal : 0
    property real gpuShown: gpu
    Behavior on cpuShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
    Behavior on memShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
    Behavior on diskShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
    Behavior on swapShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
    Behavior on gpuShown { NumberAnimation { duration: Config.ms(900); easing.type: Easing.InOutCubic } }
    function gb(bytes) {
        const g = bytes / 1e9;
        return g >= 1000 ? (g / 1000).toFixed(1) + " TB" : g >= 100 ? Math.round(g) + " GB" : g.toFixed(1) + " GB";
    }
    // A fixed list, so the meters stay put (and animate) as the readings change
    Repeater {
        model: ["CPU", "GPU", "Memory", "Swap", "Disk"]
        delegate: Column {
            id: meter
            required property string modelData
            readonly property real frac: modelData === "CPU" ? bat.cpuShown : modelData === "GPU" ? bat.gpuShown
                : modelData === "Memory" ? bat.memShown : modelData === "Swap" ? bat.swapShown : bat.diskShown
            readonly property string value: modelData === "CPU" ? Math.round(bat.cpuShown * 100) + "%"
                : modelData === "GPU" ? (bat.gpuState === "asleep" ? "Asleep" : Math.round(bat.gpuShown * 100) + "%")
                : modelData === "Memory" ? (bat.memTotal ? (bat.memShown * bat.memTotal / 1e9).toFixed(1) + " / " + (bat.memTotal / 1e9).toFixed(1) + " GB" : "")
                : modelData === "Swap" ? (bat.swapTotal ? (bat.swapShown * bat.swapTotal / 1e9).toFixed(1) + " / " + (bat.swapTotal / 1e9).toFixed(1) + " GB" : "")
                : (bat.diskTotal ? bat.gb(bat.diskShown * bat.diskTotal) + " / " + bat.gb(bat.diskTotal) : "")
            // (no swap, or no graphics card that can say how busy it is: no row)
            visible: modelData === "Swap" ? bat.swapTotal > 0 : modelData === "GPU" ? bat.gpuState !== "" : true
            width: bat.width
            spacing: 5
            Item {
                width: parent.width; height: meterLabel.height
                Label { id: meterLabel; text: meter.modelData; font.pixelSize: Config.text(12) }
                Label {
                    anchors.right: parent.right
                    text: meter.value
                    color: pop.dim; font.pixelSize: Config.text(12)
                }
            }
            Meter {
                width: parent.width
                value: Math.min(1, meter.frac)
                trackColour: pop.card
                // Yellow above 70%, red above 90%
                colour: meter.frac > 0.9 ? pop.danger : meter.frac > 0.7 ? pop.warn : pop.accent
                colourMs: 300
            }
        }
    }

    Divider {}
    LinkRow {
        code: 0xEB20; text: "Power settings"
        onClicked: pop.openSettingsPage("power")
    }
}
