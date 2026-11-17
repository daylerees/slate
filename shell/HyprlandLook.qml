// Hyprland's look, from Slate's theme: window borders and gaps, window mode, the title bar
// plugin's colours and buttons, put back whenever Hyprland reloads its config (which it's
// also checked for errors).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root
    property var hold: null                  // UpdateHold.qml
    property var userFiles: null            // UserFiles.qml (its errors are part of the notice)

    // Window borders follow the theme (and the width set in Settings): accent on the active window, the bar's colour on
    // the others (60% and 85%; Hyprland cannot blur behind borders), plus dimming and gaps. Hyprland's config
    // (colors.lua) has fallbacks; these replace them, and again after a config reload.
    readonly property string borderCmd: {
        const rgba = (c, a) => "rgba(" + c.toString().slice(1, 7) + Math.round(a * 255).toString(16).padStart(2, "0") + ")";
        // (Accessibility → High contrast: a bright, solid border round the window you're in, and
        // a plainly visible one round the rest)
        const hc = Config.s.highContrast;
        const active = hc ? rgba(Config.tint("#eef1f5"), 1) : rgba(Config.accent, 0.6);
        const inactive = hc ? rgba(Config.tint("#5a6372"), 1) : rgba(Config.tint("#0f1216"), 0.85);
        // Glass (with its gloss): a sheen on the borders, as Hyprland can draw one. Its gradients
        // spread their colours evenly, so the light is the first of several: a bright catch on
        // the top left corner, fading within the first sixth or so into the colour itself, a
        // touch deeper at the far corner (how strong follows Glass → Gloss). Hyprland's angles
        // put the first colour at the left for 0°, the top for 90°: 45° is the top left.
        // Without glass (or in game mode), flat
        // (Config.borderSheen: shared with Slate's own windows, WindowBorder.qml)
        const g = Config.glassGloss ? Math.min(1, Config.glossAmount) : 0;
        const sheen = (pairs) => pairs.map(p => `"${rgba(p[0], p[1])}"`).join(", ");
        const activeColors = g > 0 ? sheen(Config.activeBorderSheen) : `"${active}"`;
        const inactiveBorder = g > 0
            ? `{ colors = { ${sheen(Config.borderSheen(Config.tint("#0f1216"), 0.85, 0.3, 0.1, 0))} }, angle = 45 }`
            : `"${inactive}"`;
        const size = Math.max(hc ? 3 : 0, Math.min(12, Config.s.windowBorderSize));   // Settings → Windows (at least 3 in high contrast)
        const dim = Math.max(0, Math.min(80, Config.s.inactiveDim)) / 100;   // Settings → Windows
        // Spacing: gaps_in is added on each side of a window, so half the gap between two;
        // the screen edges get a little more. Lone windows stay gapless (workspaces.lua)
        const gap = Math.max(0, Math.min(32, Config.s.windowGap));
        const gapIn = Math.round(gap / 2), gapOut = gap > 0 ? gap + 2 : 0;
        // A window alone on its workspace: no gaps unless set (re-sending a rule replaces it).
        // Maximised and full-screen apps always fill the screen.
        const solo = Math.max(0, Math.min(32, Config.s.soloWindowGap));
        // ...with square corners only while it fills the screen (rule in windowrules.lua)
        const solos = `hl.workspace_rule({ workspace = "w[tv1]", gaps_out = ${solo}, gaps_in = 0 }); `
            + `if SOLO_SQUARE_RULE then SOLO_SQUARE_RULE:set_enabled(${solo === 0}) end; `;
        // Window mode: Hyprland's layout, and the float-all rule on or off (windowrules.lua); converting open
        // windows happens only when the setting changes (below)
        const mode = `hl.config({ general = { layout = "${Config.hyprLayout}" } }); WINDOW_MODE = "${Config.windowMode}"; `
            + `SLATE_TITLEBARS = ${Config.slateTitleBars}; SLATE_TITLEBAR_HEIGHT = ${Math.round(13 * 2.6 * Config.uiScale)}; WORKSPACE_MODES = ${Config.workspaceModesLua}; `
            + `if setWindowMode then setWindowMode(${Config.windowMode === "floating"}, false) end; `
            + `if setSpareWorkspace then setSpareWorkspace(${Config.s.keepEmptyWorkspace}) end; `;
        // Floating windows' title bars (hyprbars, when built): Slate's bar colour, text, font and button colours
        const bars = `if HYPRBARS_LOADED then pcall(hl.config, { plugin = { hyprbars = { bar_color = "${rgba(Config.tint("#0f1216"), 1)}", `
            + `col = { text = "${rgba(Config.tint("#eef1f5"), 1)}" }, inactive_button_color = "${rgba(Config.tint("#3a424e"), 1)}", `
            + `bar_text_font = ${Config.luaString(Config.s.fontFamily)}, bar_text_size = ${Math.round(13 * Config.uiScale)}, bar_height = ${Math.round(13 * 2.6 * Config.uiScale)}, `
            + `bar_buttons_alignment = "${Config.s.titleButtons === "left" ? "left" : "right"}" } } }); `
            + `if HYPRBARS_IDLE then pcall(hl.config, { plugin = { hyprbars = { idle_button_color = "${rgba(Config.tint("#5a6372"), 1)}" } } }) end end; `;
        return solos + mode + bars + `ACTIVE_BORDER = { colors = { ${activeColors} }${g > 0 ? ", angle = 45" : ""} }; INACTIVE_BORDER = ${inactiveBorder}; BORDER_SIZE = ${size}; `
            + `hl.config({ general = { border_size = BORDER_SIZE, gaps_in = ${gapIn}, gaps_out = ${gapOut}, col = { active_border = ACTIVE_BORDER, inactive_border = INACTIVE_BORDER } }, `
            + `decoration = { dim_inactive = ${dim > 0}, dim_strength = ${dim.toFixed(2)} } })`;
    }
    onBorderCmdChanged: borderPush.restart()
    // Title bar button colours and size (hyprbars.lua reads them when Hyprland's config loads, as
    // hyprbars can't recolour buttons later): written here, then Hyprland reloads, only when
    // they've changed and title bars are showing (floating mode). In tiling mode there are none to
    // recolour, so the reload waits until floating mode comes on: a reload makes the screen
    // flicker, and the accent changes with every theme preset and, from the wallpaper, with it
    readonly property string barButtonsLua: {
        const rgb = c => "rgb(" + c.toString().slice(1, 7) + ")";
        return `return { accent = "${rgb(Config.accent)}", accent_text = "${rgb(Config.tint("#12151a"))}", `
            + `button_size = ${Math.round(13 * 1.25 * Config.uiScale)} }\n`;
    }
    onBarButtonsLuaChanged: barButtonsSync.restart()
    FileView {
        id: barButtonsFile
        path: Config.stateHome + "/slate/hyprbars.lua"
        blockLoading: true
        printErrors: false
    }
    Timer {
        id: barButtonsSync
        interval: 1500; running: true
        onTriggered: {
            if (root.hold.heldBack(barButtonsSync) || barButtonsFile.text() === root.barButtonsLua) return;
            barButtonsFile.setText(root.barButtonsLua);
            if (Config.anyFloating && !Config.slateTitleBars) barButtonsReload.restart();
            else root.barButtonsStale = true;
        }
    }
    // Written while there were no title bars; Hyprland hasn't read them yet
    property bool barButtonsStale: false
    Connections {
        target: Config
        function onAnyFloatingChanged() { if (Config.anyFloating && !Config.slateTitleBars && root.barButtonsStale) barButtonsReload.restart(); }
    }
    Timer { id: barButtonsReload; interval: 300; onTriggered: { root.barButtonsStale = false; Config.reloadHyprland(); } }
    // Switching window mode also floats (or re-tiles) the windows already open. Only when
    // the setting changes: title bars turning up or going away just changes new windows
    Connections {
        target: Config.s
        function onWindowModeChanged() {
            Quickshell.execDetached(["hyprctl", "dispatch",
                `function() WINDOW_MODE = "${Config.windowMode}"; WORKSPACE_MODES = ${Config.workspaceModesLua}; if setWindowMode then setWindowMode(${Config.windowMode === "floating"}, true) end end`]);
        }
    }
    Timer { id: borderPush; interval: 300; running: true; onTriggered: if (!root.hold.heldBack(borderPush)) Quickshell.execDetached(["hyprctl", "eval", root.borderCmd]) }
    Connections {
        target: Config
        // Hyprland reloaded: borders go back (and see whether Hyprbars is loaded now: it may
        // have been rebuilt), and check the config for errors
        function onHyprConfigReloaded() {
            borderPush.restart();
            Config.checkTitleBars();
            root.barButtonsStale = false;
            hyprErrors.running = false; hyprErrors.running = true;
        }
    }
    // (hyprErrors runs again whenever Hyprland reloads: see onHyprConfigReloaded above)
    // Everything wrong with Hyprland's config, in one notice: Hyprland's own config errors, and
    // your files in hypr/ that failed to load. Hyprland knows nothing of those: the session's
    // hyprland.lua skips such a file and notes it in slate-hypr-errors.txt, so that's read here
    // too (after a line holding only a record separator, to tell the two apart). UserFiles.qml
    // once reported them itself, so one mistake made two notifications that could disagree
    Process {
        id: hyprErrors
        command: ["sh", "-c", "hyprctl -j configerrors 2>/dev/null; printf '\\n\\036\\n'; cat \"$0\" 2>/dev/null", userFiles.errorsPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\x1e");
                let errs = [];
                try { errs = JSON.parse(parts[0]).filter(e => e && String(e).trim() !== "").map(String); } catch (e) {}
                // (your own files first: each line says which file it's in)
                errs = (parts[1] || "").split("\n").map(l => l.trim()).filter(l => l !== "").concat(errs);
                // No news when Slate reloaded it itself (to apply a setting); errors always show
                if (errs.length === 0 && Config.ownHyprReload()) return;
                if (errs.length === 0)
                    Quickshell.execDetached(Config.notify("Hyprland settings reloaded", "Hyprland has read its config again, and all is well.", { page: "windows" }));
                else
                    Quickshell.execDetached(Config.notify("Hyprland settings have errors",
                        errs.join("\n").split("\n").slice(0, 6).join("\n"), { page: "windows" }));
            }
        }
    }
}
