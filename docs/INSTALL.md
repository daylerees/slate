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
`otf-geist` (the installer downloads Geist otherwise).

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
Hyprland 0.57), `sudo nixos-rebuild switch`, then `./install.sh --no-deps`.

### Other distros

Install Hyprland 0.57+, Quickshell 0.3+ (see its
[build guide](https://github.com/quickshell-mirror/quickshell/blob/master/BUILD.md)) and the
packages in [ARCHITECTURE.md → Dependencies](ARCHITECTURE.md#dependencies), then run
`./install.sh --no-deps`.

### Not packaged everywhere

- **swash** (screenshot editor) is only packaged for Arch. Without it, screenshots are
  saved to `~/Pictures/Screenshots` and copied to the clipboard.
- **Geist** (the interface font) is bundled with Slate, so nothing to install.
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
   and asked first).
2. **Checks** Hyprland and Quickshell are new enough.
3. **Font** — [Geist](https://vercel.com/font) ships with Slate (and Slate loads it itself);
   the installer also installs it to `~/.local/share/fonts` for your other apps if it's
   missing. Slate's icon font is bundled too.
   **Icons and cursor** — the Papirus icon theme (a package) becomes your icon theme,
   Papirus-Dark, unless you've chosen one of your own; Slate's cursors (bundled) are
   linked into `~/.local/share/icons` for the session to use.
   **Title bars** — builds the [hyprbars](https://github.com/hyprwm/hyprland-plugins/tree/main/hyprbars)
   Hyprland plugin for your Hyprland into `~/.local/share/slate/plugins` (no root), for
   floating mode (Settings → Windows → Window mode). It's optional: without it (or without
   Slate's patch to it) Slate tiles windows and Settings doesn't offer floating mode.
   Rebuild it after Hyprland updates with `slate build-hyprbars`.
4. **Slate** — copies `shell/` to `~/.config/slate`. An existing copy is moved
   aside to `slate.backup-<date>` first (your `settings.json` is carried over).
5. **Login entry** — adds two files so login screens list "Slate":
   `/usr/local/bin/slate-session` and `/usr/share/wayland-sessions/slate.desktop`. This
   works with GDM, SDDM, LightDM and greetd login screens.
6. **Login screen (only with `--login-screen`)** — switches greetd to Slate's own login
   screen, keeping your old greetd setup to go back to. See
   [LOCK-AND-LOGIN.md](LOCK-AND-LOGIN.md).

## First steps

- **Settings**: Super+Z (or the gear in the control centre, Super+X). Set your **location**
  in Settings → General for weather and the sunset-to-sunrise night light, and pick a
  **wallpaper** in Settings → Appearance (Super+Shift+W). Images come from `~/Pictures`
  (change the folder there).
- **Monitors** (resolution, refresh rate, scale, rotation, arrangement and which is the
  main display) are in Settings → Displays; **how big Slate itself is** is Settings →
  Appearance → Interface size.
- **Keyboard & mouse** (layouts, Caps Lock, key repeat, pointer and touchpad), **Sound**,
  **Power** (lid, power button, power mode on battery and plugged in), **Default apps**,
  **Startup apps**, **Date & time**, **Screenshots** and a searchable list of **Shortcuts**
  are all in Settings (Super+Z; the Overview page lists the less-used ones). Settings only
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
| Super+Return | terminal (with the launcher open: the selected app on a new workspace) |
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
- **Login screen problems** — switch back from a text console (Ctrl+Alt+F3):
  `sudo ~/.config/slate/bin/slate-greeter-install --revert`, then reboot.
