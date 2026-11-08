pragma Singleton

// Every Slate setting, for searching: Settings' All Settings page and the app launcher.
//  - curated: pages and settings with extra words to find them by ("dpi" finds Interface
//    size), kept by hand
//  - each setting's label, description and heading, read from SettingsWindow.qml
//    (scripts/settings-index.py), so new settings are found without adding them here
// search() ranks both together.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var pageIcons: ({ input: 0xEBD6, sound: 0xEB51, power: 0xEA38, shortcuts: 0xEA78, apps: 0xEBB6,
        startup: 0xEC45, datetime: 0xEA70, screenshots: 0xF201, general: 0xEB20, appearance: 0xEB01, bar: 0xEAD7, dock: 0xEAD3, launcher: 0xEB1C, spaces: 0xEEF6,
        windows: 0xEFE6, displays: 0xEA89, hotcorners: 0xF7A0, notifications: 0xEA35, workspaces: 0xEDBA, lock: 0xEAE2, screensaver: 0xEAF8, apptheming: 0xEB01, updates: 0xEA96, wifi: 0xEB52, bluetooth: 0xEA37, about: 0xEAC5 })
    readonly property var pageNames: ({ input: "Keyboard & mouse", sound: "Sound", power: "Power", shortcuts: "Shortcuts",
        apps: "Default apps", startup: "Startup apps", datetime: "Date & time", screenshots: "Screenshots", general: "General", appearance: "Appearance", bar: "Menu bar", dock: "Dock", launcher: "Launcher", spaces: "Spaces",
        windows: "Windows", displays: "Displays", hotcorners: "Hot corners", notifications: "Notifications", workspaces: "Workspaces", lock: "Lock & idle", screensaver: "Screensaver", apptheming: "App theming", updates: "Updates", wifi: "Wi-Fi",
        bluetooth: "Bluetooth", about: "About" })
    readonly property var curated: [
        // [name, page, extra search words]
        ["General settings", "general", "settings preferences account"],
        ["Appearance", "appearance", "look theme colours colors style fonts"],
        ["Screensaver", "screensaver", "screen saver idle clock slideshow away burn-in oled"],
        ["App theming", "apptheming", "theme other apps colours colors dark light accent gtk qt kde terminal editor"],
        ["Theme other apps", "apptheming", "app theming colours colors match follow"],
        ["Welcome", "about", "welcome introduction tour first start getting started setup onboarding"],
        ["Glass", "appearance", "glass glassy liquid frosted translucent transparent see-through blur acrylic"],
        ["Blur", "appearance", "glass blur strength frosted"],
        ["Shine", "appearance", "glass rim edge highlight"],
        ["Gloss", "appearance", "glass glossy sheen shiny highlight"],
        ["Gloss colour", "appearance", "glass gloss tint hue colour color wallpaper sheen"],
        ["Fast blur", "appearance", "blur performance smooth lag xray wallpaper"],
        ["Blur quality", "appearance", "blur passes smooth performance"],
        ["Updates", "updates", "update upgrade new version release what's new check latest go back revert downgrade"],
        ["Check for updates", "updates", "update notification daily automatic new version"],
        ["Spaces", "spaces", "saved workspaces presets layouts sessions restore badges borders"],
        ["Theme (dark, light or auto)", "appearance", "dark mode light mode auto appearance"],
        ["Accent colour", "appearance", "color highlight"],
        ["Colour", "appearance", "colourful colorful monotone monochrome pastel variety colours colors"],
        ["Interface font", "appearance", "typeface"],
        ["Interface size", "appearance", "scale scaling zoom bigger smaller text size font size dpi hidpi"],
        ["Rounded screen corners", "appearance", ""],
        ["Location", "general", "weather city town sunrise sunset"],
        ["Night light", "general", "blue light warm schedule temperature"],
        ["Volume key sound", "sound", "tick click audio feedback"],
        ["Sound effects volume", "sound", "alert tick click quiet loud"],
        ["Sound", "sound", "audio speakers headphones output input microphone volume mute"],
        ["Play sound through", "sound", "output speakers headphones device audio"],
        ["Microphone", "sound", "input mic recording device"],
        ["Keyboard & mouse", "input", "keyboard mouse touchpad trackpad input"],
        ["Add a layout", "input", "keyboard layout language qwerty azerty dvorak region"],
        ["Caps Lock key", "input", "capslock ctrl escape remap"],
        ["Repeat delay", "input", "key repeat hold keyboard"],
        ["Repeat speed", "input", "key repeat rate hold keyboard"],
        ["Pointer speed", "input", "mouse sensitivity cursor speed"],
        ["Acceleration", "input", "mouse acceleration flat adaptive"],
        ["Natural scrolling", "input", "reverse scroll direction"],
        ["Pointer size", "input", "cursor size mouse pointer big large"],
        ["Tap to click", "input", "touchpad trackpad tap"],
        ["Ignore while typing", "input", "touchpad palm rejection disable while typing"],
        ["Power", "power", "battery lid power button suspend sleep performance"],
        ["Closing the lid", "power", "laptop lid suspend sleep close"],
        ["Power button", "power", "power key shut down suspend"],
        ["On battery", "power", "power mode profile saver battery"],
        ["Plugged in", "power", "power mode profile performance charger"],
        ["Keyboard layout", "bar", "language switcher layout menu bar input"],
        ["Bluetooth", "bar", "menu bar bluetooth icon devices"],
        ["Keyboard layout code", "bar", "language code text beside icon layout gb us"],
        ["Connected Bluetooth devices", "bar", "bluetooth count number devices"],
        ["Tuck the tray away", "bar", "tray collapse hide icons system tray expand"],
        ["Wi-Fi network name", "bar", "values text beside icons network name ssid"],
        ["Volume percentage", "bar", "values text beside icons volume number"],
        ["Battery percentage", "bar", "values text beside icons battery number"],
        ["Shortcuts", "shortcuts", "keyboard shortcuts keybinds hotkeys keys"],
        ["Default apps", "apps", "terminal browser file manager editor calculator default applications"],
        ["Startup apps", "startup", "autostart login start open at login"],
        ["Date & time", "datetime", "time zone timezone clock ntp automatic"],
        ["Time zone", "datetime", "timezone region clock"],
        ["Screenshots", "screenshots", "screenshot print screen capture folder"],
        ["Animations", "appearance", "motion reduce motion speed fast off"],
        ["Focus follows the pointer", "windows", "focus follows mouse click to focus hover"],
        ["Wallpaper", "appearance", "background picture image desktop"],
        ["Change wallpaper", "appearance", "automatically rotate shuffle slideshow timer login cycle background theme"],
        ["Menu bar", "bar", "top bar panel status"],
        ["Clock format", "bar", "time 24 hour 12 hour seconds date"],
        ["Bar items", "bar", "tray battery wifi volume notifications power show hide"],
        ["Dock", "dock", "pinned apps magnification icon size auto-hide"],
        ["Layout", "launcher", "launcher list grid icons view apps"],
        ["Columns", "launcher", "launcher grid icons across size"],
        ["Rows", "launcher", "launcher grid icons size"],
        ["Launcher settings", "launcher", "app search descriptions usage"],
        ["Window borders", "windows", "border outline frame width"],
        ["Dim inactive windows", "windows", "dimming darken focus unfocused"],
        ["Folder colour", "appearance", "folders nautilus dolphin files papirus icon colour color"],
        ["Shape", "appearance", "app icons icon shape tile squircle circle round square original rounded"],
        ["Fill the shape", "appearance", "app icons crop border shadow grow zoom whole margins"],
        ["Tint app icons", "appearance", "icon colour color accent theme tint monochrome themed icons"],
        ["Workspace indicators", "workspaces", "dots shape circles squares rounded workspace"],
        ["Displays", "displays", "monitors screens resolution refresh rate hz scale scaling rotate rotation arrange arrangement main primary external"],
        ["Window mode (tiling or floating)", "windows", "floating stacking free move drag traditional desktop tile"],
        ["Keep an empty workspace", "workspaces", "spare new blank extra dynamic workspaces gnome"],
        ["Window spacing", "windows", "gaps gap padding space between margin"],
        ["Space around a lone window", "windows", "gaps padding margin lone single solo full screen rounded corners"],
        ["Account picture", "general", "avatar profile photo user face picture"],
        ["Window switcher", "windows", "alt tab previews"],
        ["Workspace overview", "workspaces", "overview workspaces super down cards"],
        ["Workspaces", "workspaces", "workspace switching animation slide fade crossfade wrap around empty overview indicators dots"],
        ["Workspace switching", "workspaces", "animation slide fade crossfade vertical transition effect"],
        ["Workspaces wrap around", "workspaces", "circular loop cycle last first ends"],
        ["Hot corners", "hotcorners", "screen corners actions"],
        ["Notifications", "notifications", "pop-ups toasts position do not disturb history"],
        ["Lock screen", "lock", "password lock"],
        ["Idle and sleep", "lock", "screen off suspend sleep idle timeout"],
        ["Login screen", "lock", "greeter greetd sign in"],
        ["Wi-Fi", "wifi", "wireless network internet"],
        ["Bluetooth", "bluetooth", "devices headphones pair"],
        ["About Slate", "about", "version restart settings file"]
    ]

    // Settings' own rows, read when Slate starts
    property var rows: []
    Process {
        running: true
        command: [Quickshell.shellPath("scripts/settings-index.py"), Quickshell.shellPath("SettingsWindow.qml")]
        stdout: StdioCollector { onStreamFinished: { try { root.rows = JSON.parse(text); } catch (e) {} } }
    }

    // One list: { label, page, detail, group, words, row (true: a setting on its page, to
    // scroll to) }. A curated entry naming a row lends it its extra words instead.
    // The apps App theming can theme (scripts/apply-theme.py --apps), so search finds them by
    // name: their rows are only made when that page opens, so the scan above can't see them
    property var themeApps: []
    Process {
        running: true
        command: ["python3", Quickshell.shellPath("scripts/apply-theme.py"), "--apps"]
        stdout: StdioCollector { onStreamFinished: { try { root.themeApps = JSON.parse(text); } catch (e) {} } }
    }

    readonly property var entries: {
        const out = [], byKey = {};
        for (const a of themeApps)
            out.push({ label: a.label, page: "apptheming", detail: a.detail || "", group: "App theming",
                       words: "theme colours colors " + a.id + (a.installed ? "" : " not installed"), row: true });
        for (const r of rows) {
            const e = { label: r.label, page: r.page, detail: r.detail || "", group: r.group || "", words: "", row: true };
            byKey[r.page + "|" + r.label.toLowerCase()] = e;
            out.push(e);
        }
        for (const c of curated) {
            const hit = byKey[c[1] + "|" + c[0].toLowerCase()];
            if (hit) hit.words += " " + c[2];
            else out.push({ label: c[0], page: c[1], detail: "", group: "", words: c[2], row: false });
        }
        return out;
    }

    // Ignore case and punctuation, so "wifi" finds "Wi-Fi" and "and idle" finds "Lock & idle"
    function norm(t) { return (t || "").toLowerCase().replace(/[^a-z0-9 ]+/g, "").replace(/\s+/g, " ").trim(); }
    // Best matches first: the label starting with it, then a word in the label, then
    // anywhere in the label, then its heading, page, extra words or description
    function search(text, limit) {
        const q = norm(text);
        if (q.length < 2) return [];
        const hidden = l => !Config.titleBarsAvailable && (l === "Window mode" || l === "Title bar buttons" || l === "Window mode (tiling or floating)");
        return entries.filter(e => !hidden(e.label)).map(e => {
            const n = norm(e.label);
            const more = norm(e.group + " " + (pageNames[e.page] || "") + " " + e.words + " " + e.detail);
            let s = n.startsWith(q) ? 0 : n.split(" ").some(w => w.startsWith(q)) ? 1 : n.includes(q) ? 2
                : more.split(" ").some(w => w.startsWith(q)) ? 3 : more.includes(q) ? 4 : -1;
            // Several words ("dock size"): each has to start a word somewhere
            if (s < 0 && q.includes(" ")) {
                const starts = (text, w) => text.split(" ").some(x => x.startsWith(w));
                const all = n + " " + more, qs = q.split(" ");
                if (qs.every(w => starts(all, w))) s = qs.every(w => starts(n, w)) ? 2.5 : 3.5;
            }
            // On the page it names ("wifi" → the Wi-Fi page before the bar's Wi-Fi switch)
            const home = norm(pageNames[e.page] || "").startsWith(q) ? 0 : 1;
            return { e: e, s: s, home: home };
        }).filter(x => x.s >= 0)
          .sort((a, b) => a.s - b.s || a.home - b.home || a.e.label.length - b.e.label.length)
          .slice(0, limit || 50)
          .map(x => x.e);
    }
}
