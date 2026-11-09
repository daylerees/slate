# Architecture

Slate is one Quickshell config (`shell.qml` is the root) plus a set of Hyprland Lua
config files that bind keys and run Slate commands. Everything visible is a Wayland
layer-shell surface (`PanelWindow`), except the settings window (`FloatingWindow`) and
the lock screen (`WlSessionLock`).

## Components (`~/.config/slate`)

```
shell.qml               root: creates everything below, plus the dock itself
├─ Bar.qml              top bar (layer "slate-bar")
├─ Popouts.qml          drop-down panels under the bar ("slate-popout")
├─ PowerConfirm.qml     centred confirmation ("slate-confirm"): log out / restart / shut down,
│                       and confirmWith() for anything else (deleting a space)
├─ Wallpaper.qml        desktop wallpaper, one per screen ("slate-wallpaper")
├─ Picker.qml           clipboard history + emoji picker ("slate-picker")
├─ PolkitAgent.qml      password prompts for apps ("slate-polkit")
├─ NightLight.qml       warm screen via Hyprland's screen shader
├─ Notifications.qml    notification server + toasts ("slate-notifications")
│  └─ NotificationCard.qml
├─ Launcher.qml         app launcher + calculator ("slate-launcher")
├─ Switcher.qml         Super+Tab window switcher ("slate-switcher")
├─ WorkspaceOverview.qml Super+Down workspace overview ("slate-overview")
├─ SettingsWindow.qml   settings app (floating window "Slate Settings")
├─ ScreenCorners.qml    bottom screen corners ("slate-corners")
├─ FadeIn.qml           fade in from black at login, with the welcome sound ("slate-fade-in")
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
sounds/                 volume tick; notification chime, attention, click, swish, welcome and goodbye (made by tools/make-sounds.py)
RoundImage.qml          rounded image helper
scripts/wallpaper-accent.py   picks accent + overall tone from the wallpaper
scripts/update.py             GitHub releases: check, list hand-changed files (against the
                              installed .manifest), install (install.sh --update), go back
shaders/mono.frag(.qsb)       tray icons → single theme colour
greeter/                the login screen (see LOCK-AND-LOGIN.md); greeter/files lists
                        everything it's installed with, greeter/emergency/ is its fallback
```

Only one of launcher / window switcher / workspace overview is open at once, and
opening any of them closes bar panels (wired in `shell.qml`).

## Settings and theme

- `Config.s.<name>` is a `JsonAdapter` over `settings.json`; the settings app writes it,
  editing the file by hand also works (it's watched).
- `Config.accent` is the accent in use: chosen colour, or one picked from the wallpaper.
- `Config.tint(hex)` maps every theme colour: light mode flips greys (dark ↔ light) and
  deepens colours; "background tint from wallpaper" shifts greys toward the wallpaper's
  hue. With both off it returns the colour unchanged (the default dark slate). **All
  theme colours in the QML go through `Config.tint()`** — keep it that way for new UI.
- Window mode (Settings → Windows): `setWindowMode` in `windowrules.lua` turns a float-all
  rule on or off and floats/re-tiles open windows (tagged `slate-floated`, so apps that float
  anyway stay floating); in floating mode hyprbars draws title bars, coloured from Slate's
  theme by `shell.qml`. Hyprland plugins are tied to one Hyprland build, so a stale one is
  skipped (logged) until rebuilt.
- Folder colour (Settings → Appearance): `scripts/folder-colour.py` makes
  `~/.local/share/icons/Slate-Icons`, a theme that inherits the user's Papirus theme and only
  links the folder icons to another of Papirus's colours (no root needed, unlike
  papirus-folders), then sets it for GTK, qt5ct/qt6ct and KDE. "Auto" picks the colour
  nearest `Config.wallpaperAccent`; "default" switches back and removes it.
- Mouse cursor: Slate Cursors (`shell/cursors/Slate-Cursors`, Bibata Modern Ice without
  colour, GPL-3.0; rebuilt with `tools/build-cursors.py`). The installer links it into
  `~/.local/share/icons`; the session's `variables.lua` sets `CURSOR_THEME`/`CURSOR_SIZE`
  (override them in `~/.config/slate/hypr/variables.lua`) as Hyprland's cursor and in the
  environment, and `scripts/apply-theme.py` points GTK, Qt/KDE and X11 apps at the same theme.
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
  `scripts/wallpaper-accent.py` (ImageMagick) returns the accent and tone.
- Canvas-drawn shapes (corners, panel joins) repaint on colour change via a `fill`
  property + `onFillChanged: requestPaint()`. Hot reload doesn't repaint Canvas — do a
  full restart after editing them.
- **Reload notices** (`shell.qml`): Quickshell's own reload popup is hidden; Slate sends a
  notification instead, for a reload that worked and one that failed (the error's last
  "caused by" link leads: what, which file and line, and what used it). After a failed
  reload Quickshell stops reloading on file changes until it's restarted, so Slate watches
  the files the error names and reloads itself when one is saved.

## IPC (`slate ipc call <target> <function> [args]`)

