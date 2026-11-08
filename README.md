<img alt="Slate" src="shell/assets/logo.png" height="80">

**Aesthetically pleasing yet understated, opinionated yet configurable, desktop environment
for Linux.**

**[daylerees.github.io/slate](https://daylerees.github.io/slate/)**: an overview of Slate, with
screenshots.

Slate runs on **Hyprland** and is built with **Quickshell** (QML). It has a dark-slate
look (Geist font, Tabler icons) with a top bar, a magnifying dock, an app launcher, window
and workspace switchers, drop-down panels, notifications, on-screen indicators, a
settings app, clipboard history, an emoji picker, night light, and its own lock and login
screens.

## Install

```sh
git clone https://github.com/daylerees/slate.git && cd slate
./install.sh
```

Then log out, pick **Slate** on the login screen and log in. Your current desktop stays
as it is; pick it at login to go back. Full instructions, per-distro notes and what to do
if your distro's Hyprland is too old: **[docs/INSTALL.md](docs/INSTALL.md)**.

Needs Hyprland 0.57+ (the Lua config) and Quickshell 0.3+.

## This folder

| Path | What |
|---|---|
| `install.sh` | installer (packages, font, Slate, login session; `--help` for options) |
| `shell/` | Slate itself: installed to `~/.config/slate` |
| `shell/session/` | the "Slate" login session and its Hyprland config |
| `shell/greeter/` | Slate's login screen (greetd) |
| `shell/bin/` | helpers: `slate-session-install`, `slate-greeter-install`, `slate-greeter-sync` |
| `packaging/` | package lists per distro, Quickshell build script |
| `tools/sync-from-live.sh` | copy a running Slate back into `shell/` (development) |
| `docs/` | install, architecture, session, lock/login, redistribution notes |

## What's in it

| Part | What it does | File |
|---|---|---|
| Top bar | Workspaces (dots + spring indicator), active window title / hover descriptions, tray, notifications · Wi-Fi · volume · battery group, clock, power. Rounded top screen corners | `Bar.qml` |
| Panels | Drop-downs from the bar: control centre (profile card with wallpaper, media, clock + forecast, quick toggles), Wi-Fi, volume, battery/power profiles, calendar, session, notifications. Log out / restart / shut down ask in a centred dialog | `Popouts.qml`, `PowerConfirm.qml` |
| Dock | macOS-style magnifying dock, pinned apps, right-click menus, auto-hide | `shell.qml` |
| Launcher | App search (usage-sorted), calculator, open on a new workspace left/right | `Launcher.qml` |
| Window switcher | Super+Tab, live previews, circular strip | `Switcher.qml` |
| Workspace overview | Super+Down, large live cards, reorder with Shift | `WorkspaceOverview.qml` |
| Notifications | Notification server, toasts (positionable), history | `Notifications.qml`, `NotificationCard.qml` |
| On-screen indicators | Volume, mic, brightness, keyboard backlight, workspace dots (Super+Left/Right) | `OSD.qml` |
| Settings app | General/appearance, wallpaper, menu bar (what it shows, clock format), dock, launcher, windows (borders, dimming, switcher, overview), hot corners, notifications, lock & idle, Wi-Fi, Bluetooth, about | `SettingsWindow.qml` |
| Lock screen | Wayland session lock + PAM, lockout countdown, lock-before-sleep, idle lock/screen-off/suspend | `LockScreen.qml`, `LoginScreen.qml` |
| Login screen | greetd greeter in a minimal Hyprland, same design as the lock screen | `greeter/`, `LoginScreen.qml` |
| Slate session | "Slate" entry on any login screen: Hyprland with Slate's own config, separate from `~/.config/hypr` | `session/` |
| Hot corners | Per-corner actions, disarmed while locked | `HotCorners.qml` |
| Screen corners | Rounded black screen corners | `ScreenCorners.qml`, `Bar.qml` |
| Shared settings | `Config` singleton backed by `settings.json`; theme (accent, light/dark, wallpaper tint) | `Config.qml` |
| Wallpaper | Drawn per screen on the background layer, cross-fades on change; picker in Settings (Super+Shift+W) | `Wallpaper.qml` |
| Clipboard & emoji | Super+V clipboard history (text + images), Super+. emoji picker | `Picker.qml`, `scripts/clipstore.py`, `data/emoji.json` |
| Password prompts | Polkit agent (pkexec, system settings) in Slate's style | `PolkitAgent.qml` |
| Night light | Warm screen via a Hyprland screen shader; manual, sunset-to-sunrise or custom schedule (Settings → General) | `NightLight.qml` |
| App theming | Opt-in, per app (Settings → Appearance → App theming): GTK, Qt, KDE, terminals (kitty, Alacritty, Ghostty, foot, WezTerm), editors (Text Editor, VS Code, Zed, Helix, Vim/Neovim), bat, fzf, Yazi, cava, zathura, btop, Discord (Vencord), Spotify (Spicetify) and Firefox follow Slate's colours; configs are backed up and switching an app off puts them back | `scripts/apply-theme.py`, `slate_apps.py`, `slate_theme.py` |
| Screenshots | Print (area, screen frozen) / Super+Print (screen) → swash | `scripts/screenshot.sh` |

## Docs

- [docs/INSTALL.md](docs/INSTALL.md) — installing on Arch, Debian/Ubuntu, Fedora, openSUSE, NixOS; updating; removing
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the pieces fit, IPC, Hyprland integration, theming, settings
- [docs/LOCK-AND-LOGIN.md](docs/LOCK-AND-LOGIN.md) — lock screen, idle/sleep, login screen (greetd) and recovery
- [docs/SESSION.md](docs/SESSION.md) — the "Slate" login session, its Hyprland config and personal overrides
- [docs/REDISTRIBUTION.md](docs/REDISTRIBUTION.md) — packaging status and what's left

## Where things live

| What | Path |
|---|---|
| Shell code + `settings.json` | `~/.config/slate/` (run with `slate`) |
| Saved state (pinned apps, launcher counts, notification history) | `~/.local/state/slate/` |
| Cache (app icon tiles) | `~/.cache/slate/tiles/` |
| Log | `~/.cache/slate.log` |
| Your own Hyprland config (other sessions) | `~/.config/hypr/` — not used by the Slate session |
| Slate session's Hyprland config | `~/.config/slate/session/hypr/` |
| Personal overrides for the Slate session | `~/.config/slate/hypr/` (`variables.lua`, `hyprland.lua`) |
| Session launcher + login entry (installed) | `/usr/local/bin/slate-session`, `/usr/share/wayland-sessions/slate.desktop` |
| Login screen code (root-owned copy) | `/usr/local/share/slate-greeter/` |
| Login screen appearance (synced) | `/var/lib/slate-greeter/` |
| Helpers | `~/.config/slate/bin/`: `slate-session-install` (sudo), `slate-greeter-install` (sudo), `slate-greeter-sync` |
| App-icon tile generator | `scripts/appicon.py` (in the shell folder) |

## Everyday commands

```sh
# Restart Slate
slate restart

# Talk to a running Slate
slate ipc call settings toggle
slate ipc call lock preview lock      # or: preview login
slate ipc call launcher search "2*pi"

# Slate as its own login session
sudo ~/.config/slate/bin/slate-session-install            # add "Slate" to the login screen
sudo ~/.config/slate/bin/slate-session-install --remove   # take it off again

# Login screen
sudo ~/.config/slate/bin/slate-greeter-install            # install / update its code
sudo ~/.config/slate/bin/slate-greeter-install --revert   # back to the previous greeter
```

## Gotchas

- **GTK4 apps need reopening to change colour.** GNOME/libadwaita apps (Nautilus, Text
  Editor, Settings…) read Slate's colours only when they start. Nautilus also keeps running
  in the background after its windows close, so Slate restarts it once its last window is
  closed; reopen it to see the new colours. GTK3 and Qt/KDE apps update straight away.
- **The login screen updates separately.** It runs before you log in, from a system folder
  (`/usr/local/share/slate-greeter`), so it can't read your home folder:
  - Wallpaper, accent, theme and picture changes are copied to it automatically (once it's
    set up with `./install.sh --login-screen`).
  - When the login screen's own code changes, Slate shows a **Login screen out of date**
    notification. **Update** asks for your password; until then you'll see the previous
    version at login. Settings → Lock & idle has the same button.
  - The lock screen is part of Slate itself, so it's always current.
- **Floating mode's title bars need rebuilding after Hyprland updates.** Floating mode is
  optional: Slate tiles windows by default, and this only matters if you've switched to
  floating windows in Settings → Windows. The title bars come from the hyprbars plugin, which only works with the exact Hyprland it was built for. After a
  Hyprland update, Slate goes back to tiling (and Settings hides the window mode) until
  you run `slate build-hyprbars` (then log out and in, or `hyprctl reload`). Your choice
  of floating is kept and comes back once it's built.
- **Some changes need a fresh login.** The mouse cursor theme and other environment settings
  reach apps when they start; already-open apps keep the old ones, and Slate itself picks
  them up after logging out and in (`slate restart` reloads Slate's code, not its
  environment).
- **Folder colours need Papirus.** Settings → Appearance → Folder colour uses the coloured
  folders in the Papirus icon theme (installed and set by default); other icon themes keep
  their own folders.
- **Quickshell built from source must be rebuilt after Qt updates** (Ubuntu, Debian and
  openSUSE, where the installer builds it): run `packaging/build-quickshell.sh` again, or
  Slate won't start.

## Thanks

Slate stands on the work of two projects and the people behind them:

- **[Hyprland](https://hypr.land)**, by Vaxry and contributors: the compositor that draws
  every window, animation and blur here, and whose Lua configuration Slate is built around.
- **[Quickshell](https://quickshell.org)**, by outfoxxed and contributors: the toolkit
  every part of Slate's interface is written in, from the bar to the lock screen.

Thank you for making something this good to build on. Thanks also to the authors of
Bibata (the cursors), Tabler Icons, Geist and Papirus.

## Licence

Slate is released under the [MIT License](LICENSE). The bundled Tabler icon font (MIT)
and Geist fonts (SIL Open Font License) keep their own licences; see `LICENSE` and
`shell/fonts/`. The mouse cursors, Slate Cursors, are [Bibata Modern Ice](https://github.com/ful1e5/Bibata_Cursor)
redrawn without colour, under Bibata's GPL-3.0; see `shell/cursors/Slate-Cursors/`.
