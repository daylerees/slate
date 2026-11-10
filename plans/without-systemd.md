# Plan: Slate on systems without systemd

Status: **planned** (2026-11-10). Nothing built yet.

## Goal

Slate runs properly on Linux systems that don't use systemd: first Artix, then others as
their Hyprland catches up. Everything that works today on systemd keeps working exactly as it
does. Where a feature can't work on a system, Slate says so kindly instead of failing
silently (CLAUDE.md, Voice; the "Slate is redistributed" rule).

Not a goal: managing every init system's services from Settings (OpenRC, runit, dinit, s6
each differ). Slate tells you what to switch on, and how, rather than doing it.

## Are Hyprland and Quickshell fine without systemd?

Checked on 2026-11-10 (sources at the end; "unverified" where a page couldn't be read).

**Hyprland.** Yes. systemd is optional in its build: `NO_SYSTEMD` "removes systemd
dependencies" (and with it the uwsm session file, which is only installed when systemd
support is on). Its CMake list has no libsystemd, libelogind or libseat; seat access comes
through aquamarine/libseat, which works with seatd or elogind. What `USES_SYSTEMD` changes
inside Hyprland's source is unverified (most likely the systemd user target and
notifications to it). Slate needs Hyprland 0.57+ (the Lua config and `start-hyprland`), and
Hyprland now needs a C++26 compiler (gcc 16 or clang 19) and Lua 5.5 to build, which is
what holds slower distros back.

**Quickshell.** Yes. Its build document doesn't mention systemd, logind or elogind at all.
Each service is its own switch (PAM, polkit, PipeWire, tray, MPRIS…), and the ones Slate
uses talk to ordinary D-Bus services or libraries. Slate runs on 0.3.2 today.

**Per distro**

| Distro (init) | Hyprland | Quickshell | Verdict |
|---|---|---|---|
| Artix (OpenRC, runit, dinit, s6) | 0.57.2 in `world` (2026-11-09) | 0.3.2 in `galaxy` | Ready. pacman-based, so Slate's Arch package list nearly applies. **First target.** |
| Void (runit) | Not in the official repos ("a conflict of packaging philosophy"); third-party repos (Makrennel/hyprland-void, Event-Horizon-VL/blackhole-vl), versions unverified | In void-packages (version unverified) | Possible, on a third-party Hyprland. Second target, once a repo with 0.57+ is confirmed. |
| Alpine edge (OpenRC, musl) | 0.54.3 in `community`: too old | Not packaged on edge | Not yet. Needs Hyprland 0.57+ and a Quickshell build on musl. |
| Chimera (dinit, musl) | Not packaged | 0.3.2 in `user` | Not yet (no Hyprland). |
| Gentoo (OpenRC) | In the `hyproverlay` overlay per Hyprland's wiki; versions and USE flags unverified | 0.3.2 in the GURU overlay | Likely fine; verify, then document rather than automate (Gentoo users build their own). |
| Devuan | Follows Debian's Hyprland, which is older than 0.57 | Slate's own build script | Not yet, same as Debian itself. |

So the work is on Slate's side, and it can be proven on Artix.

## Where Slate uses systemd today

From a search of `shell/`, `install.sh` and `packaging/`. "elogind" means the standalone
logind that Artix, Void, Alpine and Gentoo offer: the same `org.freedesktop.login1` D-Bus
service and a `loginctl` with power commands, without the rest of systemd.

| What | Where | Today | Without systemd |
|---|---|---|---|
| Suspend | `LockScreen.qml` (3 places), `Popouts.qml`, `Launcher.qml`, `session/hypr/config/slate.lua` (lid, power button) | `systemctl suspend` | `loginctl suspend` (elogind); else unavailable |
| Restart, shut down | `scripts/session.sh`, `LockScreen.qml`, `greeter/shell.qml`, `greeter/emergency/` | `systemctl reboot/poweroff` | `loginctl reboot/poweroff` (elogind); else the init's own (`openrc-shutdown`, `shutdown`), which need root or a polkit/doas rule |
| Lock before sleep, lock on request | `LockScreen.qml` (`gdbus monitor … org.freedesktop.login1`: `PrepareForSleep`, `Session.Lock`) | systemd-logind | Works unchanged with elogind (same signals). With seatd alone: no signal, so the setting is hidden |
| Holding sleep until locked; lid and power button handled by Slate | `LockScreen.qml`, `Config.qml` (`systemd-inhibit`) | `systemd-inhibit` | `elogind-inhibit` (same arguments); else those settings are hidden |
| Date and time | `SettingsWindow.qml` (`timedatectl`: zone list, set zone, network time) | systemd-timedated | The `org.freedesktop.timedate1` D-Bus service where something provides it (openrc-settingsd does); zone list from `/usr/share/zoneinfo`; otherwise the rows explain why they're off |
| Services | `install.sh` (Bluetooth, NetworkManager), `scripts/printers.py` (CUPS: is it running, switch it on), Settings and `install.sh` text for greetd | `systemctl is-active / enable` | Detect the init system; check with its own command; for switching on, show the right command for it (no automatic enabling at first) |
| Which login screen is in use | `bin/slate-greeter-sync --status` (`systemctl show display-manager.service`) | systemd | Per init (`rc-update show`, `/var/service`, `dinitctl list`), else "unknown" and the text doesn't claim anything |
| Login screen's log | `bin/slate-greeter-install` (`systemd-cat`), `bin/slate-logs` (`journalctl`) | journal | A log file in `/var/cache/slate-greeter/` (already used for the greeter's own log) |
| D-Bus calls | `Bar.qml` (tray check), `scripts/set-avatar.sh` (`busctl`) | `busctl` is a systemd tool | `gdbus` (glib, already used elsewhere in Slate) |
| Session start | `session/slate-session`, `scripts/session.sh` (uwsm) | uwsm when installed | Already falls back to `start-hyprland` and `hl.dsp.exit()`. uwsm is systemd-only: never list it as wanted off systemd |

