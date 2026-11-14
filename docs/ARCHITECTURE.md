# Architecture

Slate is one Quickshell config (`shell.qml` is the root) plus a set of Hyprland Lua
config files that bind keys and run Slate commands. Everything visible is a Wayland
layer-shell surface (`PanelWindow`), except the settings window (`FloatingWindow`) and
the lock screen (`WlSessionLock`).

## Components (`~/.config/slate`)

```
shell.qml               root: creates everything below, plus the dock itself
├─ Bar.qml              top bar (layer "slate-bar")
├─ BarLabel.qml         the label off the bar saying what the pointer's over ("slate-bar-label")
├─ Popouts.qml          drop-down panels under the bar ("slate-popout")
├─ PowerConfirm.qml     centred confirmation ("slate-confirm"): log out / restart / shut down,
│                       and confirmWith() for anything else (deleting a space)
├─ Wallpaper.qml        desktop wallpaper, one per screen ("slate-wallpaper")
├─ Picker.qml           clipboard history + emoji picker ("slate-picker")
├─ PolkitAgent.qml      password prompts for apps ("slate-polkit")
├─ NightLight.qml       warm screen via Hyprland's screen shader
├─ Radios.qml          Wi-Fi and Bluetooth through IPC (`wifi`, `bluetooth`), for the assistant's tools
├─ Notifications.qml    notification server + toasts ("slate-notifications")
│  └─ NotificationCard.qml
├─ Launcher.qml         app launcher + calculator ("slate-launcher")
├─ Switcher.qml         Super+Tab window switcher ("slate-switcher")
├─ WorkspaceOverview.qml Super+Down workspace overview ("slate-overview")
├─ SettingsWindow.qml   settings app (floating window "Slate Settings")
├─ ScreenCorners.qml    bottom screen corners ("slate-corners")
├─ FadeIn.qml           fade in from the dark (with the logo) at login, with the welcome sound ("slate-fade-in")
├─ TitleBar.qml         Slate Bars: Slate's own title bar on the floating window in front (the default)
├─ SecretEmpty.qml      the note in the middle of the screen while the secret workspace shows with nothing on it
├─ HyprbarsWatch.qml     Hyprbars, the optional title-bar plugin: notices when it needs rebuilding, falls back to Slate Bars, asks
│                       on the topmost floating window (last in hyprctl clients, which runs bottom to top)
│                       ("slate-titlebar"; drags with slateDragMove/slateDragEnd in animations.lua; a layer
│                       can't be locked to a window, so a drag hides the bar, moves the pointer to the
│                       window's middle (hl.dsp.cursor.move) and shows a move handle there instead; its top
│                       corners resize the same way, from that corner of the window (slateDragResize). Its
│                       maximise (button, double-click, Super+D for floating windows: ipc titlebar maximise)
│                       fills the usable area less the bar's height, with no border, rounding or shadow
│                       (slatePlace/slateFlat), so the bar stays as its only frame
├─ FadeOut.qml          fade to black on log out, restart, shut down, with the goodbye sound ("slate-fade-out")
├─ OSD.qml              volume/brightness indicators ("slate-osd")
├─ LockScreen.qml       session lock, PAM, idle, sleep hook
│  └─ LoginScreen.qml   the lock/login screen design (shared with the greeter)
└─ HotCorners.qml       hot corners ("slate-hotcorner")

Config.qml              singleton: settings.json + theme helpers (accent, tint()), window
                        rounding (windowRounding, windowRadius()) for previews and borders,
                        Slate's sounds (playSound(), click())
ClickTap.qml, ClickArea.qml  TapHandler / MouseArea that also play the click (Settings → Sound)
Spaces.qml              singleton: saved Spaces (spaces.json), runs scripts/spaces.py
UserFiles.qml           your hypr/*.lua and user/shell.qml: made if missing, reload on save
Screensaver.qml         idle screensaver, before the lock ("slate-screensaver")
Updates.qml             singleton: new releases (scripts/update.py): daily check, notification,
                        install and go back (Settings → Updates)
AppTile.qml             an app's icon tile by desktop id (Spaces panel)
SpaceBadges.qml         a space's icon on the windows it opened ("slate-space-badge")
SpaceBadge.qml          one space badge (icon on colour): window corners, switcher, overview
SmoothWheel.qml         momentum wheel/touchpad scrolling for lists
DockBacking.qml         the dock's glass behind a magnified tile, where it rises above the dock
IconGloss.qml           the glass sheen on an app icon's tile, the same everywhere icons show
WebcamPreview.qml       Settings → Webcam's live picture (Qt Multimedia; loaded only when shown)
MenuPointer.qml         the little point on a menu's edge (dock and tray menus), drawn only outside the menu
scripts/webcam.py       Settings → Webcam: cameras, their picture settings (v4l2-ctl), kept per
                        camera and put back at login; which apps use the camera
scripts/tray-watcher.py the tray's register (org.kde.StatusNotifierWatcher), run apart from Slate
                        (started detached by the session and by Slate) so tray icons outlive
                        Slate's restarts; without it, Quickshell is the register itself. It
                        always reports a tray as showing, so apps that check once as they
                        start (Electron) still sign up while Slate is starting or restarting
wallpapers/             Slate's own wallpapers, 4K (made by tools/make-wallpapers.py); listed in Settings → Appearance below your folder's
sounds/                 volume tick; notification chime, attention, click, swish, welcome and goodbye (made by tools/make-sounds.py)
RoundImage.qml          rounded image helper
scripts/wallpaper-accent.py   picks accent + overall tone from the wallpaper
scripts/slate-mcp.py          `slate mcp`: Slate's MCP server, for AI agents (ASSISTANT.md): tools that look,
                              change and (always asking) close or leave, over Slate's IPC, `hyprctl`
                              and spaces.py; standard library only. Every call goes through its gate
                              and into ~/.local/state/slate/assistant/activity.jsonl.
                              data/assistant-prompt.md is what it tells an agent about Slate
scripts/assistant.py          hands a prompt to the person's own agent CLI (`detect`, `run`, `briefing`):
                              adds Slate's briefing and a few lines on the moment, runs the agent
                              in an empty folder with Slate's server as its tools, and turns what
                              it prints into start/text/blocks/done/error lines. scripts/slate_agents.py
                              has the agents (Claude Code, a command of your own);
                              scripts/safe_markdown.py reads the answer's small, safe subset of
                              Markdown into the blocks the window draws (no HTML, nothing fetched)
Shadow.qml                    the shadow under anything raised (panels, menus, the launcher, notifications,
                              Nova, the bar): one look, dark with a light tint of the theme
                              (Config.shadowColour, also sent to Hyprland for floating windows), drawn by
                              shaders/shadow.frag with the surface's own shape cut out of it, so glass
                              can have shadows too. Off in game mode
BarEditor.qml                 Arranging the menu bar (Settings → Menu Bar → Edit layout): the panel by the bar ("slate-bar-editor": the pool, what leaves first when it doesn't fit, the picked thing's options), the dimming over the windows ("slate-bar-dim") and what's carried under the pointer ("slate-bar-drag"). The dragging itself is in Bar.qml; the arrangement and what changes it are Config's bar… functions
Assistant.qml                 Nova's prompt window ("slate-assistant", Super+K): runs scripts/assistant.py
                              for a prompt, shows the answer (drawn from the runner's blocks:
                              lists, bold, code boxes with Copy; never Qt's own Markdown) and what was done, as
                              Slate's server reports it (`assistant did`)
AssistantGate.qml             Slate's half of that gate (`assistant` IPC): whether assistants are
                              allowed and what they may see, and their questions, shown with
                              PowerConfirm and held until the server reads the answer
scripts/update.py             GitHub releases: check, list hand-changed files (against the
                              installed .manifest), install (install.sh --update), go back
bin/slate-init                the one place that knows the init system and login service: systemd, or
                              elogind with OpenRC, runit, dinit or s6. Power (suspend, restart, shut
                              down), inhibitors, date and time, whether a service runs and the command
                              that switches it on, the login manager. Nothing else calls systemctl,
                              systemd-inhibit or timedatectl (a test checks). Config.system holds its
                              `info`, so Settings and the panels leave out or explain what can't be done
scripts/session-services.sh   at session start: Hyprland's environment to D-Bus (and systemd); without
                              systemd, PipeWire, WirePlumber and pipewire-pulse too
bin/slate-system              packages (packaging/<distro>.txt, copied in) and the login session
                              in step with this version: --check, --fix (pkexec), --prompt
                              (urgent notification 25 s after start; shell.qml)
shaders/mono.frag(.qsb)       tray icons → single theme colour
shaders/dither.frag(.qsb)     Slate's own wallpapers: scaled to the screen on the GPU and rounded with fine noise, so smooth colour doesn't band (Wallpaper.qml)
shaders/shadow.frag(.qsb)     Shadow.qml's cut-out shadow, worked out per pixel (no blur pass)
shaders/preview.frag(.qsb)    live window previews: rounded, inactive windows brightened back (PreviewShape.qml)
WindowPreview.qml             every live window preview (overview, switcher, dock, New Space): frames
                              asked for by Slate, not Quickshell's live mode (see Workarounds below)
reloading/              the "Reloading Slate" cover `slate restart` shows: a small Quickshell
                        setup of its own, so it outlives the Slate it covers for
greeter/                the login screen (see LOCK-AND-LOGIN.md); greeter/files lists
                        everything it's installed with, greeter/emergency/ is its fallback
```

