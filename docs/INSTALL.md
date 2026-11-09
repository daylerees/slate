# Installing Slate

Slate runs as its own session: after installing, **Slate** appears on your login screen
next to your current desktop. Nothing about your existing desktop changes, so you can try
it and switch back at login.

## Quick install

```sh
git clone <repo-url> slate && cd slate
./install.sh
```

Then **log out, choose "Slate" on the login screen, and log in.**

Run the installer as your normal user (not with `sudo`); it asks for your password when
it installs packages or adds the login entry, and asks before each system change.
Options: `./install.sh --help`.

| Option | What it does |
|---|---|
| `--yes` | don't ask, answer yes to everything |
| `--login-screen` | also switch your login screen to Slate's own (greetd) |
| `--no-deps` | skip installing packages (you installed them yourself) |
| `--link` | link `~/.config/slate` to this folder instead of copying (for working on Slate) |
| `--uninstall` | remove Slate (see [Removing](#removing)) |

## Requirements

- **Hyprland 0.57 or newer** — Slate's session uses Hyprland's Lua config (`hyprland.lua`),
  which older versions don't understand.
- **Quickshell 0.3 or newer** — the toolkit Slate is written in.
- A systemd-based distro with PipeWire, NetworkManager, polkit and the other packages in
  `packaging/<distro>.txt` (the installer installs them).

Your distro's notes are below. If its Hyprland or Quickshell is too old, the installer
says so and points here.

## Your distro

| Distro | Supported | How Hyprland and Quickshell get installed |
|---|---|---|
| **Arch** and derivatives (CachyOS, EndeavourOS, Manjaro) | ✓ | official repos |
| **Debian testing / sid** | ✓ | official repos |
| **Ubuntu 26.04** and newer | ✓ | Hyprland from `ppa:cppiber/hyprland` (added for you); Quickshell built from source |
| **Fedora 44** and newer | ✓ | COPRs `sdegler/hyprland` and `errornointernet/quickshell` (enabled for you) |
| **openSUSE Tumbleweed** | ✓ | Hyprland official; Quickshell built from source |
| **NixOS** (unstable) | ✓ | add `packaging/nixos.nix` to your config |
| Debian 13 "trixie", Ubuntu 24.04 / 25.10, Fedora 43, openSUSE Leap | ✗ | Hyprland 0.57 isn't available (or Qt is too old for Quickshell) |

### Arch, CachyOS, EndeavourOS, Manjaro

`./install.sh` — everything is in the official repos. Optional extras from the AUR, if you
have `paru` or `yay`: `swash` (screenshot editor; CachyOS has it in its own repo) and
`otf-geist` (otherwise the installer installs the copy of Geist bundled with Slate).

### Debian testing / sid

`./install.sh`. Debian 13 "trixie" (stable) only has Hyprland up to 0.55 in backports;
Slate needs 0.57, so use testing or sid.

### Ubuntu 26.04 and newer

`./install.sh`. It adds the `ppa:cppiber/hyprland` PPA for a current Hyprland, then
offers to **build Quickshell from source** (Ubuntu doesn't package 0.3 yet; about 5–10
minutes; it installs build tools). After Ubuntu upgrades Qt, rebuild it with
`packaging/build-quickshell.sh` or Slate won't start. Ubuntu 24.04's Qt is too old for
Quickshell.

### Fedora 44 and newer

`./install.sh`. Fedora doesn't ship Hyprland, and its own `quickshell` is too old, so the
installer enables two COPRs: `sdegler/hyprland` (Hyprland, uwsm, hyprpicker) and
`errornointernet/quickshell`. On Fedora Workstation, `tuned-ppd` already provides power
profiles, so `power-profiles-daemon` is skipped.

### openSUSE Tumbleweed

`./install.sh`. Hyprland is in the official repos; Quickshell isn't, so the installer
offers to build it from source (as on Ubuntu; rebuild after Qt upgrades).

### NixOS

Add the contents of `packaging/nixos.nix` to your configuration (needs nixos-unstable for
Hyprland 0.57), `sudo nixos-rebuild switch`, then `./install.sh --no-deps`. Install a terminal
and a file manager too if you don't have one (kitty and Nautilus, say). NixOS's `/etc` and
`/usr/share` are managed by Nix, so the Slate session and login screen are set up in your
configuration rather than by `slate-session-install` and `slate-greeter-install`: add the
session with `services.displayManager.sessionPackages`, and greetd with `services.greetd`.

### Other distros

Install Hyprland 0.57+, Quickshell 0.3+ (see its
[build guide](https://github.com/quickshell-mirror/quickshell/blob/master/BUILD.md)) and the
packages in [ARCHITECTURE.md → Dependencies](ARCHITECTURE.md#dependencies), then run
`./install.sh --no-deps`.

### Not packaged everywhere

- **swash** (screenshot editor) is only packaged for Arch. Without it, screenshots are
  saved to `~/Pictures/Screenshots` and copied to the clipboard.
- **Geist** and **Geist Mono** (the interface and code fonts) are bundled with Slate, so
  nothing to install.
- **hyprbars** (title bars in floating mode) is optional: without it Slate tiles windows,
  and Settings doesn't offer floating mode. It's only packaged for NixOS
  (`hyprlandPlugins.hyprbars`) and the AUR; Slate builds it from source, which needs Hyprland's headers
  (part of the `hyprland` package on Arch; `hyprland-devel`/`hyprland-dev` elsewhere).
- **Papirus** (the icon theme behind Settings' coloured folder icons) is packaged everywhere
  and installed with Slate. The installer makes Papirus-Dark your icon theme unless you've
  picked your own; folder colours only work while a Papirus theme is in use.
- **adw-gtk3** (makes GTK apps match) isn't packaged on Debian/Ubuntu/openSUSE; get it
  from [its releases](https://github.com/lassekongo83/adw-gtk3/releases) if you want it.


## What the installer does

1. **Packages** — installs the list for your distro from `packaging/` (you're shown the list
   and asked first). If you have no terminal or no file manager, it offers kitty and
   Nautilus (Slate's shortcuts, dock and desktop menu open them; any you already have are
   used instead, and Settings → Default Apps picks between them). It also offers to switch on
   Bluetooth and NetworkManager if they're off (some distros leave them off), leaving another
   network service alone if one is running.
2. **Checks** Hyprland and Quickshell are new enough.
3. **Fonts** — [Geist and Geist Mono](https://vercel.com/font) ship with Slate (and Slate
   loads them itself); the installer also installs each to `~/.local/share/fonts` for your
   other apps (so terminals can use Geist Mono as the code font) unless it's installed
   already, and keeps that copy up to date on updates. Slate's icon font is bundled too.
   **Icons and cursor** — the Papirus icon theme (a package) becomes your icon theme,
   Papirus-Dark, unless you've chosen one of your own; Slate's cursors (bundled) are
   linked into `~/.local/share/icons` for the session to use.
   **Title bars** — builds the [hyprbars](https://github.com/hyprwm/hyprland-plugins/tree/main/hyprbars)
   Hyprland plugin for your Hyprland into `~/.local/share/slate/plugins` (no root), for
   floating mode (Settings → Windows → Window mode). It's optional: without it (or without
   Slate's patch to it) Slate tiles windows and Settings doesn't offer floating mode.
   Rebuild it after Hyprland updates with `slate build-hyprbars`.
4. **Slate** — copies `shell/` to `~/.config/slate`. An existing copy is kept as
   `slate.previous` (one version back; your `settings.json`, `hypr/` and `user/` are
   carried over).
5. **Login entry** — adds two files so login screens list "Slate":
   `/usr/local/bin/slate-session` and `/usr/share/wayland-sessions/slate.desktop`. This
   works with GDM, SDDM, LightDM and greetd login screens.
6. **Login screen (only with `--login-screen`)** — switches greetd to Slate's own login
   screen, keeping your old greetd setup to go back to. See
   [LOCK-AND-LOGIN.md](LOCK-AND-LOGIN.md).

## First steps

- **The welcome** opens the first time Slate starts: an introduction, then a few big
  choices, each with a recommendation (tiling or floating windows; dark, light or auto,
  colours from the wallpaper and theming your other apps; where the bar and dock go; and
  the shortcuts). Skip it any time; show it again from Settings → About.
- **Settings**: Super+Z (or the gear in the control centre, Super+X). Set your **location**
  in Settings → General for weather and the sunset-to-sunrise night light, and pick a
  **wallpaper** in Settings → Appearance (Super+Shift+W). Images come from `~/Pictures`
  (change the folder there).
- **Monitors** (resolution, refresh rate, scale, rotation, arrangement and which is the
  main display) are in Settings → Displays; **how big Slate itself is** is Settings →
  Appearance → Interface size.
- **Keyboard & Mouse** (layouts, Caps Lock, key repeat, pointer and touchpad), **Sound**,
  **Power** (lid, power button, power mode on battery and plugged in), **Default Apps**,
  **Startup Apps**, **Date & Time**, **Screenshots** and a searchable list of **Shortcuts**
  are all in Settings (Super+Z; All Settings, the first page, has a tile for every page). Settings only
  sets what you change there; anything else keeps what your own files say.
- **Monitor rules, extra keys and anything else** go in your own files, which Slate loads
  on top of its config:
  - `~/.config/slate/hypr/variables.lua` — e.g. `TERMINAL = "foot"`, `BROWSER = "chromium"`
  - `~/.config/slate/hypr/hyprland.lua` — e.g.
    `hl.config({ input = { kb_layout = "de" } })`
  See [SESSION.md](SESSION.md).

### Keys

| Keys | Does |
|---|---|
| Super (tap) or Super+Space | app launcher (type to search; also a calculator) |
| Super+Return | terminal (with the launcher open: the selected app on a new workspace at the end) |
| Super+E | file manager |
| Super+Q | close window |
| Super+Tab / Alt+Tab | window switcher |
| Super+Left / Right | previous / next workspace |
| Super+Down | workspace overview |
| Super+Ctrl+1…3 | go to workspace 1…3 |
| Super+Shift+arrows | move window |
| Super+F / Super+D | fullscreen / maximise |
| Super+Alt+Space | float / tile window |
| Super+X | control centre |
| Super+A | notifications |
| Super+V | clipboard history |
| Super+. | emoji picker |
| Super+L | lock |
| Super+Alt+C | power menu |
| Super+Z | Slate settings |
| Super+Shift+W | wallpaper |
| Print / Super+Print | screenshot an area / the screen |
| Super+P | colour picker |

All keys are in `shell/session/hypr/config/binds.lua`.

## Updating

Slate looks for a new release once a day and shows a notification when one is out
(turn it off in Settings → Updates). **Settings → Updates** shows what's new and updates in
one click: it downloads the release and runs its `./install.sh --update`, which puts the new
version in place without questions or `sudo`. Your settings and overrides are always kept:
`settings.json`, `hypr/` and `user/` in `~/.config/slate`.

- The version you had is kept in `~/.config/slate.previous` (one version back), and
  Settings → Updates can go back to it. Your settings and overrides stay as they are when
  you switch, and the version you leave becomes the backup, so you can switch back again.
- Changes made by hand to Slate's own files (outside `settings.json`, `hypr/` and `user/`)
  are listed before updating, since the update replaces them (they stay in the backup).
- A release that needs new packages, or newer Hyprland or Quickshell, stops before changing
  anything and asks you to run its full installer. If it changes the login session, the
  Updates page shows the one `sudo` command left to run.

From a copy of the code instead:

```sh
cd slate && git pull
./install.sh --no-deps
```

Your settings are kept. If you use Slate's login screen, Slate notices its code changed
and offers to update it (it asks for your password).

## Removing

```sh
./install.sh --uninstall
```

This takes "Slate" off the login screen, puts back your previous login screen if you used
`--login-screen`, and moves `~/.config/slate` aside (to
`slate.removed-<date>`). Packages are left installed, since other apps may use them.
Slate's state in `~/.local/state/slate` and `~/.cache/slate` can be deleted by hand.

## Troubleshooting

- **"Slate" isn't on the login screen** — run
  `sudo ~/.config/slate/bin/slate-session-install`. Some login screens only
  rescan sessions after a reboot.
- **The Slate session starts and immediately ends** — usually Hyprland is too old or
  `start-hyprland` is missing. Check `Hyprland --version` (needs 0.57+). With uwsm:
  `journalctl --user -b -u 'wayland-wm@*'`.
- **Black screen with a cursor, no bar** — Quickshell couldn't load Slate. From a
  terminal in the session (Super+Return) run
  `slate` and read the error, or see `~/.cache/slate.log`.
- **Icons show as boxes** — the bundled icon font didn't load; reinstall Slate
  (`./install.sh --no-deps`).
- **Reporting a problem** — Settings → Debug → **Export recent logs** (or `slate logs` in a
  terminal) saves Slate's recent log and system details to a file in Downloads, without your
  location; look it over, then attach it to the issue. Turning **Log detail** up first (it
  restarts Slate) and reproducing the problem gives a fuller log.
- **Starting over** — Settings → Debug → **Factory reset** (or
  `~/.config/slate/bin/slate-factory-reset`) puts every setting back to its default and forgets
  dock pins, saved Spaces, launcher and clipboard history, notifications, the display layout and
  app theming. It asks twice first. Your own `hypr/*.lua` and `user/` files are kept unless you
  switch on **Also clear my own files** (or pass `--user-files`), which swaps them for the blank
  ones Slate starts with. Everything is moved to
  `~/.local/share/slate/backups/factory-reset-<date>`, not deleted.
- **Login screen problems** — switch back from a text console (Ctrl+Alt+F3):
  `sudo ~/.config/slate/bin/slate-greeter-install --revert`, then reboot.
