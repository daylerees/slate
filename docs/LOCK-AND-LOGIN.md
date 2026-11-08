# Lock screen and login screen

Both use the same design, `LoginScreen.qml`: wallpaper behind (plain slate if none),
round avatar with a dark border, a password frame with a caps-lock indicator,
a session switcher bottom-left (login only) and a power menu bottom-right (login
always; lock screen only if enabled). Rounded screen corners follow the setting.

## Lock screen (`LockScreen.qml`)

- **Locking** uses the Wayland session-lock protocol (`WlSessionLock`): Hyprland shows
  only the lock surfaces and sends input only to them. Notifications, bar, OSD and
  hot corners are never drawn while locked.
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
  times in Settings → Lock & idle; respects idle inhibitors (video) if enabled.
  Slate's own idle suspend locks first and waits for `secure`.
- **Crash safety:** if Slate dies while locked, Hyprland stays locked. Recover from a
  text console (Ctrl+Alt+F3): `slate restart` (or `~/.config/slate/bin/slate restart`) — `allow_session_lock_restore`
  lets it take the lock back.
- **Preview** without locking: `slate ipc call lock preview lock` (checks the
  real password, power menu only says what it would do).

## Login screen (greetd)

```
greetd ──runs as "greeter"──▶ dbus-run-session start-hyprland -c /usr/local/share/slate-greeter/hyprland.lua
                                └─ run-greeter.sh ─▶ qs -p /usr/local/share/slate-greeter   (greeter/shell.qml)
                                                      └─ Greetd: create_session → password → start_session
                                   when qs quits after launching: hyprctl dispatch hl.dsp.exit()
```

| Location | Owner | Contents | Updated by |
|---|---|---|---|
| `/usr/local/share/slate-greeter` (+ `.previous`) | root | `shell.qml` (from `greeter/`), `LoginScreen.qml`, `Config.qml`, `SettingsData.qml`, `RoundImage.qml`, `scripts/`, `hyprland.lua` (keyboard layout filled in), `run-greeter.sh`, `fonts.conf`, `settings.json` → symlink to the data folder | `sudo ~/.config/slate/bin/slate-greeter-install` |
| `/var/lib/slate-greeter` | you | appearance only: `settings.json`, `wallpaper`, `avatar`, `user.json` (user, name, default session), `fonts/` | `slate-greeter-sync` — run automatically by Slate when the wallpaper or settings change |
| `/var/cache/slate-greeter` | greeter | `last-session`, logs, caches | the greeter |

- **Updating the code:** when the login screen's code changes, Slate shows a notification
  ("Login screen out of date") with an **Update** button that asks for your password
  (pkexec) and runs `slate-greeter-install --code-only`. It asks once per version of the
  code; "Later" waits for the next change. Settings → Lock & idle has the same Update button.
  Files are read with your own permissions, not root's.
- **Safety net:** each update keeps the replaced copy as `/usr/local/share/slate-greeter.previous`.
  If the new copy fails to load, `run-greeter.sh` starts the previous one instead.
- The greeter can't read your home folder, hence the copies. Code is root-owned; the
  user-owned folder holds only data (images, fonts, setting values).
- Settings → Lock & idle → "Slate login screen" shows whether the installed code
  matches yours (`slate-greeter-sync --check`) and offers Preview / Sync now.
- Default session: the last one chosen on the login screen, else the one you were
  using at the last sync (uwsm-managed or plain Hyprland).
- greetd config backup: `/etc/greetd/config.toml.before-slate`.

### If the login screen doesn't come up

1. Ctrl+Alt+F3, log in on the text console.
2. `sudo ~/.config/slate/bin/slate-greeter-install --revert` (restores the previous greeter).
3. `sudo systemctl restart greetd` to get a graphical login now.
4. Look at `/var/cache/slate-greeter/greeter.log` and `journalctl -b -u greetd`.

### Testing without greetd

`greeter/shell.qml` honours `GREETD_SOCK` (point it at a fake greetd), `SLATE_GREETER_DATA`
(appearance folder) and `SLATE_GREETER_TEST=1` (enables `ipc call greeter submit <pw>`).
Run it in a nested Hyprland (`Hyprland -c test.lua` from inside a session). A minimal
fake greetd speaks greetd's IPC: 4-byte native-endian length + JSON
(`create_session`, `post_auth_message_response`, `start_session`, `cancel_session`).
