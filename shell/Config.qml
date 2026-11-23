pragma Singleton

// Shared settings for the bar, dock, launcher, switchers and notifications.
// Saved to settings.json next to this file; changed from the Settings window
// (slate ipc call settings toggle). Use as  Config.s.<name>

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

Singleton {
    id: root
    readonly property alias s: adapter
    signal saved()                         // settings.json changed (here or on disk)

    // The accent in use: picked by hand, or taken from the wallpaper
    readonly property color accent: s.accentFromWallpaper && wallpaperAccent !== "" ? fromWallpaper(wallpaperAccent) : accentShade(s.accent)
    // The wallpaper's colour as the accent, as bold as Settings → Appearance → Accent boldness asks.
    // Light mode keeps its deeper shade's depth (accentShade), so the light text on it stays
    // readable, and changes only its saturation: 50% is that shade as it is, less mutes it (to
    // 20% saturation at 0%) and more makes it vivid (90% at 100%)
    function fromWallpaper(c) {
        if (!s.lightMode) return boldAccent(c, s.accentBoldness);
        const a = accentShade(c);
        const k = Math.max(0, Math.min(1, Number(s.accentBoldness) || 0));
        if (Qt.lighter(c, 1.0).hslSaturation < 0.08) return a;     // a grey wallpaper stays grey
        const base = a.hslSaturation;
        const sat = k < 0.5 ? 0.2 + (base - 0.2) * (k / 0.5)
            : base + (Math.max(base, 0.9) - base) * ((k - 0.5) / 0.5);
        return Qt.hsla(a.hslHue < 0 ? 0 : a.hslHue, sat, a.hslLightness, 1);
    }
    // A colour made bolder by k (0: as it is, 1: fully): towards nearly full saturation, lightened
    // only as far as the dark text on the accent needs to stay readable (so blues and purples
    // end up lighter than reds and oranges)
    function boldAccent(c, k) {
        const a = Qt.lighter(c, 1.0);
        k = Math.max(0, Math.min(1, Number(k) || 0));
        if (k === 0 || a.hslSaturation < 0.08) return a;     // a grey wallpaper stays grey
        const h = a.hslHue < 0 ? 0 : a.hslHue;
        const lin = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        let t = a;
        for (let l = 0.5; l <= 0.8; l += 0.005) {
            t = Qt.hsla(h, 0.9, l, 1);
            if (0.2126 * lin(t.r) + 0.7152 * lin(t.g) + 0.0722 * lin(t.b) >= 0.25) break;
        }
        const sat = a.hslSaturation + (Math.max(a.hslSaturation, t.hslSaturation) - a.hslSaturation) * k;
        return Qt.hsla(h, sat, a.hslLightness + (t.hslLightness - a.hslLightness) * k, 1);
    }
    // A colour as the accent shows it: in light mode a deeper shade, so it stands out on light
    // backgrounds (Settings' accent swatches use this too, to show what you'll get)
    function accentShade(c) {
        const a = Qt.lighter(c, 1.0);
        return s.lightMode ? Qt.hsla(a.hslHue < 0 ? 0 : a.hslHue, Math.max(a.hslSaturation, 0.45), 0.42, 1) : a;
    }
    // The pointer becomes a hand over anything in Slate that can be clicked (ClickTap and
    // ClickArea, which everything pressable uses)
    readonly property Component handHover: Component { HoverHandler { cursorShape: Qt.PointingHandCursor } }
    // Hover highlight, everywhere in Slate: the accent, lightly. `hover` is see-through, for
    // things with no background of their own; hoverOn(base) is it for things with a fill
    readonly property real hoverStrength: 0.22
    readonly property color hover: Qt.rgba(accent.r, accent.g, accent.b, hoverStrength)
    // The active colour under the pointer, a little lighter: on anything filled with it that a
    // click acts on (a switch that's on, a primary button, a quick tile, a connected device), to
    // say the click will do something. A choice that stays chosen when clicked doesn't change
    readonly property color accentLit: Qt.tint(accent, Qt.rgba(1, 1, 1, 0.22))
    // The one way to fill something with the active colour that a click acts on (a switch that's
    // on, a primary button): the plain accent, or the lit one under the pointer
    function accentFor(hovered) { return hovered ? accentLit : accent }
    // ---- Rounded corners (Settings → Appearance → Rounded UI elements) -------------------
    // Every rounded corner Slate draws is given as corner(its radius): the radius, or 0 with
    // the setting off, when everything is a hard square (containers, panels, buttons, switches,
    // the dock, menus, pictures, and windows, through Hyprland). Two things keep shapes of
    // their own: app icons (Icon shape) and the workspace dots (Circles or Squares). Anything
    // new with a rounded corner uses this too
    function corner(radius) { return s.roundedElements ? radius : 0; }
    // ---- Dates, temperatures and the week, as you write them -----------------------------
    // Settings → Region → Date format: every date Slate shows goes through dateText(date,
    // style), style being "short" (Sat 7 Nov), "day" (7 Nov), "long" (Saturday, 7 November
    // 2026), "longDay" (the same without the year) or "full" (7 November 2026)
    readonly property var dateFormats: ({
        dmy: { short: "ddd d MMM", day: "d MMM", long: "dddd, d MMMM yyyy", longDay: "dddd, d MMMM", full: "d MMMM yyyy" },
        mdy: { short: "ddd, MMM d", day: "MMM d", long: "dddd, MMMM d, yyyy", longDay: "dddd, MMMM d", full: "MMMM d, yyyy" },
        ymd: { short: "yyyy-MM-dd", day: "MM-dd", long: "dddd, yyyy-MM-dd", longDay: "dddd, MM-dd", full: "yyyy-MM-dd" }
    })
    function dateText(date, style) {
        const f = dateFormats[s.dateFormat] || dateFormats.dmy;
        return Qt.formatDate(date, f[style] || f.short);
    }
    // The day a week starts on, as Date.getDay() counts them (0 Sunday … 6 Saturday)
    readonly property int weekStartDay: s.weekStart === "sunday" ? 0 : s.weekStart === "saturday" ? 6 : 1
    readonly property bool fahrenheit: s.temperatureUnit === "fahrenheit"
    // The muted hover of something destructive (Remove, Clear, Delete, Force Quit…): the same,
    // in the red such things are written in, so pointing at one says what it will do
    readonly property color hoverDanger: { const d = tint("#f28b8b"); return Qt.rgba(d.r, d.g, d.b, hoverStrength); }
    // (Under the pointer, something that has a fill of its own takes the muted hover in its
    // place, not laid over it: hovering looks the same on a card, a button or a bare row, with
    // glass or without. A solid fill gets it as it looks on the panel behind (the hover over
    // the panels' colour), solid too: animated from solid to see-through, a colour passes
    // through a brighter, fuller accent on the way and settles back, a flash on every hover)
    function hoverOn(base) { return base.a > 0.99 ? Qt.tint(tint("#0f1216"), hover) : hover; }
    // The wallpaper on screen: the one saved, or one the wallpaper switcher (Super+Alt+W,
    // WallpaperSwitcher.qml) is showing for a moment, with the theme's colours following it
    property string wallpaperPreview: ""
    property string wallpaper: wallpaperPreview !== "" ? wallpaperPreview : s.wallpaper
    // The wallpaper switcher is on screen: the bar and dock sit above it and take no clicks, and
    // what's slow or reaches outside Slate (App theming, folder colours, title bar buttons,
    // window borders, the login screen) waits until it closes, then catches up once (shell.qml)
    property bool wallpaperSwitching: false
    // The colours worked out for each wallpaper looked at while it's open, so going back to one
    // (or closing it) puts them back at once rather than working them out again
    property var wallpaperColourMemo: ({})
    property string wallpaperAccent: ""
    property string wallpaperTone: ""      // overall hue/saturation of the wallpaper
    // Settings → Appearance → Tint boldness, as a multiplier on how much of the wallpaper's colour
    // backgrounds take: 50% is 1×, 100% is 2× (80% to start with)
    readonly property real toneBold: 2 * Math.max(0, Math.min(1, Number(s.toneBoldness ?? 0.8)))

    // Every theme colour goes through tint():
    //  - Light mode flips the greys (dark backgrounds become light, light text
    //    becomes dark) and deepens coloured ones so they read on a light background.
    //  - Background tint shifts the greys toward the wallpaper's hue, keeping
    //    their lightness.
    // With both off the colour comes back unchanged (the default dark slate).
    function tint(hex) {
        const light = s.lightMode;
        const toned = s.toneFromWallpaper && wallpaperTone !== "";
        // (a colour, not the text: surface() and others read its channels; from the text, glass
        // made dark-theme surfaces fully transparent unless the wallpaper tinted them)
        const c = Qt.lighter(hex, 1.0);
        if (!light && !toned) return contrasted(c);
        const neutral = c.hslSaturation < 0.3;
        const surface = c.hslLightness < 0.5;          // backgrounds (vs text) in the dark theme
        let h = c.hslHue, sat = c.hslSaturation, l = c.hslLightness;
        // Light backgrounds sit well below the straight flip: near-white was glaring and
        // left no room for the wallpaper's tint to show
        if (light) l = neutral ? 1 - l - (surface ? 0.1 : 0) : Math.min(l, 0.45);
        if (toned && neutral) {
            const t = Qt.lighter(wallpaperTone, 1.0);
            if (t.hslHue >= 0) h = t.hslHue;
            if (light && surface) {
                // Light backgrounds: a set amount of visible colour (chroma), from how colourful
                // the wallpaper is. Near-white needs far more saturation than near-black to show
                // any, so a muted wallpaper otherwise left them looking plain white
                const chroma = Math.min(0.15 * toneBold, t.hslSaturation * 0.8 * toneBold);
                sat = Math.min(1, Math.max(sat, chroma / Math.max(0.01, 1 - Math.abs(2 * l - 1))));
            } else if (surface) {
                sat = Math.min(0.32 * toneBold, Math.max(sat, t.hslSaturation * 0.45 * toneBold));
            } else {
                sat = Math.min(0.32, Math.max(sat, t.hslSaturation * 0.22));     // text: a hint, whatever the boldness
            }
        }
        return contrasted(Qt.hsla(h < 0 ? 0 : h, sat, l, c.a));
    }
    // Accessibility → High contrast: every themed color pushed apart. Backgrounds go much nearer
    // black (white in light mode), text and icons much nearer white (black), so dim text reads
    // clearly and surfaces separate from what's on them. (A colorful accent passes through
    // tint() only where it's asked to; the accent itself is left as chosen)
    // Accessibility → Text size: a text size in Slate's own pixels, grown by the setting (1, 1.15
    // or 1.3). Text only: icons, which are font glyphs too, keep their size. Every Text's
    // font.pixelSize goes through it (a static test checks)
    // (the nearest of the three, so anything in between, from an assistant say, still works)
    readonly property real textScale: { const v = Number(s.textScale) || 1; return v >= 1.22 ? 1.3 : v >= 1.07 ? 1.15 : 1; }
    function text(px) { return Math.round(Number(px) * textScale); }
    // Whether wtype is installed (OnScreenKeyboard.qml looks): the on-screen keyboard types into
    // apps with it
    property bool wtypeAvailable: true
    // A screen recording going (ScreenRecorder.qml): its file, when it started (seconds since
    // 1970) and how long it's been
    property bool recording: false
    property string recordingFile: ""
    property int recordingSince: 0
    property int recordingSeconds: 0
    function recordingTime() { const s = recordingSeconds; return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
    // Accessibility → Screen reader: the words a control shows, gathered from the Text inside it
    // (a few levels down), for its Accessible.name when it has no label of its own: a panel's
    // row, a bar item. Read through a binding, so it follows the words as they change
    function textOf(item, depth) {
        const d = depth === undefined ? 6 : depth;
        if (!item || d < 0) return "";
        if (item.visible === false) return "";
        const own = item.text !== undefined && typeof item.text === "string" && item.font !== undefined ? item.text : "";
        // (an icon's glyph isn't a word: only text with something besides spaces and the icon
        // font's glyphs, which are in Unicode's private use area, counts. Not /\p{L}/u: Qt's
        // JavaScript doesn't know it, and nothing ever counted)
        const parts = /[^\s\uE000-\uF8FF]/.test(own) ? [own] : [];
        for (const c of item.children || []) {
            const t = textOf(c, d - 1);
            if (t) parts.push(t);
        }
        return parts.join(", ");
    }
    // A point on the desktop in Hyprland's pixels (hyprctl cursorpos) → { screen, x, y }: the
    // screen holding it and the point within it in Slate's units (Interface size divided out), or
    // null off every screen. Hyprland's layout: each monitor's x, y and its size over its scale.
    // (LocatePointer.qml, PointerTrail.qml)
    function screenPoint(x, y) {
        const k = uiScale || 1;
        for (const m of Hyprland.monitors.values) {
            const o = m.lastIpcObject || {};
            const mx = o.x !== undefined ? o.x : m.x, my = o.y !== undefined ? o.y : m.y;
            const sc = o.scale || m.scale || 1;
            const w = (o.width || m.width) / sc, h = (o.height || m.height) / sc;
            if (x < mx || y < my || x >= mx + w || y >= my + h) continue;
            const scr = Quickshell.screens.find(s => s.name === m.name);
            return scr ? { screen: scr, x: (x - mx) / k, y: (y - my) / k } : null;
        }
        return null;
    }
    // ...and Orca, the screen reader (ScreenReader.qml looks)
    property bool orcaAvailable: true
    function contrasted(c) {
        if (!s.highContrast) return c;
        const l = c.hslLightness, light = s.lightMode;
        const back = light ? l >= 0.5 : l < 0.5;          // a background (vs text) in this theme
        const toward = back === light ? 1 : 0;            // where it's pushed: white or black
        const amount = back ? 0.6 : 0.75;
        return Qt.hsla(Math.max(0, c.hslHue), c.hslSaturation * 0.6, l + (toward - l) * amount, c.a);
    }

    // Sunrise and sunset on a date at Settings' location, in minutes after local midnight
    // (NOAA's approximation; good to a minute or two). Polar day/night clamp to 0 / 1440.
    function sunTimes(date) {
        const rad = Math.PI / 180;
        const start = new Date(date.getFullYear(), 0, 0);
        const n = Math.floor((date - start) / 86400000);
        const g = 2 * Math.PI / 365 * (n - 1);
        const eq = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g) - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));
        const decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g)
            + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
        const lat = s.latitude * rad;
        const x = Math.cos(90.833 * rad) / (Math.cos(lat) * Math.cos(decl)) - Math.tan(lat) * Math.tan(decl);
        const ha = Math.acos(Math.max(-1, Math.min(1, x))) / rad;
        const offset = -date.getTimezoneOffset();
        const clamp = m => Math.max(0, Math.min(1440, m));
        return { rise: clamp(720 - 4 * (s.longitude + ha) - eq + offset), set: clamp(720 - 4 * (s.longitude - ha) - eq + offset) };
    }
    // A time of day in your clock's format (Settings → Menu Bar → Clock: 12- or 24-hour), as the
    // menu bar's clock shows it: "9:30 PM" or "21:30"
    function timeText(date) { return Qt.formatTime(date, s.barClockFormat === "24h" ? "HH:mm" : "h:mm AP"); }
    function clockText(minutes) {
        const m = Math.round(minutes);
        return String(Math.floor(m / 60) % 24).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0");
    }

    // ---- The menu bar's arrangement (Bar.qml draws it; Settings → Menu Bar changes it) -------
    // Slate's own: the control centre; Apps with Nova; Spaces with the window mode and the
    // workspace dots; the active window; a flexible space; then the tray, the status icons,
    // More, the clock and the power button
    readonly property var barStatusItems: ["notifications", "clipboard", "screenshot", "camera", "drink", "focus", "gamemode", "keyboard", "bluetooth", "volume", "wifi", "battery"]
    readonly property var barLayoutDefault: [
        barBox(["control"]), barBox(["apps", "nova"]),
        barBox(["spaces", "windowmode", "workspaces", "workspacename"]),
        barBox(["windowicon", "windowtitle"]), "space",
        barBox(["tray"]), barBox(barStatusItems, { tuck: s.barStatusCollapsed }), barBox(["more"]), barBox(["clock"]), barBox(["power"])
    ]
    // Everything that can be in a container: its name in the arrangement, what it's called, its
    // icon (for the pool on Settings → Menu Bar), and the setting that says whether it shows
    readonly property var barItems: [
        { id: "control", label: "Control Center", icon: 0xEAD7, key: "barShowControl" },
        { id: "apps", label: "Apps", icon: 0xEC42, key: "barShowApps" },
        { id: "spaces", label: "Spaces", icon: 0xEDBA, key: "barShowSpaces" },
        { id: "nova", label: "Nova", icon: 0xF014, key: "barShowAssistant" },
        { id: "windowmode", label: "Window mode", icon: 0xEFE6, key: "barShowWindowMode" },
        { id: "workspaces", label: "Workspaces", icon: 0xEA95, key: "barShowWorkspaces" },
        { id: "workspacename", label: "Workspace name", icon: 0xFF38, key: "barShowWorkspaceName" },
        { id: "windowicon", label: "Window icon", icon: 0xEFE6, key: "barShowTitleIcon" },
        { id: "windowtitle", label: "Window title", icon: 0xEBC5, key: "barShowTitle" },
        { id: "tray", label: "Tray", icon: 0xEA61, key: "barShowTray" },
        { id: "notifications", label: "Notifications", icon: 0xEA35, key: "barShowNotifications" },
        { id: "clipboard", label: "Clipboard", icon: 0xEA6F, key: "barShowClipboard" },
        { id: "screenshot", label: "Screenshot", icon: 0xF201, key: "barShowScreenshot" },
        { id: "camera", label: "Camera", icon: 0xEA9A, key: "barShowCamera" },
        { id: "drink", label: "Drink reminder", icon: 0xEA97, key: "barShowDrink" },
        { id: "focus", label: "Focus timer", icon: 0xEA70, key: "barShowFocus" },
        { id: "gamemode", label: "Game Mode", icon: 0xF1D2, key: "barShowGameMode" },
        { id: "keyboard", label: "Keyboard layout", icon: 0xEBD6, key: "barShowKeyboard" },
        { id: "bluetooth", label: "Bluetooth", icon: 0xEA37, key: "barShowBluetooth" },
        { id: "volume", label: "Volume", icon: 0xEB51, key: "barShowVolume" },
        { id: "wifi", label: "Wi-Fi", icon: 0xEB52, key: "barShowWifi" },
        { id: "battery", label: "Battery", icon: 0xEA30, key: "barShowBattery" },
        { id: "clock", label: "Clock", icon: 0xEA70, key: "barShowClock" },
        { id: "power", label: "Power", icon: 0xEB0D, key: "barShowPower" },
        // (what holds whatever there isn't room for: always on the bar, placed like the rest,
        // but never taken off it. No switch of its own, so no key)
        { id: "more", label: "More", icon: 0xEA95, key: "" }
    ]
    function barItem(id) { return barItems.find(i => i.id === id) || null; }
    // What a tray icon is called (the label off the bar says it): the app's title for it, or its
    // tooltip's title, or else its id; tidied, so a raw id reads as a name
    function trayName(item) {
        if (!item) return "";
        for (const n of [item.title, item.tooltipTitle, item.id]) { const t = trayTidy(n); if (t !== "") return t; }
        return "";
    }
    // Words are left as they are ("Fake tray app"). One with no spaces is an id: its last part
    // if it's dotted (org.kde.kdeconnect), split at _, - and camelCase, with numbers and words
    // that only say it's a tray icon (status, icon, tray, indicator…) left out, and a capital
    // first: "chrome_status_icon_1" → "Chrome", "nm-applet" → "Nm", "steam" → "Steam". Nothing left
    // ("StatusNotifierItem-1234-1", Qt's own made-up id): "", and no label
    function trayTidy(raw) {
        const t = String(raw || "").trim();
        if (t === "" || /\s/.test(t)) return t;
        const word = t.split(".").filter(p => p !== "").pop() || t;
        const parts = word.replace(/([a-z])([A-Z])/g, "$1 $2").split(/[\s_\-]+/).filter(p => p !== "" && !/^\d+$/.test(p));
        const filler = ["status", "icon", "tray", "indicator", "notifier", "notification", "item", "sni", "applet", "appindicator", "systray"];
        const kept = parts.filter(p => filler.indexOf(p.toLowerCase()) < 0);
        if (kept.length === 0) return "";
        const out = kept.join(" ");
        return out.charAt(0).toUpperCase() + out.slice(1);
    }
    // A saved name for something on the bar, as it's called now: Nova's button was "chalk"
    // (its old name) in arrangements and orders saved before it was renamed
    function barId(id) { return id === "chalk" ? "nova" : String(id); }
    // A fixed space in the arrangement: "fixed:<n>px", or "fixed:<n>%" of the screen's width (its
    // height on a side bar): { n, unit } for one, null for anything else. Kept as a word like the
    // flexible space ("space"), so whatever passes over spaces passes over these too
    function barFixed(e) {
        const m = typeof e === "string" ? /^fixed:(\d{1,4})(px|%)$/.exec(e) : null;
        return m ? { n: Number(m[1]), unit: m[2] } : null;
    }
    // (sizes kept sensible: 1 to 1000 pixels, 1 to 50% of the screen)
    function barFixedEntry(n, unit) {
        const u = unit === "%" ? "%" : "px";
        const v = Math.round(Math.max(1, Math.min(u === "%" ? 50 : 1000, Number(n) || 0)));
        return "fixed:" + v + u;
    }
    // The arrangement in use: the saved one, tidied (only things Slate knows, each once; a
    // container with nothing left in it dropped; anything it leaves out given a container of
    // its own at the end, so nothing can be lost), or Slate's own when there's none
    readonly property var barLayout: {
        const saved = s.barLayout;
        if (!saved || saved.length === undefined || saved.length === 0) return barLayoutDefault;
        const known = barItems.map(i => i.id);
        const seen = {}, out = [];
        let spaces = 0;
        for (let i = 0; i < saved.length; i++) {
            const e = saved[i];
            if (e === "space") { spaces++; out.push("space"); }
            else if (barFixed(e)) { const f = barFixed(e); out.push(barFixedEntry(f.n, f.unit)); }
            // (from when the window's icon and title were one thing of its own on the line)
            else if (e === "title") {
                const items = ["windowicon", "windowtitle"].filter(id => !seen[id]);
                for (const id of items) seen[id] = true;
                if (items.length > 0) out.push(barBox(items, null));
            }
            else if (e && e.items && e.items.length !== undefined) {
                const items = [];
                for (let j = 0; j < e.items.length; j++) {
                    const id = barId(e.items[j]);
                    if (known.indexOf(id) >= 0 && !seen[id]) { seen[id] = true; items.push(id); }
                }
                // (an empty one stays only while it's fresh from the pool, waiting for its first thing)
                if (items.length > 0) out.push(barBox(items, e));
                else if (e.keep) { const b = barBox(items, null); b.keep = true; out.push(b); }
            }
        }
        // (there's always one flexible space: without one nothing takes up the spare room)
        if (spaces === 0) out.splice(out.findIndex(e => typeof e !== "string" && e.items.indexOf("windowtitle") >= 0) + 1 || out.length, 0, "space");
        // (a saved arrangement from before there was a More: it goes just before the clock)
        if (!seen["more"]) {
            seen["more"] = true;
            const at = out.findIndex(e => typeof e !== "string" && e.items.indexOf("clock") >= 0);
            out.splice(at >= 0 ? at : out.length, 0, barBox(["more"], null));
        }
        // (anything new since it was saved: a status icon joins the other status icons, the rest
        // a container of its own at the end)
        for (const id of known) {
            if (seen[id]) continue;
            const box = barStatusItems.indexOf(id) >= 0
                ? out.find(e => typeof e !== "string" && e.items.some(x => x !== id && barStatusItems.indexOf(x) >= 0)) : null;
            if (box) {
                const t = box.items.indexOf("tuck");
                if (t >= 0 && t === box.items.length - 1) box.items.splice(t, 0, id); else box.items.push(id);
            } else out.push(barBox([id], null));
        }
        return out;
    }
    // A container as the bar wants it, from its real items and how it was saved. Its collapse
    // button is one of the things in it, "tuck" (at most one, at its start or its end: that's
    // which end the button sits at, the rest sliding out from it): `tuck` and `tuckFrom` say
    // the same for the bar. Saved the old way (tuck: true), the button goes at the end
    function barBox(items, saved) {
        // How it collapses: "never", "always" (tucked behind its button
        // until that's clicked) or "needed" (only when the bar's short of room), which is how
        // a container starts. From before there were modes: one with a button is "always"
        const legacy = !!saved && ((saved.items && saved.items.indexOf("tuck") >= 0) || !!saved.tuck);
        const mode = saved && ["never", "always", "needed"].indexOf(saved.collapse) >= 0 ? saved.collapse : legacy ? "always" : "needed";
        const first = !!saved && ((saved.items && saved.items[0] === "tuck") || saved.tuckFrom === "start");
        const has = mode === "always";
        const all = !has ? items : first ? ["tuck"].concat(items) : items.concat(["tuck"]);
        return { items: all, tuck: has, collapse: mode, tuckIcon: String((saved && saved.tuckIcon) || ""), tuckFrom: first ? "start" : "end" };
    }

    // ---- Arranging it (Settings → Menu Bar → Edit layout; BarEditor.qml, the panel by the bar) ----
    property bool barArranging: false          // on from that button until the panel's Done
    property int barSelected: -1               // what's picked on the bar, by its place in the arrangement...
    property string barSelectedItem: ""        // ...and, when it's one thing in a container, its name ("tuck": the collapse button)
    onBarSelectedChanged: if (barSelected < 0) barSelectedItem = ""
    // Pick something (a container or a flexible space: item ""); again lets go of it
    function barPick(at, item) {
        if (barSelected === at && barSelectedItem === (item || "")) { barSelected = -1; return; }
        barSelectedItem = item || "";
        barSelected = at;
    }
    // The setting that says whether an item's text shows beside its icon ("" if it has none)
    readonly property var barTextKeys: ({ clipboard: "barValueClipboard", gamemode: "barValueGameMode",
        drink: "barValueDrink", focus: "barValueFocus", wifi: "barValueWifi",
        keyboard: "barValueKeyboard", bluetooth: "barValueBluetooth", volume: "barValueVolume", battery: "barValueBattery" })
    // (should Slate have gone away mid-arranging, its keys would have stayed: the usual ones back)
    Timer { running: !root.isLoginScreen; interval: 0; onTriggered: Quickshell.execDetached(["hyprctl", "eval", `hl.dispatch(hl.dsp.submap("reset"))`]) }
    onBarArrangingChanged: {
        // While it's arranged, Hyprland's shortcuts stand down (no switching workspace, no
        // moving or closing windows under it): a set of keys with only Escape in it, which
        // ends the arranging. Back to the usual ones after
        Quickshell.execDetached(["hyprctl", "eval", barArranging
            ? `if not SLATE_ARRANGING then SLATE_ARRANGING = true; hl.define_submap("slate-arranging", function() `
              + `hl.bind("Escape", hl.dsp.exec_cmd("${slateCommand} ipc call bar edit done")) end) end; hl.dispatch(hl.dsp.submap("slate-arranging"))`
            : `hl.dispatch(hl.dsp.submap("reset"))`]);
        barPrioritising = false;
        if (barArranging) return;
        barSelected = -1; barCarry = null; barCarryTarget = null; barLeaving = false; barFloat = null; barLanding = false; barPreview = 0;
        // (a container put on the bar and never given anything goes)
        if (barLayout.some(e => typeof e !== "string" && e.keep)) barSave(barCopy().filter(e => typeof e === "string" || !e.keep));
    }
    // Something carried from the pool in the panel (BarEditor.qml) towards the bar: what it is
    // ({ kind: "item" | "space" | "box", id }), where the pointer is on the
    // desktop, and, from the bar under it, where it would land ({ join, to, slot, bar })
    property var barCarry: null
    property point barCarryAt: Qt.point(0, 0)
    property var barCarryTarget: null
    // ...and the other way: something on the bar dragged off it (let go, it's back in the pool)
    property bool barLeaving: false
    // What's being dragged, from the bar or the pool, drawn under the pointer over everything
    // (BarEditor.qml): { kind, icons: [{ code, item }], label }, and where on the desktop
    property var barFloat: null
    property point barFloatAt: Qt.point(0, 0)
    // ...gliding into the gap it was let go over, before it's moved there (BarArranger.qml)
    property bool barLanding: false
    // Let go of what's carried: onto the bar where it was aimed (true), or nowhere (false)
    function barDrop() {
        const c = barCarry, t = barCarryTarget;
        barCarry = null; barCarryTarget = null;
        if (!c || !t) return false;
        if (c.kind === "item") { barSetShown(c.id, true); barMoveItem(c.id, t.to, t.join ? t.slot : -1); }
        else if (c.kind === "space") barAddSpace(t.to);
        else if (c.kind === "fixed") barAddFixed(t.to);
        else if (c.kind === "box") barAddBox(t.to);
        else if (c.kind === "tuck") {
            if (!t.join) return false;
            barSetTuck(t.to, true, undefined, t.slot <= barLayout[t.to].items.length / 2 ? "start" : "end");
        }
        return true;
    }
    // A copy of the arrangement to change and save: each container's real items (its collapse
    // button apart, as tuck / tuckFrom). Every change goes through barSave, which puts the
    // button back among the items and drops containers left empty
    function barCopy() {
        return barLayout.map(e => typeof e === "string" ? e
            : { items: e.items.filter(id => id !== "tuck"), collapse: e.collapse || "needed", tuckFrom: e.tuckFrom || "end", tuckIcon: e.tuckIcon || "", keep: !!e.keep });
    }
    function barSave(list) {
        s.barLayout = list.filter(e => typeof e === "string" || (e.items && (e.items.length > 0 || e.keep)))
            .map(e => typeof e === "string" ? e
                : e.items.length === 0 ? { items: [], keep: true }
                : { items: e.items, collapse: e.collapse || "needed", tuckFrom: e.tuckFrom === "start" ? "start" : "end", tuckIcon: e.tuckIcon || "" });
    }
    // The bar counts a container's things with its collapse button among them: the same place
    // among its real items
    function barSlot(at, slot) {
        const e = barLayout[at];
        return e && typeof e !== "string" && e.items[0] === "tuck" ? Math.max(0, slot - 1) : slot;
    }
    function barWhere(list, id) {
        for (let i = 0; i < list.length; i++) {
            if (typeof list[i] === "string") continue;
            const j = list[i].items.indexOf(id);
            if (j >= 0) return { box: i, slot: j };
        }
        return null;
    }
    // Move an item: into the container at place `to` (before its item number `slot`), or, with
    // slot < 0, into a container of its own before whatever is at place `to` (to = how many
    // things there are: at the end)
    function barMoveItem(id, to, slot) {
        const list = barCopy();
        const from = barWhere(list, id);
        if (!from) return;
        if (slot < 0) {
            const marker = { items: [], collapse: "needed", tuckFrom: "end", tuckIcon: "" };
            list.splice(Math.max(0, Math.min(list.length, to)), 0, marker);
            const now = barWhere(list, id);
            list[now.box].items.splice(now.slot, 1);
            marker.items = [id];
        } else {
            const target = list[to];
            if (!target || typeof target === "string") return;
            const at = Math.max(0, Math.min(target.items.length, barSlot(to, slot)));
            if (target === list[from.box]) {
                target.items.splice(from.slot, 1);
                target.items.splice(from.slot < at ? at - 1 : at, 0, id);
            } else {
                list[from.box].items.splice(from.slot, 1);
                target.items.splice(at, 0, id);
            }
        }
        barSelected = -1;
        barSave(list);
    }
    // Move a container's collapse button: to the container at `to`, at its start or its end
    // (whichever `slot`, counted as the bar does, is nearer; one that already has a button
    // keeps its own), or, with to < 0 (dropped outside any container), off the bar: that
    // container no longer tucks
    function barMoveTuck(from, to, slot) {
        const list = barCopy();
        const src = list[from];
        if (!src || typeof src === "string" || src.collapse !== "always") return;
        const dst = to >= 0 ? list[to] : null;
        if (dst && typeof dst === "string") return;
        if (dst && dst !== src && dst.collapse === "always") return;
        const icon = src.tuckIcon;
        src.collapse = "never";
        if (dst) {
            dst.collapse = "always";
            dst.tuckFrom = slot <= barLayout[to].items.length / 2 ? "start" : "end";
            dst.tuckIcon = icon;
        }
        barSelected = -1;
        barSave(list);
    }
    // Move a whole thing (a container, a flexible space) to before what's at `to`
    function barMoveEntry(from, to) {
        const list = barCopy();
        if (from < 0 || from >= list.length) return;
        const e = list[from];
        list.splice(Math.max(0, Math.min(list.length, to)), 0, e);
        list.splice(from < to ? from : from + 1, 1);
        barSelected = -1;
        barSave(list);
    }
    // Slate's own arrangement again: its order and containers, and everything it starts with
    // on the bar (what each thing shows, like its text, is left as it is)
    // (an arrangement that's been changed and put back by hand is the default again too)
    readonly property bool barIsDefault: (!s.barLayout || s.barLayout.length === 0 || JSON.stringify(barLayout) === JSON.stringify(barLayoutDefault))
        && !s.barStatusCollapsed
        && barItems.every(i => i.key === "" || sameValue(s[i.key], defaultOf(i.key)))
        && (!s.barOverflow || s.barOverflow.length === 0) && sameValue(s.barStay, defaultOf("barStay"))
    signal barRedraw()          // (the bar lays its line again, drawing everything afresh)
    function barReset() {
        barSelected = -1;
        barRedraw();
        for (const i of barItems) if (i.key !== "") s[i.key] = defaultOf(i.key);
        s.barStatusCollapsed = defaultOf("barStatusCollapsed");
        s.barLayout = [];
        s.barOverflow = [];
        s.barStay = defaultOf("barStay");
    }
    // An empty container, to drag things into (it goes again if it's left empty)
    function barAddBox(to) {
        const list = barCopy();
        list.splice(Math.max(0, Math.min(list.length, to)), 0, { items: [], keep: true });
        barSave(list);
    }
    readonly property int barSpaces: barLayout.filter(e => e === "space").length
    function barAddSpace(to) {
        const list = barCopy();
        list.splice(Math.max(0, Math.min(list.length, to)), 0, "space");
        barSave(list);
    }
    // A fixed space, 32 pixels to start with (its options change it)
    function barAddFixed(to) {
        const list = barCopy();
        list.splice(Math.max(0, Math.min(list.length, to)), 0, barFixedEntry(32, "px"));
        barSave(list);
    }
    // A fixed space's size: n pixels, or n% of the screen
    function barSetFixed(at, n, unit) {
        const list = barCopy();
        if (!barFixed(list[at])) return;
        list[at] = barFixedEntry(n, unit);
        barSave(list);
    }
    // Take a flexible space away; for a container, put its items back in the pool (they keep
    // their place, for when they're put back)
    function barRemoveEntry(at) {
        const list = barCopy();
        const e = list[at];
        if (e === "space") { if (barSpaces < 2) return; list.splice(at, 1); barSave(list); }      // (the last one stays)
        else if (barFixed(e)) { list.splice(at, 1); barSave(list); }
        else if (e && e.items.length === 0) { list.splice(at, 1); barSave(list); }      // (an empty one, fresh from the pool)
        else if (e) for (const id of e.items) barSetShown(id, false);
        barSelected = -1;
    }
    // Each of a container's items into a container of its own, where it was
    function barSplit(at) {
        const list = barCopy();
        const e = list[at];
        if (!e || typeof e === "string" || e.items.length < 2) return;
        list.splice(at, 1, ...e.items.map(id => ({ items: [id], collapse: "needed", tuckFrom: "end", tuckIcon: "" })));
        barSelected = -1;
        barSave(list);
    }
    // Give the container at `at` a collapse button or take it away; choose the button's icon
    // (a Tabler codepoint, as hex; "" for Slate's own) and which end it sits at ("start" / "end").
    // Leave any of them undefined to keep it as it is
    function barSetTuck(at, tuck, icon, from) {
        const list = barCopy();
        const e = list[at];
        if (!e || typeof e === "string") return;
        if (tuck !== undefined) e.collapse = tuck ? "always" : "never";
        if (from !== undefined) e.tuckFrom = from === "start" ? "start" : "end";
        if (icon !== undefined) e.tuckIcon = String(icon || "");
        barSave(list);
    }
    // How the container at `at` collapses: "never", "always" or "needed"
    function barSetCollapse(at, mode) {
        const list = barCopy();
        const e = list[at];
        if (!e || typeof e === "string" || ["never", "always", "needed"].indexOf(mode) < 0) return;
        e.collapse = mode;
        barSave(list);
    }
    // The order things leave a bar that's short of room, first to go first (Slate's own; the
    // last three stay)
    readonly property var barOverflowDefault: ["tray", "clipboard", "screenshot", "camera", "drink", "focus", "gamemode", "keyboard", "bluetooth", "workspacename", "windowtitle", "windowicon",
        "nova", "spaces", "apps", "notifications", "battery", "wifi", "volume", "windowmode", "workspaces"]
    // The order in use: yours (Settings → Menu Bar → Edit layout → If it doesn't fit), with
    // anything it leaves out put in from Slate's own, so every thing has a place; and the
    // things that stay on the bar whatever happens. More isn't one of them: it's what the
    // rest leave for
    readonly property var barStay: {
        const known = barItems.map(i => i.id);
        return (s.barStay && s.barStay.length !== undefined ? Array.from(s.barStay) : []).map(barId).filter((id, i, a) => known.indexOf(id) >= 0 && id !== "more" && a.indexOf(id) === i);
    }
    readonly property var barOverflowOrder: {
        const known = barItems.map(i => i.id).filter(id => id !== "more");
        const saved = (s.barOverflow && s.barOverflow.length !== undefined ? Array.from(s.barOverflow) : []).map(barId);
        const out = saved.filter((id, i, a) => known.indexOf(id) >= 0 && a.indexOf(id) === i);
        const own = barOverflowDefault.concat(["control", "clock", "power"]);
        for (const id of own.concat(known)) if (out.indexOf(id) < 0 && known.indexOf(id) >= 0) out.push(id);
        return out;
    }
    function barOverflowRank(id) { const i = barOverflowOrder.indexOf(id); return i < 0 ? 1000 : i; }
    function barStays(id) { return barStay.indexOf(id) >= 0; }
    // Set the order and what stays together (the arranging panel's list, after a drag)
    function barSetOverflow(order, stay) { s.barOverflow = order.concat(stay.filter(id => order.indexOf(id) < 0)); s.barStay = stay; }
    function barSetStay(id, on) {
        const stay = barStay.filter(x => x !== id);
        if (on) stay.push(id);
        s.barStay = stay;
    }
    // ---- The whole arrangement at once (the assistant's bar_arrange, over `slate ipc call bar …`) ----
    // As it is: containers with what's on the bar in them (things in the pool left out), how
    // each collapses and which end its button sits at, what's in the pool, the order things
    // leave a bar short of room and what always stays. Nova's button is the person's own: an
    // assistant isn't told whether it's on, and never switches it
    function barArrangement() {
        return {
            layout: barLayout.map(e => typeof e === "string" ? e
                : { items: e.items.filter(id => id !== "tuck" && (id === "more" || barShown(id))),
                    collapse: e.collapse || "needed", collapseAt: e.tuckFrom || "end" })
                .filter(e => typeof e === "string" || e.items.length > 0),
            offBar: barItems.filter(i => i.key !== "" && i.id !== "nova" && !barShown(i.id)).map(i => i.id),
            leaveFirst: barOverflowOrder.filter(id => !barStays(id)),
            alwaysStay: barStay,
            slatesOwn: barIsDefault
        };
    }
    // Set it: { reset } puts Slate's own back; otherwise any of { layout, leaveFirst, alwaysStay }.
    // A layout says everything that's on the bar: what it leaves out goes to the pool (keeping
    // its place for later), except Nova's button, which keeps its place and its switch. The
    // server checks the names first; the tidying of barLayout drops anything else
    function barArrange(spec) {
        if (spec.reset) { barReset(); return; }
        if (spec.layout) {
            const old = barCopy();
            const list = spec.layout.map(e => e === "space" ? "space" : barFixed(e) ? barFixedEntry(barFixed(e).n, barFixed(e).unit)
                : { items: e.items.map(barId), collapse: ["never", "always", "needed"].indexOf(e.collapse) >= 0 ? e.collapse : "needed",
                    tuckFrom: e.collapseAt === "start" ? "start" : "end", tuckIcon: "" });
            // (a container keeps the icon its collapse button had, found by its first thing)
            for (const e of list) {
                if (typeof e === "string" || e.items.length === 0) continue;
                const was = barWhere(old, e.items[0]);
                if (was && old[was.box].tuckIcon) e.tuckIcon = old[was.box].tuckIcon;
            }
            const on = {};
            for (const e of list) if (typeof e !== "string") for (const id of e.items) on[id] = true;
            if (!on["nova"]) {
                // Nova's button where it was: beside the thing it was next to, else in a container
                // of its own at the same place
                const was = barWhere(old, "nova");
                const box = was ? old[was.box].items : [];
                const near = was ? (box[was.slot - 1] || box[was.slot + 1]) : "";
                const at = near ? barWhere(list, near) : null;
                if (at) list[at.box].items.splice(box[was.slot - 1] === near ? at.slot + 1 : at.slot, 0, "nova");
                else list.splice(was ? Math.min(was.box, list.length) : list.length, 0, { items: ["nova"], collapse: "needed", tuckFrom: "end", tuckIcon: "" });
            }
            for (const i of barItems) if (i.key !== "" && i.id !== "nova" && !!on[i.id] !== barShown(i.id)) barSetShown(i.id, !!on[i.id]);
            barSelected = -1;
            barSave(list);
        }
        if (spec.leaveFirst || spec.alwaysStay) {
            const stay = (spec.alwaysStay || barStay).map(barId);
            const order = (spec.leaveFirst || barOverflowOrder).map(barId).filter(id => stay.indexOf(id) < 0);
            barSetOverflow(order, stay);
        }
    }

    // Trying the bar shorter while it's arranged (the panel's "Try it shorter"): the share of its
    // length taken off, 0 for none. While it's tried, the bar slims, tucks and overflows as it
    // would; otherwise, arranged, everything's there to be picked up
    // (menu item priority has its window up, in place of the arranging panel: BarEditor.qml)
    property bool barPrioritising: false
    property real barPreview: 0
    readonly property bool barShowAll: barArranging && barPreview <= 0
    // On the bar, or back in the pool: an item's own switch (Settings → Menu Bar)
    function barShown(id) { const it = barItem(id); return !!it && (it.key === "" || !!s[it.key]); }
    // (Put back on the bar, a thing has its text on again: it comes as it first was, whatever
    // it was set to before it went to the pool)
    function barSetShown(id, on) {
        const it = barItem(id);
        if (!it || it.key === "") return;          // (More has no switch: it's never off the bar)
        if (on && !s[it.key] && barTextKeys[id]) s[barTextKeys[id]] = true;
        s[it.key] = !!on;
    }

    // ---- Shadows (Shadow.qml, and Hyprland's under floating windows) ------------------------
    // One colour for every shadow: still dark, with a light tint of the theme. The hue is the
    // wallpaper's when Tint from wallpaper is on, Slate's own blue-grey otherwise; never
    // flipped in light mode (a shadow is dark on any background)
    readonly property color shadowColour: {
        const toned = s.toneFromWallpaper && wallpaperTone !== "";
        const t = Qt.lighter(toned ? wallpaperTone : "#0f1216", 1.0);
        const hue = t.hslHue >= 0 ? t.hslHue : 0.6;
        const sat = toned ? Math.min(0.5, Math.max(0.2, t.hslSaturation * 0.6)) : 0.25;
        return Qt.hsla(hue, sat, 0.06, 1);
    }
    // ---- Shadows: one look everywhere -----------------------------------------------------
    // Every shadow in Slate (Shadow.qml, the few drawn by Qt's own effects, and Hyprland's under
    // floating windows) takes its look from here, so they're all alike. Settings → Appearance →
    // Shadows: on or off (and off in game mode), darkness, softness, spread, distance, direction
    readonly property bool shadowsOn: s.shadows && !gameMode
    readonly property real shadowReach: Math.max(0, Math.min(24, Number(s.shadowSoftness) || 0))   // px of soft edge
    readonly property real shadowSpread: Math.max(0, Math.min(10, Number(s.shadowSpread) || 0))    // px of full darkness past the surface
    readonly property real shadowDrop: Math.max(0, Math.min(16, Number(s.shadowDistance) || 0))    // px from the surface
    // Which way it falls (degrees clockwise from straight down), as an offset: the same for
    // every surface, a panel hanging off the bar and the bar itself included (Shadow.qml)
    readonly property real shadowAngle: (Number(s.shadowDirection) || 0) * Math.PI / 180
    readonly property real shadowDX: Math.round(-Math.sin(shadowAngle) * shadowDrop * 10) / 10
    readonly property real shadowDY: Math.round(Math.cos(shadowAngle) * shadowDrop * 10) / 10
    readonly property real shadowEffectBlur: Math.min(1, shadowReach / 32)   // the same, for Qt's MultiEffect (of a blurMax of 32 px)
    // How dark at its darkest: softer in light mode, and on glass always below the point where
    // Hyprland blurs behind Slate's surfaces (glassCut), or the shadow would be blurred glass too
    readonly property real shadowStrength: Math.min(Math.max(0.05, Math.min(1, Number(s.shadowDarkness) || 0.5)) * (s.lightMode ? 0.5 : 1), glass ? glassCut - 0.04 : 1)
    // The same colour at a given strength, for the shades at the ends of scrolling lists
    // (more that way) and anything else that's a shadow drawn by hand
    function shade(alpha) { return Qt.rgba(shadowColour.r, shadowColour.g, shadowColour.b, alpha); }
    readonly property string shadowHex: {
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return h(shadowColour.r) + h(shadowColour.g) + h(shadowColour.b);
    }
    // Hyprland's shadow under floating windows (Settings, dialogs, apps), drawn to look like
    // Shadow.qml's for the same settings. In Hyprland's pixels (what's handed to it is
    // multiplied by uiScale, as Slate's own are scaled by the Interface size).
    // Shadow.qml (shaders/shadow.frag): at d px outside the surface, moved by the distance, it's
    // ((spread + soft - d) / (1.4 × soft))², at most full, gone at spread + soft. Hyprland's is
    // ((range - d) / range)^render_power at most full at the window's edge, its colour's alpha
    // at its darkest. So: range = spread + soft and a power of 2, with the alpha lowered by
    // (range / (1.4 × soft))² where Slate's never quite reaches full (as at the defaults); and
    // where Slate's stays full for a while (much spread, little softness) the power that's half
    // as dark at the same place (1 or 2: Hyprland takes whole numbers). Softness under 1 px is
    // a hard edge, Hyprland's sharp shadow, as wide as the spread. So is one whose solid part is
    // at least as long as its fade (spread ≥ 1.8 × softness: softness 1 and spread 3, say):
    // Slate's is a dark band with a short soft edge, half dark about at the spread, and
    // Hyprland's fade spread over the whole width looked far softer than the panels' and menus'
    readonly property var hyprShadow: {
        const S = shadowSpread, B = shadowReach, k = uiScale;
        const sharp = B < 1 || S >= 1.8 * B;
        const R = sharp ? S : S + B;
        const flat = sharp || R > 1.4 * B;
        const power = sharp ? 1 : !flat ? 2
            : Math.max(1, Math.min(2, Math.round(Math.log(0.5) / Math.log(1.4 * B / (Math.SQRT2 * R)))));
        // (with a distance, what shows most is the shape moved: Slate's is at full strength
        // there, and Hyprland's is its colour's alpha, so that stays full; lowered to match
        // the faint edge, Settings' shadow was half as dark as the panels')
        const moved = Math.abs(shadowDX) + Math.abs(shadowDY) > 0;
        const alpha = shadowStrength * (flat || moved ? 1 : Math.pow(R / (1.4 * B), 2));
        return {
            // (no spread or softness but a distance is still a shadow: the shape, moved; it was
            // switched off, and floating windows had none while panels and menus had one)
            on: shadowsOn && (R > 0 || Math.abs(shadowDX) + Math.abs(shadowDY) > 0),
            range: Math.max(1, Math.round(R * k)),
            power: power,
            sharp: sharp,
            offsetX: Math.round(shadowDX * k * 10) / 10,
            offsetY: Math.round(shadowDY * k * 10) / 10,
            colour: "rgba(" + shadowHex + Math.round(Math.max(0, Math.min(1, alpha)) * 255).toString(16).padStart(2, "0") + ")"
        };
    }

    // ---- Assistants (Settings → Assistant, docs/ASSISTANT.md) -------------------------------
    // On only when switched on *and* the risks, as they're written now, were accepted there:
    // setting assistantEnabled some other way switches nothing on. The number goes up when a
    // release changes what the risks are, and Slate asks again
    readonly property int assistantRisksVersion: 1
    readonly property bool assistantOn: s.assistantEnabled && s.assistantRisksAccepted === assistantRisksVersion && !isLoginScreen && !s.privateMode
    // Caffeine (a control centre quick switch): the screen stays on and unlocked while it's on.
    // Slate's own idle timers (lock, screen off, suspend, the screensaver) stand still for it
    // whatever Settings → Security → Wait while media plays says, since you asked; apps and
    // other tools hear it as a usual "stay awake" request too (Popouts.qml). Not kept over a
    // restart, so it can't be left on by mistake for days
    property bool caffeine: false
    // Something playing full screen: a media player (MPRIS) that's playing, and a window of the
    // same app that's full screen. Slate's idle timers wait for it as they do for an app that
    // asks the screen to stay awake, under the same switch (Settings → Security → Wait while
    // media plays): some players (Plezy, for one) say they're playing but never ask, and the
    // screensaver came on mid-episode. Full screen, so music playing in the background doesn't
    // keep the screen on. The timers leave it out while the screen is locked (LockScreen.qml)
    readonly property bool mediaFullscreen: !isLoginScreen && s.idleRespectInhibitors
        && playingFullscreen(Mpris.players.values, ToplevelManager.toplevels.values)
    // (the decision itself: players as MPRIS has them, windows as ToplevelManager has them.
    // A player names its app by desktopEntry or identity, a window by appId; they match
    // ignoring case and ".desktop", or by the last part of a reverse-DNS name
    // ("org.videolan.VLC" and "vlc")
    function playingFullscreen(players, windows) {
        const name = n => String(n || "").toLowerCase().replace(/\.desktop$/, "");
        const last = n => n.split(".").pop();
        const same = (a, b) => a !== "" && b !== "" && (a === b || last(a) === b || a === last(b));
        const playing = players.filter(p => p.isPlaying).map(p => [name(p.desktopEntry), name(p.identity)]);
        if (playing.length === 0) return false;
        return windows.some(w => w.fullscreen && playing.some(ns => ns.some(n => same(n, name(w.appId)))));
    }
    property bool assistantWorking: false       // Nova has a prompt out (Assistant.qml): the bar's button shows it

    // ---- The camera in use (scripts/camera-watch.py) -----------------------------------------
    // Whether any app has a camera open, and which (by name, where Slate can see them): the
    // pop-up says so as it changes (OSD.qml), and the menu bar's camera indicator shows it
    property bool cameraOn: false
    property var cameraApps: []
    Process {
        running: !root.isLoginScreen
        command: [Quickshell.shellPath("scripts/camera-watch.py")]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const e = JSON.parse(line);
                    root.cameraApps = e.apps || [];
                    root.cameraOn = !!e.on;
                } catch (err) {}
            }
        }
    }
    // Switched on under an earlier version of the risks: paused until they're read again
    readonly property bool assistantRisksChanged: s.assistantEnabled && s.assistantRisksAccepted > 0 && s.assistantRisksAccepted !== assistantRisksVersion

    // Change a setting from the command line, as the Settings window does:
    //   slate ipc call config set barPosition bottom      slate ipc call config get barPosition
    IpcHandler {
        target: "config"
        function set(key: string, value: string): void {
            const cur = root.s[key];
            if (cur === undefined) return;
            if (key === "barPosition") { root.moveBar(value); return; }
            if (key === "dockPosition") { root.moveDock(value); return; }
            const v = root.settingFromText(cur, value);
            if (v === undefined) return;
            root.s[key] = v;
            root.hyprKeyEdited(key, cur);
        }
        // (a list or an object as JSON, as set takes it back: as String() it came out as "" for an
        // empty list and "[object Object]" for App Rules' rules, so tests couldn't put one back)
        function get(key: string): string { const v = root.s[key]; return v !== null && typeof v === "object" ? JSON.stringify(v) : String(v); }
    }
    // What a setting given as text (config set) becomes, going by the kind of value it holds
    // now, or undefined when the text isn't one of those: the setting is then left alone. A
    // switch takes only "true" or "false", a number only a real number (not "abc", which would
    // be stored as NaN), and a list or an object only JSON for another of the same: stored as
    // plain text, every place that reads the list (themedApps.some(…)) would stop with an error.
    // (On the command line a list needs a space before it, ' ["a", "b"]': `qs ipc call` takes
    // an argument that starts with [ and ends with ] apart, as several of its own)
    function settingFromText(cur, text) {
        if (typeof cur === "boolean") return text === "true" ? true : text === "false" ? false : undefined;
        if (typeof cur === "number") {
            const n = Number(text);
            return String(text).trim() !== "" && isFinite(n) ? n : undefined;
        }
        if (cur !== null && typeof cur === "object") {
            const list = v => Array.isArray(v) || (v !== null && typeof v === "object" && typeof v.length === "number");
            let v;
            try { v = JSON.parse(text); } catch (e) { return undefined; }
            if (v === null || typeof v !== "object" || Array.isArray(v) !== list(cur)) return undefined;
            return v;
        }
        return text;
    }
    // A piece of text as Lua writes one, for anything spliced into Lua that Hyprland runs
    // (hyprctl eval / dispatch, displays.lua): in double quotes, with whatever would end the
    // string early or mean something else to Lua written as an escape. Always this, never
    // quotes or long brackets written round it by hand: a monitor's description, a folder's
    // name or a command can hold a quote, a backslash or a closing bracket, and the rest of it
    // would run as Lua. (\x22 is the double quote: a bare one in the pattern would read as the
    // start of a string to tools/check-greeter-files)
    function luaString(text) {
        const quote = "\x22";
        return quote + String(text).replace(/[\\\x22\x00-\x1f\x7f]/g, c =>
            c === "\\" || c === quote ? "\\" + c : "\\" + ("00" + c.charCodeAt(0)).slice(-3)) + quote;
    }

    // Lua for the command line that runs `argsLua` (a Lua string expression) in the default
    // terminal. Which flag a terminal wants (-e, --, start --...) is the session's one table,
    // TERMINAL_RUN (variables.lua; scripts/spaces.py writes the same); a Hyprland config
    // without it gets -e
    function inTerminalLua(argsLua) {
        return "(TERMINAL_RUN or function(a) return (TERMINAL or 'kitty') .. ' -e ' .. a end)(" + argsLua + ")";
    }
    // Runs a command line in the default terminal, as an app of its own (through uwsm, where the
    // session uses it): Nova's and Settings' Sign in
    function runInTerminal(cmd) {
        const lua = `function() hl.exec_cmd((os.getenv("UWSM_FINALIZE_VARNAMES") and "uwsm app -- " or "") .. ${inTerminalLua(luaString(cmd))}) end`;
        Quickshell.execDetached(["hyprctl", "dispatch", lua]);
    }

    // ---- App icon tint: 0 (off) to 1 (fully in the accent colour); see IconTint.qml
    readonly property real iconTint: s.tintIcons ? Math.max(0, Math.min(100, s.iconTintStrength)) / 100 : 0

    // ---- Workspace indicators: circles, or rounded squares (Settings → Appearance)
    function dotRadius(size) { return s.workspaceShape === "square" ? size * 0.28 : size / 2; }
    // ...and of what holds them, where that floats by itself (the indicator shown as you
    // switch, under the window switcher, in the overview): a pill round circles, a rounded
    // rectangle round squares
    function dotHolderRadius(height) { return corner(s.workspaceShape === "square" ? Math.min(12, height * 0.3) : height / 2); }

    // ---- Account picture ------------------------------------------------------------
    // AccountsService's picture for this user (shared with GNOME, KDE and the login
    // screen). Changing it keeps the same path, so avatarUrl carries a version number to
    // make images load the new one.
    readonly property string avatarPath: "/var/lib/AccountsService/icons/" + Quickshell.env("USER")
    property int avatarVersion: 0
    readonly property string avatarUrl: "file://" + avatarPath + "?v=" + avatarVersion
    property bool avatarBusy: false
    property string avatarError: ""
    function setAvatar(path) {
        if (avatarBusy || !path) return;
        avatarBusy = true;
        avatarError = "";
        path = String(path);
        if (path.startsWith("file://")) path = decodeURIComponent(path.slice(7));   // from a file dialog
        avatarProc.command = [Quickshell.shellPath("scripts/set-avatar.sh"), path];
        avatarProc.running = true;
    }
    Process {
        id: avatarProc
        stderr: StdioCollector { id: avatarErr }
        onExited: code => {
            root.avatarBusy = false;
            if (code === 0) root.avatarVersion++;
            else root.avatarError = avatarErr.text.trim().split("\n").pop() || "Slate couldn't change your picture";
        }
    }

    // ---- Where the bar and dock sit ------------------------------------------------
    readonly property bool barAtBottom: s.barPosition === "bottom"
    readonly property string barEdge: s.barPosition
    readonly property string dockEdge: s.dockPosition
    // The bar and dock never share an edge: moving one onto the other's edge sends the other
    // to the opposite edge. Both change in one step (Settings and `slate ipc call config set`
    // use these), because the settings store can undo a second change made while the first is
    // still being saved.
    function opposite(e) { return ({ top: "bottom", bottom: "top", left: "right", right: "left" })[e] || "bottom"; }
    function moveBar(v) {
        if (s.dockPosition === v) s.dockPosition = opposite(v);
        s.barPosition = v;
    }
    function moveDock(v) {
        if (s.barPosition === v) s.barPosition = opposite(v);
        s.dockPosition = v;
    }
    // After a hand edit of settings.json, or older settings with both at the bottom: the dock moves
    // The four edges, for a Position submenu (DesktopMenu.qml): the one in use ticked; `move`
    // is moveBar or moveDock
    function edgeMenu(current, move) {
        return ["top", "bottom", "left", "right"].map(e => ({
            label: e.charAt(0).toUpperCase() + e.slice(1), icon: e === current ? 0xEA5E : 0, run: () => move(e)
        }));
    }
    // A menu item ticked while a setting is on, and switching it when picked
    function tickItem(label, key) {
        return { label: label, icon: s[key] ? 0xEA5E : 0, run: () => s[key] = !s[key] };
    }
    // A pick-one submenu for a setting: [[value, label], …], the value in use ticked
    function choiceMenu(key, choices, fallback) {
        const cur = s[key] !== undefined && choices.some(c => c[0] === s[key]) ? s[key] : fallback;
        return choices.map(c => ({ label: c[1], icon: c[0] === cur ? 0xEA5E : 0, run: () => s[key] = c[0] }));
    }
    function separateBarAndDock() { if (s.dockPosition === s.barPosition) s.dockPosition = opposite(s.barPosition); }
    Component.onCompleted: {
        chargeLimitRefresh();       // (whether the battery has a charging limit, and if it's on)
        // Settings and the wallpaper's colours are in place before anything is drawn, so a
        // reload starts in the right colours rather than the defaults (see loadColourCache)
        const saved = file.text();
        titleBarStyleUnset = saved !== "" && saved.indexOf('"titleBarStyle"') < 0;
        // The dock's window previews: a delay of 0 used to mean "off"; now it means "at once",
        // and there's a switch. Settings from before the switch with 0 keep them off
        if (saved !== "" && saved.indexOf('"dockPreviews"') < 0 && s.dockPreviewDelay <= 0) {
            s.dockPreviews = false;
            s.dockPreviewDelay = defaults.dockPreviewDelay;
        }
        loadColourCache();
        Qt.callLater(separateBarAndDock);
        clickAvailable = effect("click") !== null;        // Slate's sounds, below
    }

    // ---- Light/dark by time of day (themeMode "auto") -------------------------------
    // Light from sunrise to sunset at Settings' location, else 07:00–19:00
    readonly property string themeMode: s.themeMode !== "" ? s.themeMode : (s.lightMode ? "light" : "dark")
    function setThemeMode(m) {
        s.themeMode = m;
        if (m !== "auto") s.lightMode = m === "light";
    }
    // Light mode isn't finished: moving off Dark asks first (Settings → Appearance, the welcome).
    // Remove this, and the questions, once it is
    // Two finished looks (Settings → Appearance → Preset, and the Welcome window's "Glass or
    // flat?"): what each sets
    readonly property var lookPresets: ({
        "Liquid Glass": {
            themeMode: "dark", colourStyle: "colourful", accentFromWallpaper: true, accentBoldness: 0.5, accent: "#8fb3e8",
            toneFromWallpaper: true, toneBoldness: 0.5,
            glass: true, glassOpacity: 0.7, glassBlur: 10, glassGloss: 1, glassGlossTint: 1, folderColour: "auto" },
        "Metro Flat": {
            themeMode: "dark", colourStyle: "colourful", accentFromWallpaper: true, accentBoldness: 0.4, accent: "#8fb3e8",
            toneFromWallpaper: true, toneBoldness: 0.5,
            glass: false, glassOpacity: 0.7, glassBlur: 10, glassGloss: 1, glassGlossTint: 1, folderColour: "auto" }
    })
    // One of them for its look alone: the theme (dark, light or auto) and the accent stay as
    // they are (the Welcome window, where those are chosen on the page before)
    function applyLook(name) {
        const p = lookPresets[name];
        if (!p) return;
        for (const k in p) if (k !== "themeMode" && k !== "accent" && k !== "accentFromWallpaper") s[k] = p[k];
    }
    readonly property bool lightModeAsks: true
    function lightModeQuestion(m) {
        return {
            title: m === "light" ? "Switch to light mode?" : "Use light mode by day?",
            body: "Light mode is still being polished, so a few parts may not look quite as good as they do in dark mode just yet. "
                + "You're welcome to switch back to Dark at any time.",
            button: m === "light" ? "Use Light" : "Use Auto"
        };
    }
    function lightHours(date) {
        if (s.locationName !== "") { const st = sunTimes(date); return { from: st.rise, to: st.set }; }
        return { from: 7 * 60, to: 19 * 60 };
    }
    function applyAutoTheme() {
        if (themeMode !== "auto") return;
        const now = new Date(), h = lightHours(now), t = now.getHours() * 60 + now.getMinutes();
        const light = t >= h.from && t < h.to;
        if (s.lightMode !== light) s.lightMode = light;
    }
    onThemeModeChanged: applyAutoTheme()
    Timer { interval: 60000; running: root.themeMode === "auto"; repeat: true; triggeredOnStart: true; onTriggered: root.applyAutoTheme() }

    // The wallpaper (Settings → Appearance, or ipc call wallpaper set <path>); drawn by Wallpaper.qml.
    // The login screen sets this to its own copy instead.
    onWallpaperChanged: refreshWallpaperAccent()
    // ---- Screens -------------------------------------------------------------
    // The screen with Hyprland's focus: launcher, switcher, overview and the like open there
    readonly property var focusedScreen: {
        const m = Hyprland.focusedMonitor;
        const all = Quickshell.screens;
        return (m && all.find(s => s.name === m.name)) || all[0] || null;
    }
    // The main display (Settings → Displays): its bar is the main one. Saved by the
    // monitor's description; the first screen when unset or not connected
    readonly property var primaryScreen: {
        const all = Quickshell.screens, d = s.mainDisplay;
        const m = d ? Hyprland.monitors.values.find(x => x.description === d || x.name === d) : null;
        return (m && all.find(x => x.name === m.name)) || all[0] || null;
    }
    // Every bar (one per screen) registers here, so commands can reach the focused one
    property var bars: []
    function barFor(screen) {
        return bars.find(b => b.screen && screen && b.screen.name === screen.name) || bars.find(b => b.primary) || null;
    }

    // ---- A fresh login ----------------------------------------------------------
    // Once per Hyprland session, not when Slate restarts within it: a marker in the runtime
    // folder, named after this Hyprland session, says Slate has already started. atLogin
    // fires a moment after Slate starts, once its settings have loaded (the wallpaper can
    // change, startup apps open).
    signal atLogin()
    // Back from sleep, or unlocked (LockScreen.qml): clocks that last read the time again.
    // Their minute tick is timed on a clock that stops while the computer sleeps, so after waking
    // the menu bar's showed the old time for up to a minute
    signal woke()
    property int wakes: 0                       // (the tests: how many times)
    onWoke: wakes++
    readonly property string loginMarker: root.runtimeDir + "/slate-started-"
        + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "session")
    Process {
        running: true
        command: ["sh", "-c", "[ -e \"$0\" ] && exit 1; touch \"$0\"", root.loginMarker]
        onExited: code => { if (code === 0) loginSettle.start(); }
    }
    Timer { id: loginSettle; interval: 2500; onTriggered: root.atLogin() }
    // Your apps from last time and the startup apps (Settings → Startup Apps). Apps kept as you
    // left (session.sh) come back with Always: spaces.py reopens them, back where they were, then
    // opens the startup apps, each on a workspace of its own, and returns to your last workspace.
    // With Ask, the startup apps open as usual and a notification offers the rest (Reopen / Not
    // now). Not on the login screen, which loads this file with a copy of your settings: there,
    // spaces.py isn't installed, so the check failed and every startup app was launched
    onAtLogin: if (!isLoginScreen && !testMode) {
        pickUpAtLogin();
        // Webcams forget their picture settings when unplugged or restarted: put yours back
        Quickshell.execDetached([Quickshell.shellPath("scripts/webcam.py"), "apply"]);
    }
    // "ask", "always" or "never" (the old restart switch, turned off, reads as never)
    readonly property string reopenMode: ["always", "never"].includes(s.reopenApps) ? s.reopenApps
        : s.reopenAppsAfterRestart === false ? "never" : "ask"
    function pickUpAtLogin() { reopenCheck.running = false; reopenCheck.running = true; }
    readonly property string spacesScript: Quickshell.shellPath("scripts/spaces.py")
    Process {
        id: reopenCheck
        command: ["python3", root.spacesScript, "session-pending"]
        onExited: code => {
            if (code === 0 && root.reopenMode === "always") {
                Quickshell.execDetached(["python3", root.spacesScript, "session-restore"].concat(root.s.startupApps || []));
                return;
            }
            if (code === 0 && root.reopenMode === "ask") { reopenAsk.running = false; reopenAsk.running = true; }
            else if (code === 0) Quickshell.execDetached(["python3", root.spacesScript, "session-forget"]);
            for (const id of (root.s.startupApps || [])) {
                const e = DesktopEntries.byId(id);
                if (e) e.execute();
            }
        }
    }
    // The question, as a notification that stays until it's answered (it waits for the quiet
    // spell after logging in, Notifications.qml). Reopen brings them back (the startup apps are
    // open already, and an app that's open isn't started twice); Not now forgets them. Closed
    // without an answer, they're kept, and replaced as you next leave
    readonly property string reopenTitle: "Pick up where you left off?"
    Process {
        id: reopenAsk
        command: ["notify-send", "--app-name=Slate", "--icon=" + Quickshell.shellPath("assets/icon/icon-64.png"),
            "--urgency=critical", "--hint=string:x-slate-page:startup", "--action=reopen=Reopen", "--action=later=Not now", "--wait",
            "--", root.reopenTitle,
            "Slate can open the apps you had last time, on the same workspaces and just where you left them. Nothing opens unless you say so."]
        stdout: StdioCollector {
            onStreamFinished: {
                const said = text.trim();
                if (said === "reopen") Quickshell.execDetached(["python3", root.spacesScript, "session-restore"]);
                else if (said === "later") Quickshell.execDetached(["python3", root.spacesScript, "session-forget"]);
            }
        }
    }

    // ---- Settings Hyprland applies (session/hypr/config/slate.lua) -----------------------
    // Only the ones changed in Settings; the rest stay as Hyprland's config has them
    function appCommand(id) {
        const e = id ? DesktopEntries.byId(id) : null;
        if (!e || !e.command || e.command.length === 0) return "";
        return e.command.filter(a => !/^%[a-zA-Z]$/.test(a))
            .map(a => /^[A-Za-z0-9_@%+=:,.\/-]+$/.test(a) ? a : "'" + a.replace(/'/g, "'\\''") + "'").join(" ");
    }
    // The main display's scale (Settings → Displays → Scale): what apps made for X11 are told to
    // draw at with Sharp older apps on (one scale for them all: they can't follow each display)
    readonly property real x11Scale: {
        const p = primaryScreen;
        const m = p ? Hyprland.monitors.values.find(x => x.name === p.name) : null;
        const o = m ? (m.lastIpcObject || {}) : {};
        return Number(o.scale || (m && m.scale) || 1) || 1;
    }
    readonly property string hyprSettings: {
        // (worked out again once the apps' entries have loaded: the default apps below are
        // looked up there, and before they'd loaded they came back empty and were left out,
        // so Hyprland kept its own first guess: Dolphin for folders, though Nautilus was chosen)
        DesktopEntries.applications.values;
        const t = [];
        const q = v => JSON.stringify(String(v));
        const onOff = v => v === "on" ? "true" : "false";
        if (s.kbLayouts !== "") t.push(`kb_layout = ${q(s.kbLayouts)}, kb_variant = ${q(s.kbVariants)}`);
        if (s.capsLock !== "" || s.kbSwitch !== "") {
            const opts = [];
            const caps = { ctrl: "caps:ctrl_modifier", escape: "caps:escape", super: "caps:super", off: "caps:none" }[s.capsLock];
            const sw = { alt_shift: "grp:alt_shift_toggle", ctrl_space: "grp:ctrl_space_toggle", caps: "grp:caps_toggle" }[s.kbSwitch];
            if (caps && !(sw === "grp:caps_toggle")) opts.push(caps);
            if (sw) opts.push(sw);
            t.push(`kb_options = ${q(opts.join(","))}`);
        }
        if (s.keyRepeatDelay > 0) t.push(`repeat_delay = ${s.keyRepeatDelay}`);
        if (s.keyRepeatRate > 0) t.push(`repeat_rate = ${s.keyRepeatRate}`);
        // Pointer speed: mice (the general setting) and touchpads (set on each, see slate.lua)
        if (s.mouseSpeed >= -1) t.push(`sensitivity = ${s.mouseSpeed.toFixed(2)}, tp_sensitivity = ${s.mouseSpeed.toFixed(2)}`);
        if (s.mouseAccel !== "") t.push(`accel_profile = ${q(s.mouseAccel)}`);
        if (s.mouseNaturalScroll !== "") t.push(`natural_scroll = ${onOff(s.mouseNaturalScroll)}`);
        if (s.touchpadScrollSpeed > 0) t.push(`tp_scroll = ${s.touchpadScrollSpeed.toFixed(2)}`);
        if (s.touchpadNaturalScroll !== "") t.push(`tp_natural_scroll = ${onOff(s.touchpadNaturalScroll)}`);
        if (s.touchpadTapToClick !== "") t.push(`tp_tap = ${onOff(s.touchpadTapToClick)}`);
        if (gameMode) t.push(`tp_dwt = false`);             // game mode: the touchpad works while you type
        else if (s.touchpadIgnoreWhileTyping !== "") t.push(`tp_dwt = ${onOff(s.touchpadIgnoreWhileTyping)}`);
        // Touchpad gestures (Settings → Input): always sent, as they're Slate's own (gestures.lua);
        // game mode leaves them on, as they're input like any other
        const gesture = v => q(["overview", "desktop", "launcher", "none"].includes(v) ? v : "none");
        const sideways = v => v === "workspace" ? q(v) : gesture(v);      // (left and right can switch workspace too)
        t.push(`gestures = { on = ${s.touchpadGestures ? "true" : "false"}, fingers = ${s.gestureFingers === 4 ? 4 : 3}, `
            + `left = ${sideways(s.gestureLeft)}, right = ${sideways(s.gestureRight)}, up = ${gesture(s.gestureUp)}, down = ${gesture(s.gestureDown)}, `
            + `pinchin = ${gesture(s.gesturePinchIn)}, pinchout = ${gesture(s.gesturePinchOut)} }`);
        // Focus: follows the pointer (1), or a click, with scrolling still reaching the window under it (2).
        // With Slate's own title bars, always a click (the setting's kept, and hidden meanwhile)
        if (clickToFocus) t.push(`follow_mouse = 2`);
        else if (s.focusFollowsMouse !== "") t.push(`follow_mouse = ${s.focusFollowsMouse === "on" ? 1 : 2}`);
        if (s.cursorSize > 0) t.push(`cursor_size = ${s.cursorSize}`);
        // ("" = the session's own: Slate's, or yours from hypr/variables.lua)
        t.push(`cursor_theme = ${q(/^[\w.+-]+$/.test(s.cursorTheme) ? s.cursorTheme : "")}`);
        // (and whether GNOME's own pointer settings follow: Settings → Input → Pointer in your apps)
        t.push(`cursor_in_apps = ${s.pointerInApps ? "true" : "false"}`);
        if (gameMode) t.push(`animations = "off"`);          // game mode: no animations
        else if (s.animations !== "") t.push(`animations = ${q(s.animations)}`);
        const apps = { terminal: s.defaultTerminal, browser: s.defaultBrowser, file_manager: s.defaultFileManager,
                       editor: s.defaultEditor, calculator: s.defaultCalculator };
        for (const k in apps) { const c = appCommand(apps[k]); if (c) t.push(`${k} = ${q(c)}`); }
        t.push(`lid_action = ${q(s.lidAction)}, power_key_action = ${q(s.powerKeyAction)}`);
        // Sharp older apps (Settings → Displays): X11 apps drawn at the screen's own pixels, and
        // told the main display's scale to draw themselves at (slate.lua)
        t.push(`sharp_x11 = ${s.sharpX11Apps ? "true" : "false"}, x11_scale = ${x11Scale.toFixed(2)}`);
        // Set directly (not through slateApply), so a Hyprland config of your own can read it too
        return `if slateApply then slateApply({ ${t.join(", ")} }) end; WRAP_WORKSPACES = ${s.wrapWorkspaces ? "true" : "false"}; `
            // The drop-down terminal's height (Settings → Windows): placed again, if it's open
            + `DROPDOWN_HEIGHT = ${(Math.max(20, Math.min(90, s.dropdownHeight)) / 100).toFixed(2)}; if placeDropdown then placeDropdown() end; `
            + appRulesLua
            + `if setWorkspaceAnimation then setWorkspaceAnimation(${q(s.workspaceAnimation || "slidefade")}) end; `
            // Accessibility → Zoom (binds.lua's setZoom; the keys tell Slate where they got to)
            + `if setZoom then setZoom(${s.zoom ? "true" : "false"}, ${Math.max(1.25, Math.min(5, Number(s.zoomLevel) || 2)).toFixed(2)}, ${s.zoomFollow === "center" ? "true" : "false"}) end; `
            // Accessibility → Reduce motion: windows and workspaces only fade (animations.lua)
            + `if setReduceMotion then setReduceMotion(${s.reduceMotion ? "true" : "false"}) end; `
            // Glass: blur behind Slate's surfaces, from just under their own opacity (glassCut).
            // One rule for most, one each for the dock and the menu bar, whose backgrounds have
            // an opacity of their own (Settings → Dock, → Menu Bar). Each is made once, and made
            // again when its opacity changes; then switched on or off
            + glassRules
            + `SLATE_GLASS_V = 3`
            + (glass && s.glassBlur > 0 ? `; hl.config({ decoration = { blur = { size = ${Math.round(s.glassBlur)} } } })` : "")
            // Rounded UI elements off: windows are square too. (Put back to the config's own
            // rounding, 10, only if Slate was what squared them)
            + (s.roundedElements ? `; if SLATE_SQUARED then SLATE_SQUARED = nil; hl.config({ decoration = { rounding = SLATE_ROUNDING or 10 } }) end`
                                 : `; SLATE_SQUARED = true; hl.config({ decoration = { rounding = 0 } })`)
            // Blur (Settings → Appearance → Blur): only the wallpaper (fast), and how many passes
            + `; hl.config({ decoration = { blur = { xray = ${s.fastBlur ? "true" : "false"} } } })`
            + (s.blurPasses > 0 ? `; hl.config({ decoration = { blur = { passes = ${Math.round(s.blurPasses)} } } })` : "")
            // Floating windows' shadows: Slate's one shadow, drawn by Hyprland (hyprShadow: the
            // same colour, darkness, softness, spread, distance and direction), or none
            // (Settings → Appearance → Shadows, game mode)
            + `; hl.config({ decoration = { shadow = { enabled = ${hyprShadow.on ? "true" : "false"}, range = ${hyprShadow.range}, render_power = ${hyprShadow.power}, sharp = ${hyprShadow.sharp ? "true" : "false"}, offset = { ${hyprShadow.offsetX}, ${hyprShadow.offsetY} }, color = "${hyprShadow.colour}" } } })`
            // Game mode: no blur or shadows behind anything, and every window fully opaque
            + (gameMode ? `; hl.config({ decoration = { blur = { enabled = false }, shadow = { enabled = false }, active_opacity = 1, inactive_opacity = 1 } })` : "")
            // Accessibility → Reduce transparency: no blur, every window fully opaque (shadows stay)
            + (s.reduceTransparency && !gameMode ? `; hl.config({ decoration = { blur = { enabled = false }, active_opacity = 1, inactive_opacity = 1 } })` : "")
            // ...terminals too, which draw their own see-through background (kitty's
            // background_opacity): with the blur gone that showed the bare wallpaper. Only
            // terminals: apps drawing their own rounded corners or shadows would turn them black.
            // Which windows are terminals is the session's one list, TERMINAL_CLASSES
            // (session/hypr/config/variables.lua), read here in Lua rather than listed again:
            // the rule is made once, and made again if that list changes. Under a Hyprland
            // config that isn't Slate's there's no list, and no rule
            + `; if SLATE_GAME_OPAQUE and SLATE_GAME_OPAQUE_FOR ~= TERMINAL_CLASSES then SLATE_GAME_OPAQUE:set_enabled(false); SLATE_GAME_OPAQUE = nil end; `
            + `if TERMINAL_CLASSES and not SLATE_GAME_OPAQUE then SLATE_GAME_OPAQUE_FOR = TERMINAL_CLASSES; SLATE_GAME_OPAQUE = hl.window_rule({ name = "slate-game-opaque", match = { class = "^(" .. TERMINAL_CLASSES .. ")$" }, force_rgbx = true }) end; `
            + `if SLATE_GAME_OPAQUE then SLATE_GAME_OPAQUE:set_enabled(${gameMode || s.reduceTransparency ? "true" : "false"}) end`;
    }
    onHyprSettingsChanged: hyprPush.restart()
    // The blur rules alone, sent straight away when one changes (an opacity slider being
    // dragged): waiting with the rest left the blur a step behind the surface, gone or wrong
    // for a moment
    readonly property string glassRules: ""
        + glassRule("SLATE_GLASS", "^slate-(bar-editor|bar-label|dock-previews|picker|switcher|tray-menu|desktop-menu|confirm|polkit|osd|welcome|quicklook)$", glassCut)
        + glassRule("SLATE_GLASS_DOCK", "^slate-dock$", dockGlassCut, s.dockBlur)
        + glassRule("SLATE_GLASS_BAR", "^slate-bar$", barGlassCut, s.barBlur && !barArranging)
        // (the panels that come out of the bar: an opacity and a blur of their own too)
        + glassRule("SLATE_GLASS_PANEL", "^slate-popout$", panelGlassCut, s.barPanelBlur)
        // (notifications as they pop up: the same again, Settings → Notifications → Glass)
        + glassRule("SLATE_GLASS_TOAST", "^slate-notifications$", toastGlassCut, s.notificationBlur)
        // (the launcher: Settings → Launcher → Glass)
        + glassRule("SLATE_GLASS_LAUNCHER", "^slate-launcher$", launcherGlassCut, s.launcherBlur)
        // (Nova's window, a real window: blurred behind as every window is, unless Settings →
        // Assistant → Glass's blur is off. Its old layer's rule, named for Nova's old name,
        // Chalk, is let go in a Hyprland that still has it)
        + `if SLATE_GLASS_CHALK then SLATE_GLASS_CHALK:set_enabled(false); SLATE_GLASS_CHALK = nil end; `
        + `if not SLATE_NOVA_NO_BLUR then SLATE_NOVA_NO_BLUR = hl.window_rule({ name = "slate-nova-no-blur", match = { class = "^(slate-settings)$", title = "^(${novaTitle})$" }, no_blur = true }) end; `
        + `SLATE_NOVA_NO_BLUR:set_enabled(${glass && s.assistantBlur ? "false" : "true"}); `
    onGlassRulesChanged: if (!glassPush.running) glassPush.start()
    Timer { id: glassPush; interval: 16; onTriggered: Quickshell.execDetached(["hyprctl", "eval", root.glassRules]) }
    Timer {
        id: hyprPush; interval: 400; running: true
        onTriggered: {
            // While the wallpaper switcher shows wallpapers, nothing reaches Hyprland (as with
            // the borders and the theme: UpdateHold.qml's heldBack); one push goes when it closes
            if (root.wallpaperSwitching) { root.hyprPushHeld = true; return; }
            root.hyprPushHeld = false;
            // (under the tests, each push is counted and Hyprland keeps the count, so a test can
            // tell the settings have arrived: testHypr())
            if (root.testMode) root.testPushes++;
            Quickshell.execDetached(["hyprctl", "eval", root.hyprSettings + (root.testMode ? `; SLATE_TEST_PUSHES = ${root.testPushes}` : "")]);
            if (root.blurOverride) root.blurOverridden = true;
            // The blur is read back only when something that sets it has changed since the last
            // reading (a reload of Hyprland's config reads it too: the events handler below).
            // Every push used to start a shell and five hyprctl calls
            if (root.blurInputs !== root.blurReadFor) { root.blurReadFor = root.blurInputs; blurLater.restart(); }
        }
    }
    property bool hyprPushHeld: false
    // What hyprSettings sets about the blur, and what it was when the blur was last read
    readonly property string blurInputs: [glass && s.glassBlur > 0 ? Math.round(s.glassBlur) : 0, s.fastBlur, s.blurPasses > 0 ? Math.round(s.blurPasses) : 0, gameMode].join()
    property string blurReadFor: ""
    property int testBlurReads: 0       // (tests: how many times Hyprland's blur was read)
    // Test mode: Slate's settings on their way to Hyprland (busy: a push or a reading back of
    // Hyprland's blur or rounding still to come), how many pushes have gone (Hyprland's
    // SLATE_TEST_PUSHES matches once the last has arrived), and the rounding Slate read back
    property int testPushes: 0
    function testHypr() {
        return { busy: hyprPush.running || hyprPushHeld || blurLater.running || blurProc.running || roundingLater.running || roundingProc.running,
                 pushes: testPushes, rounding: windowRounding, blurReads: testBlurReads, kbReads: testKbReads };
    }
    // ---- Hyprland's events -------------------------------------------------------------
    // One handler for all of Config's (Hyprland sends many events a second while windows move),
    // and hyprConfigReloaded for the rest of Slate, so other files needn't each look at every event
    signal hyprConfigReloaded()
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "activelayout":                 // the keyboard layout switched
                kbActiveLater.restart();
                break;
            case "activespecial": {              // a secret workspace shown or hidden: "special:name,monitor"
                const i = event.data.lastIndexOf(",");
                const o = Object.assign({}, root.specialOpen);
                o[event.data.slice(i + 1)] = event.data.slice(0, i);
                root.specialOpen = o;
                // (and where the windows are, read again from Hyprland, should an event ever be missed)
                if (event.data.slice(0, i) !== "") { secretWindowsRead.running = false; secretWindowsRead.running = true; }
                break;
            }
            // Which window is on which secret workspace (see secretWindows below)
            case "openwindow": {                 // "address,workspace name,class,title"
                const p = event.data.split(",");
                root.secretWindowMoved(p[0], p[1]);
                break;
            }
            case "movewindowv2": {               // "address,workspace id,workspace name"
                const p = event.data.split(",");
                root.secretWindowMoved(p[0], p.slice(2).join(","));
                break;
            }
            case "closewindow":                  // "address"
                root.secretWindowMoved(event.data, "");
                break;
            case "destroyworkspacev2": {         // a workspace is gone ("id,name"): so is its name
                const gone = event.data.split(",")[0];
                if (root.workspaceNames[gone] !== undefined) {
                    const m = Object.assign({}, root.workspaceNames);
                    delete m[gone];
                    root.saveWorkspaceNames(m);
                }
                break;
            }
            case "configreloaded":               // Hyprland reloaded: settings it lost go back
                hyprPush.restart();
                kbLater.restart();
                blurLater.restart();
                roundingProc.running = false; roundingProc.running = true;
                root.hyprConfigReloaded();
                break;
            }
        }
    }

    // ---- The secret (special) workspace: which is showing on each monitor ("" = hidden) ----
    // From Hyprland's events (above); for the launcher (apps open there while it shows) and
    // the note that says it's empty (SecretEmpty.qml)
    property var specialOpen: ({})
    // The windows on secret workspaces, by address: kept from Hyprland's own events, not from
    // Quickshell's list of windows, which could keep a window closed just as its secret workspace
    // was put away, so the note never said it was empty
    property var secretWindows: ({})
    function secretWindowMoved(address, workspace) {
        const a = String(address).replace(/^0x/, "");
        const on = String(workspace).startsWith("special");
        if (on === (secretWindows[a] !== undefined) && (!on || secretWindows[a] === workspace)) return;
        const m = Object.assign({}, secretWindows);
        if (on) m[a] = workspace; else delete m[a];
        secretWindows = m;
        if (secretWindowsRead.running) secretTouched[a] = true;
    }
    property var secretTouched: ({})        // (windows an event moved while the list was being read)
    Process {
        id: secretWindowsRead
        running: true
        command: ["hyprctl", "clients", "-j"]
        onRunningChanged: if (running) root.secretTouched = ({})
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const m = {};
                    for (const c of JSON.parse(text))
                        if (c.workspace && String(c.workspace.name).startsWith("special")) m[String(c.address).replace(/^0x/, "")] = c.workspace.name;
                    // (what an event said while this was being read is newer than the list)
                    for (const a in root.secretTouched) {
                        if (root.secretWindows[a] !== undefined) m[a] = root.secretWindows[a]; else delete m[a];
                    }
                    root.secretWindows = m;
                } catch (e) {}
            }
        }
    }
    // Showing on this monitor, with no windows on it
    function secretEmpty(monitor) {
        const name = specialOpen[monitor] || "";
        if (name === "") return false;
        for (const a in secretWindows) if (secretWindows[a] === name) return false;
        return true;
    }
    Process {
        // Already showing when Slate starts
        running: true
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = {};
                    for (const m of JSON.parse(text)) o[m.name] = (m.specialWorkspace && m.specialWorkspace.name) || "";
                    root.specialOpen = o;
                } catch (e) {}
            }
        }
    }

    // ---- Keyboard layouts (for the menu bar's switcher) ---------------------------------
    // The layouts in use (set in Settings → Input, or Hyprland's own config), their
    // names, and which one is active (Hyprland's activelayout event says when it changes)
    property var xkbNames: ({})
    property string hyprLayouts: ""
    property string hyprVariants: ""
    readonly property var kbLayoutList: {
        const set = s.kbLayouts !== "";
        const ls = (set ? s.kbLayouts : hyprLayouts).split(",");
        const vs = (set ? s.kbVariants : hyprVariants).split(",");
        return ls.map(l => l.trim()).filter(l => l !== "").map((l, i) => {
            const v = (vs[i] || "").trim();
            const key = v ? l + ":" + v : l;
            return { layout: l, variant: v, name: xkbNames[key] || xkbNames[l] || key, code: l.toUpperCase() };
        });
    }
    property int kbActive: 0
    function switchLayout(i) {
        const n = kbLayoutList.length;
        if (n < 2) return;
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", String(((i % n) + n) % n)]);
    }
    property int testKbReads: 0         // (tests: how many times the layouts were read from Hyprland)
    function refreshKeyboard() { if (testMode) testKbReads++; kbState.running = false; kbState.running = true; kbOptions.running = false; kbOptions.running = true; }
    Process {
        id: kbState
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const k = JSON.parse(text).keyboards.find(k => k.main);
                    if (k && k.active_layout_index !== undefined) root.kbActive = k.active_layout_index;
                } catch (e) {}
            }
        }
    }
    Process {
        id: kbOptions
        running: true
        command: [Quickshell.shellPath("scripts/hypr-options.py"), "input:kb_layout", "input:kb_variant"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const o = JSON.parse(text); root.hyprLayouts = o["input:kb_layout"] || "us"; root.hyprVariants = o["input:kb_variant"] || ""; } catch (e) {}
            }
        }
    }
    Process {
        running: true
        command: [Quickshell.shellPath("scripts/xkb-layouts.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const m = {}; for (const o of JSON.parse(text)) m[o.value] = o.label; root.xkbNames = m; } catch (e) {}
            }
        }
    }
    // Everything again when the layouts themselves may have changed (yours, or Hyprland's config
    // reloading); on a switch between layouts, only which one is active (the layout list doesn't
    // change, so hypr-options.py needn't run on every switch)
    Timer { id: kbLater; interval: 400; onTriggered: root.refreshKeyboard() }
    Timer { id: kbActiveLater; interval: 400; onTriggered: { kbState.running = false; kbState.running = true; } }
    // Started by what the layouts come from: yours (set in Settings) and Hyprland's reload (the
    // events handler above). Not by kbLayoutList, which reading them changes itself
    Connections {
        target: root.s
        function onKbLayoutsChanged() { kbLater.restart(); }
        function onKbVariantsChanged() { kbLater.restart(); }
    }

    // ---- Lid and power button (Settings → Power) --------------------------------------
    // ---- What this computer can do (bin/slate-init info) -----------------------------------
    // Slate runs with systemd, and without it where elogind is (Artix, Void, Gentoo…). With
    // neither (seatd alone, say) it still runs, but nothing can suspend, restart or shut down
    // for it, tell it the computer's about to sleep, or hold the lid and power button: those
    // are left out, or shown greyed with why. Assumed all there until slate-init has answered
    // (and on the login screen, which doesn't ask).
    property var system: ({ init: "systemd", logind: "systemd", suspend: "yes", power: "yes", inhibit: "yes", timedate: "yes" })
    readonly property bool canSuspend: system.suspend !== "no"
    readonly property bool canPowerOff: system.power !== "no"          // restart and shut down
    readonly property bool canInhibit: system.inhibit !== "no"         // hold sleep, the lid, the power button
    readonly property bool hasLogind: system.logind !== "none"         // told when the computer's about to sleep
    Process {
        // (not in the tests: their container has no init system, and they say what they want
        // through the `test` IPC target)
        running: !root.isLoginScreen && !root.testMode
        command: [Quickshell.shellPath("bin/slate-init"), "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const line of text.split("\n")) { const i = line.indexOf("="); if (i > 0) o[line.slice(0, i)] = line.slice(i + 1).trim(); }
                if (o.init) root.system = o;
            }
        }
    }

    // When an action is chosen, the system's own handling (logind) is held back while Slate
    // runs, and Hyprland does the action (slate.lua). Restarted when the choice changes.
    readonly property string inhibitWhat: [s.lidAction !== "" ? "handle-lid-switch" : "", s.powerKeyAction !== "" ? "handle-power-key" : ""]
        .filter(x => x !== "").join(":")
    onInhibitWhatChanged: { inhibitor.running = false; inhibitRestart.restart(); }
    // Not on the login screen: nothing there does the action, so holding the system's own handling
    // back left the lid (or power button) doing nothing
    Timer { id: inhibitRestart; interval: 200; onTriggered: inhibitor.running = root.inhibitWhat !== "" && !root.isLoginScreen && root.canInhibit }
    onCanInhibitChanged: inhibitRestart.restart()
    Process {
        id: inhibitor
        running: false
        command: [Quickshell.shellPath("bin/slate-init"), "inhibit", "--what=" + root.inhibitWhat, "--who=Slate", "--why=Slate handles the lid and power button (Settings → Power)",
                  "--mode=block", "sleep", "infinity"]
    }

    // ---- Power profile on battery / plugged in (Settings → Power) ------------------------
    // Set when the power source changes (and as Slate starts); changing it by hand afterwards
    // sticks until the next change
    function applyPowerProfile() {
        const want = UPower.onBattery ? s.profileOnBattery : s.profileOnAC;
        const p = { "power-saver": PowerProfile.PowerSaver, "balanced": PowerProfile.Balanced, "performance": PowerProfile.Performance }[want];
        if (p === undefined) return;
        if (p === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile) return;
        PowerProfiles.profile = p;
    }
    Connections {
        target: UPower
        function onOnBatteryChanged() { root.applyPowerProfile(); }
    }
    Timer { interval: 3000; running: true; onTriggered: root.applyPowerProfile() }

    // ---- App icons ----------------------------------------------------------------
    // Drawn by scripts/appicon.py in the shape and style from Settings → Appearance → App
    // icons, and cached per style (the default keeps the original folder)
    readonly property string tileScript: Quickshell.shellPath("scripts/appicon.py")
    // The tile behind icons that don't fill their shape (IconPlate.qml): slate, following the theme;
    // with glass, solid with the frosting over it (frostedTile)
    readonly property color iconPlateColor: frostedTile(tint("#2a313c"))
    // Tiles with glass (behind app icons everywhere, and the dock's own buttons): the tile's own
    // colour, solid, with the frosting over it (as one colour), so icons sit on something
    // rather than on a faint film
    function frostedTile(c) {
        c = Qt.lighter(c, 1.0);
        if (!glass) return c;
        const f = raised(c);
        const mix = (x, y) => x * (1 - f.a) + y * f.a;
        return Qt.rgba(mix(c.r, f.r), mix(c.g, f.g), mix(c.b, f.b), 1);
    }
    // The icon theme: the one chosen in Settings → Icons → Icon theme ("" = this computer's)
    readonly property string iconThemeChosen: /^[\w.+-]+$/.test(s.iconTheme) ? s.iconTheme : ""
    // ...and the one actually in use, which the tiles are drawn from: the chosen one, else what
    // GTK apps use (read from gtk-3.0/settings.ini, so a theme set outside Slate counts too;
    // Slate's folder-colour theme counts as the theme it's made from)
    // The command that shows a notice from Slate (run it with Quickshell.execDetached, or as a
    // Process command when an action's answer is read back). `opts`: page (the Settings page
    // that opens when it's clicked), urgent (critical: it stays up), actions (["id=Label", ...],
    // the answer is printed on stdout), icon (a name or path; Slate's own by default). The "--"
    // keeps a title or text that starts with a dash from being taken for an option
    function notify(title, body, opts) {
        const o = opts || {};
        let c = ["notify-send", "--app-name=Slate", "--icon=" + (o.icon || Quickshell.shellPath("assets/icon/icon-64.png"))];
        if (o.urgent) c.push("--urgency=critical");
        if (o.page) c.push("--hint=string:x-slate-page:" + o.page);
        for (const a of (o.actions || [])) c.push("--action=" + a);
        if (o.wait) c.push("--wait");          // (stays running until it's clicked or closed: actions answer on stdout)
        return c.concat(["--", title, body]);
    }
    // A size in bytes in words: "1.2 GB", "340 MB", "1.5 TB" (as the battery panel's free space)
    function bytesText(bytes) {
        const g = bytes / 1e9;
        if (g >= 1000) return (g / 1000).toFixed(1) + " TB";
        if (g >= 100) return Math.round(g) + " GB";
        if (g >= 1) return g.toFixed(1) + " GB";
        const m = bytes / 1e6;
        return m >= 1 ? Math.round(m) + " MB" : bytes > 0 ? "Under 1 MB" : "Nothing";
    }
    // "2 min ago", worded as on notifications ("now", then a date after a day). `t` is in
    // milliseconds. `wordy` is the clipboard's wording instead: "Just now", and "Yesterday" /
    // "3 days ago" rather than a date
    function ago(t, wordy) {
        const s = Math.max(0, wordy ? Math.floor((Date.now() - t) / 1000) : (Date.now() - t) / 1000);
        if (s < 60) return wordy ? "Just now" : "now";
        if (s < 3600) return Math.floor(s / 60) + " min ago";
        if (s < 86400) return Math.floor(s / 3600) + " h ago";
        if (!wordy) return root.dateText(new Date(t), "day");
        const d = Math.floor(s / 86400);
        return d === 1 ? "Yesterday" : d + " days ago";
    }
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    // Your own Slate files: settings.json, hypr/ (your Hyprland tweaks) and user/ (your own QML).
    // Always here, wherever Slate's code is: in this same folder for an install of your own (or
    // ~/.config/slate linked to a checkout), or apart from it when Slate is installed once for
    // everyone on the computer (/usr/local/share/slate). The login screen has none: its copy of
    // your settings is next to its code (slate-greeter-install)
    readonly property string userDir: configHome + "/slate"
    // The login screen: the folder of the look of the person chosen on it (greeter/shell.qml), or
    // "" for the shared look next to its code
    property string loginLook: ""
    onLoginLookChanged: Qt.callLater(() => file.reload())
    // Where Slate keeps its saved state and its cache (XDG_STATE_HOME / XDG_CACHE_HOME). Two
    // paths still use ~/.local/state and ~/.cache directly on purpose: the dock's dock.json
    // (shell.qml), the tiles (tileDir below), the notifications history, the launcher's list and
    // the night light's shader. For anyone who sets those variables, moving them would lose
    // their saved state, so they keep resolving exactly as they always have
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"
    FileView { id: gtkSettingsFile; path: root.isLoginScreen ? "" : root.configHome + "/gtk-3.0/settings.ini"; watchChanges: true; printErrors: false; onFileChanged: reload() }
    FileView { id: slateIconsFile; path: root.isLoginScreen ? "" : root.dataHome + "/icons/Slate-Icons/index.theme"; watchChanges: true; printErrors: false; onFileChanged: reload() }
    function iniValue(text, key) {
        const m = String(text || "").match(new RegExp("^\\s*" + key + "\\s*=\\s*(.*?)\\s*$", "m"));
        return m ? m[1] : "";
    }
    readonly property string gtkIconTheme: {
        const t = iniValue(gtkSettingsFile.text(), "gtk-icon-theme-name");
        return t === "Slate-Icons" ? (iniValue(slateIconsFile.text(), "X-Slate-Base") || "Papirus-Dark") : t;
    }
    readonly property string iconThemeInUse: iconThemeChosen !== "" ? iconThemeChosen
        : (/^[\w.+-]+$/.test(gtkIconTheme) ? gtkIconTheme : "")
    // Each theme's tiles have folders of their own, tiles/themes/<theme>/<style>: drawn from it
    // alone (tiles from two themes never mix), and kept, so switching back is instant
    // (~/.cache on purpose, not cacheHome: the tiles stay where they have always been)
    readonly property string tileDir: Quickshell.env("HOME") + "/.cache/slate/tiles"
        + (iconThemeInUse !== ""
            ? "/themes/" + iconThemeInUse + "/" + s.iconShape + (s.iconFill ? "" : "-whole")
            : (s.iconShape === "tile" && s.iconFill ? "" : "/" + s.iconShape + (s.iconFill ? "" : "-whole")))
    readonly property var tileStyle: ["--shape", s.iconShape, s.iconFill ? "--fill" : "--whole"]
        .concat(iconThemeInUse !== "" ? ["--theme", iconThemeInUse] : [])
    // Command to draw one app's icon: tileCommand(app id or class, file). Built from the
    // settings themselves, not tileStyle: right after a change tileStyle can still hold the
    // old style while the file is already in the new style's folder (the script also goes
    // by the folder, so the two can't disagree)
    function tileCommand(app, path) {
        return [tileScript, "--tile", app, path, "192", "--shape", s.iconShape, s.iconFill ? "--fill" : "--whole"]
            .concat(iconThemeInUse !== "" ? ["--theme", iconThemeInUse] : []);
    }
    // How rounded an app icon's corners are at a given size (Settings → Icons → App icons),
    // for things drawn to match it, like a sheen on the tile
    function iconCornerFor(size) {
        const shape = s.iconShape;
        return shape === "circle" ? size / 2 : shape === "square" ? 0 : shape === "squircle" ? size * 0.3 : size * 0.225;
    }
    // Where an app's drawn icon lives: tilePath(app id, class or window key). Characters a file
    // name can't safely hold become "_", the same way scripts/appicon.py names them.
    function tilePath(key) { return tileDir + "/" + String(key).replace(/[^A-Za-z0-9._-]/g, "_") + ".png"; }

    // ---- Slate's own commands (bin/slate) -------------------------------------------
    readonly property string slateCommand: Quickshell.shellPath("bin/slate")
    // Call one of Slate's IPC functions, as `slate ipc call <target> <function> [args…]` does
    // (slate ipc show lists them): slateCall("settings", "page", "updates")
    function slateCall(...args) { Quickshell.execDetached([slateCommand, "ipc", "call", ...args]); }
    // Restart Slate completely (for changes it can only pick up that way), then open Settings
    // on a page again once it's back. Run detached, as this Slate is about to stop
    // Settings → Debug → Reload everything: Hyprland's config, then Slate itself as a new
    // process (not the in-place reload), back on the Debug page
    function reloadEverything() {
        reloadHyprland();
        restartToPage("debug");
    }
    // Reload Slate in place, the gentle way: through `slate restart`, which fades the screen to
    // "Reloading Slate" and back (bin/slate, reloading/shell.qml). Everything in Slate that
    // reloads it goes through here, not Quickshell.reload itself. Detached: this Slate's
    // windows are about to go
    function restartSlate() { Quickshell.execDetached(["setsid", "-f", slateCommand, "restart"]); }
    function restartToPage(page) {
        Quickshell.execDetached(["setsid", "-f", "sh", "-c",
            `sleep 0.5; "$0" restart --full; for i in $(seq 40); do sleep 0.25; "$0" ipc call settings page "$1" >/dev/null 2>&1 && break; done`,
            slateCommand, page]);
    }

    // ---- Live window previews ------------------------------------------------------
    // Hyprland dims windows without focus (Settings → Windows → Dim inactive windows), and the
    // live pictures of them come out dimmed too. Previews (shaders/preview.frag, through
    // PreviewShape) brighten them back by this much: 1 for the focused window and for Settings
    // (which is never dimmed), 1 / (1 - dim) for the rest
    readonly property real inactiveDim: Math.max(0, Math.min(80, s.inactiveDim)) / 100
    function undimGain(active, appClass) {
        return active || inactiveDim <= 0 || appClass === "slate-settings" ? 1 : 1 / (1 - inactiveDim);
    }

    // ---- App entries ---------------------------------------------------------------
    // The installed app (.desktop entry) for a window's app ID, as the dock, bar, switcher and
    // overview show it. Hyprland's app IDs don't always match an entry's name, so this tries,
    // in turn: the exact entry, Quickshell's best guess (the class, a looser match), and an
    // entry sharing its reverse-domain prefix (org.godotengine.Editor -> org.godotengine.Godot).
    // Results are remembered until the installed apps change, since the same few IDs are
    // looked up over and over (the dock does it for every window, every time one opens).
    property int appsVersion: 0
    // (one object, changed inside but never replaced, so bindings that look things up don't
    // re-run when the memo fills in; they re-run when appsVersion goes up)
    readonly property var appEntryMemo: ({ version: -1, entries: {} })
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.appsVersion++; }
    }
    function appEntry(appId) {
        if (!appId) return null;
        // (read here so a binding that calls this runs again when apps are installed or removed)
        const memo = appEntryMemo;
        if (memo.version !== appsVersion) { memo.entries = {}; memo.version = appsVersion; }
        if (appId in memo.entries) return memo.entries[appId];
        let e = DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId);
        if (!e) {
            const parts = appId.toLowerCase().split(".");
            if (parts.length >= 3) {
                const prefix = parts.slice(0, 2).join(".") + ".";
                e = DesktopEntries.applications.values.find(a => a.id.toLowerCase().startsWith(prefix)) ?? null;
            }
        }
        memo.entries[appId] = e ?? null;
        return memo.entries[appId];
    }
    // Changing the style draws every installed app's icon in it, in the background (and at
    // startup, any that are missing); tileVersion goes up when that's done, to reload images
    property int tileVersion: 0
    onTileDirChanged: tileAll.restart()
    // (not on the login screen, which has neither the script nor any use for the tiles)
    Timer { id: tileAll; interval: 600; running: !root.isLoginScreen; onTriggered: { if (root.isLoginScreen) return; tileAllRun.running = false; tileAllRun.running = true; } }
    Process {
        id: tileAllRun
        command: [root.tileScript, "--tile-all", root.tileDir, "192"].concat(root.tileStyle)
        onExited: { root.tileVersion++; if (root.iconColoursWanted) iconColoursSoon.restart(); }
    }

    // ---- Tiles in each icon's colour (Settings → Icons → App icons) ------------------
    // appicon.py --colours notes each drawn icon's main colour (colours.json in the tiles
    // folder); the tile behind an icon (IconPlate.qml) then takes a deep shade of it
    readonly property string iconColoursPath: tileDir + "/colours.json"
    // Wanted for coloured tiles, and for the dock's glow (Settings → Dock → Hover effect)
    readonly property bool iconColoursWanted: s.iconTileColour || s.dockHoverEffect === "glow" || s.dockHoverEffect === "glowmagnify"
    property var iconColours: ({})                 // icon file name → "#rrggbb"
    FileView {
        id: iconColoursFile
        path: root.iconColoursWanted ? root.iconColoursPath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.iconColoursReading = false;
            try {
                const d = JSON.parse(text()), m = {};
                for (const k in d) if (d[k] && d[k].c) m[k] = d[k].c;
                root.iconColours = m;
            } catch (e) {}
        }
        onLoadFailed: { root.iconColoursReading = false; iconColoursSoon.restart(); }     // not made yet
    }
    // Slate Software's icons for apps not installed (tiles/<style>/flathub, appicon.py
    // --tile-files) note their colours there; read with the dock's (after the dock's own)
    property var flathubColours: ({})
    FileView {
        id: flathubColoursFile
        path: root.iconColoursWanted ? root.tileDir + "/flathub/colours.json" : ""
        // (watched once its folder exists; Slate Software also asks for it again as it opens and
        // after drawing: the file can arrive after Slate started, before anything watched it)
        watchChanges: true
        onFileChanged: reload()
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text()), m = {};
                for (const k in d) if (d[k] && d[k].c) m[k] = d[k].c;
                root.flathubColours = m;
            } catch (e) {}
        }
        onLoadFailed: root.flathubColours = ({})
    }
    // (Slate Software, when it has drawn some)
    function rereadFlathubColours() { if (flathubColoursFile.path !== "") flathubColoursFile.reload(); }
    Timer { id: iconColoursSoon; interval: 1500; onTriggered: if (root.iconColoursWanted) { iconColoursRun.running = false; iconColoursRun.running = true; } }
    // Read straight after it's written: watching for the file only works once its folder
    // exists, and a style's folder is made by the first tiles drawn in it (on a first login,
    // or a style never used before), after the watch began, so the colours never arrived
    Process {
        id: iconColoursRun
        command: [root.tileScript, "--colours", root.tileDir, root.iconColoursPath]
        onExited: code => { if (code === 0 && iconColoursFile.path !== "") { root.iconColoursReading = true; iconColoursFile.reload(); } }
    }
    property bool iconColoursReading: false
    // Still drawing tiles or noting their colours (the test hook waits for this before a picture)
    // (a function, asked only when the hook runs: as a bool binding, a reload tearing Config
    // down still evaluated it to undefined now and then, "Unable to assign [undefined] to
    // bool", whatever the expression)
    // (the tests: each thing iconsBusy waits on, for a wait that never ends)
    function iconsBusyWhy() {
        return { tileAll: !!tileAll?.running, tileAllRun: !!tileAllRun?.running, coloursSoon: !!iconColoursSoon?.running,
                 coloursRun: !!iconColoursRun?.running, coloursReading: !!iconColoursReading, drawing: tilesDrawing };
    }
    function iconsBusy() {
        return !!(tileAll?.running || tileAllRun?.running || iconColoursSoon?.running
            || iconColoursRun?.running || iconColoursReading || tilesDrawing > 0);
    }
    // One app's tile being drawn as it first shows (the menu bar, the dock, the launcher and a
    // notification each draw a missing one themselves): counted, so iconsBusy says so too. Each
    // drawing Process calls tileDrawing(running) as it starts and stops, and tileDrawing(false)
    // if it's taken away while still drawing. Once one's drawn, its colour is noted straight
    // away, as after tileAll: asked before the tile existed, the next look was 30 s off, and
    // the app sat on the theme's tile until then (Settings, opened, on the dock)
    property int tilesDrawing: 0
    function tileDrawing(on) {
        tilesDrawing = Math.max(0, tilesDrawing + (on ? 1 : -1));
        if (!on && iconColoursWanted) iconColoursSoon.restart();
    }
    onIconColoursWantedChanged: if (iconColoursWanted) iconColoursSoon.restart()
    // An icon with no colour noted yet (an app just drawn): look again, at most every 30 s each
    property var iconColourAsked: ({})
    function askIconColour(app) {
        const now = Date.now();
        if (now - (iconColourAsked[app] || 0) < 30000) return;
        iconColourAsked[app] = now;
        iconColoursSoon.restart();
    }
    // The tile behind an app's icon: a deep shade of the icon's colour (a light one in light
    // mode) with the setting on, else `fallback`. Grey and white icons get a plain neutral grey,
    // clearer than the theme's tile (which barely showed on a card, and leans to the accent)
    function iconTileFor(app, fallback) { return iconTileShade(app) ?? fallback; }
    // The shade itself, or null when the theme's tile applies (setting off, filled icons, or
    // its colour not noted yet)
    function iconTileShade(app) {
        if (!s.iconTileColour || s.iconFill || !app) return null;
        const hex = iconColours[app] || flathubColours[app];
        if (!hex) { askIconColour(app); return null; }
        return iconTileShadeOf(hex);
    }
    // The shade for an icon whose main colour is `hex` (also Settings' preview of it)
    function iconTileShadeOf(hex) {
        if (!s.iconTileColour || s.iconFill || !hex) return null;
        const c = Qt.color(hex);
        if (c.hslSaturation * (1 - Math.abs(2 * c.hslLightness - 1)) < 0.1)
            return Qt.color(s.lightMode ? "#d2d4d8" : "#484b50");      // (plain grey: tint() would lean it to the accent)
        const h = Math.max(0, c.hslHue), sat = Math.min(0.65, c.hslSaturation);
        const t = s.lightMode ? Qt.hsla(h, sat * 0.7, 0.84, 1) : Qt.hsla(h, sat * 0.8, 0.22, 1);
        return t;
    }

    // ---- Keyboard shortcuts set (Settings → Shortcuts) ------------------------------
    // "slate", "hyprland" or "hyprland-extras": saved where binds.lua reads it
    // (~/.local/state/slate/keyset.lua), then Hyprland's config reloads to use it
    readonly property string keysetPath: root.stateHome + "/slate/keyset.lua"
    signal keysetApplied()
    function setKeyset(v) {
        if (["slate", "hyprland", "hyprland-extras"].indexOf(v) < 0) return;
        s.keyset = v;
        keysetProc.command = ["sh", "-c", "mkdir -p \"$(dirname \"$0\")\" && printf 'KEYSET = \"%s\"\\n' \"$1\" > \"$0\" && hyprctl reload >/dev/null",
                              keysetPath, v];
        ownHyprReloadAt = Date.now();      // Slate's own reload: no "reloaded" notice
        keysetProc.running = true;
    }
    Process { id: keysetProc; onExited: root.keysetApplied() }

    // ---- App theming (scripts/apply-theme.py, run by shell.qml) ----------------------------
    // Settings → App Theming → Refresh asks for every switched-on app's theme to be written again
    signal refreshThemes()
    property bool themesBusy: false

    // ---- Colour (Settings → Appearance → Colour) -------------------------------------------
    // Colourful: more variety of colour (pastels) where Monotone uses the accent and greys
    readonly property bool colourful: s.colourStyle === "colourful"
    // Each Settings page's own colour (its icon in the sidebar and on All Settings), a pastel,
    // deepened in light mode by tint(); the accent when monotone
    readonly property var pagePastels: ({
        overview: "#b9a6e8", general: "#9db4d8", appearance: "#e8a6c8", displays: "#8fc7e8",
        input: "#b9a6e8", sound: "#e8b48f", power: "#a6d3a0", windows: "#8fd0c8",
        workspaces: "#c3a6e6", notifications: "#e8c48f", wifi: "#8fb3e8", bluetooth: "#7fa8e8", printers: "#d8c0a0", users: "#e8b8c8", accessibility: "#9fc6e8", timers: "#e8b0a0", storage: "#b8c8a0",
        bar: "#a6c8e8", control: "#a6d8c8", dock: "#9ad3b8", launcher: "#e8d08f", spaces: "#d8a6e8",
        hotcorners: "#e89f8f", lock: "#a8b8cc", unlock: "#a6c4e0", screensaver: "#b0a6e8", shortcuts: "#c8c8a0",
        apps: "#8fd8d0", startup: "#e8b0a0", apprules: "#b8c8a6", datetime: "#e8a6a6", apptheming: "#e6a6e6", wallpaper: "#a6d8c8", icons: "#e8c4a6",
        screenshots: "#a6e0e8", updates: "#a6d8a6", assistant: "#b9a6e8", about: "#b8c0cc", debug: "#e8a0a0", webcam: "#c0dc9a",
        // Slate Software's sections and Flathub's categories (SoftwareWindow.qml), the same way
        "software-discover": "#8fb3e8", "software-installed": "#e8c48f", "software-updates": "#a6d8a6",
        // (Flathub's categories: ten hues evenly round the wheel, neighbours far apart, none repeated)
        "software-Game": "#e396c4", "software-Graphics": "#e3c496", "software-AudioVideo": "#a696e3",
        "software-Office": "#a6e396", "software-Network": "#96b5e3", "software-Development": "#d4e396",
        "software-Education": "#e39696", "software-Science": "#96e3e3", "software-Utility": "#96e3b5",
        "software-System": "#d496e3"
    })
    function pageColour(id) { return colourful && pagePastels[id] ? tint(pagePastels[id]) : accent; }
    // ---- The control centre's quick switches (Settings → Control Centre) --------------------
    // Every switch there is: its name and icon as Settings shows them. What each one does, and
    // whether it's on, is in Popouts.qml (the control centre), by the same id
    readonly property var controlSwitchList: [
        { id: "wifi", label: "Wi-Fi", icon: 0xEB52 },
        { id: "bt", label: "Bluetooth", icon: 0xEA37 },
        { id: "caffeine", label: "Caffeine", icon: 0xEF0E },
        { id: "night", label: "Night Light", icon: 0xEAF8 },
        { id: "dnd", label: "Do Not Disturb", icon: 0xECE9 },
        { id: "perf", label: "Performance", icon: 0xEC45 },
        { id: "airplane", label: "Airplane Mode", icon: 0xEB6F },
        { id: "gamemode", label: "Game Mode", icon: 0xF1D2 },
        { id: "light", label: "Light Mode", icon: 0xEB30 },
        { id: "mute", label: "Mute", icon: 0xF1C3 },
        { id: "micmute", label: "Mute Mic", icon: 0xED16 },
        { id: "saver", label: "Power Saver", icon: 0xED4F },
        { id: "glass", label: "Glass", icon: 0xEF8C },
        { id: "chargelimit", label: "Charging Limit", icon: 0xEF3C },
        { id: "dockhide", label: "Hide Dock", icon: 0xEAD3 },
        { id: "barhide", label: "Hide Menu Bar", icon: 0xEAD7 },
        { id: "floating", label: "Floating", icon: 0xEE17 },
        { id: "clipboard", label: "Clipboard", icon: 0xEA6F },
        { id: "private", label: "Private Mode", icon: 0xF227 }
    ]
    // Private Mode on or off, from wherever it's switched (PrivateMode.qml does it: the first
    // time, it asks first)
    signal privateModeAsked(bool on)
    // Every right-click menu closes (DesktopMenu.qml, TrayMenu.qml): sent as the launcher, Nova,
    // the pickers, the window switcher or the overview opens (shell.qml)
    signal closeMenus()
    // A press on the menu bar (Bar.qml). The launcher, Nova and every right-click menu (the
    // dock's Downloads and Waste Basket grids are in one) close on it: they leave the bar's
    // place out of their click catchers, so the press reaches the bar too
    signal barPressed()
    // What a bar press closed ("launcher", "assistant"), so the same press's click on the button
    // that opened it doesn't open it again (barClosed(what) says so once)
    property string barClosedWhat: ""
    function barPress() { barClosedWhat = ""; barPressed(); }
    function noteBarClosed(what) { barClosedWhat = what; }
    function barClosed(what) {
        if (barClosedWhat !== what) return false;
        barClosedWhat = "";
        return true;
    }
    // Where each screen's bar takes the pointer, in that screen's own coordinates (Slate's
    // units, so Interface size needs nothing), by screen name; read by the catchers above
    property var barRects: ({})
    function setBarRect(name, r) {
        const next = Object.assign({}, barRects);
        if (r) next[name] = r; else delete next[name];
        barRects = next;
    }
    function barRectOn(screen) {
        // (a window with no screen of its own is on the first one)
        const sc = screen || Quickshell.screens[0];
        const r = sc ? barRects[sc.name] : null;
        return r || Qt.rect(0, 0, 0, 0);
    }
    function setPrivateMode(on) { privateModeAsked(on); }
    // The ones this computer can't use (SwitchHardware.qml), and the list without them: what
    // the panel and Settings choose from
    property var controlSwitchMissing: []
    readonly property var controlSwitchesHere: controlSwitchList.filter(x => controlSwitchMissing.indexOf(x.id) < 0)
    // The panel always has eight (or every one there is, if that's fewer): yours in your order,
    // only ones that exist here, each once; any places left over are filled from the list above
    // (so a switch whose hardware is missing gives its place up, and has it back when it returns)
    readonly property int controlSwitchesMost: 8
    readonly property var controlSwitches: {
        const known = controlSwitchesHere.map(x => x.id), saved = s.controlSwitches;
        const mine = (saved && saved.length !== undefined ? Array.from(saved) : []).map(String)
            .filter((id, i, a) => known.indexOf(id) >= 0 && a.indexOf(id) === i);
        return mine.concat(known.filter(id => mine.indexOf(id) < 0)).slice(0, controlSwitchesMost);
    }

    // How they're laid out in the panel's right-hand column: two to a row, all the same size,
    // sharing its height. Used by the panel and by Settings' picture of it, so the two can't
    // differ. Each one's place in a column w wide and h tall:
    function controlSwitchRects(n, w, h) {
        if (n <= 0) return [];
        const gap = 8, rows = Math.ceil(n / 2), cw = (w - gap) / 2, ch = Math.max(0, h - (rows - 1) * gap) / rows;
        const out = [];
        for (let i = 0; i < n; i++) out.push(Qt.rect((i % 2) * (cw + gap), Math.floor(i / 2) * (ch + gap), cw, ch));
        return out;
    }

    // ---- The battery's charging limit (Settings → Power, and a quick switch) ----------------
    // Where the laptop can stop charging short of full (UPower's charge threshold), Slate can
    // switch that on and off
    readonly property var laptopBattery: UPower.devices.values.find(d => d.isLaptopBattery) ?? null
    readonly property string batteryPath: laptopBattery && laptopBattery.nativePath
        ? "/org/freedesktop/UPower/devices/battery_" + String(laptopBattery.nativePath).split("/").pop().replace(/[^A-Za-z0-9]/g, "_") : ""
    property bool chargeLimitSupported: false
    property bool chargeLimitOn: false
    property int chargeLimitAt: 80
    function chargeLimitRefresh() { if (batteryPath !== "" && !isLoginScreen) chargeLimitAsk.running = true; }
    onBatteryPathChanged: chargeLimitRefresh()
    Process {
        id: chargeLimitAsk
        command: ["gdbus", "call", "--system", "--dest", "org.freedesktop.UPower", "--object-path", root.batteryPath,
                  "--method", "org.freedesktop.DBus.Properties.GetAll", "org.freedesktop.UPower.Device"]
        stdout: StdioCollector {
            onStreamFinished: {
                const end = /'ChargeEndThreshold': <uint32 (\d+)>/.exec(text);
                root.chargeLimitSupported = /'ChargeThresholdSupported': <true>/.test(text) && !!end && Number(end[1]) > 0 && Number(end[1]) < 100;
                root.chargeLimitOn = /'ChargeThresholdEnabled': <true>/.test(text);
                if (end) root.chargeLimitAt = Number(end[1]);
            }
        }
    }
    Process {
        id: chargeLimitSet
        property bool to: true
        command: ["gdbus", "call", "--system", "--dest", "org.freedesktop.UPower", "--object-path", root.batteryPath,
                  "--method", "org.freedesktop.UPower.Device.EnableChargeThreshold", to ? "true" : "false"]
        onExited: chargeLimitAsk.running = true
    }
    function setChargeLimit(on) { chargeLimitOn = on; chargeLimitSet.to = on; chargeLimitSet.running = true; }
    // (charging past the limit is asked about first, in `confirmer` (PowerConfirm): it's the
    // battery's life at stake)
    function askChargeLimit(on, confirmer) {
        if (on || !confirmer) { setChargeLimit(on); return; }
        confirmer.confirmWith({
            title: "Charge all the way to full?",
            body: "Keeping a battery full wears it out sooner, most of all when your laptop spends its days plugged in. "
                + "Stopping at " + chargeLimitAt + "% helps it hold its charge for years longer. Charging to full is worth it when "
                + "you need every hour away from a socket. You can switch the limit back on at any time.",
            button: "Charge to full", code: 0xEA33, danger: false
        }, () => root.setChargeLimit(false));
    }

    // The menu bar's status icons (notifications, Wi-Fi, volume…), each its own pastel
    readonly property var statusPastels: ({
        notifications: "#e8c48f", clipboard: "#8fd0c8", screenshot: "#a6e0e8", wifi: "#8fb3e8",
        keyboard: "#b9a6e8", bluetooth: "#7fa8e8", volume: "#e8b48f", battery: "#a6d3a0",
        gamemode: "#e8a6b4", camera: "#c0dc9a", drink: "#9fd0e8", focus: "#e8b0a0",
        windowmode: "#9ed6b4"       // (the workspace's window mode, by the dots: a mint green)
    })
    function statusColour(key, fallback) { return colourful && statusPastels[key] ? tint(statusPastels[key]) : fallback; }
    // The bar's Apps button (its three bars) and Spaces button (its four squares): one pastel
    // each on the bar, the first of its list (the rest are for where the parts are coloured apart)
    readonly property var appsPastels: ["#e8a6c8", "#e8c48f", "#8fc7e8"]
    readonly property var spacesPastels: ["#8fb3e8", "#a6d3a0", "#e8b48f", "#c3a6e6"]
    // (Nova's icon is one colour wherever it's drawn: the Assistant page's, below)
    function partColour(list, i, fallback) { return colourful && list[i] ? tint(list[i]) : fallback; }

    // ---- Game mode (the bar's game mode panel) -----------------------------------------
    // Turns off what costs the most to draw, and the touchpad ignoring it while you type (games
    // use both at once): Slate's glass, and Hyprland's blur, shadows, animations and see-through
    // windows. Your own settings for them are kept, not changed, so turning it off puts them
    // all back. Not on the login screen, which reads a copy of these settings
    readonly property bool isLoginScreen: Quickshell.shellPath("").indexOf("slate-greeter") >= 0
    // Where Slate keeps what lasts only for this login (marks, locks, the workspaces' modes and
    // names): $XDG_RUNTIME_DIR, which is yours alone. Should that not be set, a folder of your
    // own that only you can open, never /tmp, where anyone on the computer could put a file of
    // that name first. The same rule everywhere, since the scripts read and write the same
    // files: bin/slate, bin/slate-build-hyprbars, scripts/screenshot.sh, spaces.py, voice.py,
    // launcher-entries.py and session/hypr/hyprland.lua (tests/unit/test_runtime_dir.py)
    readonly property bool runtimeDirOwn: !Quickshell.env("XDG_RUNTIME_DIR")
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR")
        || ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/slate/run")
    Process {
        running: root.runtimeDirOwn && !root.isLoginScreen
        command: ["sh", "-c", 'mkdir -p "$0" && chmod 700 "$0"', root.runtimeDir]
    }
    // Under the test suite (tests/run sets SLATE_TEST=1): no sounds, welcome, startup apps,
    // update checks or login screen prompts, so a run is quiet and the same every time
    readonly property bool testMode: Quickshell.env("SLATE_TEST") === "1"
    // (the tests: when the daily look for updates, SoftwareUpdates.qml, was made; 0 until it is)
    property real softwareDailyMadeAt: 0
    // (which Config this is, for the tests: your shell.qml must see Slate's own, never a copy)
    readonly property string madeAs: testMode ? String(Date.now()) + "-" + Math.random() : ""
    // The tests' computer has no Wi-Fi and no sound card, and the bar hides what a computer
    // hasn't got. So the tests pretend it has both (the bar they arrange and measure is the
    // usual one), and take either away to see the bar without it: `test hardware wifi false`
    property bool pretendWifi: testMode
    property bool pretendAudio: testMode
    // The time the clocks show under test (SLATE_TEST_TIME, e.g. "2026-01-05T09:41:00"), so
    // screenshots match from run to run. clockDate(d) is the time to show: d, or that one
    readonly property var testTime: testMode && Quickshell.env("SLATE_TEST_TIME") ? new Date(Quickshell.env("SLATE_TEST_TIME")) : null
    function clockDate(d) { return testTime || d; }
    readonly property bool gameMode: s.gameMode && !isLoginScreen
    // Off again: Hyprland reloads its config (quietly), for its own blur, shadows, animations
    // and touchpad setting, then Slate's settings go back on top (hyprPush)
    onGameModeChanged: if (!gameMode) reloadHyprland()
    // Accessibility → Reduce transparency off again: Hyprland's own blur and window opacity
    // come back the same way
    readonly property bool reduceTransparency: s.reduceTransparency
    onReduceTransparencyChanged: if (!reduceTransparency) reloadHyprland()
    function setGameMode(on) { s.gameMode = on; }

    // ---- Glass (Settings → Appearance → Glass; off by default) ---------------------------
    // Surfaces (bar, dock, panels, Settings, the launcher, menus…) turn see-through, and
    // Hyprland blurs what's behind them (a layer rule, pushed with the other settings). Off in
    // game mode: always draw with this, not s.glass
    readonly property bool glass: s.glass && !gameMode && !s.reduceTransparency && !s.highContrast

    // ---- Shared by the bars and the screensaver ------------------------------------------
    // Tray apps that only have a menu (Ayatana indicators): found once, by the main bar (Bar.qml),
    // for every bar
    property var trayIndicatorIds: []
    // The screensaver's Videos style: its folder (Settings → Screensaver)
    readonly property string screensaverVideoFolder: s.screensaverVideoFolder || (Quickshell.env("HOME") + "/Videos/Screensaver")
    // The size scenery videos download in: as set, or for Automatic, by the widest screen's real
    // pixels (4K above 2560 wide, 1440p above 1920, else 1080p)
    readonly property string screenSceneryQuality: {
        let w = 0;
        for (const m of Hyprland.monitors.values) w = Math.max(w, m.width || 0);
        return w > 2560 ? "2160p" : w > 1920 ? "1440p" : "1080p";
    }
    readonly property string sceneryQuality: ["2160p", "1440p", "1080p"].includes(s.screensaverVideoQuality) ? s.screensaverVideoQuality : screenSceneryQuality

    // ---- Slate's own animations -----------------------------------------------------------
    // They follow Settings → Appearance → Animations, as Hyprland's do: Fast halves them, Off
    // (and game mode) makes them instant. Every animation in Slate takes its time from here:
    //   NumberAnimation { duration: Config.ms(200) }
    // except motion that's the point of the thing (the screensaver's drift, busy spinners, a
    // notification's countdown) and scrolling's glide
    // (Accessibility → Reduce motion: none of Slate's own either, its fades included: they
    // can't be told apart from movement here. Hyprland's windows and workspaces still fade)
    readonly property real animScale: gameMode || s.reduceMotion || s.animations === "off" ? 0 : s.animations === "fast" ? 0.5 : 1
    readonly property bool animate: animScale > 0
    function ms(t) { return Math.round(Number(t) * animScale); }
    readonly property real glassOpacity: Math.max(0.3, Math.min(0.95, s.glassOpacity))
    // A surface's colour: as it is, or see-through with glass
    function surface(c) { return glass ? Qt.rgba(c.r, c.g, c.b, c.a * glassOpacity) : c; }
    // Opacity sliders (Settings → Dock, → Menu Bar) are plain opacity: 0 is clear, 1 is solid.
    // Below 0 is "Slate's own", which is what each starts as, and follows the look.
    // The dock's own background with glass: Slate's own is a fifth clearer than the rest of the
    // glass (and Hyprland starts blurring behind it that much sooner: dockGlassCut, as glassCut
    // below). And the tiles on it (its icons' and its buttons'): solid unless turned down
    // (with its blur on, never quite clear: Hyprland blurs nothing behind nothing, so 0% is
    // drawn at 1%, enough for the blur to stay. The slider still says 0)
    readonly property real dockGlassOpacity: s.dockOpacity < 0 ? glassOpacity * 0.8 : Math.max(s.dockBlur ? 0.01 : 0, Math.min(1, s.dockOpacity))
    function dockSurface(c) { return glass ? Qt.rgba(c.r, c.g, c.b, c.a * dockGlassOpacity) : c; }
    // ...and what's on them: the icons, and the foreground of the dock's own buttons
    readonly property real dockIconOpacity: glass ? Math.max(0, Math.min(1, s.dockIconOpacity)) : 1
    readonly property real dockTileOpacity: glass ? Math.max(0, Math.min(1, s.dockTileOpacity)) : 1
    // Where Hyprland starts blurring behind the dock: from next to nothing, whatever its
    // opacity. One rule that never changes: nothing fainter than the dock in its window needs
    // keeping clear of the blur, and remaking the rule as a slider moved made the blur blink
    readonly property real dockGlassCut: 0.005
    // The menu bar's own background with glass (Bar.qml's barBackground): Slate's own is, in
    // dark mode, a quarter of the way from the glass's opacity to solid
    // (While the bar's being arranged it's solid, its containers too, with no blur: all there
    // to see and pick up, whatever the sliders say)
    readonly property real barGlassOpacity: barArranging ? 1 : barGlassOpacityUsual
    // (...as it is when it isn't being arranged: the bar eases between the two, Bar.qml's arrangeLook)
    readonly property real barGlassOpacityUsual: s.barOpacity < 0 ? (s.lightMode ? glassOpacity : glassOpacity + (1 - glassOpacity) * 0.25)
        : Math.max(s.barBlur ? 0.01 : 0, Math.min(1, s.barOpacity))
    // The containers on the bar (Bar.qml's Capsule), with glass: drawn solid, and the whole of
    // each faded to Settings → Menu Bar → Glass → Contents opacity as one: its fill, icons,
    // text, highlight and the lines between things. And to Hover opacity while the pointer's
    // over it. Each its own: neither follows the other. (Below 0, from before they had a
    // number to start at: 1)
    readonly property real barItemOpacity: !glass || s.barItemOpacity < 0 ? 1 : Math.min(1, s.barItemOpacity)
    readonly property real barItemHoverOpacity: !glass || s.barItemHoverOpacity < 0 ? 1 : Math.min(1, s.barItemHoverOpacity)
    // Where Hyprland starts blurring behind the bar. Its window also holds its shadow, which
    // has to stay fainter than this or it's blurred too: so a clear bar (under a quarter) has
    // next to no threshold and no shadow, and from there both rise with it, the threshold in
    // a few wide steps (each remakes Hyprland's rule, which blinks the blur: least seen on a
    // bar that's mostly colour, and never at the clear end)
    readonly property real barGlassCut: barGlassOpacity < 0.25 ? 0.005 : Math.min(glassCut, Math.floor(barGlassOpacity * 0.85 * 10) / 10)
    // The bar's panels (Popouts.qml): the bar's own colour, at an opacity of their own (Settings
    // → Menu Bar → Glass → Panel opacity), with a blur rule and a shadow kept under it, as the
    // bar's are
    // With their blur off the slider covers only the solid end: its 0% is 80% opacity, its 100%
    // solid. Clearer than that with nothing blurred behind, a panel couldn't be read
    readonly property real panelGlassOpacity: {
        const o = Math.max(0, Math.min(1, s.barPanelOpacity));
        return s.barPanelBlur ? Math.max(0.01, o) : 0.8 + 0.2 * o;
    }
    readonly property real panelGlassCut: panelGlassOpacity < 0.25 ? 0.005 : Math.min(glassCut, Math.floor(panelGlassOpacity * 0.85 * 10) / 10)
    // The launcher and Nova's window: a background opacity of their own with glass, and a blur
    // rule (the launcher's with a shadow kept under it, as the panels' are; Nova's shadow is
    // Hyprland's, as every window's). An opacity not set (below 0) is Appearance's
    function ownGlassOpacity(v, blur) { return v < 0 ? glassOpacity : Math.max(blur ? 0.01 : 0, Math.min(1, v)); }
    function ownGlassCut(o) { return o < 0.25 ? 0.005 : Math.min(glassCut, Math.floor(o * 0.85 * 10) / 10); }
    function ownShadowShare(o, blur) { return !glass || !blur ? 1 : Math.min(1, Math.max(0, o - 0.25) / Math.max(0.01, shadowStrength)); }
    readonly property real launcherGlassOpacity: ownGlassOpacity(s.launcherOpacity, s.launcherBlur)
    readonly property real launcherGlassCut: ownGlassCut(launcherGlassOpacity)
    readonly property real launcherShadowShare: ownShadowShare(launcherGlassOpacity, s.launcherBlur)
    function launcherSurface(c) { return glass ? Qt.rgba(c.r, c.g, c.b, c.a * launcherGlassOpacity) : c; }
    readonly property real assistantGlassOpacity: ownGlassOpacity(s.assistantOpacity, s.assistantBlur)
    function assistantSurface(c) { return glass ? Qt.rgba(c.r, c.g, c.b, c.a * assistantGlassOpacity) : c; }
    // Notifications as they pop up: a background opacity of their own with glass, another while
    // the pointer's on one (to read it by), a blur rule and a shadow kept under it, as the
    // panels' are (Settings → Notifications → Glass)
    readonly property real toastGlassOpacity: Math.max(s.notificationBlur ? 0.01 : 0, Math.min(1, s.notificationOpacity))
    readonly property real toastGlassHoverOpacity: Math.max(s.notificationBlur ? 0.01 : 0, Math.min(1, s.notificationHoverOpacity))
    function toastSurface(c, hovered) { return glass ? Qt.rgba(c.r, c.g, c.b, hovered ? toastGlassHoverOpacity : toastGlassOpacity) : c; }
    // (blur from under whichever of the two is clearer, so it's there for both)
    readonly property real toastGlassLow: Math.min(toastGlassOpacity, toastGlassHoverOpacity)
    readonly property real toastGlassCut: toastGlassLow < 0.25 ? 0.005 : Math.min(glassCut, Math.floor(toastGlassLow * 0.85 * 10) / 10)
    readonly property real toastShadowShare: !glass || !s.notificationBlur ? 1
        : Math.min(1, Math.max(0, toastGlassLow - 0.25) / Math.max(0.01, shadowStrength))
    readonly property real panelShadowShare: !glass || !s.barPanelBlur ? 1
        : Math.min(1, Math.max(0, panelGlassOpacity - 0.25) / Math.max(0.01, shadowStrength))
    // ...and the bar's shadow: as dark as every other (Settings → Appearance → Shadows), but
    // always just under where Hyprland starts blurring behind the bar (barGlassCut, which can be
    // lower than the bar's own opacity suggests): over it, Hyprland blurred behind the darkest
    // part of the shadow, a hard-edged band of blurred window under the bar
    readonly property real barShadowShare: !glass || !s.barBlur || barArranging ? 1
        : Math.min(1, Math.max(0, Math.min(barGlassOpacity - 0.25, barGlassCut - 0.04)) / Math.max(0.01, shadowStrength))
    // Hyprland's rule that blurs behind the layers named `match`, where they're more solid than
    // `cut` (Lua, for hyprPush): kept in the global `v`, with what it was made for beside it.
    // `wanted` false: made, but off (the dock with its Blur switched off)
    function glassRule(v, match, cut, wanted) {
        // (the number after the cut: put up by one whenever a rule here changes what it matches,
        // so a Hyprland that's still running remakes it)
        const c = cut.toFixed(3), made = `"${c} 8"`;
        return `if ${v} and ${v}_ALPHA ~= ${made} then ${v}:set_enabled(false); ${v} = nil end; `
            + `if not ${v} then ${v}_ALPHA = ${made}; ${v} = hl.layer_rule({ name = "${v.toLowerCase().replace(/_/g, "-")}-${Math.round(cut * 1000)}", `
            + `match = { namespace = "${match}" }, blur = true, ignore_alpha = ${c} }) end; ${v}:set_enabled(${glass && wanted !== false ? "true" : "false"}); `;
    }
    // Cards, capsules and fields on a surface: with glass, a soft frosted layer rather than
    // solid grey (so the glass shows through them too)
    function raised(c) {
        if (!glass) return c;
        // White, with a hint of the wallpaper's colour (Glass → Gloss colour), like the sheen
        const w = wallpaperAccent ? Qt.color(wallpaperAccent) : null;
        const k = w ? glossTint : 0;
        const r = 1 - k + (w ? w.r * k : 0), g = 1 - k + (w ? w.g * k : 0), b = 1 - k + (w ? w.b * k : 0);
        return s.lightMode ? Qt.rgba(r, g, b, 0.55) : Qt.rgba(r, g, b, 0.07 + 0.04 * k);
    }
    // Where Hyprland's blur stops: just under the surfaces' own opacity. It goes by each pixel
    // (no smoothing), so along rounded edges it steps; stopping where the surface is nearly
    // solid hides that, where stopping at its faint edge showed it ("pixely" against a bright
    // window border)
    readonly property real glassCut: Math.max(0.05, glassOpacity * 0.85)
    // The shine, a thin light rim around glass surfaces, is always there with glass (it was a
    // setting once, and made too little difference to keep): draw it with `glass`
    // Gloss: a sheen on the bar's containers, hover highlights and tooltips (Gloss.qml)
    readonly property real glossAmount: Math.max(0, Math.min(2, Number(s.glassGloss)))
    readonly property bool glassGloss: glass && glossAmount > 0
    readonly property real glossTint: Math.max(0, Math.min(1, Number(s.glassGlossTint)))
    // A window border's sheen, as Hyprland draws one with glass and gloss (HyprlandLook): seven
    // colours spread evenly along a 45° gradient from the top left, a bright catch fading within
    // the first sixth or so into the colour itself, a touch deeper at the far corner (how strong
    // follows Glass → Gloss). Without gloss, the colour all the way. [opaque colour, alpha] pairs
    function borderSheen(base, a, light, soft, deep) {
        const g = glassGloss ? Math.min(1, glossAmount) : 0;
        if (g <= 0) return Array(7).fill([base, a]);
        const toWhite = (c, k) => Qt.rgba(c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k, 1);
        return [[toWhite(base, light * g), Math.min(1, a + 0.3 * g)], [toWhite(base, soft * g), a],
            [base, a], [base, a], [base, a], [base, a], [Qt.darker(base, 1 + deep * g), a]];
    }
    // Hyprland's active window border, so Slate's own windows can have the very same
    readonly property var activeBorderSheen: borderSheen(accent, 0.6, 0.75, 0.3, 0.2)
    // The border round Slate's own glass windows (the launcher, Nova, the switchers, the
    // pickers, the bar's arranging panel): drawn as Hyprland draws the active window's (the
    // same colours and sheen: WindowBorder.qml), and as wide as Settings → Windows → Window
    // borders makes tiled windows'. That width is in Hyprland's pixels, so it's divided by the
    // Interface size to match on screen; 0 turns it off here too. Without glass (or in game
    // mode) there's none. Use `WindowBorder { radius: parent.radius }` inside the window's panel
    readonly property var windowBorderColours: activeBorderSheen.map(p => Qt.rgba(p[0].r, p[0].g, p[0].b, p[1]))
    readonly property real windowBorderWidth: glass ? Math.max(0, Math.min(12, Number(s.windowBorderSize) || 0)) / uiScale : 0
    // The bright edge round the title bars' move handle: a bright, light shade of the theme's
    // accent, so it belongs to the colours in use. (A grey accent has no colour to give: it
    // stays white)
    readonly property color glassEdge: {
        const a = Qt.lighter(accent, 1.0);
        const sat = Math.min(1, a.hslSaturation * 1.5);
        return Qt.hsla(a.hslHue >= 0 ? a.hslHue : 0, sat, s.lightMode ? 0.8 : 0.72, s.lightMode ? 0.7 : 0.38);
    }
    // Hyprland's blur (behind see-through windows), for drawing it in previews too. Read at
    // start, when Hyprland reloads its config, and after Slate changes it (glass)
    property var hyprBlur: ({ enabled: false, size: 8, passes: 1, contrast: 1, vibrancy: 0 })
    Process {
        id: blurProc
        running: true
        command: ["sh", "-c", "printf '['; for o in enabled size passes contrast vibrancy; do hyprctl -j getoption decoration:blur:$o; [ $o = vibrancy ] || printf ','; done; printf ']'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const a = JSON.parse(text);
                    const b = { enabled: !!(a[0].bool ?? a[0].int), size: a[1].int, passes: a[2].int,
                                contrast: a[3].float, vibrancy: a[4].float };
                    // (only when it differs: everything drawing the blur redraws on a new object)
                    const o = root.hyprBlur;
                    if (b.enabled !== o.enabled || b.size !== o.size || b.passes !== o.passes || b.contrast !== o.contrast || b.vibrancy !== o.vibrancy)
                        root.hyprBlur = b;
                } catch (e) {}
            }
        }
    }
    function readBlur() { if (testMode) testBlurReads++; blurProc.running = false; blurProc.running = true; }
    // (read again after Hyprland reloads: the Hyprland events handler starts blurLater)
    Timer { id: blurLater; interval: 600; onTriggered: root.readBlur() }
    // Glass's blur size put back to Hyprland's own (glass off, or "Hyprland's own" picked):
    // reload Hyprland's config so its value comes back
    property bool blurOverridden: false
    readonly property bool blurOverride: (s.glass && s.glassBlur > 0) || s.blurPasses > 0
    // Which: a blur size or passes going back to Hyprland's own needs a reload
    readonly property string blurOverrideKey: (s.glass && s.glassBlur > 0 ? "size" : "") + (s.blurPasses > 0 ? "passes" : "")
    property string blurOverriddenKey: ""
    onBlurOverrideKeyChanged: {
        const was = blurOverriddenKey, now = blurOverrideKey;
        if (was !== "" && (was.includes("size") && !now.includes("size") || was.includes("passes") && !now.includes("passes")))
            hyprReload.restart();
        blurOverriddenKey = now;
    }
    onBlurOverrideChanged: if (!blurOverride && blurOverridden) { blurOverridden = false; hyprReload.restart(); }

    // Nova's window (Assistant.qml): a real window of Slate's, with Slate's app id
    // (slate-settings) and this title, but not one of your windows: it's left out of the window
    // switcher, the overview, the dock, the launcher's window search, the bar's title, Slate's
    // title bars and the counts of what's on a workspace. Takes any kind of window Slate sees:
    // Hyprland's (a toplevel, or its details from hyprctl) or a Wayland toplevel. (The same
    // test is slateIsNova in windowrules.lua and is_nova in scripts/spaces.py)
    readonly property string novaTitle: "Nova"
    // Slate's own windows pinned to every workspace: Nova, Settings and its picture chooser.
    // None of them makes a workspace in use or is counted on one (the dots, new and spare
    // workspaces, which workspaces a mode change reaches); Settings is still yours to switch to.
    // (The same titles are slateIsPinned's in windowrules.lua)
    readonly property var pinnedTitles: [novaTitle, "Settings", "Choose a picture"]
    function isPinnedSlate(t) {
        if (!t || pinnedTitles.indexOf(t.title) < 0) return false;
        const o = t.lastIpcObject;
        const cls = t.appId !== undefined ? t.appId : t.class !== undefined ? t.class
            : t.wayland ? t.wayland.appId : o && o.class !== undefined ? o.class : "";
        return cls === "slate-settings" || cls === "" || cls === undefined || cls === null;
    }
    // Which app a window is, by its app ID, with Slate's own sorted out: Slate's windows all share
    // Slate's app ID (slate-settings), and Slate Software is an app of its own (its own place in the
    // dock and the switcher, its own icon), told apart by its title, as Nova is
    readonly property string softwareTitle: "Software"
    function appIdOf(t) {
        if (!t) return "";
        const id = t.appId || "";
        return id === "slate-settings" && t.title === softwareTitle ? "slate-software" : id;
    }
    // App rules (Settings → App Rules) as Hyprland window rules, one per app, matched on its whole
    // window class. Made again only when the rules change (SLATE_APP_RULES_FOR), the old ones
    // switched off. Only plain names reach Hyprland: a class or monitor with anything but
    // letters, digits, dots, dashes and underscores is left out, never quoted into the rule
    function ruleClassOf(e) { return e ? String(e.startupClass || e.id || "") : ""; }
    readonly property string appRulesLua: {
        const plain = v => /^[A-Za-z0-9._-]+$/.test(String(v || ""));
        const made = [], key = [];
        for (const r of s.appRules || []) {
            if (!r || !plain(r.cls)) continue;
            const ws = Math.round(Number(r.workspace) || 0), as = String(r.as || ""), mon = plain(r.monitor) ? r.monitor : "";
            const fx = [];
            if (ws >= 1 && ws <= 10) fx.push(`workspace = "${ws}"`);
            if (["float", "tile", "maximize", "fullscreen"].includes(as)) fx.push(`${as} = true`);
            if (mon) fx.push(`monitor = "${mon}"`);
            if (fx.length === 0) continue;
            key.push(`${r.cls}|${ws}|${as}|${mon}`);
            made.push(`SLATE_APP_RULES[#SLATE_APP_RULES + 1] = hl.window_rule({ match = { class = "^(${r.cls.replace(/\./g, "\\\\.")})$" }, ${fx.join(", ")} })`);
        }
        return `if SLATE_APP_RULES_FOR ~= "${key.join(";")}" then `
            + `for _, r in ipairs(SLATE_APP_RULES or {}) do r:set_enabled(false) end; `
            + `SLATE_APP_RULES = {}; SLATE_APP_RULES_FOR = "${key.join(";")}"; ${made.join("; ")} end; `;
    }
    // The drop-down terminal (Super+`, binds.lua): Slate's own, on a hidden workspace of its own,
    // so it isn't a running app in the dock or a window to find in the launcher
    readonly property string dropdownClass: "org.slate.dropdown"
    function isDropdown(t) {
        if (!t) return false;
        const o = t.lastIpcObject;
        const cls = t.appId !== undefined ? t.appId : t.wayland ? t.wayland.appId : o && o.class !== undefined ? o.class : "";
        return cls === dropdownClass;
    }
    function isNova(t) {
        if (!t || t.title !== novaTitle) return false;
        const o = t.lastIpcObject;
        const cls = t.appId !== undefined ? t.appId : t.class !== undefined ? t.class
            : t.wayland ? t.wayland.appId : o && o.class !== undefined ? o.class : "";
        // (a Hyprland window whose details haven't come yet: by its title alone)
        return cls === "slate-settings" || cls === "" || cls === undefined || cls === null;
    }

    // Hyprland's corner rounding for windows (decoration:rounding), in Hyprland's pixels, for
    // drawing windows the way they look: previews, borders. A tiled window alone on its
    // workspace and a maximised one are square (windowrules.lua): see windowRadius().
    // Read at start and again when Hyprland reloads its config.
    property real windowRounding: 10
    // (asked again a moment after Rounded UI elements changes it: Hyprland has to be told first)
    readonly property bool roundedNow: s.roundedElements
    onRoundedNowChanged: roundingLater.restart()
    Timer { id: roundingLater; interval: 900; onTriggered: { roundingProc.running = false; roundingProc.running = true; } }
    Process {
        id: roundingProc
        running: true
        command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
        stdout: StdioCollector { onStreamFinished: { try { root.windowRounding = JSON.parse(text).int; } catch (e) {} } }
    }
    // (read again after Hyprland reloads, from the Hyprland events handler)
    // A window's rounding (Hyprland's pixels) from its Hyprland data (lastIpcObject or
    // hyprctl clients), given how many tiled windows share its workspace
    function windowRadius(o, tiledOnWorkspace) {
        if (!o) return windowRounding;
        return o.fullscreen === 1 || (!o.floating && tiledOnWorkspace === 1) ? 0 : windowRounding;
    }

    // ---- Interface size ---------------------------------------------------------
    // Settings → Appearance → Interface size scales all of Slate through Qt (QT_SCALE_FACTOR,
    // set by bin/slate when it starts Slate), so the scale in use is the one Slate started
    // with; changing the setting restarts Slate (SettingsWindow). Hyprland's own pieces
    // (title bars) and anything mixing Hyprland's screen positions with Slate's use uiScale.
    readonly property real uiScale: {
        const v = parseFloat(Quickshell.env("QT_SCALE_FACTOR") || "1");
        return v > 0 ? v : 1;
    }
    // Called when the setting is changed from Settings (not when the file loads, so a
    // mismatch can never restart Slate over and over): restarts Slate a moment after the
    // last change, then reopens Settings where it was
    function uiScaleEdited() { scaleRestart.restart(); }
    // Settings → Debug → Log detail: the level Slate started with (bin/slate passes it on), and
    // a full restart to apply a different one, back on the Debug page
    readonly property string runningLogLevel: Quickshell.env("SLATE_LOG_LEVEL") || "normal"
    function logLevelEdited() { logRestart.restart(); }
    Timer {
        id: logRestart
        interval: 1200
        onTriggered: {
            if ((root.s.logLevel || "normal") === root.runningLogLevel) return;
            root.restartToPage("debug");
        }
    }
    Timer {
        id: scaleRestart
        interval: 1200
        onTriggered: {
            if (Math.abs(root.s.uiScale - root.uiScale) < 0.001) return;
            root.restartToPage("appearance");
        }
    }

    // ---- Title bars on floating windows (Settings → Windows → Title bars) -------------------
    // Slate's own (TitleBar.qml) are the default: Slate draws them, so there's nothing to build
    // and nothing that breaks when Hyprland updates. Hyprbars, a Hyprland plugin Slate builds, is
    // the option: a bar on every floating window, but it has to be rebuilt for every new
    // Hyprland. Whenever Hyprbars can't be used, Slate's are, so floating windows always have
    // title bars. HyprbarsWatch.qml keeps `hyprbars` up to date and does the asking.
    property var hyprbars: ({})              // what slate-build-hyprbars --status says (its keys)
    property bool hyprbarsKnown: false       // …once it has said it
    // (after Remove Hyprbars it stays in the running Hyprland until that restarts, unused)
    readonly property bool hyprbarsLoaded: hyprbars.loaded === "yes" && hyprbars.removed !== "yes"
    // Slate's title bars are in use: chosen, or Hyprbars is chosen but isn't loaded (whatever the
    // settings file says: a Spaces restore, a hand-edited file, a build that failed)
    readonly property bool slateTitleBars: s.titleBarStyle !== "hyprbars" || (hyprbarsKnown && !hyprbarsLoaded)
    // The Hyprland that's running, and the one that's installed (they differ between a package
    // update and the next restart; a build is always for the installed one)
    readonly property string hyprbarsRunning: hyprbars.runningCommit || hyprbars.running || ""
    readonly property string hyprbarsInstalled: hyprbars.installedCommit || hyprbars.installed || hyprbarsRunning
    readonly property bool hyprlandUpdated: hyprbarsRunning !== "" && hyprbarsInstalled !== hyprbarsRunning
    // Where Hyprbars stands, for Settings:
    //   none      never built (and no distro package)
    //   building  being built now
    //   loaded    in the running Hyprland
    //   ready     built for the running Hyprland, loads at the next Hyprland reload
    //   stale     built for another Hyprland: needs rebuilding
    //   failed    the last build failed (hyprbars.error says why)
    //   unreleased  the plugin has no release for this Hyprland yet: nothing was built, and
    //             the newest unreleased version only with a yes (a calm wait, not a failure)
    //   system    a distro's package is there but didn't load
    //   removed   removed, but still in the running Hyprland until that restarts
    readonly property string hyprbarsState: !hyprbarsKnown ? ""
        : hyprbars.state === "building" ? "building"
        : hyprbarsLoaded ? "loaded"
        : hyprbars.build === "yes" ? "ready"
        : hyprbars.state === "unreleased" ? "unreleased"
        : hyprbars.state === "failed" ? "failed"
        : hyprbars.any === "yes" ? "stale"
        : hyprbars.removed === "yes" ? "removed"
        : hyprbars.system === "yes" ? "system"
        : "none"
    // Asked of HyprbarsWatch.qml (Settings → Windows): use Hyprbars (asks first, with its risks,
    // and builds it if need be); build it again; reload Hyprland to load a finished build;
    // remove it; look again
    signal hyprbarsChoose()
    signal hyprbarsRebuild()
    signal hyprbarsReload()
    signal hyprbarsRemove()
    signal hyprbarsBuildUnreleased()      // the person said yes to building the newest unreleased version
    signal hyprbarsCheck()
    // Slate switched from Hyprbars to its own title bars because Hyprbars couldn't load (it asks
    // whether to switch back once it can): for Settings and the tests
    property bool hyprbarsFallback: false
    // The settings file is from before there was a title bar setting: someone with Hyprbars
    // working keeps it, rather than getting the new default (HyprbarsWatch.qml)
    property bool titleBarStyleUnset: false
    function checkTitleBars() { hyprbarsCheck(); }
    property string titleBarOn: ""          // the window Slate's title bar is showing on (its address; for the tests)
    property bool titleBarAway: false       // ...and it's stepped away while the window's moved by something else (tests)
    // (test mode only) how many times the title bar has looked at the windows, and the window in
    // front as it last saw it ("address,x,y,w,h"): tests wait for Slate to have caught up
    property int titleBarLooks: 0
    property string titleBarSeen: ""
    // Floating windows with Slate's own title bars: a window takes focus when it's clicked, not
    // when the pointer passes over it (focus moving on its own would leave the bar on a window
    // that isn't the one you're using). Overrides the setting without changing it; when it
    // ends and the setting isn't Slate's, Hyprland's config is read again for its own value
    readonly property bool clickToFocus: anyFloating && slateTitleBars
    onClickToFocusChanged: if (!clickToFocus && s.focusFollowsMouse === "") hyprReload.restart()
    // Maximising with Slate's title bars (the bar's button, double-click, Super+D): the title bar
    // on that window's screen does it; where each window was before, to put it back
    signal titleBarMaximise(string address)
    property var titleBarRestore: ({})
    // The focused workspace is floating (each workspace can have its own mode: below)
    readonly property bool floatingWindows: focusedMode === "floating"
    // The window modes (Settings → Windows): Hyprland's layouts, and floating (every window
    // floats over dwindle, which a window tiled with Super+Alt+Space then uses). ink: how much of
    // its icon's height is drawn (measured), so the menu bar can draw each the same visible height
    readonly property var windowModes: [
        { value: "tiling", label: "Tiling", icon: 0xEF94, ink: 0.75, layout: "dwindle" },
        { value: "master", label: "Side Stack", icon: 0xEAD9, ink: 0.75, layout: "master" },
        { value: "scrolling", label: "Scrolling", icon: 0xF659, ink: 0.667, layout: "scrolling" },
        { value: "monocle", label: "Stacking", icon: 0xEAEA, ink: 0.75, layout: "monocle" },
        // Solo: one window per workspace, filling it (a lone tile does); a second one moves on to
        // a new workspace of its own (windowrules.lua)
        { value: "solo", label: "Solo", icon: 0xEFE6, ink: 0.667, layout: "dwindle" },
        { value: "floating", label: "Floating", icon: 0xEE17, ink: 0.833, layout: "dwindle" }
    ]
    // A mode that can be used: an unknown one is tiling
    function usableMode(v) {
        const m = windowModes.find(x => x.value === v);
        return m ? m.value : "tiling";
    }
    // The default window mode (Settings → Windows), for every workspace without one of its own
    readonly property string windowMode: usableMode(s.windowMode)

    // ---- Each workspace's own mode (the menu bar's workspace indicator) ----------------------
    // Workspace id → mode, for the ones set; the rest follow the default. Kept for this Hyprland
    // session in the runtime folder (so it survives Slate reloading and restarting, and Spaces
    // can read it: scripts/spaces.py), not in Settings: workspaces come and go
    readonly property string workspaceModesPath: root.runtimeDir + "/slate/workspace-modes-"
        + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "none") + ".json"
    FileView { id: workspaceModesFile; path: root.workspaceModesPath; blockLoading: true; printErrors: false }
    property var workspaceModes: {
        try { const m = JSON.parse(workspaceModesFile.text() || "{}"); return m && typeof m === "object" ? m : {}; }
        catch (e) { return {}; }
    }
    function workspaceMode(id) {
        const own = workspaceModes[String(id)];
        return own ? usableMode(own) : windowMode;
    }
    readonly property int focusedWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    // What the workspace you're on is called: its own name or "Workspace 3", or a named
    // workspace's name (one made by your own rules, which has no number)
    readonly property string focusedWorkspaceLabel: workspaceLabelOf(Hyprland.focusedWorkspace)
    // The workspaces as one list, in Hyprland's own order: the numbered ones by number, then any
    // named ones by name. Hyprland 0.57 gives a named workspace no number (Quickshell has -1 for
    // every one), so where there's none a workspace is told apart by its name. The secret
    // (special) workspace stays out
    function isShownWorkspace(w) {
        return !!w && (w.id > 0 || (!!w.name && !/^special(:|$)/.test(String(w.name))));
    }
    readonly property var workspaceList: Hyprland.workspaces.values.filter(isShownWorkspace).sort((a, b) =>
        (a.id > 0) !== (b.id > 0) ? (a.id > 0 ? -1 : 1) : a.id > 0 ? a.id - b.id : String(a.name).localeCompare(String(b.name)))
    function sameWorkspace(a, b) { return !!a && !!b && (a.id > 0 ? a.id === b.id : b.id <= 0 && a.name === b.name); }
    function workspaceLabelOf(w) { return !w ? "" : w.id > 0 ? workspaceLabel(w.id) : String(w.name || ""); }
    // The workspace as goToWorkspace (binds.lua) takes it: its number, or a named one's name
    function workspaceTarget(w) { return w.id > 0 ? String(w.id) : luaString("name:" + w.name); }
    readonly property string focusedMode: workspaceMode(focusedWorkspaceId)
    // Any workspace floating (title bars, click to focus)
    readonly property bool anyFloating: windowMode === "floating"
        || Object.keys(workspaceModes).some(k => workspaceMode(k) === "floating")
    // Set (mode "" or the default: back to following it) and apply at once: Hyprland floats
    // or re-tiles that workspace's windows (setWorkspaceMode, windowrules.lua)
    function setWorkspaceMode(id, mode) {
        // (both end up in Lua that Hyprland runs, and this can be called from the command line:
        // only a workspace's number, and only a mode Slate has, or "" for the default)
        id = Number(id);
        if (!Number.isInteger(id) || id <= 0) return;
        if (mode && !windowModes.some(x => x.value === mode)) return;
        const m = Object.assign({}, workspaceModes);
        if (!mode || mode === windowMode) delete m[String(id)];
        else m[String(id)] = mode;
        workspaceModes = m;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "${0%/*}"', workspaceModesPath]);
        workspaceModesFile.setText(JSON.stringify(m));
        Quickshell.execDetached(["hyprctl", "dispatch",
            `function() SLATE_TITLEBARS = ${slateTitleBars}; WINDOW_MODE = "${windowMode}"; if setWorkspaceMode then setWorkspaceMode(${id}, ${luaString(m[String(id)] || "")}) end end`]);
    }
    // ---- Each workspace's own name (the pencil on the window mode panel) -----------------
    // "Coding" in place of "Workspace 3", everywhere Slate would show the number. Kept like the
    // modes above (the runtime folder, for this Hyprland session: it survives Slate reloading,
    // and Spaces reads it), but a name describes what's on the workspace, so it goes when
    // Hyprland removes the workspace (its last window closed and you've moved off it).
    // Slate keeps it itself rather than renaming Hyprland's workspace: Hyprland's own name is
    // what its config and other tools match on.
    readonly property int workspaceNameLimit: 20
    readonly property string workspaceNamesPath: root.runtimeDir + "/slate/workspace-names-"
        + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "none") + ".json"
    FileView { id: workspaceNamesFile; path: root.workspaceNamesPath; blockLoading: true; printErrors: false }
    property var workspaceNames: {
        try { const m = JSON.parse(workspaceNamesFile.text() || "{}"); return m && typeof m === "object" ? m : {}; }
        catch (e) { return {}; }
    }
    function workspaceName(id) { const n = workspaceNames[String(id)]; return typeof n === "string" ? n : ""; }
    // What to call a workspace: its name, or "Workspace 3". Every place that shows one uses this
    function workspaceLabel(id) { return workspaceName(id) || workspaceNumber(id); }
    function workspaceNumber(id) { return "Workspace " + id; }      // (what it's called without a name)
    function saveWorkspaceNames(m) {
        workspaceNames = m;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "${0%/*}"', workspaceNamesPath]);
        workspaceNamesFile.setText(JSON.stringify(m));
    }
    // Swap two workspaces' places (the overview's reorder): their numbers trade through a
    // spare one, so each keeps its windows, their layout and their live pictures (moving the
    // windows across instead re-tiled them, and the overview's previews of them went blank);
    // their names and window modes go with them
    function swapWorkspaces(a, b) {
        if (!(a > 0) || !(b > 0) || a === b) return;
        const spare = 90000 + a;
        Quickshell.execDetached(["hyprctl", "dispatch", "function() "
            + `hl.dispatch(hl.dsp.workspace.change_id({ workspace = ${a}, id = ${spare} })); `
            + `hl.dispatch(hl.dsp.workspace.change_id({ workspace = ${b}, id = ${a} })); `
            + `hl.dispatch(hl.dsp.workspace.change_id({ workspace = ${spare}, id = ${b} })) end`]);
        const n = Object.assign({}, workspaceNames), na = n[String(a)], nb = n[String(b)];
        delete n[String(a)]; delete n[String(b)];
        if (nb !== undefined) n[String(a)] = nb;
        if (na !== undefined) n[String(b)] = na;
        saveWorkspaceNames(n);
        const ma = workspaceModes[String(a)] || "", mb = workspaceModes[String(b)] || "";
        if (ma !== mb) { setWorkspaceMode(a, mb); setWorkspaceMode(b, ma); }
    }
    // Name it (an empty name: back to its number)
    function setWorkspaceName(id, name) {
        if (!(id > 0)) return;
        const m = Object.assign({}, workspaceNames);
        const n = String(name || "").replace(/\s+/g, " ").trim().slice(0, workspaceNameLimit).trim();
        if (n === "") delete m[String(id)];
        else m[String(id)] = n;
        saveWorkspaceNames(m);
    }
    // Forget the names of workspaces that are gone. Not before Hyprland's list is in (just
    // after Slate starts or reloads it's empty for a moment, which would forget them all), and
    // a moment after a change, since a workspace can blink out while its windows move
    Timer {
        id: workspaceNamesPrune
        interval: 1500
        onTriggered: {
            const live = Hyprland.workspaces.values.filter(w => w.id > 0).map(w => String(w.id));
            if (live.length === 0) return;
            const m = {};
            let gone = false;
            for (const k in root.workspaceNames) { if (live.includes(k)) m[k] = root.workspaceNames[k]; else gone = true; }
            if (gone) root.saveWorkspaceNames(m);
        }
    }
    Connections { target: Hyprland.workspaces; function onValuesChanged() { if (Object.keys(root.workspaceNames).length > 0) workspaceNamesPrune.restart(); } }

    // Changing the default mode (Settings → Windows) can shift every workspace in use to it.
    // These are the ones that would change: with windows open, in another mode (the default
    // they follow, or one of their own)
    function workspacesNotIn(v) {
        return Hyprland.workspaces.values.filter(w => w.id > 0 && workspaceMode(w.id) !== v
            && (w.toplevels?.values ?? []).some(t => !isPinnedSlate(t))).map(w => w.id);
    }
    // Change the default. tidy: every workspace takes the new mode, those with a mode of their
    // own included (they go back to following the default), and their windows are rearranged.
    // Otherwise the workspaces in use are left as they are: each keeps the mode it has, as its
    // own, and only new workspaces get the new one
    function setDefaultMode(v, tidy) {
        if (!windowModes.some(x => x.value === v) || v === s.windowMode) return;
        const m = tidy ? {} : Object.assign({}, workspaceModes);
        if (!tidy) for (const id of workspacesNotIn(v)) m[String(id)] = workspaceMode(id);
        // (one whose own mode is the new default just follows it from now on)
        for (const k in m) if (m[k] === v) delete m[k];
        workspaceModes = m;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "${0%/*}"', workspaceModesPath]);
        workspaceModesFile.setText(JSON.stringify(m));
        s.windowMode = v;          // (shell.qml tells Hyprland, with each workspace's mode)
    }
    // For the Lua config: { [3] = "floating", … } (shell.qml sends it with the rest)
    readonly property string workspaceModesLua: "{ " + Object.keys(workspaceModes)
        .filter(k => /^\d+$/.test(k)).map(k => `[${k}] = "${workspaceMode(k)}"`).join(", ") + " }"
    // Hyprland's layout for it (binds.lua also gets the mode, as WINDOW_MODE, for Super+J and
    // focusing in monocle)
    readonly property string hyprLayout: windowModes.find(x => x.value === windowMode).layout
    function refreshWallpaperAccent() {
        if (wallpaper === "") return;
        // (the wallpaper switcher: one already looked at has its colours back at once)
        const known = wallpaperSwitching ? wallpaperColourMemo[wallpaper] : null;
        if (known) {
            picker.running = false;
            wallpaperAccent = known.accent;
            wallpaperTone = known.tone;
            return;
        }
        picker.forWallpaper = wallpaper;
        picker.command = [Qt.resolvedUrl("scripts/wallpaper-accent.py").toString().replace("file://", ""), wallpaper];
        // (started afresh: one still working out an earlier wallpaper's colours would carry on
        // with that one, and this one's would never be worked out)
        picker.running = false;
        picker.running = true;
    }
    Process {
        id: picker
        property string forWallpaper: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                // (another wallpaper's on screen since, or it was stopped for one)
                if (picker.forWallpaper !== root.wallpaper || !/^#[0-9a-f]{6}$/i.test(lines[0])) return;
                root.wallpaperAccent = lines[0];
                if (lines[1] && /^#[0-9a-f]{6}$/i.test(lines[1])) root.wallpaperTone = lines[1];
                if (root.wallpaperSwitching) root.rememberWallpaperColours(picker.forWallpaper);
                root.saveColourCache(picker.forWallpaper);
            }
        }
    }
    // The wallpaper switcher: the colours of the wallpaper on screen, kept for it
    function rememberWallpaperColours(path) {
        if (path === "" || !isHex(wallpaperAccent)) return;
        const m = Object.assign({}, wallpaperColourMemo);
        m[path] = { accent: wallpaperAccent, tone: wallpaperTone };
        wallpaperColourMemo = m;
    }
    // The wallpaper's colours, kept between reloads: working them out takes a moment, and until
    // then the theme showed in its default colours. Only a cache for the wallpaper in use, with
    // colours in the right form, is used; anything else (no file, unreadable, another wallpaper)
    // is ignored and they're worked out as before. Not on the login screen.
    function isHex(c) { return typeof c === "string" && /^#[0-9a-f]{6}$/i.test(c); }
    FileView {
        id: colourCache
        path: root.cacheHome + "/slate/wallpaper-colours.json"
        blockLoading: true
        printErrors: false
    }
    function loadColourCache() {
        if (isLoginScreen) return;
        try {
            const c = JSON.parse(colourCache.text() || "null");
            if (!c || c.wallpaper !== s.wallpaper || s.wallpaper === "") return;
            if (isHex(c.accent) && wallpaperAccent === "") wallpaperAccent = c.accent;
            if (isHex(c.tone) && wallpaperTone === "") wallpaperTone = c.tone;
        } catch (e) {
            // A damaged cache: start without it (it's written again once the colours are worked out)
        }
    }
    function saveColourCache(forWallpaper) {
        // (not for one the wallpaper switcher is only showing: the cache is for the one saved)
        if (isLoginScreen || forWallpaper === "" || forWallpaper !== wallpaper || forWallpaper !== s.wallpaper || !isHex(wallpaperAccent)) return;
        const text = JSON.stringify({ wallpaper: forWallpaper, accent: wallpaperAccent, tone: isHex(wallpaperTone) ? wallpaperTone : "" }) + "\n";
        if (colourCache.text() === text) return;
        cacheDir.running = false; cacheDir.pending = text; cacheDir.running = true;
    }
    // (the folder may not exist yet)
    Process {
        id: cacheDir
        property string pending: ""
        command: ["mkdir", "-p", colourCache.path.replace(/\/[^/]*$/, "")]
        onExited: code => { if (code === 0) colourCache.setText(pending); }
    }

    // The theme's colours, kept in a small file for the "Reloading Slate" cover (reloading/
    // shell.qml): it runs by itself while Slate restarts, with no Config to ask, and should
    // still be in the colours in use (light or dark, the wallpaper's tint, the accent).
    // Written a moment after any of them changes. Not on the login screen
    readonly property string coverColours: JSON.stringify({
        background: "" + tint("#0f1216"), text: "" + tint("#eef1f5"), dim: "" + tint("#8b94a3"), accent: "" + accent,
        mark: "" + tint("#566173") }) + "\n"
    onCoverColoursChanged: coverLater.restart()
    // (not while the wallpaper switcher is showing one: once it closes)
    onWallpaperSwitchingChanged: { if (!wallpaperSwitching) coverLater.restart(); if (!wallpaperSwitching && hyprPushHeld) hyprPush.restart(); }   // (the held-back push, hyprPush)
    Timer { id: coverLater; interval: 800; running: true; onTriggered: if (!root.isLoginScreen && !root.wallpaperSwitching && coverFile.text() !== root.coverColours) { coverDir.running = false; coverDir.running = true; } }
    FileView {
        id: coverFile
        path: root.cacheHome + "/slate/cover.json"
        blockLoading: true
        printErrors: false
    }
    Process {
        id: coverDir
        command: ["mkdir", "-p", coverFile.path.replace(/\/[^/]*$/, "")]
        onExited: code => { if (code === 0) coverFile.setText(root.coverColours); }
    }

    FileView {
        id: file
        path: root.isLoginScreen ? (root.loginLook !== "" ? root.loginLook + "/settings.json"
                                                         : Qt.resolvedUrl("settings.json").toString().replace("file://", ""))
            : root.userDir + "/settings.json"
        watchChanges: true
        // Each save finishes before anything else happens, so the file is never caught halfway
        blockWrites: true
        // Reload when something else edits the file (a hand edit). Our own saves trigger this too,
        // sometimes late (while Slate is busy applying a theme); reloading one of those could put
        // back settings changed since, which is how a preset sometimes came out as Custom. So it
        // goes by what's in the file, not the time: only a file that differs from the settings in
        // use is loaded.
        onFileChanged: {
            if (root.diskMatches()) return;
            reload();
            root.saved();
            Qt.callLater(root.separateBarAndDock);
        }
        // Changes are saved together, a moment after the last one: a preset or Restore defaults
        // changes many at once, and is written once rather than once for each
        // (the login screen only ever reads: the settings there are a copy, someone's look)
        onAdapterUpdated: { if (!root.isLoginScreen) settingsSave.restart(); root.saved(); }
        // First run: create the file with the defaults (SettingsData.qml)
        onLoadFailed: error => { if (error === FileViewError.FileNotFound && !root.isLoginScreen) writeAdapter(); }

        adapter: SettingsData { id: adapter }
        // Read before anything is drawn (Config's Component.onCompleted), not in the background:
        // otherwise the first frames after a reload used the default theme
        blockLoading: true
    }
    Timer { id: settingsSave; interval: 50; onTriggered: file.writeAdapter() }
    // settings.json as it is on disk, read only to compare (diskMatches)
    FileView { id: diskCopy; path: file.path; blockLoading: true; printErrors: false }
    // Whether the file holds the settings in use (our own save), rather than an edit made elsewhere
    function diskMatches() {
        if (settingsSave.running) return true;          // our save is still to come; it wins
        diskCopy.reload();
        let d;
        try { d = JSON.parse(diskCopy.text()); } catch (e) { return true; }   // half-written: wait for the next change
        for (const k in d) if (adapter[k] !== undefined && !sameValue(d[k], adapter[k])) return false;
        return true;
    }

    // ---- Slate's sounds (sounds/<name>.wav), each at its own volume (Settings → Sound) -------
    // With Qt Multimedia (optional) each is loaded once and plays straight away; without it
    // pw-play starts for each one, a little late (~80 ms) but fine for the chime and the tick
    property var effects: ({})
    // Qt keeps loaded sounds for as long as Slate runs, even across reloads; a stamp per load
    // makes a reload (or an update) pick up changed sound files
    property real soundStamp: 0
    function effect(name) {
        if (name in effects) return effects[name];
        if (!soundStamp) soundStamp = Date.now();     // set on first use, whatever the load order
        let e = null;
        try {
            e = Qt.createQmlObject("import QtMultimedia; SoundEffect { source: "
                + JSON.stringify(Qt.resolvedUrl("sounds/" + name + ".wav").toString() + "?v=" + soundStamp) + " }", root, "sound-" + name);
        } catch (err) { e = null; }
        effects[name] = e;
        return e;
    }
    // The click needs to be on time, so it only plays with Qt Multimedia (Settings says so).
    // Worked out once at start (a binding would loop: loading a sound sets soundStamp)
    property bool clickAvailable: false
    // Qt Multimedia (qt6-multimedia, optional) is there: the click sound and the screensaver's
    // videos need it (found by loading the click, which only works with it)
    readonly property bool multimediaAvailable: clickAvailable
    // How loud each sound is (Settings → Sound), 0-100, 0 = off. Not set yet: from the earlier
    // on/off switch and the single effects volume
    readonly property var soundSettings: ({
        tick: ["tickVolume", "volumeSound"], notification: ["notificationVolume", "notificationSound"],
        click: ["clickVolume", "clickSound"], swish: ["swishVolume", "swishSound"],
        welcome: ["welcomeVolume", "welcomeSound"], goodbye: ["goodbyeVolume", "goodbyeSound"],
        attention: ["attentionVolume", ""],      // newer than the switches: on, at the effects volume
        answered: ["answeredVolume", ""]         // (Nova's answer: the same)
    })
    function soundVolume(which) {
        const k = soundSettings[which];
        if (!k) return 0;
        const v = s[k[0]];
        if (v >= 0) return Math.min(100, v);
        return !k[1] || s[k[1]] ? Math.max(0, Math.min(100, s.soundEffectsVolume)) : 0;
    }
    // Play sounds/<name>.wav at the volume set for `which` (Settings → Sound). The tests'
    // Slate never plays one: it notes the name in testSounds instead (the last 20), for a
    // test to check what would have played
    property var testSounds: []
    function playSound(name, which) {
        const v = soundVolume(which) / 100;
        if (v <= 0) return;
        if (testMode) { testSounds = testSounds.concat([name]).slice(-20); return; }
        const e = effect(name);
        if (e) { e.volume = v; e.play(); return; }
        Quickshell.execDetached(["sh", "-c", "pw-play --volume=\"$1\" \"$0\" 2>/dev/null || paplay --volume=\"$2\" \"$0\"",
            Quickshell.shellPath("sounds/" + name + ".wav"), v.toFixed(2), String(Math.round(v * 65536))]);
    }
    // Logging in: Slate fades in from the dark (FadeIn.qml) with the welcome sound, once per session
    // (per start of Hyprland), not when Slate reloads or restarts. A marker in the runtime folder,
    // named for this Hyprland instance, says it's happened. It's read as this file loads, before
    // any window opens, so the screens are covered from the very first frame (the wallpaper never
    // shows first). welcomeCheck then writes the marker; a moment's wait lets the sound system come
    // up, then the sound plays and the cover fades. The login screen loads this file too but has no
    // sounds/ (greeter/files), so the check fails there: it stays silent and doesn't fade.
    readonly property string welcomeMarker: root.runtimeDir + "/slate/welcomed-"
        + (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "none")
    FileView { id: welcomeMarkerFile; path: root.welcomeMarker; blockLoading: true; printErrors: false }
    // covered until welcomeFading, then fading out
    property bool welcoming: { if (testMode) return false; welcomeMarkerFile.text(); return !welcomeMarkerFile.loaded; }
    property bool welcomeFading: false
    Process {
        id: welcomeCheck
        running: !root.testMode
        command: ["sh", "-c", '[ -e "$0" ] || exit 1; f="$1"; [ -e "$f" ] && exit 1; mkdir -p "${f%/*}" && : > "$f"',
            Quickshell.shellPath("sounds/welcome.wav"), root.welcomeMarker]
        onExited: code => { if (code === 0) welcomeStart.start(); else root.welcoming = false; }
    }
    Timer {
        id: welcomeStart; interval: 1500
        onTriggered: { root.playSound("welcome", "welcome"); root.welcomeFading = true; }
    }

    // Log out, restart or shut down (scripts/session.sh), with the goodbye sound first when it's on.
    // The screens fade to black (FadeOut.qml) while it plays; with the sound off, a shorter fade
    // runs first. If the session is somehow still here a while later (the action failed), the
    // black goes away again.
    property bool leaving: false
    property int leaveFade: 2400
    property string leaveAction: ""
    function sessionAction(action) {
        if (leaving) return;
        const v = soundVolume("goodbye") / 100;
        leaveFade = v > 0 ? 2400 : 900;
        leaveAction = action;
        leaving = true;
        leaveGiveUp.restart();
        if (v > 0) runSessionAction();
        else leaveAfterFade.restart();
    }
    function runSessionAction() {
        Quickshell.execDetached([Quickshell.shellPath("scripts/session.sh"), leaveAction, (soundVolume("goodbye") / 100).toFixed(2)]
            .concat(reopenMode !== "never" ? ["reopen"] : []));
    }
    Timer { id: leaveAfterFade; interval: root.leaveFade; onTriggered: root.runSessionAction() }
    Timer { id: leaveGiveUp; interval: 20000; onTriggered: root.leaving = false }

    // A soft question for confirmations, password prompts and warnings (Settings → Sound);
    // two dialogs opening together ask once
    property real lastAttention: 0
    function attention() {
        if (Date.now() - lastAttention < 800) return;
        lastAttention = Date.now();
        playSound("attention", "attention");
    }

    // A soft swish when switching (Settings → Sound): workspaces on the desktop, and moving
    // through the window switcher and workspace overview. step < 0 drifts gently left,
    // otherwise right; quick repeats (holding a key) swish once.
    property real lastSwish: 0
    function swish(step) {
        if (soundVolume("swish") <= 0 || Date.now() - lastSwish < 60) return;
        lastSwish = Date.now();
        playSound(step < 0 ? "swish-left" : "swish-right", "swish");
    }
    // Each screen's workspace: when one changes (keys, the bar, the overview…), swish towards
    // it. Focus moving between screens changes nothing here, so it's silent; so is a reload.
    readonly property string screenWorkspaces: Hyprland.monitors.values
        .map(m => m.name + "=" + ((m.activeWorkspace && m.activeWorkspace.id) || 0)).join(",")
    property var lastScreenWorkspaces: null
    onScreenWorkspacesChanged: {
        const now = {};
        for (const pair of screenWorkspaces.split(",")) {
            const [name, id] = pair.split("=");
            if (name) now[name] = Number(id);
        }
        const before = lastScreenWorkspaces;
        lastScreenWorkspaces = now;
        if (!before) return;
        for (const name in now) {
            const a = before[name], b = now[name];
            if (a > 0 && b > 0 && a !== b) { swish(b - a); return; }
        }
    }

    // A very quiet click for Slate's buttons, menus and toggles (ClickTap / ClickArea)
    property real lastClick: 0
    function click() {
        if (!clickAvailable || soundVolume("click") <= 0 || Date.now() - lastClick < 40) return;
        lastClick = Date.now();
        playSound("click", "click");
    }
    // ---- Defaults --------------------------------------------------------------------
    // A spare copy of the settings, never loaded from disk, so it holds the defaults
    SettingsData { id: defaults }
    function defaultOf(key) { return defaults[key]; }
    // Settings Hyprland applies (hyprSettings): putting one back to "not set here" reloads
    // Hyprland's config, so its own value (or your hyprland.lua's) is used again
    readonly property var hyprKeys: ["kbLayouts", "kbVariants", "kbSwitch", "capsLock", "keyRepeatDelay", "keyRepeatRate",
        "mouseSpeed", "mouseAccel", "mouseNaturalScroll", "touchpadScrollSpeed", "touchpadNaturalScroll",
        "touchpadTapToClick", "touchpadIgnoreWhileTyping", "focusFollowsMouse", "animations", "cursorSize",
        "defaultTerminal", "defaultBrowser", "defaultFileManager", "defaultEditor", "defaultCalculator"]
    Timer { id: hyprReload; interval: 300; onTriggered: root.reloadHyprland() }
    // One of them changed from `was` to what it is now: put back to "not set here", Hyprland
    // still holds the old value (Slate stops sending it, it doesn't send Hyprland's own), so
    // its config is reloaded. (config set and Restore defaults: putting your keyboard layouts
    // back left the old ones in use, and the bar's layout switcher with them)
    function hyprKeyEdited(key, was) {
        if (hyprKeys.includes(key) && !sameValue(was, defaults[key]) && sameValue(root.s[key], defaults[key]))
            hyprReload.restart();
    }
    // Slate reloading Hyprland's config itself (to apply something of its own), rather than you
    // editing your Hyprland files: shell.qml leaves out the "reloaded" notice for these
    property real ownHyprReloadAt: 0
    function reloadHyprland() {
        ownHyprReloadAt = Date.now();
        Quickshell.execDetached(["hyprctl", "reload"]);
    }
    function ownHyprReload() { return Date.now() - ownHyprReloadAt < 5000; }
    function sameValue(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
    // Put these settings back to their defaults (Settings → each page's Restore defaults)
    function resetKeys(keys) {
        for (const k of keys) {
            if (defaults[k] === undefined) continue;
            if (k === "barPosition") moveBar(defaults[k]);
            else if (k === "dockPosition") moveDock(defaults[k]);
            else if (!sameValue(root.s[k], defaults[k])) {
                const was = root.s[k];
                root.s[k] = defaults[k];
                if (k === "uiScale") uiScaleEdited();
                if (k === "logLevel") logLevelEdited();
                hyprKeyEdited(k, was);
            }
        }
    }
    // How many of these differ from their defaults
    function changedCount(keys) {
        let n = 0;
        for (const k of keys) if (defaults[k] !== undefined && !sameValue(root.s[k], defaults[k])) n++;
        return n;
    }

    // ---- Clipboard history (scripts/clipstore.py): how many items it holds, for the bar ----
    readonly property string clipIndex: root.stateHome + "/slate/clipboard/index.json"
    property int clipCount: 0
    FileView {
        path: root.clipIndex
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.clipCount = (JSON.parse(text()).entries || []).length; } catch (e) { root.clipCount = 0; } }
        onLoadFailed: root.clipCount = 0
    }
}
