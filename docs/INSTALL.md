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
| `--login-screen` | also switch your login screen to Slate's own (greetd). Optional; read the risks in [LOCK-AND-LOGIN.md](LOCK-AND-LOGIN.md#login-screen-greetd) first |
| `--no-deps` | skip installing packages (you installed them yourself) |
| `--link` | link `~/.config/slate` to this folder instead of copying (for working on Slate) |
| `--uninstall` | remove Slate (see [Removing](#removing)) |

## Requirements

- **Hyprland 0.57 or newer** — Slate's session uses Hyprland's Lua config (`hyprland.lua`),
  which older versions don't understand.
- **Quickshell 0.3 or newer** — the toolkit Slate is written in.
- **A login service:** systemd (which most distros use, and includes one), or, without
  systemd, **elogind**. It's what lets Slate suspend, restart and shut down, lock before
  sleep, and show password prompts. See [Without systemd](#without-systemd-artix-void-gentoo).
- PipeWire, NetworkManager, polkit and the other packages in `packaging/<distro>.txt` (the
  installer installs them).

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
| **Artix** (OpenRC, runit, dinit, s6) | ✓ new, not yet tried on a real install | `world` (Hyprland) and `galaxy` (Quickshell) repositories. [Without systemd](#without-systemd-artix-void-gentoo) |
| **Void** (runit) | ✓ new, not yet tried on a real install | Hyprland from a third-party repository; Quickshell official. [Without systemd](#without-systemd-artix-void-gentoo) |
| **Gentoo** (OpenRC or systemd) | ✓ new, not yet tried on a real install | you emerge them (hyproverlay, GURU). [Without systemd](#without-systemd-artix-void-gentoo) |
| Alpine, Chimera, Devuan | ✗ | no Hyprland 0.57 yet (Alpine edge has 0.54; Chimera has none; Devuan follows Debian's) |
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

### Without systemd: Artix, Void, Gentoo

Slate was written on systemd, and it now also runs without it. Hyprland and Quickshell
themselves don't need systemd; Slate used a handful of systemd's tools, and those calls now
go through one helper (`bin/slate-init`) that uses the right thing for your system. With
systemd, nothing has changed.

**Please know before you start:** this support is new, and it has been built and tested
against stand-ins for these systems, not yet on real installs of them. The package names for
Void and Gentoo are our best knowledge. If something doesn't work, we'd love to hear about it.

**What you need**

- **elogind, running.** This is the one firm requirement. It does for Slate what
  systemd's login service does elsewhere: seats for Hyprland, suspend, restart and shut
  down (`loginctl`), telling Slate the computer is about to sleep, holding the lid and power
  button for Slate, and the login session that password prompts (polkit) need. Use the
  polkit built for elogind.
- **With seatd alone** (no elogind) Slate still starts and the desktop works, but it can't
  suspend, restart or shut down for you, "Lock before sleep" and the lid and power button
  settings are greyed out with a note saying why, and password prompts may be refused. It's
  not a setup we can recommend.
- **Hyprland 0.57+ and Quickshell 0.3+**, as everywhere.

**What's different from a systemd system**

- **Slate doesn't switch services on for you.** Each init system has its own way, so
  where Slate would offer a "Turn on" button (printing), or the installer would enable
  Bluetooth and NetworkManager, it shows you the command for your init system instead, for
  example `sudo rc-update add bluetooth default && sudo rc-service bluetooth start`, or
  `sudo ln -s /etc/sv/bluetoothd /var/service/`. `bin/slate-init service-hint bluetooth`
  prints it at any time.
- **Sound is started by the session.** systemd's user session normally starts PipeWire;
  without it Slate's session starts PipeWire, WirePlumber and pipewire-pulse itself
  (`scripts/session-services.sh`), unless they're already running. If you start them your own
  way, Slate leaves them alone.
- **The session starts Hyprland directly.** uwsm (which runs a session through systemd)
  isn't used, and Slate starts a D-Bus session bus itself if nothing has.
- **Date & Time:** changing the time zone or network time needs a service that offers what
  systemd's does (`org.freedesktop.timedate1`; openrc-settingsd provides it). Without one,
  the page shows your time zone but can't change it, and says so.
- **Slate's login screen** (optional, as everywhere) works with greetd under any init
  system; you enable the greetd service yourself, and Settings → Lock & Idle shows the
  command. Its log goes to `/var/cache/slate-greeter/hyprland.log` rather than the journal.
- **Hyprland updates:** the same as on any distro, but note that Hyprland needs a very
  recent compiler to build (gcc 16 or clang 19), which is why some distros are behind.

**Artix**

Switch on the `world` and `galaxy` repositories in `/etc/pacman.conf` (Hyprland is in
`world`, Quickshell in `galaxy`), then:

```sh
./install.sh
```

The installer uses `packaging/artix.txt` (Arch's list without systemd and uwsm, with
elogind) and then adds each service's package for your init system
(`networkmanager-openrc`, `bluez-runit`, `greetd-dinit`…), which is what lets your init
system start it. It then tells you which services aren't running and how to switch them on.

**Void**

Hyprland isn't in Void's own repositories ("a conflict of packaging philosophy", in
Hyprland's words), so you need a third-party repository that has Hyprland 0.57 or newer,
such as [hyprland-void](https://github.com/Makrennel/hyprland-void). We haven't been able to
confirm which version each currently carries: check before you rely on one, and remember that
a third-party repository is run by its maintainer, not by Void or by Slate. Quickshell is in
Void's own packages. Then:

```sh
./install.sh
```

It installs `packaging/void.txt` one package at a time, so a name Void spells differently is
reported rather than stopping everything. Add yourself to the `_seatd` group if your
Hyprland repository's notes say to.

**Gentoo**

Slate leaves `emerge` to you, since USE flags, overlays and build time are yours to choose.
`./install.sh` shows the list (`packaging/gentoo.txt`) and stops; emerge them, then run
`./install.sh --no-deps`. Hyprland 0.57+ is in the hyproverlay overlay and Quickshell in
GURU. Without systemd, build with `USE="elogind -systemd"`, and add
`app-admin/openrc-settingsd` if you'd like Settings to change the time zone. Gentoo on
systemd needs none of this section.

**Not yet:** Alpine and Chimera (no Hyprland 0.57 packaged; both also use musl, which Slate
hasn't been tried on) and Devuan (its Hyprland is Debian's, which is older).

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
- **Hyprbars** is optional and not installed with Slate: floating windows get Slate Bars,
  Slate's own title bars, which need nothing. Hyprbars is a Hyprland plugin that puts a title bar on every
  floating window; choose it in Settings → Windows → Title bars and Slate builds it from
  source, which needs `git`, `make`, `g++`, a connection and Hyprland's headers (part of the
  `hyprland` package on Arch; `hyprland-devel`/`hyprland-dev` elsewhere). See
  [Title bars](#title-bars) below for what it involves.
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
4. **Slate** — copies `shell/` to `~/.config/slate`. An existing copy is kept as
   `slate.previous` (one version back; your `settings.json`, `hypr/` and `user/` are
   carried over).
5. **Login entry** — adds two files so login screens list "Slate":
   `/usr/local/bin/slate-session` and `/usr/share/wayland-sessions/slate.desktop`. This
   works with GDM, SDDM, LightDM and greetd login screens.
6. **Login screen (only with `--login-screen`)** — switches greetd to Slate's own login
   screen, keeping your old greetd setup to go back to. It's optional and not installed
   otherwise; you can also install it later from Settings → Lock & Idle. A broken login
   screen can stop you logging in, and it needs updating (with your password) when Slate,
   Hyprland, Quickshell or greetd change: see
   [LOCK-AND-LOGIN.md](LOCK-AND-LOGIN.md#login-screen-greetd) before choosing it.

## Title bars

Floating windows (Settings → Windows → Default window mode, or one workspace from the menu
bar) have title bars. There are two kinds:

- **Slate Bars** (the default): Slate draws a title bar on the floating window in front. Nothing
  to install, and nothing that breaks when Hyprland updates. The bar fades out while a window
  moves, resizes or maximises and comes back once it's in place, and floating windows take
  focus when clicked rather than as the pointer passes over them.
- **Hyprbars** (optional): the
  [hyprbars](https://github.com/hyprwm/hyprland-plugins/tree/main/hyprbars) Hyprland plugin,
  with a bar on every floating window that moves as one with it. Choose it in Settings →
  Windows → Title bars; Slate says what's involved, builds it into
  `~/.local/share/slate/plugins` (no root), and switches once it's loaded.

What choosing Hyprbars involves:

- **It stops working after every Hyprland update**, because a plugin only loads in the exact
  Hyprland it was built for. Slate never loads a build made for another Hyprland (so no error
  messages at login); it switches to Slate Bars, shows that in Settings, and asks
  whether to rebuild. When the build is done, a notification offers to reload Hyprland (your
  windows stay open), and after that Slate asks whether to switch back to Hyprbars.
- **If Hyprland was updated but you haven't restarted yet**, Hyprbars keeps working, and Slate
  offers to rebuild it right away so it's ready after your next restart.
- **Building needs** `git`, `make`, `g++`, Hyprland's headers and (the first time) an internet
  connection. If a build fails, one notification says why, Slate Bars stay in use,
  and Settings → Windows has Retry. The full log is `~/.cache/slate/hyprbars-build.log`.
- **Remove** (Settings → Windows → Hyprbars) switches floating windows to Slate Bars
  at once and deletes Slate's builds; the plugin is fully gone after your next restart.
- By hand: `slate build-hyprbars` builds it, `slate build-hyprbars --status` says where it
  stands.

If you already had Hyprbars working before Slate Bars became the default, you
keep it.

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
- A release that needs packages you don't have asks for your password and installs them
  before it puts itself in place; one that changes the login session does the same for it.
  If you cancel, or it needs newer Hyprland or Quickshell than your distro has, it stops
  before changing anything and asks you to run its full installer.
- Slate also checks this itself, 25 seconds after it starts (for a copy put in place by
  hand, or a package removed since): when something is missing, an urgent notification
  offers to install it, with your password. It asks once for each set of changes, and
  "Later" waits a week. `~/.config/slate/bin/slate-system --check` lists what it would do.
  Only the required packages are installed this way; optional ones are left to
  `./install.sh`, and on NixOS they come from your configuration.

From a copy of the code instead:

```sh
cd slate && git pull
./install.sh --no-deps
```

Your settings are kept. If you installed Slate's login screen, Slate notices its code changed
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

- **Suspend, Restart or Shut down are missing, or settings are greyed out with "This needs
  systemd or elogind"** — your computer has no login service running. Run
  `~/.config/slate/bin/slate-init info`: `logind=none` means elogind isn't installed or
  isn't started. See [Without systemd](#without-systemd-artix-void-gentoo).
- **No sound, without systemd** — check PipeWire is installed; Slate's session starts it.
  `pgrep -a pipewire` should show `pipewire`, `wireplumber` and `pipewire-pulse`.
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
