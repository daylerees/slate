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

Slate is inspired by the best parts of macOS, Windows and Linux, and blends them together
into something fresh. Things work the way you'd expect, so it's a welcoming place for
people new to Linux and experienced users alike.

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
| `shell/wallpapers/` | Slate's own wallpapers (made by `tools/make-wallpapers.py`) |
| `shell/bin/` | helpers: `slate-session-install`, `slate-greeter-install`, `slate-greeter-sync`, `slate-greeter-check`, `slate-system` (packages and login session in step with Slate) |
| `packaging/` | package lists per distro, Quickshell build script |
| `tools/sync-from-live.sh` | copy a running Slate back into `shell/` (development) |
| `tools/check-greeter-files` | check the login screen's file list against its code (CI and the pre-commit hook run it) |
| `tests/` | the test suite: `tests/run` (in Docker, never touches your desktop); see [docs/TESTING.md](docs/TESTING.md) |
| `.githooks/` | pre-commit checks (the quick tests, and the login screen); turn on with `git config core.hooksPath .githooks` |
| `docs/` | install, architecture, session, lock/login, testing, redistribution notes |

## What's in it

| Part | What it does | File |
|---|---|---|
| Top bar | Spaces button, workspaces (dots + spring indicator), active window title / hover descriptions, tray, notifications · clipboard · screenshot · game mode · Wi-Fi · keyboard · Bluetooth · volume · battery group (clipboard, screenshot, game mode and hover descriptions off by default), clock, power. Rounded top screen corners | `Bar.qml` |
| Panels | Drop-downs from the bar: control centre (profile card with wallpaper, media, clock + forecast, quick toggles), Wi-Fi, volume, battery/power profiles, calendar, session, notifications, clipboard (recent items, clear), screenshot (area, window, screen). Log out / restart / shut down, and deleting a space, ask in a centred dialog; restarting can reopen your apps where they were | `Popouts.qml`, `PowerConfirm.qml` |
| Dock | macOS-style magnifying dock, pinned apps, right-click menus, auto-hide, media controls with album art, a waste basket | `shell.qml` |
| Launcher | App search (usage-sorted, forgiving), calculator and conversions, open windows, app actions, quick toggles, recent files and folders, commands (`>`), emoji (`:`), web search, open on a new workspace left/right | `Launcher.qml` |
| Spaces | Save the apps and window layout of one or more workspaces under a name, icon and colour; one click on the bar opens them again on new workspaces, each window wearing the space's colour along its top and its icon in a corner (`slate ipc call spaces restore <name>`) | `Spaces.qml`, `SpaceBadges.qml`, `SpaceBadge.qml`, `Popouts.qml`, `scripts/spaces.py` |
| Window switcher | Super+Tab, live previews, circular strip | `Switcher.qml` |
| Workspace overview | Super+Down, large live cards, reorder with Shift | `WorkspaceOverview.qml` |
| Notifications | Notification server, toasts (positionable), history | `Notifications.qml`, `NotificationCard.qml` |
| On-screen indicators | Volume, mic, brightness, keyboard backlight, workspace dots (Super+Left/Right) | `OSD.qml` |
| Settings app | General/appearance, wallpaper, menu bar (what it shows, clock format), dock, launcher, spaces, windows (borders, dimming, switcher, overview), hot corners, notifications, lock & idle, Wi-Fi, Bluetooth, printers & scanners, about, debug (login screen resync, log detail, exporting logs for bug reports, factory reset) | `SettingsWindow.qml`, `bin/slate-logs`, `bin/slate-factory-reset` |
| Lock screen | Wayland session lock + PAM, lockout countdown, lock-before-sleep, idle lock/screen-off/suspend | `LockScreen.qml`, `LoginScreen.qml` |
| Updates | Daily check for new releases with a notification; Settings → Updates shows what's new, updates in one click (keeping `settings.json`, `hypr/` and `user/`; new packages and login session changes are installed with your password) and can go back one version (`slate ipc call updates check`) | `Updates.qml`, `scripts/update.py`, `install.sh --update` |
| Screensaver | Your wallpaper drifting, a wallpaper slideshow, videos (your own folder, or free scenery clips to download) or black, each with or without the clock; starts before the lock, optional lock on wake (Settings → Screensaver; `slate ipc call screensaver start`) | `Screensaver.qml` |
| Login screen | optional greetd greeter in a minimal Hyprland, same design as the lock screen (Settings → Lock & Idle → Install) | `greeter/`, `LoginScreen.qml` |
| Slate session | "Slate" entry on any login screen: Hyprland with Slate's own config, separate from `~/.config/hypr` | `session/` |
| Hot corners | Per-corner actions, disarmed while locked | `HotCorners.qml` |
| MCP server | `slate mcp`: add it to an AI agent you already use (Claude Code, Codex…) and it can answer questions about your desktop: your settings, open windows, workspaces, Spaces, apps and wallpapers. It only looks, in words: never the screen, files or the clipboard ([docs/ASSISTANT.md](docs/ASSISTANT.md)) | `scripts/slate-mcp.py`, `data/assistant-prompt.md` |
| Screen corners | Rounded black screen corners | `ScreenCorners.qml`, `Bar.qml` |
| Shared settings | `Config` singleton backed by `settings.json`; theme (accent, light/dark, wallpaper tint) | `Config.qml` |
| Wallpaper | Drawn per screen on the background layer, cross-fades on change; picker in Settings (Super+Shift+W) | `Wallpaper.qml` |
| Clipboard & emoji | Super+V clipboard history (text + images; can be switched off in Settings → General), Super+. emoji picker | `Picker.qml`, `scripts/clipstore.py`, `data/emoji.json` |
| Password prompts | Polkit agent (pkexec, system settings) in Slate's style | `PolkitAgent.qml` |
| Night light | Warm screen via a Hyprland screen shader; manual, sunset-to-sunrise or custom schedule (Settings → General) | `NightLight.qml` |
| App theming | Opt-in, per app (Settings → App Theming): GTK, Qt, KDE, terminals (kitty, Alacritty, Ghostty, foot, WezTerm), editors (Text Editor, VS Code, Zed, Helix, Vim/Neovim), bat, fzf, Yazi, cava, zathura, btop, Discord (Vencord), Spotify (Spicetify), Obsidian and Firefox follow Slate's colours; configs are backed up and switching an app off puts them back | `scripts/apply-theme.py`, `slate_apps.py`, `slate_theme.py` |
| Screenshots | Print (area, screen frozen) / Super+Print (screen), or area / window / screen from the bar → saved to the chosen folder and copied, then optionally opened in swash | `scripts/screenshot.sh` |

