# Lock screen and login screen

Both use the same design, `LoginScreen.qml`: wallpaper behind (plain slate if none),
round avatar with a dark border, a password frame with a caps-lock indicator,
a session switcher bottom-left (login only) and a power menu bottom-right (login
always; lock screen only if enabled). Rounded screen corners follow the setting.
With glass on, the panels are glass too (frosted wallpaper drawn by `WallBlur.qml`, since
the screen draws its own wallpaper and Hyprland's blur can't reach behind them), with
the gloss sheen like the bar's containers and no outline.

## Lock screen (`LockScreen.qml`)

- **Locking** uses the Wayland session-lock protocol (`WlSessionLock`): Hyprland shows
  only the lock surfaces and sends input only to them. Notifications, bar, OSD and
  hot corners are never drawn while locked.
- **Fading** in and out is only a look; it never delays or shortens the lock. The lock
  engages at once (input goes to it from the first moment), then Hyprland's
  `misc:session_lock_xray` is turned on just for the fade, so the lock screen crossfades over
  the live desktop, and off again when it's fully shown. On the way out, xray goes on only
  after the password is accepted, and the lock is held until the fade ends, so input stays
  with it. Locks before sleep (and idle suspend) don't fade; with Animations off or in game
  mode nothing fades. xray is turned off whenever Slate starts and whenever the lock is let
  go, and the lock screen at rest is opaque, so even if it were left on nothing would show
  through. Safety nets: the lock screen appears after 1 s if a fade never starts, and after
  the password the lock lets go after 1.5 s if a fade never finishes.
- **Password** is checked by PAM (`PamContext`, the `login` stack, incl. `pam_faillock`).
  The field is emptied on Enter; Slate drops its copy after the check and runs `gc()`.
- **Lockout:** after a failure Slate reads `faillock --user $USER`; at 3 failures within
  15 min it shows "Too many attempts · try again in m:ss", disables the field and stops
  sending attempts. Wrong passwords show the tries left.
- **Triggers:** Super+L, the power panel (Lock / Suspend), hot corners, logind
  `Lock` requests (`loginctl lock-session`), idle, and sleep.