Only one of launcher / window switcher / workspace overview is open at once, and
opening any of them closes bar panels (wired in `shell.qml`).

## Settings and theme

- `Config.s.<name>` is a `JsonAdapter` over `settings.json`; the settings app writes it,
  editing the file by hand also works (it's watched). It's read up front (blocking, in
  Config's `Component.onCompleted`), so a reload starts in your theme, not the defaults.
- `Config.accent` is the accent in use: chosen colour, or one picked from the wallpaper.
- `Config.tint(hex)` maps every theme colour: light mode flips greys (dark ↔ light) and
  deepens colours; "background tint from wallpaper" shifts greys toward the wallpaper's
  hue. With both off it returns the colour unchanged (the default dark slate). **All
  theme colours in the QML go through `Config.tint()`** — keep it that way for new UI.
- Workspace names: a workspace can have a name of its own (the pencil on the window mode
  panel), shown wherever Slate would say "Workspace 3": always through
  `Config.workspaceLabel(id)`, never built by hand (a test checks). Kept by Slate, not as
  Hyprland's workspace name, in `$XDG_RUNTIME_DIR/slate/workspace-names-<instance>.json`
  (`ipc workspacename set|get|label`); dropped when Hyprland removes the workspace; saved and
  restored by Spaces and the session as `name` on a workspace. The rename question is
  `PowerConfirm.confirmWith` with `input: { text, placeholder, maxLength }`, which adds a
  text field and passes what was typed as the second argument.
- Window mode: Settings → Windows sets the default (`Config.windowMode`), and each workspace
  can have its own from the menu bar (`Config.workspaceModes`, kept for the Hyprland session in
  `$XDG_RUNTIME_DIR/slate/workspace-modes-<instance>.json`; `ipc workspacemode set|get`; Spaces
  saves and restores it, and so does reopening apps after a restart). Tiling, master, scrolling
  and monocle are Hyprland layouts: the default in `general:layout`, the rest per workspace
  (`hl.workspace_rule` layout). Floating is a float rule per workspace (1–30, the rest, the
  secret workspace) switched on where the mode is floating. Solo (one window per workspace)
  uses dwindle, a lone tile filling the workspace; windowrules.lua moves a second tiled window
  that opens on (or is moved to) a Solo workspace on to a new one (`soloSpill`/`soloSpread`). Slate pushes `WINDOW_MODE` and
  `WORKSPACE_MODES` with the border settings, so they come back after a Hyprland reload;
  `applyWorkspaceModes`/`setWorkspaceMode`/`setWindowMode` in `windowrules.lua` set the rules
  and float or re-tile open windows (tagged `slate-floated`, so apps that float
  anyway stay floating). Floating windows' title bars are Slate Bars, Slate's own (`TitleBar.qml`), unless
  Hyprbars is chosen and loaded, when the plugin draws them, coloured from Slate's theme by
  `shell.qml`. A Hyprland plugin is tied to one Hyprland build: `slate-build-hyprbars` names
  each build for its Hyprland (`hyprbars-<version>-<commit>.so` plus a `.json` record),
  `hyprbars.lua` asks Hyprland only for the one matching the running Hyprland (and keeps
  asking for the file it loaded for as long as that Hyprland runs), and `HyprbarsWatch.qml`
  reads `slate-build-hyprbars --status`, switches the setting to Slate Bars when Hyprbars is
  wanted but can't load, and asks about rebuilding and switching back
  (`~/.local/state/slate/hyprbars-notes.json` remembers what it has asked).
- Folder colour (Settings → Appearance): `scripts/folder-colour.py` makes
  `~/.local/share/icons/Slate-Icons`, a theme that inherits the user's Papirus theme and only
  links the folder icons to another of Papirus's colours (no root needed, unlike
  papirus-folders), then sets it for GTK, qt5ct/qt6ct and KDE. Themes that only have their
  plain folder in colours (folder.svg beside folder-<colour>.svg: Kora, Nordzy, "kind":
  "plain" in --list) get it swapped, and their other folders (Desktop, Home…, drawn in the
  plain folder's colours) repainted: those colours swapped for the chosen one's, emblem colours
  moved the same way (`recolour`). `X-Slate-Build` makes older builds be made again. "Auto" picks the colour
  nearest `Config.wallpaperAccent`; "default" switches back and removes it.
- Mouse cursor: Slate Cursors (`shell/cursors/Slate-Cursors`, Bibata Modern Ice without
  colour, GPL-3.0; rebuilt with `tools/build-cursors.py`). The installer links it into
  `~/.local/share/icons`; the session's `variables.lua` sets `CURSOR_THEME`/`CURSOR_SIZE`
  (override them in `~/.config/slate/hypr/variables.lua`) as Hyprland's cursor and in the
  environment, and `scripts/apply-theme.py` points GTK, Qt/KDE and X11 apps at the same theme.
  Settings → Input → Pointer style (`cursorTheme`, listed by `scripts/icon-themes.py`) changes
  it while running: `slateApply` in `slate.lua` sets Hyprland's cursor, the environment and
  gsettings ("" = the session's own), and apply-theme.py gets the name from Slate.
- Icon theme: Settings → Icons → Icon theme (`iconTheme`, listed by `scripts/icon-themes.py`).
  `shell.qml` sets it for GTK, Qt and KDE with `folder-colour.py --icon-theme`, then makes the
  folder colour again on top of it. Slate's tiles follow: `Config.tileDir` is
  `tiles/themes/<theme>/<style>`, and `appicon.py` draws from the theme, the themes it
  inherits, then the usual ones, finding app icons where each theme's index.theme says.
- Window borders (0–12 px, default 0, Settings → Windows; only when a workspace has more than one window) follow the
  theme: `shell.qml` sends the accent (active) and bar colour (inactive), at 60% and 85% (Hyprland cannot blur behind borders),
  to Hyprland with `hyprctl eval`, and again after a config reload. Fallbacks and
  `BORDER_SIZE` live in `colors.lua`.
- Bar and dock position: `Config.s.barPosition` and `dockPosition` (top/bottom/left/right).
  On a side, the bar's groups are one-column grids: status icons lose their text, the clock
  stacks and the window title is rotated; panels slide out sideways. They never share an edge: moving one onto the other's edge
  sends the other to the opposite edge (`Config.separateBarAndDock()`). The bar flips its curves and screen corners to its edge; `ScreenCorners.qml` draws
  the two corners away from it. The dock is laid out as a horizontal strip and turned to its edge with a
  matrix transform (`stripMatrix`), each icon/label turned back (`upright()`).
- Slate's windows use the app id `slate-settings` (`//@ pragma AppId` at the top of
  `shell.qml`), matched by `data/slate-settings.desktop` (hidden) and the icon
  `assets/icon/settings-*.png` (rendered by `tools/render-settings-icon.py`), which the
  installer puts in `~/.local/share/applications` and the hicolor icon theme.
- Location for weather and night light's sunset/sunrise: `Config.s.latitude/longitude`
  (`Config.sunTimes()` computes the sun locally).
- The wallpaper is `Config.s.wallpaper` (drawn by `Wallpaper.qml`);
  `scripts/wallpaper-accent.py` (ImageMagick) returns the accent and tone. They're cached in
  `~/.cache/slate/wallpaper-colours.json` (with the wallpaper they're for) and used at start-up
  until the script answers; a cache that's damaged, for another wallpaper or not colours is
  ignored and written again. The login screen doesn't use it.
- Canvas-drawn shapes (corners, panel joins) repaint on colour change via a `fill`
  property + `onFillChanged: requestPaint()`. Hot reload doesn't repaint Canvas — do a
  full restart after editing them.
- **The menu bar is one arranged line** (`Bar.qml`): every item is a `Segment`, written once in
  a hidden holder and handed to a `Container` made from `Config.barLayout` (containers,
  `"space"`s). Moving one between containers and showing it in the same instant leaves it
  undrawn, so the line is re-laid a frame after a change and a thing that wasn't showing
  stays unseen through the move (`place()`); `tests/live/test_bar_layout.py` checks nothing
  on the bar is blank.
- **When the bar's contents don't fit** (`Bar.qml` `fit()`): it tries giving things up in
  order (the title, text, the clock's date and seconds, tucking "When needed" containers,
  then things leaving for More in `Config.barOverflowOrder`), laying the line out afresh at
  each step in one go so none of it is drawn, and keeps the fewest that fit; something comes
  back only with a margin to spare. `bar.gives` says what's been given up.
  That last order is **menu item priority**: `BarEditor.qml`'s second window (Set priority,
  `Config.barPrioritising`) lists it backwards, highest priority first, without what always
  stays (`Config.barStay`), and saves a dragged row with `Config.barSetOverflow`.
- **Reload notices** (`shell.qml`): Quickshell's own reload popup is hidden; Slate sends a
  notification instead, for a reload that worked and one that failed (the error's last
  "caused by" link leads: what, which file and line, and what used it). After a failed
  reload Quickshell stops reloading on file changes until it's restarted, so Slate watches
  the files the error names and reloads itself when one is saved.

## IPC (`slate ipc call <target> <function> [args]`)

| Target | Functions |
|---|---|
| `bar` | `panel <control\|spaces\|notifications\|session\|volume\|wifi\|clipboard\|screenshot\|keyboard\|bluetooth\|battery\|gamemode\|calendar>`, `setFilled <bool>`, `reveal` |
| `popout` | `toggle <name> <x>`, `close` |
| `launcher` | `toggle`, `open`, `close`, `search <text>`, `launchSelected`, `launchOnNewWorkspace`, `launchLeft`, `launchRight`, `launch <desktop-id>` (an app only; answers `ok` or `unknown`) |
| `switcher` | `next`, `prev`, `commit`, `cancel` |
| `overview` | `open`, `close`, `toggle`, `next`, `prev`, `go`, `moveLeft`, `moveRight`, `hold <bool>` |
| `dock` | `menu <app>`, `closeMenu`, `downloads` (the Downloads stack's grid), `more` (More's grid, when apps don't fit), `preview <app>`, `closePreview` |
| `settings` | `toggle`, `open`, `close`, `page <id>` |
| `osd` | `volume <up\|down\|mute>`, `mic mute`, `brightness <up\|down>`, `keyboard <up\|down>`, `workspace` (big workspace dots; Super+Left/Right), `volumeGet` (JSON), `volumeSet <0-100>`, `brightnessSet <1-100>` |
| `lock` | `lock`, `preview <lock\|login>`, `closePreview` |
| `media` | `toggle`, `next`, `previous` (media keys), `info` (what's playing, JSON) |
| `notifications` | `dnd <bool>`, `dndGet`, `list` (the latest, JSON), `clear` |
| `assistant` | `toggle`, `open`, `close`, `ask <text>` (open and send), `stop` (the prompt window); `did <json>` (what a tool did, from the server); `status` (JSON: enabled, locked, game mode, what may be seen), `confirm <id> <json>` (ask in the confirmation window), `answer <id>` ("" until answered, then `yes` or `no`, once), `withdraw <id>`: for `slate mcp` (ASSISTANT.md) |
| `picker` | `clipboard`, `emoji`, `toggle <clipboard\|emoji>`, `close` |
| `wallpaper` | `set <path>`, `get` |
| `nightlight` | `toggle`, `on`, `off` |
| `polkit` | `preview`, `previewWrong`, `close` (preview only) |
| `power` | `confirm <logout\|reboot\|shutdown>` (asks first), `cancel` |
| `spaces` | `restore <name>`, `list` |
| `screensaver` | `start` (a preview: any input puts it away), `stop` |
| `welcome` | `open`, `close` |
| `test` | `state` (JSON of what's on screen, tray icons included), `dockHover <slot>` (magnify the dock as if pointed at; -1 stops), `dockDrag <app> <slot> <up>` and `dockDrop` (drag an app on the dock: over a slot, a number of pixels up off it, then let go), `dockMoreDrag <app> <slot> <up>` and `dockMoreDrop` (the same for an app dragged out of More's grid, open with `dock more`), `dockRoom <px>` (less room for the dock's things than its edge has, so a few windows fill it and apps go into More; 0 for the whole edge); only with `SLATE_TEST=1`, for the test suite |

### Test mode (`SLATE_TEST=1`)

Set by the test suite (docs/TESTING.md) for the Slate it starts. Slate then plays no sounds,
skips the welcome, startup apps, update checks and the login-screen/package prompts, shows
the time in `SLATE_TEST_TIME` on its clocks (`Config.clockDate`), writes
`$XDG_RUNTIME_DIR/slate-ready` once it has loaded, and answers `ipc call test state`.
Anything new that starts a side effect at login (a prompt, a sound, a network check) should
check `Config.testMode`.

## Hyprland integration (`~/.config/hypr/config/*.lua`)

- `autostart.lua` — starts `slate`.
- `binds.lua` — three sets (Settings → Shortcuts, `~/.local/state/slate/keyset.lua`): Slate's
  (below), Hyprland's default shortcuts, or Hyprland's plus Slate's on free keys. Slate's set: Super tap → launcher; Super+Space launcher; Super+Tab switcher;
  Super+Down overview (arrows/Enter/Shift+arrows drive it while open); Super+Up go /
  special workspace; Super+Return new workspace launch; Super+X control centre;
  Super+A notifications; Super+Alt+C power; Super+Z settings; Super+L lock; media,
  volume, brightness and keyboard-backlight keys → `osd`.
- `animations.lua` — `fadeTo(dispatcher)` (crossfade) and `instantTo(dispatcher)` used
  when switching from a Slate overlay, so the switch starts from that screen.
- `workspaces.lua` — `newWorkspace(movingAddr)` (the number after the last workspace with
  windows: Super+W, Super+Return in the launcher) and `besideWorkspace(dir)` for "open on a
  new workspace left/right".
- `windowrules.lua` — `no_anim` for Slate overlay layers; "Slate Settings" floats.
- `misc.lua` — `allow_session_lock_restore = true` (a restarted Slate re-takes a lock);
  `focus_on_activate = true` (an app asking to come forward, like a browser handed a link, is
  switched to, on its workspace).

**Gotcha:** Hyprland won't move focus or switch workspace while a layer holds exclusive
keyboard focus. Slate overlays first release the keyboard (`releasing`), then dispatch
~40 ms later.

## State and files

`~/.local/state/slate/`: `dock.json` (pinned apps), `launcher.json` (usage counts),
`notifications.json` (history, DND). App icon tiles are drawn by
`scripts/appicon.py --tile` into `~/.cache/slate/tiles/`. Clipboard history:
`~/.local/state/slate/clipboard/`, recent emoji: `emoji.json`.
Spaces: `~/.local/share/slate/spaces.json` (kept by the installer, unlike `~/.config/slate`).

### Spaces

`scripts/spaces.py` saves each window's start command (its `.desktop` Exec, else
`/proc/<pid>/cmdline`) and its place as fractions of the screen's usable area. Restoring
opens each workspace as a new one after the last in use, then rebuilds the dwindle tree:
the tiled windows are cut along lines no window crosses into a binary tree; the first app
opens alone, and for each cut the first window of the first half is focused,
`hl.dsp.layout("preselect r|d")` is sent, the second half's first app is started (the script
waits for its window), and the split is set with `splitratio … exact`. Floating windows
are started floating, then moved and sized. Apps that don't open a window within 15 s are
skipped and named in a notification.

Each window a restore opens is noted by its Hyprland `stableId` (addresses get reused) in
`$XDG_RUNTIME_DIR/slate/space-windows.json`, stamped with `HYPRLAND_INSTANCE_SIGNATURE`
(window ids start over in each Hyprland session, so another session's file is ignored).
The marks survive Slate reloads and Hyprland config reloads. `Spaces.qml` reads the file
(`Spaces.owners`); `SpaceBadges.qml` also keeps `Spaces.spaceOfAddress` (window address →
space), which the bar uses to put the focused window's icon on its space's colour, and the
window switcher and workspace overview use to badge those windows (`SpaceBadge.qml`). `SpaceBadges.qml` puts a Top-layer strip along
the top edge of each such window, drawing a 3 px border in the space's colour that wraps down the curve at each end and tapers to
a point: the window's rounded corner (`decoration:rounding`; none for a lone tiled or
maximised window), or the bar's curve where the window sits under a top bar's curved end) that's on a showing workspace (clear, and taking the
pointer only where the badge is), placed from `HyprlandToplevel.lastIpcObject` (re-read on
window/workspace events, and every 0.5 s while there are any, since Hyprland sends no event
for resizes or drags); which workspaces are showing comes from `hyprctl -j monitors`.
Hovering the badge fades it across to the other top corner, inside the strip, so Hyprland
never animates it; a focus change puts it back. Hyprland gives no positions while a workspace
switch slides, so borders and badges vanish when one starts and fade back in (220 ms) after the slide
(500 ms, 300 ms with fast animations).

## Workarounds for bugs elsewhere

Bugs in Hyprland, Quickshell and the rest that Slate works around. Each says where it's reported,
how to check whether a new release fixed it, and how to take the workaround out once it has.

### Quickshell: a live ScreencopyView crashes when its window closes

- **The bug:** a `ScreencopyView` with `live: true` showing a window can kill the whole process
  when that window closes ("The Wayland connection experienced a fatal error: Invalid argument",
  a frame after `ToplevelHandle(…) closed`), most often when several close at once: live mode's
  stream of captures racing windows coming and going. Seen with Quickshell 0.3.2
  and Hyprland 0.57.2, on an Intel graphics card; never in the test container.
- **Reported:** quickshell-mirror/quickshell#1481 (ours, with the repro below). Very likely the same
  as quickshell-mirror/quickshell#1123 (open since September; seen there on Quickshell 0.3.1 and
  Hyprland 0.56.2, with a trace pointing at Wayland object ids reused during a burst of captures,
  and also set off by many windows opening at once). Watch both. On the same path but not the
  same: quickshell-mirror/quickshell#1418 (window captures failing outright on Hyprland 0.57.0).
  With WindowPreview, both held here: three windows closing at once under New Space and the
  overview (5 of 5), and ten opening at once, then closing at once, with the overview showing (4 of 4).
