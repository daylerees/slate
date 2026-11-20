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
    id: displaysPane
    spacing: 4
    PageTitle { text: "Displays" }
    Displays { id: disp }
    // The monitor being set up below the arrangement (Hyprland's name, e.g. DP-1)
    property string selected: ""
    // (with none chosen yet, the first one in use rather than one that's off)
    readonly property var mon: disp.monitors.find(m => m.name === selected) || disp.monitors.find(m => !m.disabled) || disp.monitors[0] || null
    readonly property var cfg: mon ? disp.configOf(mon) : null
    readonly property int enabledCount: disp.monitors.filter(m => !m.disabled).length
    readonly property bool hdrShown: !!mon && !!cfg && !cfg.disabled && disp.hdrCapable(mon)

    // Change one thing about the selected monitor, and apply it
    function change(field, value) {
        if (!mon) return;
        const all = disp.currentConfigs();
        const old = Object.assign({}, all[mon.name]);
        const c = all[mon.name];
        c[field] = value;
        // A new resolution may not suit the scale: take the nearest one that does
        if (field === "mode") {
            const ok = disp.scaleOptions(c.mode, -1);
            if (!ok.some(o => Math.abs(o.value - c.scale) < 0.001))
                c.scale = ok.reduce((a, b) => Math.abs(b.value - c.scale) < Math.abs(a.value - c.scale) ? b : a, ok[0]).value;
        }
        disp.apply(disp.reflow(all, mon.name, old));
    }

    // Keep or go back (changes revert by themselves if not kept). Asked in Slate's
    // confirmation window as well as the banner below: the banner alone was easy to miss (it's
    // at the top of the page), and closing Settings or leaving the page puts the change back,
    // so a new refresh rate seemed to undo itself a moment later.
    readonly property string keepQuestion: "displays-keep"
    Connections {
        target: disp
        function onPendingChanged() {
            const c = displaysPane.win ? displaysPane.win.confirmer : null;
            if (!c) return;
            if (!disp.pending) { c.withdraw(displaysPane.keepQuestion); return; }
            c.confirmWith({
                id: displaysPane.keepQuestion, title: "Keep these display settings?",
                body: "If you don't answer, Slate goes back to the old ones in " + disp.revertSeconds
                    + " seconds, in case your screen can't show these.",
                button: "Keep", cancelLabel: "Go back", code: 0xEA89, danger: false
            }, () => disp.keep(), () => disp.revert());
        }
    }
    Component.onDestruction: if (win && win.confirmer) win.confirmer.withdraw(keepQuestion)
    Rectangle {
        visible: disp.pending
        width: parent.width
        height: keepRow.implicitHeight + 24
        radius: Config.corner(12)
        color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.16)
        border.width: 1; border.color: win.accent
        Row {
            id: keepRow
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
            spacing: 12
            Text {
                width: parent.width - revertBtn.width - keepBtn.width - 24
                anchors.verticalCenter: parent.verticalCenter
                text: "Keep these display settings? Going back in " + disp.secondsLeft + " s"
                color: win.text; font.family: win.font; font.pixelSize: Config.text(13); font.weight: Font.Medium
                wrapMode: Text.Wrap
            }
            Button { id: revertBtn; label: "Go back"; anchors.verticalCenter: parent.verticalCenter; onClicked: disp.revert() }
            Button { id: keepBtn; label: "Keep"; primary: true; anchors.verticalCenter: parent.verticalCenter; onClicked: disp.keep() }
        }
    }

    // ---- Arrangement: the monitors to scale; drag one beside another --------------
    GroupLabel { text: disp.monitors.length > 1 ? "Arrangement (drag to move, click to choose)" : "Display" }
    Group {
        Item {
            id: arrange
            width: parent.width; height: 200
            readonly property var live: disp.monitors.filter(m => !m.disabled)
            // Fit the layout into the box
            readonly property var box: {
                let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
                for (const m of live) {
                    const c = disp.configOf(m), sz = disp.logicalSize(c);
                    x0 = Math.min(x0, c.x); y0 = Math.min(y0, c.y);
                    x1 = Math.max(x1, c.x + sz.w); y1 = Math.max(y1, c.y + sz.h);
                }
                if (!isFinite(x0)) return { x0: 0, y0: 0, k: 1, ox: 0, oy: 0 };
                const k = Math.min((width - 48) / (x1 - x0), (height - 40) / (y1 - y0));
                return { x0: x0, y0: y0, k: k, ox: (width - (x1 - x0) * k) / 2, oy: (height - (y1 - y0) * k) / 2 };
            }
            Repeater {
                model: arrange.live
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    readonly property var c: disp.configOf(modelData)
                    readonly property var sz: disp.logicalSize(c)
                    readonly property bool chosen: displaysPane.mon && displaysPane.mon.name === modelData.name
                    readonly property real homeX: arrange.box.ox + (c.x - arrange.box.x0) * arrange.box.k
                    readonly property real homeY: arrange.box.oy + (c.y - arrange.box.y0) * arrange.box.k
                    x: homeX; y: homeY
                    width: Math.max(24, sz.w * arrange.box.k - 4); height: Math.max(18, sz.h * arrange.box.k - 4)
                    radius: Config.corner(6)
                    color: chosen ? win.accent : win.outline
                    border.width: 1; border.color: chosen ? win.accent : win.ring
                    z: drag.active ? 2 : 1
                    Column {
                        anchors.centerIn: parent
                        spacing: 1
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            textFormat: Text.PlainText        // never markup: the display's own name
                            text: tile.modelData.name
                            color: tile.chosen ? win.accentText : win.text
                            font.family: win.font; font.pixelSize: Config.text(12); font.weight: Font.Medium
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: Config.primaryScreen && Config.primaryScreen.name === tile.modelData.name && disp.monitors.length > 1
                            text: "Main"
                            color: tile.chosen ? win.accentText : win.dim
                            font.family: win.font; font.pixelSize: Config.text(11)
                        }
                    }
                    HoverHandler { cursorShape: arrange.live.length > 1 ? Qt.OpenHandCursor : Qt.ArrowCursor }
                    ClickTap { onTapped: displaysPane.selected = tile.modelData.name }
                    DragHandler {
                        id: drag
                        enabled: arrange.live.length > 1
                        onActiveChanged: {
                            if (active) { displaysPane.selected = tile.modelData.name; return; }
                            // Dropped: from the box back to the layout, then snap beside the nearest
                            const lx = (tile.x - arrange.box.ox) / arrange.box.k + arrange.box.x0;
                            const ly = (tile.y - arrange.box.oy) / arrange.box.k + arrange.box.y0;
                            tile.x = Qt.binding(() => tile.homeX);
                            tile.y = Qt.binding(() => tile.homeY);
                            const all = disp.currentConfigs();
                            const before = JSON.stringify(all);
                            const placed = disp.placeBeside(all, tile.modelData.name, lx, ly);
                            if (JSON.stringify(placed) !== before) disp.apply(placed);
                        }
                    }
                }
            }
        }
    }

    // ---- The chosen monitor -----------------------------------------------------
    GroupLabel { visible: !!displaysPane.mon; textFormat: Text.PlainText; text: displaysPane.mon ? disp.displayName(displaysPane.mon) + " (" + displaysPane.mon.name + ")" : "" }
    Group {
        visible: !!displaysPane.mon
        SettingRow {
            visible: disp.monitors.length > 1
            label: "Use this display"
            detail: displaysPane.cfg && !displaysPane.cfg.disabled && displaysPane.enabledCount <= 1 ? "The only display in use can't be turned off" : "Turn it off to leave it dark and unused"
            SettingToggle {
                checked: displaysPane.cfg ? !displaysPane.cfg.disabled : true
                opacity: displaysPane.cfg && !displaysPane.cfg.disabled && displaysPane.enabledCount <= 1 ? 0.4 : 1
                onToggled: v => { if (v || displaysPane.enabledCount > 1) displaysPane.change("disabled", !v); }
            }
        }
        Separator { visible: disp.monitors.length > 1 }
        // Brightness: the built-in screen's backlight, as the keys set it, or a monitor's own
        // control over DDC/CI (DisplayBrightness.qml). A monitor Slate can't reach says why
        SettingRow {
            id: brightRow
            visible: displaysPane.cfg && !displaysPane.cfg.disabled
            readonly property var b: displaysPane.mon ? DisplayBrightness.displays[displaysPane.mon.name] : undefined
            readonly property bool settable: !!b && (b.kind === "backlight" || b.kind === "ddc")
            label: "Brightness"
            detail: !b ? (DisplayBrightness.checking ? "Checking what this display allows…" : "")
                : b.kind === "backlight" ? "How bright this screen is. The brightness keys change it too"
                : b.kind === "ddc" ? "How bright this display is, set through its own controls. It can take a moment to change"
                : b.why === "missing" ? "Slate can set a monitor's brightness through its own controls (DDC/CI), with ddcutil"
                : b.why === "access" ? "Slate can't reach your monitors' controls yet. Loading the i2c-dev module and joining the i2c group usually sorts it"
                : "This display doesn't let Slate change its brightness. Its own buttons still can"
            needsMet: !b || (b.why !== "missing" && b.why !== "access")
            needs: b && b.why === "access" ? "Needs access to i2c (the i2c group)" : "Needs ddcutil to be installed"
            ValueSlider {
                visible: brightRow.settable
                from: brightRow.b && brightRow.b.kind === "backlight" ? 1 : 0; to: 100; stepSize: 1; suffix: "%"
                value: brightRow.b && brightRow.b.percent !== undefined ? brightRow.b.percent : 0
                onMoved: v => DisplayBrightness.set(displaysPane.mon.name, v)
                onReleased: DisplayBrightness.settle()
            }
        }
        Separator { visible: displaysPane.cfg && !displaysPane.cfg.disabled }
        DropdownSetting {
            visible: displaysPane.cfg && !displaysPane.cfg.disabled
            label: "Resolution"
            detail: "The sizes this display reports. Laptop panels often report only their own; to make things larger or smaller there, use Scale"
            options: displaysPane.mon ? disp.resolutionOptions(displaysPane.mon) : []
            value: displaysPane.cfg ? displaysPane.cfg.mode.split("@")[0] : ""
            // Keeps the refresh rate if the new size has it, else its fastest
            onPicked: v => displaysPane.change("mode", disp.modeAt(displaysPane.mon, v, displaysPane.cfg.mode.split("@")[1]))
        }
        Separator { visible: displaysPane.cfg && !displaysPane.cfg.disabled }
        DropdownSetting {
            visible: displaysPane.cfg && !displaysPane.cfg.disabled
            label: "Refresh rate"
            detail: "How many times a second the picture updates, from the rates this resolution has. Higher is smoother"
            options: displaysPane.mon && displaysPane.cfg ? disp.refreshOptions(displaysPane.mon, displaysPane.cfg.mode.split("@")[0]) : []
            value: displaysPane.cfg ? displaysPane.cfg.mode.split("@")[1] : ""
            onPicked: v => displaysPane.change("mode", displaysPane.cfg.mode.split("@")[0] + "@" + v)
        }
        Separator { visible: displaysPane.cfg && !displaysPane.cfg.disabled }
        DropdownSetting {
            visible: displaysPane.cfg && !displaysPane.cfg.disabled
            label: "Scale"
            detail: "How large everything on this display looks, apps included. Only scales that suit the resolution are offered. "
                + "To resize just Slate (the bar, dock and panels) on every display, use Interface size in Appearance"
            options: displaysPane.cfg ? disp.scaleOptions(displaysPane.cfg.mode, displaysPane.cfg.scale) : []
            value: displaysPane.cfg ? displaysPane.cfg.scale : 1
            onPicked: v => displaysPane.change("scale", v)
        }
        Separator { visible: displaysPane.cfg && !displaysPane.cfg.disabled }
        DropdownSetting {
            visible: displaysPane.cfg && !displaysPane.cfg.disabled
            label: "Rotation"
            options: disp.transformOptions
            value: displaysPane.cfg ? displaysPane.cfg.transform : 0
            onPicked: v => displaysPane.change("transform", v)
        }
        // HDR: only for displays that can show it
        Separator { visible: displaysPane.hdrShown }
        DropdownSetting {
            visible: displaysPane.hdrShown
            label: "HDR"
            detail: "Auto: HDR while a game or video fills the screen with HDR content. On: always, in 10-bit color. Off: never"
            options: disp.hdrOptions
            value: displaysPane.cfg ? displaysPane.cfg.hdr : "auto"
            onPicked: v => displaysPane.change("hdr", v)
        }
        Separator { visible: displaysPane.hdrShown && displaysPane.cfg.hdr === "on" }
        SettingRow {
            visible: displaysPane.hdrShown && displaysPane.cfg.hdr === "on"
            label: "SDR brightness"
            detail: "How bright everything that isn't HDR (most apps, the desktop) looks while HDR is on"
            ValueSlider { from: 0.5; to: 2; stepSize: 0.05; decimals: 2; suffix: "×"; value: displaysPane.cfg ? displaysPane.cfg.sdrBrightness : 1; onMoved: v => displaysPane.change("sdrBrightness", v) }
        }
        Separator { visible: displaysPane.hdrShown && displaysPane.cfg.hdr === "on" }
        SettingRow {
            visible: displaysPane.hdrShown && displaysPane.cfg.hdr === "on"
            label: "SDR color"
            detail: "How colorful everything that isn't HDR looks while HDR is on"
            ValueSlider { from: 0.5; to: 1.5; stepSize: 0.05; decimals: 2; suffix: "×"; value: displaysPane.cfg ? displaysPane.cfg.sdrSaturation : 1; onMoved: v => displaysPane.change("sdrSaturation", v) }
        }
        Separator { visible: disp.monitors.length > 1 }
        DropdownSetting {
            visible: disp.monitors.length > 1
            label: "Main display"
            settingKey: "mainDisplay"
            detail: "Where the main menu bar lives (every display has a bar; the launcher and other panels open on the display you're using)"
            options: disp.monitors.filter(m => !m.disabled).map(m => ({ value: m.description || m.name, label: m.name + " · " + disp.displayName(m) }))
            value: {
                const p = Config.primaryScreen;
                const m = p ? disp.monitors.find(x => x.name === p.name) : null;
                return m ? (m.description || m.name) : "";
            }
            onPicked: v => Config.s.mainDisplay = v
        }
    }
    // Apps made for X11 (Steam and the like): at a scale like 125%, Hyprland draws them at 100%
    // and stretches them, which blurs them; this has them draw themselves at the scale instead
    // (slate.lua's slateApply)
    GroupLabel { text: "Older apps" }
    Group {
        ToggleSetting {
            label: "Sharp older apps"
            key: "sharpX11Apps"
            detail: "Apps made for older Linux desktops (X11), like Steam, draw at your display's own pixels and scale themselves, "
                + "so they're sharp rather than blurry. A few that can't scale themselves look smaller. Apps you open after changing it follow it"
            needsMet: disp.monitors.some(m => !m.disabled && Math.abs(m.scale - Math.round(m.scale)) > 0.01)
            needs: "Needs a display at a scale like 125% (Scale, above)"
        }
    }
    // Automatic brightness: only where there's a light sensor to follow (AutoBrightness.qml).
    // A sensor the kernel has but nothing reads yet says what to install. And how bright each
    // display is (DisplayBrightness.qml): looked at as the page opens, and again for a display
    // that comes along while it's open
    Component.onCompleted: { AutoBrightness.refresh(); DisplayBrightness.refresh(); }
    readonly property bool unseenDisplay: disp.monitors.some(m => !m.disabled && !DisplayBrightness.displays[m.name])
    onUnseenDisplayChanged: if (unseenDisplay && DisplayBrightness.checked) DisplayBrightness.refresh()
    GroupLabel { visible: AutoBrightness.shown; text: "Brightness" }
    Group {
        visible: AutoBrightness.shown
        ToggleSetting {
            label: "Automatic brightness"
            key: "autoBrightness"
            detail: (AutoBrightness.keyboard ? "Your screen and keyboard light follow the light in the room."
                                             : "Your screen follows the light in the room.")
                + " When you change it yourself, Slate remembers what you like for that light"
            needsMet: AutoBrightness.sensor
            needs: "Needs iio-sensor-proxy to be installed"
        }
    }
    Footnote { text: "Slate's own size (bar, panels, this window) is under Appearance → Interface size, on top of each display's scale. Monitor rules in ~/.config/slate/hypr/monitors.lua override these." }
}