## Docs

- [docs/INSTALL.md](docs/INSTALL.md) — installing on Arch, Debian/Ubuntu, Fedora, openSUSE, NixOS, and without systemd on Artix, Void and Gentoo; updating; removing
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the pieces fit, IPC, Hyprland integration, theming, settings
- [docs/LOCK-AND-LOGIN.md](docs/LOCK-AND-LOGIN.md) — lock screen, idle/sleep, login screen (greetd) and recovery
- [docs/SESSION.md](docs/SESSION.md) — the "Slate" login session, its Hyprland config and personal overrides
- [docs/ASSISTANT.md](docs/ASSISTANT.md) — Slate's MCP server: adding it to an AI agent, its tools, what leaves your computer
- [docs/TESTING.md](docs/TESTING.md) — the test suite: what it checks, running it, approving new screenshots
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
| Your own tweaks for the Slate session (made with instructions; reloaded as you save) | `~/.config/slate/hypr/` (`env`, `variables`, `monitors`, `binds`, `rules`, `autostart`, `hyprland` `.lua`) and `~/.config/slate/user/shell.qml` (QML loaded into Slate) |
| Session launcher + login entry (installed) | `/usr/local/bin/slate-session`, `/usr/share/wayland-sessions/slate.desktop` |
| Login screen code (root-owned copy) | `/usr/local/share/slate-greeter/` |
| Login screen appearance (synced) | `/var/lib/slate-greeter/` |
| Helpers | `~/.config/slate/bin/`: `slate-session-install` (sudo), `slate-greeter-install` (sudo), `slate-greeter-sync`, `slate-system` (`--check`, `--fix`) |
| App-icon tile generator | `scripts/appicon.py` (in the shell folder) |

## Everyday commands

```sh
# Restart Slate
slate restart

# Talk to a running Slate
slate ipc call settings toggle
slate ipc call lock preview lock      # or: preview login
slate ipc call launcher search "2*pi"

# Let an AI agent ask about your desktop (docs/ASSISTANT.md)
claude mcp add slate -- ~/.config/slate/bin/slate mcp

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
  - It's optional and isn't installed unless you ask: Settings → Lock & Idle → Install (or
    `./install.sh --login-screen`). It replaces your system's login screen, so a broken one
    can stop you logging in, and it needs updating with your password when Slate, Hyprland,
    Quickshell or greetd change. [docs/LOCK-AND-LOGIN.md](docs/LOCK-AND-LOGIN.md#login-screen-greetd)
    has the details and how to switch back.
  - Wallpaper, accent, theme and picture changes are copied to it automatically.
  - When the login screen's own code changes, Slate shows a **Login screen out of date**
    notification. **Update** asks for your password; until then you'll see the previous
    version at login. Settings → Lock & Idle has the same button.
  - Each update is test-loaded before it's installed; if it doesn't load, nothing changes.
    If the login screen still fails at boot, the last version you logged in with takes
    over, and failing that a basic emergency login screen, so you're never left at a
    text console.
  - The lock screen is part of Slate itself, so it's always current.
- **Hyprbars needs rebuilding after Hyprland updates.** Floating windows use Slate Bars (Slate's own
  title bars) by default, which need nothing. Hyprbars (Settings → Windows → Title bars) is the
  optional alternative: a Hyprland plugin with a bar on every floating window, which only
  works with the exact Hyprland it was built for. After a Hyprland update Slate switches to
  Slate Bars and asks whether to rebuild Hyprbars; once that's done and Hyprland has
  reloaded, it asks whether to switch back. See
  [docs/INSTALL.md](docs/INSTALL.md#title-bars).
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