- **What Slate does instead:** every live preview is a `WindowPreview` (`shell/WindowPreview.qml`):
  `live: false`, and Slate asks for frames itself with `captureFrame()` on a timer (30 a second,
  starting once the first frame is in, which comes by itself). Previews update at 30 frames a
  second rather than the window's own rate. Static checks in `tests/static/test_consistency.py`
  (`WindowPreviews`) keep every preview on it.
- **Checking a new Quickshell:** run `qs -n -p tools/repro/screencopy-close` beside Slate, open
  three windows, and close them all at once (one `hyprctl dispatch` closing each). It died three
  times in four on 0.3.2; if it survives ten tries, the bug is likely fixed.
- **Taking it out:** in `WindowPreview.qml`, `live: running` in place of `live: false` and the
  Timer removed (keep the component, so every preview stays in one place); change
  `test_never_live` to match; then close windows under New Space and the overview a few times.

## Dependencies

Arch package names (other distros: `packaging/<distro>.txt`).

**Required**

| Package | Used for |
|---|---|
| `hyprland` (0.57+, Lua config) | the compositor; `hyprctl` for dispatches, borders, night light shader |
| `quickshell` (0.3.x) | runs Slate (`qs`) |
| `qt6-declarative`, `qt6-shadertools` | QML / QtQuick.Effects; `qsb` to build `shaders/*.frag.qsb` |
| `python`, `python-pillow` | scripts (`apply-theme.py`, `clipstore.py`, `wallpaper-accent.py` and the rest); Pillow for `appicon.py`'s tiles and `image-sizes.py` |
| `python-numpy`, `librsvg` (`rsvg-convert`) | `appicon.py`: theme shadows taken off icons, and SVG icons drawn |
| `imagemagick` | accent and tone picked from the wallpaper |
| Noto Color Emoji (`noto-fonts-emoji`, Debian `fonts-noto-color-emoji`, Fedora `google-noto-color-emoji-fonts`, openSUSE `noto-coloremoji-fonts`) | emoji in the picker and the launcher's `:emoji` |
| `accountsservice` | your account picture (Settings → General, the lock and login screens) |
| `dbus` (`dbus-monitor`) | the dock's badges and progress: apps' Unity launcher updates (`scripts/launcher-entries.py`) |
| `v4l-utils` (`v4l2-ctl`) | Settings → Webcam: reading and setting the camera's picture settings (`scripts/webcam.py`) |
| `python-gobject` (PyGObject) | the tray's register, apart from Slate so tray icons outlive its restarts (`scripts/tray-watcher.py`); without it, Quickshell is the register (icons from apps that sign up once are lost when Slate restarts) |
| `wl-clipboard` | clipboard history (`wl-paste --watch`), copying from the pickers |
| `pipewire`, `wireplumber` (+ `pw-play`: Arch `pipewire-audio`, Debian `pipewire-bin`, Fedora `pipewire-utils`, openSUSE `pipewire-tools`) | volume, mic; volume key tick and notification chime (`sounds/`) |
| `networkmanager` | Wi-Fi panel |
| `bluez` | Bluetooth |
| `upower` | battery |
| `polkit` | password prompts (`PolkitAgent.qml`), `pkexec` for login-screen updates |
| `pam` | lock screen password check, `faillock` lockout |
| `systemd` or `elogind`, `util-linux`, `dbus`, `glib2`, `procps-ng` | the login service: `systemctl`/`systemd-inhibit`, or `loginctl`/`elogind-inhibit` without systemd (power, sleep; through `bin/slate-init`), `setpriv`/`runuser`, `dbus-send`/`gdbus`/`gsettings`, `pgrep`/`pkill` |
| `libnotify` | `notify-send` (login-screen update prompt, screenshot fallback) |
| `fontconfig` | font lists in Settings, greeter font sync |
| `curl` | weather |
| `xdg-utils` | `xdg-open` (open settings file, links) |
| `glib2` (`gio`) | the dock: emptying and binning to the Waste Basket (`gio trash`), opening files dropped on an app (`gio launch`, `scripts/open-with.sh`) |
| — | Geist (interface + mono) is bundled in `fonts/` (SIL OFL) and loaded by Slate itself |