Not affected (plain D-Bus services or libraries that exist without systemd): UPower,
power-profiles-daemon, polkit and `pkexec` (with elogind), PAM, PipeWire/WirePlumber,
NetworkManager, BlueZ, accountsservice, greetd, CUPS itself.

## What a system needs

- **Required: a login service (logind).** On systemd distros that's systemd-logind, which
  they already have: nothing changes there, and elogind is never installed (it conflicts
  with systemd). Without systemd it's elogind (and polkit built for it). Either gives Slate
  seats for Hyprland, a login session for polkit prompts, sleep signals, inhibitors and
  `loginctl` power commands, which is why almost everything works unchanged.
- **The current distros are untouched:** their package lists don't change (elogind is only
  in `artix.txt`), and `slate-init` takes the systemd branch first, running the same
  commands as today. It decides by what's running (`/run/systemd/system` exists → systemd;
  else an `org.freedesktop.login1` owner on the system bus → elogind), never by which
  commands happen to be installed: `loginctl` exists on both.
- **seatd alone** (no elogind): Slate starts and the desktop works, but no suspend/restart
  from Slate without extra setup, no lock-before-sleep, and password prompts (polkit) may
  refuse. Supported as "runs, with these parts switched off and explained", not as a
  first-class setup.
- A D-Bus session bus for the Slate session (`dbus-run-session` in `slate-session` when
  none is running: systemd's user session usually provides it today).
- PipeWire and WirePlumber started for the session (systemd user units do this today):
  `slate-session`/`autostart.lua` start them when they aren't running.

## Changes

### 1. One place that knows the system (`shell/bin/slate-init`, new)
A small script, used by the shell scripts and by `Config.qml` (run once at start, result in
`Config.system`):
- `slate-init info` → `init=systemd|openrc|runit|dinit|s6|unknown`,
  `logind=systemd|elogind|none`, `inhibit=<command or empty>`, `timedate=yes|no`.
- `slate-init suspend|reboot|poweroff` → the right command (`systemctl …`, `loginctl …`,
  else fails with a clear message).
- `slate-init inhibit <what> <who> <why> -- cmd…` → `systemd-inhibit` or `elogind-inhibit`.
- `slate-init service-active <name>` and `slate-init service-hint <name>` → is it running;
  the command a person would type to switch it on (`rc-update add bluetooth default &&
  rc-service bluetooth start`, `ln -s /etc/sv/bluetoothd /var/service`, …), with the
  service's name on that distro where it differs.
- `slate-init display-manager` → its name, or `unknown`.
systemd stays the first branch everywhere, so nothing changes for today's users.

### 2. Use it
- Power: every `systemctl suspend/reboot/poweroff` call site goes through `slate-init`
  (the Lua ones via `SLATE_DIR .. "/bin/slate-init suspend"`). The greeter's copies too
  (it gets `slate-init` in `greeter/files`; that's a login screen update, announced as
  such).
- Inhibitors: `LockScreen.qml` and `Config.qml` use `slate-init inhibit`.
- `busctl` → `gdbus` in `Bar.qml` and `set-avatar.sh`.
- Date and time: read and set through `org.freedesktop.timedate1` with `gdbus` (works for
  systemd and openrc-settingsd alike); time zones from `/usr/share/zoneinfo/tzdata.zi` or
  the folder itself.
- Logs: the greeter writes to its log file when `systemd-cat` isn't there; `slate-logs`
  reads that file.
- `install.sh`, `printers.py`, greeter status: `slate-init service-active` and
  `service-hint`.

### 3. Say what's missing (Settings and panels)
`Config.system` drives it:
- No way to suspend → Suspend is left out of the power menu, the lock screen, the launcher
  and Settings → Power's choices.
- No sleep signals or inhibitors → "Lock before sleep" and the lid and power button rows
  show, greyed, with one line: "These need elogind, which isn't running on this computer."
- No timedate service → the time zone and network time rows say what to install
  (openrc-settingsd) or that the clock follows the system's own settings.
- A service that's off (Bluetooth, printing, NetworkManager) → the existing "isn't running"
  rows show the command for this init system, with a Copy button, instead of a switch that
  runs `systemctl`.
- Settings → About shows the init system and login manager, for bug reports.

### 4. Session start (`session/slate-session`, `autostart.lua`)
- Start a D-Bus session bus if there isn't one.
- Start PipeWire, WirePlumber and pipewire-pulse if they aren't running and aren't
  managed by a user service manager (Artix documents starting them from the session).
- uwsm only when systemd is the init.

### 5. Installer and packages
- `packaging/artix.txt` (the Arch list without uwsm, with elogind, the matching
  `polkit`, and the service packages named for each init: `bluez-openrc`, `cups-runit`…).
  `install.sh`, `slate-system` and `slate_apps.family()` learn `artix` (its `ID_LIKE` is
  `arch`, so check `ID` first).
- `install.sh` replaces its `systemctl enable` step with `slate-init service-hint` output
  off systemd ("To switch Bluetooth on: …").
- `packaging/void.txt` later, with notes on the third-party Hyprland repo; Gentoo as a
  documented list of atoms.
- `docs/REDISTRIBUTION.md`: a section on init systems and the elogind requirement.

## Risks and unknowns
- What `USES_SYSTEMD` changes inside Hyprland, and whether `start-hyprland` behaves the
  same without it. To check on Artix first thing.
- polkit prompts depend on an active elogind session; a greetd login must register one
  (PAM's `pam_elogind`). Check on Artix with greetd and with a bare tty login.
- Slate's own login screen on a non-systemd greetd: the same `greetd` config, but the
  service is enabled per init. Keep it opt-in, as now.
- Restart and shut down without elogind need root: left unsupported rather than adding
  doas/sudo rules.
- musl (Alpine, Chimera, Void-musl): Slate's Python scripts and helpers should be fine,
  but the hyprbars build and anything compiled needs a pass. Out of scope until those
  distros have Hyprland 0.57.

## Tests
- **Unit** (`tests/unit/test_slate_init.py`): `slate-init` against stub commands on PATH
  for each combination: systemd; elogind + OpenRC; elogind + runit; elogind + dinit; seatd
  only; nothing. Each of `info`, the power commands, `inhibit`, `service-active`,
  `service-hint`, `display-manager`. The systemd branch's exact commands are asserted so
  today's behaviour can't drift.
- **Unit**: `install.sh` and `slate-system` pick `artix.txt` for `ID=artix`; `printers.py`
  without `systemctl`.
- **Static**: no direct `systemctl`, `systemd-inhibit`, `busctl`, `timedatectl`,
  `journalctl` or `systemd-cat` call left outside `slate-init` (a grep test, with the
  allowed places listed).
- **Live**: with `Config.system` overridden through the `test` IPC target (no suspend, no
  inhibitors, no timedate): the power menu has no Suspend, the Power and Date & Time rows
  show their explanations. A visual scene of each.
- **A real system**: an Artix container image as a second target for
  `tests/run --deps artix` (OpenRC, elogind, greetd), running the same live tier. This is
  what proves Hyprland and Quickshell there, and it's the largest single piece of work.

## Docs and site
`docs/INSTALL.md` (Artix; what elogind is for; what's switched off without it),
`docs/SESSION.md`, `docs/ARCHITECTURE.md` (`slate-init`), `README.md`, and a line on the
site's install section and feature list.

## Order of work
1. `slate-init` with its unit tests (systemd and elogind branches), and the static grep
   test listing today's call sites as the to-do list.
2. Move the call sites over (power, inhibit, busctl, logs). No behaviour change on systemd.
3. `Config.system` and the Settings/panel explanations, with live tests.
4. Session start (D-Bus, PipeWire), `artix.txt`, installer.
5. The Artix test image; fix what it finds (this is where the Hyprland and polkit unknowns
   get answered).
6. Date and time over D-Bus. Docs and site.
7. Later: Void, Gentoo notes; Alpine and Chimera when they have Hyprland 0.57.

## Sources
- Hyprland wiki, Installation: https://wiki.hypr.land/Getting-Started/Installation/
- Hyprland CMakeLists.txt (main): https://raw.githubusercontent.com/hyprwm/Hyprland/main/CMakeLists.txt
- Quickshell BUILD.md: https://git.outfoxxed.me/quickshell/quickshell/raw/branch/master/BUILD.md
- Artix packages: https://packages.artixlinux.org/packages/?q=hyprland and https://packages.artixlinux.org/packages/?q=quickshell
- Alpine packages (edge): https://pkgs.alpinelinux.org/packages?name=hyprland&branch=edge
- Chimera packages: https://pkgs.chimera-linux.org/packages?name=quickshell
- Gentoo overlays (Quickshell): https://gpo.zugaina.org/gui-apps/quickshell
- Void: https://github.com/Makrennel/hyprland-void and https://github.com/void-linux/void-packages/tree/master/srcpkgs/quickshell
- Seats without systemd: https://github.com/hyprwm/Hyprland/discussions/12689 and https://wiki.alpinelinux.org/wiki/Hyprland