- **Before sleep:** a `systemd-inhibit --mode=delay` watcher on logind's
  `PrepareForSleep`; it's released once Hyprland confirms the lock is up
  (`secure`), or after 4 s (logind's limit is 5 s). Wrapped in
  `setpriv --pdeathsig` so it never outlives Slate.
- **Idle** (`IdleMonitor`): lock / screen off (`hl.dsp.dpms`) / suspend after the
  times in Settings → Security; respects idle inhibitors (video) if enabled.
  Slate's own idle suspend locks first and waits for `secure`.
- **Crash safety:** if Slate dies while locked, Hyprland stays locked. Recover from a
  text console (Ctrl+Alt+F3): `slate restart` (or `~/.config/slate/bin/slate restart`) — `allow_session_lock_restore`
  lets it take the lock back.
- **Preview** without locking: `slate ipc call lock preview lock` (checks the
  real password, power menu only says what it would do).

## Login screen (greetd)

Slate's login screen is **optional, and off unless you install it**. Installing Slate only
adds "Slate" to whatever login screen you already have; Slate's own replaces that login
screen, so it's something you choose:

- **Install:** Settings → Security → "Slate login screen" → **Install** (it asks for your
  password), or `./install.sh --login-screen`, or `sudo ~/.config/slate/bin/slate-greeter-install`.
  It needs greetd installed; if your computer starts another display manager (GDM, SDDM,
  LightDM), Settings says so and gives the command to switch to greetd.
- **Switch back:** the same row's **Switch back** button, or
  `sudo ~/.config/slate/bin/slate-greeter-install --revert`. Either puts greetd's previous
  config back (from `/etc/greetd/config.toml.before-slate`); Slate then stops offering updates.

Before you install it, know what it involves:

- **It can stop you logging in.** It runs before anyone logs in, as a system service, from a
  root-owned copy outside Slate. If that copy breaks there's no desktop to fix it from. The
  safety net below makes this unlikely (each copy is tested first, the last working one and a
  basic emergency login are kept), but if all of that fails you need a text console:
  Ctrl+Alt+F3, log in, run `sudo ~/.config/slate/bin/slate-greeter-install --revert`, then
  `sudo systemctl restart greetd`.
- **It needs updating, by you, with your password.** The installed copy doesn't change when
  Slate does. When Slate's login screen code changes, Slate asks you to update it (see below);
  until you do, you see the old version. Updates to Hyprland, Quickshell or greetd can also
  break the installed copy without Slate changing at all: the fallbacks cover that at boot,
  and updating it again (or switching back) fixes it.
- **It depends on more of your system:** greetd being the display manager systemd starts, a
  `greeter` user (`_greetd` on Debian), polkit for the password prompts, and Hyprland and
  Quickshell working for that user as well as for you.

```
greetd ──runs as "greeter"──▶ systemd-cat dbus-run-session start-hyprland -c /usr/local/share/slate-greeter/hyprland.lua
                                └─ run-greeter.sh ─▶ qs -p /usr/local/share/slate-greeter   (greeter/shell.qml)
                                     if it fails to load: slate-greeter.good, then emergency/
                                                      └─ Greetd: create_session → password → start_session
                                   when qs quits after launching: hyprctl dispatch hl.dsp.exit()
```

The greeter's output goes to the journal (`journalctl -t slate-greeter`), not tty1.

| Location | Owner | Contents | Updated by |
|---|---|---|---|
| `/usr/local/share/slate-greeter` (+ `.good`) | root | the files listed in `greeter/files` (`shell.qml`, `LoginWindow.qml`, `LoginScreen.qml`, `Config.qml`, … and the `emergency/` login screen), plus `hyprland.lua` (keyboard layout filled in), `version`, and `settings.json` → symlink to the data folder | `sudo ~/.config/slate/bin/slate-greeter-install` |
| `/var/lib/slate-greeter` | you | appearance only: `settings.json`, `wallpaper`, `avatar`, `user.json` (user, name, default session), `fonts/` | `slate-greeter-sync` — run automatically by Slate when the wallpaper or settings change |
| `/var/cache/slate-greeter` | greeter | `last-session`, `proven` (version of the last copy someone logged in with), logs, caches | the greeter |

- **Keeping the appearance in step:** Slate runs `slate-greeter-sync` a few seconds after the
  wallpaper, settings or avatar change. If something changed outside Slate (the wallpaper file
  replaced in place, the picture, name or keyboard layout changed elsewhere), Settings → Debug
  (a tile on All Settings) → **Resync** runs it by hand.
- **Updating the code:** when the login screen's code changes, Slate shows an urgent
  notification ("Login screen out of date": it stays until answered, shows through Do Not
  Disturb and plays the attention sound) with an **Update** button that asks for your password
  (pkexec) and runs `slate-greeter-install --code-only`. It asks only when the login
  screen's own code changes (its design, glass pieces, fonts, keyboard layout), not for
  `Config.qml` or `SettingsData.qml`, which are shared with the rest of Slate and change with
  nearly everything; those come along with the next update. It asks once per version, and
  "Later" (or dismissing it) waits a week. If the update is cancelled or fails, an urgent
  "Login screen not updated" notification gives the command to run instead. Settings → Lock
  & Idle has the same Update button.
  Files are read with your own permissions, not root's.
- **Safety net**, so a broken update never leaves anyone at a text console:
  1. **Tested before it's installed.** `slate-greeter-install` test-loads the new copy with
     `slate-greeter-check` (as you, offscreen, cut off from your session): the greeter's
     Hyprland config, `run-greeter.sh`, the login screen and the emergency one. If any
     fails, it says why and leaves the installed copy as it was (`--no-check` skips this,
     for when the test itself is what's wrong).
  2. **Last known good.** When someone logs in, the greeter writes its `version` to
     `/var/cache/slate-greeter/proven`. On the next update, the copy being replaced becomes
     `/usr/local/share/slate-greeter.good` only if it's proven (or there's no `.good` yet);
     otherwise the existing `.good` stays.
  3. **Fallbacks at boot.** If the copy fails to load (Quickshell exits with an error
     within 10 s), `run-greeter.sh` starts `.good`, then `emergency/`: a basic login
     screen (user name, password, session, restart / shut down) using only Quickshell's own
     types, so the things that can break the real one can't break it. The log notes which
     copy started.
- The greeter can't read your home folder, hence the copies. Code is root-owned; the
  user-owned folder holds only data (images, fonts, setting values).
- Settings → Security → "Slate login screen" shows whether it's installed and whether the
  installed code matches yours (`slate-greeter-sync --status`), and offers Preview, then
  Install (with a warning of the above first), Update or Switch back. The automatic update
  prompt only runs while greetd uses Slate's login screen.
- Default session: the last one chosen on the login screen, else the one you were
  using at the last sync (uwsm-managed or plain Hyprland).
- greetd config backup: `/etc/greetd/config.toml.before-slate`.

### If the login screen doesn't come up

The fallbacks above should cover this; if you see the emergency login screen, log in and
update the login screen from Settings → Security. If even that fails:

1. Ctrl+Alt+F3, log in on the text console.
2. `sudo ~/.config/slate/bin/slate-greeter-install --revert` (restores the previous greeter).
3. `sudo systemctl restart greetd` to get a graphical login now.
4. Look at `/var/cache/slate-greeter/greeter.log` and `journalctl -b -u greetd`.

### Changing what the login screen loads

The login screen runs from a root-owned copy, so every file it loads must be listed in
`shell/greeter/files` (`<installed path> <source>`; `- <source>` for files its code
mentions but doesn't need at login, `+ <installed path>` for ones the installer makes).
Three checks keep the list honest:

- `tools/check-greeter-files` reads the login screen's QML and fails if a Slate type
  (`SettingsData {…}`) or file (`shellPath("scripts/…")`) it uses isn't on the list, or a
  QML file under `greeter/` isn't.
- `shell/bin/slate-greeter-check --source` builds a copy from the list and test-loads it
  offscreen, the same test the installer runs.
- Both run in CI (`.github/workflows/checks.yml`, in an Arch container) and in the
  pre-commit hook (turn it on with `git config core.hooksPath .githooks`).

Check mode (`SLATE_GREETER_CHECK=1`, `QT_QPA_PLATFORM=offscreen`) builds the login screen
without a window and exits 0 if it loaded. Windows can't be made without a display, which
is why each screen's `PanelWindow` lives in its own file (`LoginWindow.qml`,
`emergency/Window.qml`) that check mode doesn't load; if it fails to load for real, the
greeter exits so the fallbacks take over.

### Testing without greetd

`greeter/shell.qml` honours `GREETD_SOCK` (point it at a fake greetd), `SLATE_GREETER_DATA`
(appearance folder) and `SLATE_GREETER_TEST=1` (enables `ipc call greeter submit <pw>`).
Run it in a nested Hyprland (`Hyprland -c test.lua` from inside a session). A minimal
fake greetd speaks greetd's IPC: 4-byte native-endian length + JSON
(`create_session`, `post_auth_message_response`, `start_session`, `cancel_session`).
