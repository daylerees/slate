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

    // Every Settings page, in order, each a tile on All Settings (the first page). The ones used
    // most are also down the sidebar; the rest (more: true) are reached from All Settings.
    // SettingsWindow shows these; the launcher and search use the icons and names below.
    readonly property var pages: [
        { id: "general", label: "General", icon: 0xEB20, about: "Your account, location, night light and clipboard history" },
        { id: "appearance", label: "Appearance", icon: 0xEB01, about: "Theme, colours, glass, icons, fonts, size and wallpaper" },
        { id: "displays", label: "Displays", icon: 0xEA89, about: "Resolution, scale, rotation and arranging your screens" },
        { id: "input", label: "Input", icon: 0xEBD6, about: "Keyboard layouts, key repeat, the mouse and the touchpad" },
        { id: "sound", label: "Sound", icon: 0xEB51, about: "Speakers, microphones, volume and sound effects" },
        { id: "power", label: "Power", icon: 0xEA38, about: "Power mode, the charging limit, the lid and the power button" },
        { id: "windows", label: "Windows", icon: 0xEFE6, about: "Tiling, scrolling or floating, gaps, borders, focus and Super+Tab" },
        { id: "workspaces", label: "Workspaces", icon: 0xEDBA, about: "Switching, wrapping round, indicators and the overview" },
        { id: "notifications", label: "Notifications", icon: 0xEA35, about: "Where pop-ups go, how long they stay, Do Not Disturb" },
        { id: "wifi", label: "Network", icon: 0xF09F, about: "Your connection, wired and Wi-Fi, and networks to join" },
        { id: "bluetooth", label: "Bluetooth", icon: 0xEA37, about: "Pairing and connecting devices" },
        { id: "printers", label: "Printers", icon: 0xEB0E, more: true, about: "Adding printers, test pages, and scanning" },
        { id: "webcam", label: "Webcam", icon: 0xEA54, more: true, about: "The camera's picture: brightness, colour, light and flicker" },
        { id: "bar", label: "Menu Bar", icon: 0xEAD7, more: true, about: "Position, auto-hide, and what it shows" },
        { id: "control", label: "Control Centre", icon: 0xEB3F, more: true, about: "Its quick switches: which ones, and in what order" },
        { id: "dock", label: "Dock", icon: 0xEAD3, more: true, about: "Position, auto-hide, icon size and magnification" },
        { id: "launcher", label: "Launcher", icon: 0xEB1C, more: true, about: "App descriptions and ordering by use" },
        { id: "spaces", label: "Spaces", icon: 0xEEF6, more: true, about: "Saved sets of workspaces, and how their windows are marked" },
        { id: "hotcorners", label: "Hot Corners", icon: 0xF7A0, more: true, about: "Actions for the corners of the screen" },
        { id: "lock", label: "Security", icon: 0xEAE2, more: true, about: "Locking, screen off and sleep when idle; the login screen" },
        { id: "screensaver", label: "Screensaver", icon: 0xEAF8, more: true, about: "A clock, your wallpaper, a slideshow or videos while you're away" },
        { id: "shortcuts", label: "Shortcuts", icon: 0xEA78, more: true, about: "Every keyboard shortcut, searchable" },
        { id: "apps", label: "Default Apps", icon: 0xEBB6, more: true, about: "Terminal, browser, files, editor and calculator" },
        { id: "startup", label: "Startup Apps", icon: 0xEC45, more: true, about: "Apps that open when you log in" },
        { id: "datetime", label: "Region", icon: 0xEA70, more: true, about: "Time zone, the clock, and how dates and temperatures are written" },
        { id: "apptheming", label: "App Theming", icon: 0xEB01, more: true, about: "Other apps following Slate's colours: terminals, editors, GTK, Qt…" },
        { id: "screenshots", label: "Screenshots", icon: 0xF201, more: true, about: "Where they're saved, their names, and marking up" },
        { id: "assistant", label: "Assistant", icon: 0xF38A, more: true, about: "AI agents using Slate: what they may do and see" },
        { id: "updates", label: "Updates", icon: 0xEA96, more: true, about: "New versions of Slate: what's new, updating and going back" },
        { id: "debug", label: "Debug", icon: 0xEA48, more: true, about: "Fixes for when something hasn't caught up" },
        // About is always last
        { id: "about", label: "About", icon: 0xEAC5, more: true, about: "Slate's files, and restarting it" }
    ]
    // Each page's icon and name by its id, All Settings (overview) included
    readonly property var pageIcons: {
        const icons = { overview: 0xEA03 };
        for (const p of pages) icons[p.id] = p.icon;
        return icons;
    }
    readonly property var pageNames: {
        const names = { overview: "All Settings" };
        for (const p of pages) names[p.id] = p.label;
        return names;
    }
    readonly property var curated: [
        // [name, page, extra search words]
        ["General settings", "general", "settings preferences account"],
        ["Appearance", "appearance", "look theme colours colors style fonts"],
        ["Theme presets", "appearance", "preset look style liquid glass theme colours glass"],
        ["Debug", "debug", "troubleshooting troubleshoot fix problems resync sync login screen greeter"],
        ["Webcam", "webcam", "camera webcam video picture preview face call meeting"],
        ["Brightness", "webcam", "webcam camera picture light dark"],
        ["Contrast", "webcam", "webcam camera picture"],
        ["Colour", "webcam", "webcam camera saturation vivid color colors colours"],
        ["Sharpness", "webcam", "webcam camera picture sharp soft"],
        ["Gain", "webcam", "webcam camera dim dark grain noise iso"],
        ["Gamma", "webcam", "webcam camera mid tones midtones"],
        ["Colour temperature", "webcam", "webcam camera white balance warm cool color temperature kelvin"],
        ["Exposure", "webcam", "webcam camera bright dark shutter"],
        ["Backlight compensation", "webcam", "webcam camera backlit window behind"],
        ["Screensaver", "screensaver", "screen saver idle clock slideshow away burn-in oled"],
        ["App Theming", "apptheming", "theme other apps colours colors dark light accent gtk qt kde terminal editor"],
        ["Theme other apps", "apptheming", "app theming colours colors match follow"],
        ["Install apps to theme", "apptheming", "install download get website homepage app theming terminal editor"],
        ["Welcome", "about", "welcome introduction tour first start getting started setup onboarding"],
        ["Glass", "appearance", "glass glassy liquid frosted translucent transparent see-through blur acrylic"],
        ["Blur", "appearance", "glass blur strength frosted"],
        ["Gloss", "appearance", "glass glossy sheen shiny highlight"],
        ["Gloss colour", "appearance", "glass gloss tint hue colour color wallpaper sheen"],
        ["Fast blur", "appearance", "blur performance smooth lag xray wallpaper"],
        ["Blur quality", "appearance", "blur passes smooth performance"],
        ["Assistant", "assistant", "assistant ai agent agents claude chatgpt codex gemini copilot mcp server tools chalk"],
        ["Let assistants use Slate", "assistant", "assistant ai agent switch on off enable allow mcp risks privacy"],
        ["Updates", "updates", "update upgrade new version release what's new check latest go back revert downgrade"],
        ["Check for updates", "updates", "update notification daily automatic new version"],
        ["Spaces", "spaces", "saved workspaces presets layouts sessions restore badges borders"],
        ["Theme (dark, light or auto)", "appearance", "dark mode light mode auto appearance"],
        ["Accent colour", "appearance", "color highlight"],
        ["Colour", "appearance", "colourful colorful monotone monochrome pastel variety colours colors"],
        ["Interface font", "appearance", "typeface"],
        ["Interface size", "appearance", "scale scaling zoom bigger smaller text size font size dpi hidpi"],
        ["Rounded screen corners", "appearance", ""],
        ["Rounded UI elements", "appearance", "square corners sharp hard edges radius rounding windows buttons panels"],
        ["Location", "general", "weather city town sunrise sunset"],
        ["Night light", "general", "blue light warm schedule temperature"],
        ["Volume keys sound", "sound", "tick click audio feedback volume"],
        ["Notifications sound", "sound", "chime alert ding audio notifications volume"],
        ["Questions and warnings sound", "sound", "attention alert confirm confirmation password prompt warning critical urgent audio volume"],
        ["Clicks sound", "sound", "click tap button feedback audio ui volume"],
        ["Switching sound", "sound", "swish whoosh workspace window switcher overview audio volume"],
        ["Welcome sound", "sound", "login startup chime audio session start volume"],
        ["Goodbye sound", "sound", "logout log off shutdown shut down restart reboot audio session end volume"],
        ["Sound effects volume", "sound", "alert tick click quiet loud"],
        ["Sound", "sound", "audio speakers headphones output input microphone volume mute"],
        ["Play sound through", "sound", "output speakers headphones device audio"],
        ["Microphone", "sound", "input mic recording device"],
        ["Input", "input", "keyboard and mouse touchpad trackpad pointer typing layouts"],
        ["Add a layout", "input", "keyboard layout language qwerty azerty dvorak region"],
        ["Caps Lock key", "input", "capslock ctrl escape remap"],
        ["Repeat delay", "input", "key repeat hold keyboard"],
        ["Repeat speed", "input", "key repeat rate hold keyboard"],
        ["Pointer speed", "input", "mouse touchpad trackpad sensitivity cursor speed"],
        ["Acceleration", "input", "mouse acceleration flat adaptive"],
        ["Natural scrolling", "input", "reverse scroll direction"],
        ["Pointer size", "input", "cursor size mouse pointer big large"],
        ["Tap to click", "input", "touchpad trackpad tap"],
        ["Ignore while typing", "input", "touchpad palm rejection disable while typing"],
        ["Power", "power", "battery lid power button suspend sleep performance"],
        ["Closing the lid", "power", "laptop lid suspend sleep close"],
        ["Power button", "power", "power key shut down suspend"],
        ["Charging limit", "power", "battery charge limit 80% full health threshold maximum"],
        ["On battery", "power", "power mode profile saver battery"],
        ["Plugged in", "power", "power mode profile performance charger"],
        ["Reopen apps after restarting", "power", "restart reboot reopen restore apps windows workspaces session"],
        ["Tiles in the icon's colour", "appearance", "icon tile background colour colourful dock launcher plate match"],
        ["Game mode", "bar", "game gaming performance fps smooth effects glass blur animations shadows touchpad"],
        ["Windows show", "workspaces", "overview live previews app icons windows cards thumbnails screenshots"],
        ["Windows show", "windows", "switcher alt tab super tab live previews app icons thumbnails"],
        ["Factory reset", "debug", "reset defaults start over wipe erase fresh install restore clear everything"],
        ["Shortcuts", "shortcuts", "keyboard shortcuts keybinds hotkeys keys"],
        ["Default Apps", "apps", "terminal browser file manager editor calculator default applications"],
        ["Startup Apps", "startup", "autostart login start open at login"],
        ["Region", "datetime", "date time zone timezone clock ntp automatic regional formats locale"],
        ["Time zone", "datetime", "timezone region clock"],
        ["Date format", "datetime", "date order day month year american british iso clock calendar"],
        ["Week starts on", "datetime", "week first day monday sunday saturday calendar"],
        ["Temperature", "datetime", "weather celsius fahrenheit degrees units"],
        ["Screenshots", "screenshots", "screenshot print screen capture folder"],
        ["Animations", "appearance", "motion reduce motion speed fast off"],
        ["Focus follows the pointer", "windows", "focus follows mouse click to focus hover"],
        ["Title bars", "windows", "floating window title bar titlebar slate bars hyprbars decoration"],
        ["Hyprbars", "windows", "title bars plugin build rebuild retry remove reload hyprland update optional"],
        ["Title bar buttons", "windows", "close maximise maximize buttons left right side floating"],
        ["Wallpaper", "appearance", "background picture image desktop"],
        ["Slate's wallpapers", "appearance", "included bundled built in default backgrounds ember iris lagoon blossom fern cobalt ruby honey graphite mist gradient colourful colorful green blue red yellow black white grey gray plain logo mark"],
        ["Change wallpaper", "appearance", "automatically rotate shuffle slideshow timer login cycle background theme"],
        ["Menu Bar", "bar", "top bar panel status"],
        ["Panel blur", "bar", "menu bar panels popouts glass blur frosted clear see through"],
        ["Panel opacity", "bar", "menu bar panels popouts glass transparency transparent see-through opacity background"],
        ["Contents opacity", "bar", "menu bar contents container items groups containers capsules pills transparency transparent see-through opacity"],
        ["Hover opacity", "bar", "menu bar items groups containers hover pointer over transparency transparent see-through opacity"],
        ["Blur", "bar", "menu bar glass blur frosted frosting clear see through"],
        ["Background opacity", "bar", "menu bar glass transparency transparent see-through clear opacity background"],
        ["Monochrome tray icons", "bar", "tray icons one colour black white mono monotone colourful apps"],
        ["Arrange the menu bar", "bar", "edit layout drag reorder order containers pool items show hide tray battery wifi volume notifications power clock time 24 hour 12 hour seconds date values text beside icons percentage network name collapse tuck away flexible space bluetooth keyboard layout"],
        ["Name when switching", "workspaces", "workspace name indicator switch super left right on-screen label"],
        ["Dock", "dock", "pinned apps magnification icon size auto-hide"],
        ["Blur", "dock", "dock glass blur frosted frosting clear see through"],
        ["Background opacity", "dock", "dock glass transparency transparent see-through clear opacity background"],
        ["Icon opacity", "dock", "dock glass transparency transparent see-through icons foreground apps buttons opacity"],
        ["Tile opacity", "dock", "dock glass transparency transparent see-through icons widgets buttons tiles opacity"],
        ["Window previews", "dock", "live preview thumbnails windows hover rest pointer peek"],
        ["Previews appear after", "dock", "window previews delay wait time instant immediately how long seconds hover"],
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
        ["Default window mode (tiling, side stack, scrolling, stacking, floating or solo)", "windows", "layout floating stacking free move drag traditional desktop tile dwindle master stack scrolling columns strip monocle one window full solo per workspace maximised maximized"],
        ["Keep an empty workspace", "workspaces", "spare new blank extra dynamic workspaces gnome"],
        ["Window spacing", "windows", "gaps gap padding space between margin"],
        ["Space around a lone window", "windows", "gaps padding margin lone single solo full screen rounded corners"],
        ["Account picture", "general", "avatar profile photo user face picture"],
        ["Window switcher", "windows", "alt tab previews"],
        ["Workspace overview", "workspaces", "overview workspaces super down cards"],
        ["Workspaces", "workspaces", "workspace switching animation slide fade crossfade wrap around empty overview indicators dots"],
        ["Workspace switching", "workspaces", "animation slide fade crossfade vertical transition effect"],
        ["Workspaces wrap around", "workspaces", "circular loop cycle last first ends"],
        ["Hot Corners", "hotcorners", "screen corners actions"],
        ["Quick switches", "control", "control centre center panel toggles tiles wi-fi bluetooth caffeine night light do not disturb performance airplane aeroplane flight game mode light mode mute microphone power saver glass charging limit hide dock menu bar floating clipboard order arrange drag swap"],
        ["Notifications", "notifications", "pop-ups toasts position do not disturb history"],
        ["Launcher glass", "launcher", "blur opacity transparency see-through frosted app launcher window"],
        ["Chalk's window glass", "assistant", "blur opacity transparency see-through frosted chalk assistant window"],
        ["Notification glass", "notifications", "blur opacity hover transparency see-through frosted pop-ups toasts"],
        ["Security", "lock", "lock and idle locking lock screen screen off sleep suspend idle login screen password"],
        ["Lock screen", "lock", "password lock"],
        ["Idle and sleep", "lock", "screen off suspend sleep idle timeout"],
        ["Login screen", "lock", "greeter greetd sign in install update switch back display manager"],
        ["Wi-Fi", "wifi", "wireless network internet"],
        ["Network", "wifi", "connection internet ip address gateway dns link speed online offline"],
        ["Wired", "wifi", "ethernet cable lan socket network"],
        ["Bluetooth", "bluetooth", "devices headphones pair"],
        ["Printers", "printers", "printers and scanners print printer printing scanner scan scanning cups sane test page"],
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
            out.push({ label: a.label, page: "apptheming", detail: a.detail || "", group: "App Theming",
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

    // Ignore case and punctuation, so "wifi" finds "Wi-Fi"
    function norm(t) { return (t || "").toLowerCase().replace(/[^a-z0-9 ]+/g, "").replace(/\s+/g, " ").trim(); }
    // Each entry's text as search compares it, worked out once when the list changes rather
    // than for all ~400 entries on every keystroke (the launcher searches as you type too)
    readonly property var prepared: entries.map(e => {
        const n = norm(e.label);
        const more = norm(e.group + " " + (pageNames[e.page] || "") + " " + e.words + " " + e.detail);
        return { e: e, n: n, nWords: n.split(" "), more: more, moreWords: more.split(" "), page: norm(pageNames[e.page] || "") };
    })
    // Best matches first: the label starting with it, then a word in the label, then
    // anywhere in the label, then its heading, page, extra words or description
    function search(text, limit) {
        const q = norm(text);
        if (q.length < 2) return [];
        const hidden = l => Config.clickToFocus && l === "Focus follows the pointer";     // (Slate's title bars: always a click)
        return prepared.filter(p => !hidden(p.e.label)).map(p => {
            const n = p.n, more = p.more;
            let s = n.startsWith(q) ? 0 : p.nWords.some(w => w.startsWith(q)) ? 1 : n.includes(q) ? 2
                : p.moreWords.some(w => w.startsWith(q)) ? 3 : more.includes(q) ? 4 : -1;
            // Several words ("dock size"): each has to start a word somewhere
            if (s < 0 && q.includes(" ")) {
                const qs = q.split(" ");
                const inLabel = w => p.nWords.some(x => x.startsWith(w));
                if (qs.every(w => inLabel(w) || p.moreWords.some(x => x.startsWith(w))))
                    s = qs.every(inLabel) ? 2.5 : 3.5;
            }
            // On the page it names ("wifi" → the Wi-Fi page before the bar's Wi-Fi switch)
            const home = p.page.startsWith(q) ? 0 : 1;
            return { e: p.e, s: s, home: home };
        }).filter(x => x.s >= 0)
          .sort((a, b) => a.s - b.s || a.home - b.home || a.e.label.length - b.e.label.length)
          .slice(0, limit || 50)
          .map(x => x.e);
    }
}