| Target | Functions |
|---|---|
| `bar` | `panel <control\|spaces\|notifications\|session\|volume\|wifi\|battery\|calendar>`, `setFilled <bool>`, `reveal` |
| `popout` | `toggle <name> <x>`, `close` |
| `launcher` | `toggle`, `open`, `close`, `search <text>`, `launchSelected`, `launchOnNewWorkspace`, `launchLeft`, `launchRight` |
| `switcher` | `next`, `prev`, `commit`, `cancel` |
| `overview` | `open`, `close`, `toggle`, `next`, `prev`, `go`, `moveLeft`, `moveRight`, `hold <bool>` |
| `dock` | `menu <app>`, `closeMenu` |
| `settings` | `toggle`, `open`, `close`, `page <id>` |
| `osd` | `volume <up\|down\|mute>`, `mic mute`, `brightness <up\|down>`, `keyboard <up\|down>`, `workspace` (big workspace dots; Super+Left/Right) |
| `lock` | `lock`, `preview <lock\|login>`, `closePreview` |
| `media` | `toggle`, `next`, `previous` (media keys) |
| `picker` | `clipboard`, `emoji`, `toggle <clipboard\|emoji>`, `close` |
| `wallpaper` | `set <path>`, `get` |
| `nightlight` | `toggle`, `on`, `off` |
| `polkit` | `preview`, `previewWrong`, `close` (preview only) |
| `power` | `confirm <logout\|reboot\|shutdown>` (asks first), `cancel` |
| `spaces` | `restore <name>`, `list` |
| `screensaver` | `start` (a preview: any input puts it away), `stop` |

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

## Dependencies

Arch package names (other distros: `packaging/<distro>.txt`).

**Required**

| Package | Used for |
|---|---|
| `hyprland` (0.57+, Lua config) | the compositor; `hyprctl` for dispatches, borders, night light shader |
| `quickshell` (0.3.x) | runs Slate (`qs`) |
| `qt6-declarative`, `qt6-shadertools` | QML / QtQuick.Effects; `qsb` to build `shaders/mono.frag.qsb` |
| `python`, `python-pillow` | scripts (`apply-theme.py`, `clipstore.py`, `wallpaper-accent.py`); `appicon.py` tiles |
| `imagemagick` | accent and tone picked from the wallpaper |
| `wl-clipboard` | clipboard history (`wl-paste --watch`), copying from the pickers |
| `pipewire`, `wireplumber` (+ `pw-play`: Arch `pipewire-audio`, Debian `pipewire-bin`, Fedora `pipewire-utils`, openSUSE `pipewire-tools`) | volume, mic; volume key tick and notification chime (`sounds/`) |
| `networkmanager` | Wi-Fi panel |
| `bluez` | Bluetooth |
| `upower` | battery |
| `polkit` | password prompts (`PolkitAgent.qml`), `pkexec` for login-screen updates |
| `pam` | lock screen password check, `faillock` lockout |
| `systemd`, `util-linux`, `dbus`, `glib2`, `procps-ng` | `systemctl`/`systemd-inhibit` (power, sleep), `setpriv`/`runuser`, `dbus-send`/`gdbus`/`gsettings`, `pgrep`/`pkill` |
| `libnotify` | `notify-send` (login-screen update prompt, screenshot fallback) |
| `fontconfig` | font lists in Settings, greeter font sync |
| `curl` | weather |
| `xdg-utils` | `xdg-open` (open settings file, links) |
| — | Geist (interface + mono) is bundled in `fonts/` (SIL OFL) and loaded by Slate itself |

**Needed for specific features**

| Package | Feature |
|---|---|
| `grim`, `slurp` | screenshots (Print / Super+Print) |
| `hyprpicker` | freezes the screen while picking a screenshot area (optional) |
| `swash` | opens screenshots to annotate; without it they're saved to ~/Pictures/Screenshots and copied |
| `uwsm` | session management; log out goes through `uwsm stop` when it manages the session (else Hyprland exits directly) |
| `brightnessctl` | screen and keyboard brightness keys |
| `power-profiles-daemon` | power profiles in the battery panel |
| `greetd` | the Slate login screen |
| `adw-gtk-theme`, `qt6ct` | GTK and Qt apps following Slate's colours |
| hyprbars (Hyprland plugin; `git`, `make`, `g++` to build it) | Title bars on floating windows in floating mode. Built per Hyprland version by `slate build-hyprbars` into `~/.local/share/slate/plugins`, loaded by `session/hypr/config/hyprbars.lua` |
| `qt6-multimedia` (Debian `qml6-module-qtmultimedia`, Fedora `qt6-qtmultimedia`, openSUSE `qt6-multimedia-imports`) | Settings → Sound → Click sound, and the other sounds without `pw-play`'s short delay (optional) |
| `papirus-icon-theme` | The default icon theme (Papirus-Dark); its coloured folders back Settings → Appearance → Folder colour |

Bundled (no package): Geist and Geist Mono (`fonts/`, SIL OFL), the Tabler icon font (`fonts/`, MIT) and emoji data (`data/emoji.json`).

Other scripts: `scripts/session.sh` (log out via uwsm/Hyprland, restart, shut down; the goodbye sound first;
before a restart with "Reopen my apps" on, `spaces.py session-save` keeps the windows, and the next login's
`spaces.py session-restore` reopens them, then the startup apps on workspaces of their own),
`scripts/screenshot.sh`, `scripts/apply-theme.py` (app theming and the code font — fontconfig's "monospace",
GTK's monospace font, Qt/KDE's fixed font; run by `shell.qml` when the theme, accent, code font or the
apps switched on in Settings → App Theming change). The apps live in `scripts/slate_apps.py`
(one function each, all off until switched on); `scripts/slate_theme.py` makes every change through an
undo log (`~/.local/state/slate/app-theming.json`) so switching an app off puts its config back, and backs
config files up once (`.bak-slate-theme`). Open apps reload live where they can: kitty SIGUSR1, Ghostty
SIGUSR2, Helix SIGUSR1, btop SIGUSR2, cava SIGUSR2, alacritty by itself, GTK by switching the theme name
away and back, qt6ct via its config folder, KDE via the `KGlobalSettings.notifyChange` signal.
`scripts/clipstore.py` is fed by `wl-paste --watch`.
