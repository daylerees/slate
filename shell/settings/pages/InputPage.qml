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

// ---- Input ----------------------------------------------------
// Only what's changed here is set (Config.hyprSettings); the rest shows what Hyprland's
// config (and your own hyprland.lua) has, read when the page opens
Column {
    readonly property var win: SettingsHost.win
    id: inputPane
    spacing: 4
    PageTitle { text: "Input" }
    property var cur: ({})
    property var layoutOptions: []
    property bool hasTouchpad: false
    Process {
        running: true
        command: [Quickshell.shellPath("scripts/hypr-options.py"), "input:kb_layout", "input:kb_variant", "input:kb_options",
            "input:repeat_rate", "input:repeat_delay", "input:sensitivity", "input:accel_profile", "input:natural_scroll",
            "input:touchpad:natural_scroll", "input:touchpad:tap-to-click", "input:touchpad:disable_while_typing",
            "input:touchpad:scroll_factor"]
        stdout: StdioCollector { onStreamFinished: { try { inputPane.cur = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        running: true
        command: [Quickshell.shellPath("scripts/xkb-layouts.py")]
        stdout: StdioCollector { onStreamFinished: { try { inputPane.layoutOptions = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector { onStreamFinished: { try { inputPane.hasTouchpad = JSON.parse(text).mice.some(m => m.name.toLowerCase().includes("touchpad")); } catch (e) {} } }
    }

    // Keyboard layouts in use, in order: [{ layout, variant }]
    readonly property var layouts: {
        const set = Config.s.kbLayouts !== "";
        const ls = (set ? Config.s.kbLayouts : (cur["input:kb_layout"] || "us")).split(",");
        const vs = (set ? Config.s.kbVariants : (cur["input:kb_variant"] || "")).split(",");
        return ls.map(l => l.trim()).filter(l => l !== "").map((l, i) => ({ layout: l, variant: (vs[i] || "").trim() }));
    }
    function setLayouts(list) {
        Config.s.kbVariants = list.map(x => x.variant).join(",");
        Config.s.kbLayouts = list.map(x => x.layout).join(",");
    }
    function layoutName(x) {
        const key = x.variant ? x.layout + ":" + x.variant : x.layout;
        const o = layoutOptions.find(o => o.value === key);
        return o ? o.label : key;
    }
    readonly property string curOptions: cur["input:kb_options"] || ""
    readonly property string capsValue: Config.s.capsLock !== "" ? Config.s.capsLock
        : curOptions.includes("caps:ctrl_modifier") ? "ctrl" : curOptions.includes("caps:escape") ? "escape"
        : curOptions.includes("caps:none") ? "off" : "default"
    readonly property string switchValue: Config.s.kbSwitch !== "" ? Config.s.kbSwitch
        : curOptions.includes("grp:alt_shift_toggle") ? "alt_shift" : curOptions.includes("grp:ctrl_space_toggle") ? "ctrl_space"
        : curOptions.includes("grp:caps_toggle") ? "caps" : "none"

    GroupLabel { text: "Keyboard" }
    Group {
        SearchPicker {
            label: "Add a layout"
            detail: "Search by language or name, e.g. French or Dvorak"
            buttonLabel: "Add…"
            buttonIcon: 0xEB0B
            options: inputPane.layoutOptions
            onPicked: v => {
                const parts = String(v).split(":");
                const l = inputPane.layouts.slice();
                if (!l.some(x => x.layout === parts[0] && x.variant === (parts[1] || "")))
                    l.push({ layout: parts[0], variant: parts[1] || "" });
                inputPane.setLayouts(l);
            }
        }
    }
    GroupLabel { text: "Your layouts" }
    // The layouts in use, in their own container under Add a layout
    Group {
        Repeater {
            model: inputPane.layouts
            delegate: Column {
                id: layoutRow
                required property var modelData
                required property int index
                width: parent ? parent.width : 0
                Separator { visible: layoutRow.index > 0 }
                ListItemRow {
                    label: inputPane.layoutName(layoutRow.modelData)
                    detail: inputPane.layouts.length > 1 && layoutRow.index === 0 ? "Used first" : ""
                    removable: inputPane.layouts.length > 1
                    onRemoved: { const l = inputPane.layouts.slice(); l.splice(layoutRow.index, 1); inputPane.setLayouts(l); }
                }
            }
        }
    }
    GroupLabel { text: "Switching & keys" }
    Group {
        DropdownSetting {
            visible: inputPane.layouts.length > 1
            label: "Switch layouts with"
            settingKey: "kbSwitch"
            options: [{ value: "alt_shift", label: "Alt+Shift" }, { value: "ctrl_space", label: "Ctrl+Space" },
                      { value: "caps", label: "Caps Lock" }, { value: "none", label: "No shortcut" }]
            value: inputPane.switchValue
            onPicked: v => Config.s.kbSwitch = v
        }
        Separator { visible: inputPane.layouts.length > 1 }
        DropdownSetting {
            label: "Caps Lock key"
            settingKey: "capsLock"
            detail: inputPane.switchValue === "caps" && inputPane.layouts.length > 1 ? "It switches layouts (above)" : "What the Caps Lock key does"
            options: [{ value: "default", label: "Caps Lock" }, { value: "ctrl", label: "Another Ctrl" },
                      { value: "escape", label: "Escape" }, { value: "off", label: "Nothing" }]
            value: inputPane.capsValue
            onPicked: v => Config.s.capsLock = v
        }
        Separator {}
        SettingRow {
            label: "Repeat delay"
            settingKey: "keyRepeatDelay"
            detail: "How long a held key waits before it repeats"
            ValueSlider {
                from: 150; to: 1000; stepSize: 25; suffix: " ms"
                value: Config.s.keyRepeatDelay > 0 ? Config.s.keyRepeatDelay : (inputPane.cur["input:repeat_delay"] || 600)
                onMoved: v => Config.s.keyRepeatDelay = Math.round(v)
            }
        }
        Separator {}
        SettingRow {
            label: "Repeat speed"
            settingKey: "keyRepeatRate"
            detail: "How fast a held key repeats"
            ValueSlider {
                from: 10; to: 80; stepSize: 1; suffix: " /s"
                value: Config.s.keyRepeatRate > 0 ? Config.s.keyRepeatRate : (inputPane.cur["input:repeat_rate"] || 25)
                onMoved: v => Config.s.keyRepeatRate = Math.round(v)
            }
        }
    }

    GroupLabel { text: "Mouse" }
    Group {
        SettingRow {
            label: "Pointer speed"
            settingKey: "mouseSpeed"
            defaultText: "Hyprland's own"       // (not set here until you move it)
            detail: inputPane.hasTouchpad ? "Mice and touchpads. Slower to faster; 0 is the device's own speed" : "Slower to faster; 0 is the mouse's own speed"
            ValueSlider {
                per: 100
                from: -100; to: 100; stepSize: 5
                value: Math.round((Config.s.mouseSpeed >= -1 ? Config.s.mouseSpeed : (inputPane.cur["input:sensitivity"] || 0)) * 100)
                onMoved: v => Config.s.mouseSpeed = v / 100
            }
        }
        Separator {}
        SettingRow {
            label: "Acceleration"
            settingKey: "mouseAccel"
            detail: "Quick movements carry the pointer further. Off: the same distance however fast you move"
            SettingToggle {
                checked: (Config.s.mouseAccel !== "" ? Config.s.mouseAccel : (inputPane.cur["input:accel_profile"] || "adaptive")) !== "flat"
                onToggled: v => Config.s.mouseAccel = v ? "adaptive" : "flat"
            }
        }
        Separator {}
        SettingRow {
            label: "Natural scrolling"
            settingKey: "mouseNaturalScroll"
            detail: "Content moves the way the wheel turns, like a touch screen"
            SettingToggle {
                checked: Config.s.mouseNaturalScroll !== "" ? Config.s.mouseNaturalScroll === "on" : !!inputPane.cur["input:natural_scroll"]
                onToggled: v => Config.s.mouseNaturalScroll = v ? "on" : "off"
            }
        }
        Separator {}
        // The pointer's look: Slate's own, or any cursor theme installed here
        // (scripts/icon-themes.py lists them; Hyprland and apps all follow: slate.lua, apply-theme.py)
        DropdownSetting {
            id: cursorThemeSet
            property var themes: []
            function look() { cursorThemeList.running = false; cursorThemeList.running = true; }
            Process {
                id: cursorThemeList
                running: true
                command: [Quickshell.shellPath("scripts/icon-themes.py"), "--cursors"]
                stdout: StdioCollector { onStreamFinished: { try { cursorThemeSet.themes = JSON.parse(text).filter(t => t.id !== "Slate-Cursors"); } catch (e) {} } }
            }
            label: "Pointer style"
            settingKey: "cursorTheme"
            detail: Config.s.cursorTheme !== "" && !themes.some(t => t.id === Config.s.cursorTheme) && themes.length > 0
                ? "The pointer chosen here isn't installed any more, so Slate's own is back. Choose another whenever you like"
                : "Slate's own, or any pointer theme installed. Apps opened from now on use it too"
            options: [{ value: "", label: "Slate (default)" }].concat(themes.map(t => ({ value: t.id, label: t.name.replace(/[-_]/g, " ") })))
            value: themes.some(t => t.id === Config.s.cursorTheme) ? Config.s.cursorTheme : ""
            onPicked: v => Config.s.cursorTheme = v
        }
        Separator {}
        DropdownSetting {
            label: "Pointer size"
            settingKey: "cursorSize"
            detail: "Apps opened from now on use it too"
            options: [16, 20, 24, 32, 40, 48, 64].map(n => ({ value: n, label: n + " px" }))
            value: Config.s.cursorSize > 0 ? Config.s.cursorSize : 20
            onPicked: v => Config.s.cursorSize = v
        }
        Separator {}
        // Off until chosen (the Welcome window offers it): the pointer written into other
        // apps' own settings, each change recorded and put back when it's switched off
        // (scripts/apply-theme.py, as the app "pointer")
        ToggleSetting {
            label: "Pointer in your apps"
            detail: "Sets this pointer in your other apps' own settings too (GTK, KDE and older X11 apps), so it's the same everywhere. Switch it off and Slate puts those settings back as they were"
            key: "pointerInApps"
        }
    }

    GroupLabel { text: "More pointer styles" }
    ThemePacks { kind: "cursors"; chooseIn: "Pointer style"; onInstalled: cursorThemeSet.look() }

    GroupLabel { visible: inputPane.hasTouchpad; text: "Touchpad" }
    Group {
        visible: inputPane.hasTouchpad
        SettingRow {
            label: "Scroll speed"
            settingKey: "touchpadScrollSpeed"
            defaultText: "Hyprland's own"       // (not set here until you move it)
            ValueSlider {
                per: 100
                from: 10; to: 200; stepSize: 10; suffix: "%"
                value: Math.round((Config.s.touchpadScrollSpeed > 0 ? Config.s.touchpadScrollSpeed : (inputPane.cur["input:touchpad:scroll_factor"] || 1)) * 100)
                onMoved: v => Config.s.touchpadScrollSpeed = v / 100
            }
        }
        Separator {}
        SettingRow {
            label: "Natural scrolling"
            settingKey: "touchpadNaturalScroll"
            detail: "Content follows your fingers, like a phone"
            SettingToggle {
                checked: Config.s.touchpadNaturalScroll !== "" ? Config.s.touchpadNaturalScroll === "on" : !!inputPane.cur["input:touchpad:natural_scroll"]
                onToggled: v => Config.s.touchpadNaturalScroll = v ? "on" : "off"
            }
        }
        Separator {}
        SettingRow {
            label: "Tap to click"
            settingKey: "touchpadTapToClick"
            SettingToggle {
                checked: Config.s.touchpadTapToClick !== "" ? Config.s.touchpadTapToClick === "on" : inputPane.cur["input:touchpad:tap-to-click"] !== false
                onToggled: v => Config.s.touchpadTapToClick = v ? "on" : "off"
            }
        }
        Separator {}
        SettingRow {
            label: "Ignore while typing"
            settingKey: "touchpadIgnoreWhileTyping"
            detail: "Stops a palm on the touchpad moving the pointer as you type"
            SettingToggle {
                checked: Config.s.touchpadIgnoreWhileTyping !== "" ? Config.s.touchpadIgnoreWhileTyping === "on" : inputPane.cur["input:touchpad:disable_while_typing"] !== false
                onToggled: v => Config.s.touchpadIgnoreWhileTyping = v ? "on" : "off"
            }
        }
    }
}