**Needed for specific features**

| Package | Feature |
|---|---|
| `grim`, `slurp` | screenshots (Print / Super+Print) |
| `hyprpicker` | freezes the screen while picking a screenshot area (optional) |
| `btop` | Ctrl+Shift+Esc (system monitor in a terminal) |
| `ffmpeg` (Fedora `ffmpeg-free`) | takes the sound out of downloaded screensaver videos |
| `xdg-user-dirs` | finding your Downloads and Pictures folders (else `~/Downloads`, `~/Pictures`) |
| `pciutils` | Debug → Export logs (graphics card details) |
| a terminal, a file manager (kitty and Nautilus offered when you have none) | the shortcuts, dock and desktop menu; the first installed is used (`session/hypr/config/variables.lua`), Settings → Default Apps picks |
| `swash` | opens screenshots to annotate; without it they're saved to ~/Pictures/Screenshots and copied |
| `uwsm` | session management, with systemd only; log out goes through `uwsm stop` when it manages the session (else Hyprland exits directly) |
| `brightnessctl` | screen and keyboard brightness keys |
| `power-profiles-daemon` | power profiles in the battery panel |
| `greetd` | the Slate login screen |
| `adw-gtk-theme`, `qt6ct` | GTK and Qt apps following Slate's colours |
| `xdg-desktop-portal-gtk` | Flatpak and Snap apps following light or dark (the Settings portal reads `color-scheme` from gsettings; Hyprland's own portal has no Settings) |
| hyprbars (Hyprland plugin; `git`, `make`, `g++` to build it) | Optional title bars on every floating window (Slate's own are the default and need nothing). Built per Hyprland version, when chosen in Settings, by `slate build-hyprbars` into `~/.local/share/slate/plugins`, loaded by `session/hypr/config/hyprbars.lua` |
| `qt6-multimedia` (Debian `qml6-module-qtmultimedia`, Fedora `qt6-qtmultimedia`, openSUSE `qt6-multimedia-imports`) | Settings → Sound → Click sound, and the other sounds without `pw-play`'s short delay (optional) |
| `cups` (+ `system-config-printer`, optional) | Settings → Printers: printers, adding driverless (IPP Everywhere) ones, test pages (`scripts/printers.py`); the printer settings app for ones that need a driver, else CUPS's web page |
| `sane` (Debian `sane-utils`, Fedora/openSUSE `sane-backends`), `sane-airscan`, `simple-scan` | Settings → Printers: finding scanners (network ones through airscan) and opening an app to scan with (optional) |
| `papirus-icon-theme` | The default icon theme (Papirus-Dark); its coloured folders back Settings → Icons → Folder colour |

Bundled (no package): Geist and Geist Mono (`fonts/`, SIL OFL), the Tabler icon font (`fonts/`, MIT) and emoji data (`data/emoji.json`).

Other scripts: `scripts/session.sh` (log out via uwsm/Hyprland, restart, shut down; the goodbye sound first;
before a restart with "Reopen my apps" on, `spaces.py session-save` keeps the windows, and the next login's
`spaces.py session-restore` reopens them, then the startup apps on workspaces of their own),
`scripts/screenshot.sh`, `scripts/apply-theme.py` (app theming and the code font — fontconfig's "monospace",
GTK's monospace font, Qt/KDE's fixed font; run by `shell.qml` when the theme, accent, code font or the
apps switched on in Settings → App Theming change). The apps live in `scripts/slate_apps.py`
(one function each, all off until switched on; `INFO` there gives Settings each one's description,
website and packages per distro family, for its Install button, which runs
`bin/slate-system --install` through pkexec). Apps with Flatpak builds (Discord's Vencord,
Vesktop, VS Code, VSCodium, Zed, Helix, Neovim, WezTerm, zathura, GNOME Text Editor, Firefox,
Obsidian) are themed in their Flatpak's own folders too (`~/.var/app/<id>/config` or `data`:
`flatpak()` and `config_dirs()`). Flatpak GTK and KDE apps are given read-only access to your
`gtk-3.0`, `gtk-4.0` and `kdeglobals` through an entry in Flatpak's overrides for all apps
(`$FLATPAK_USER_DIR` or `~/.local/share/flatpak/overrides/global`, what `flatpak override --user
--filesystem=…:ro` writes: `flatpak_share()`, recorded as a `listitem` so undo takes out only
Slate's entry), and each snap gets GTK's theme files in its own `~/snap/<name>/current/.config`
(`snap_configs()`). A config that's a link is written where it leads (it stays a link), and one
that's read-only, such as Home Manager's in the Nix store, is left alone with a line in the log
(`slate_theme.writable()`). Spotify and Discord are themed through a patch in the app's own
files (Spicetify, Vencord), which an update of the app removes: each has a `@stale` check
(`apply-theme.py --stale`, run by `shell.qml` every five minutes while either is themed), and
the next apply patches it again (`spicetify backup apply`; for Discord, the small `app.asar`
Vencord's installer left, kept in `~/.local/state/slate/vencord-app.asar`) and prints
`restored`/`lost` lines that `shell.qml` turns into a notification; `scripts/slate_theme.py` makes every change through an
undo log (`~/.local/state/slate/app-theming.json`) so switching an app off puts its config back, and backs
config files up once (`.bak-slate-theme`). Open apps reload live where they can: kitty SIGUSR1, Ghostty
SIGUSR2, Helix SIGUSR1, btop SIGUSR2, cava SIGUSR2, alacritty by itself, GTK by switching the theme name
away and back, qt6ct and qt5ct via their config folders, KDE via the `KGlobalSettings.notifyChange` signal.
`scripts/clipstore.py` is fed by `wl-paste --watch`.
