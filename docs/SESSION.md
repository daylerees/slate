# The Slate session

Slate shows up as its own entry, **Slate**, on the login screen (the Slate login screen,
or any other that reads `/usr/share/wayland-sessions`: SDDM, GDM, other greetd greeters).
Picking it starts Hyprland with Slate's own config. Your other sessions and
`~/.config/hypr` are left alone, so you can try Slate and go back by picking your usual
session at login. This is how Slate is meant to be installed for other people.

Until Slate draws your wallpaper, the session shows a plain dark background in the login
screen's color (`misc.lua` turns off Hyprland's default wallpaper and logo, which some
distros replace with their own), so nothing flashes up between the login screen and Slate.

```
login screen ─ "Slate" (slate.desktop) ─▶ /usr/local/bin/slate-session
   └─ uwsm start -e -D Hyprland -N Slate -- start-hyprland -- -c <slate>/session/hypr/hyprland.lua
      (plain start-hyprland when uwsm isn't installed, or systemd isn't running: then inside
       dbus-run-session if there's no session bus yet)
         ├─ ~/.config/slate/hypr/env.lua, variables.lua        (yours, first)
         ├─ Slate's config: colors, variables, animations, autostart, decorations,
         │  hyprbars, inputs, binds, misc, monitors, windowrules, workspaces, slate
         ├─ ~/.config/slate/hypr/monitors.lua, binds.lua, rules.lua,
         │  autostart.lua, hyprland.lua                        (yours, last; they win)
         └─ autostart: slate ─▶ the keeper (`slate _keep`) ─▶ qs -p ~/.config/slate
```

## Files

| Path | What |
|---|---|
| `~/.config/slate/session/hypr/` | Slate's Hyprland config (source) |
| `~/.config/slate/session/slate-session` | launcher (source) |
| `~/.config/slate/session/slate.desktop` | login entry (source) |
| `/usr/local/bin/slate-session`, `/usr/share/wayland-sessions/slate.desktop` | installed copies |
| `~/.config/slate/hypr/env.lua` | yours: `hl.env(...)` environment variables for apps (loaded first) |
| `~/.config/slate/hypr/variables.lua` | yours: `TERMINAL`, `BROWSER`, `FILE_MANAGER`, `EDITOR`, `CALCULATOR`, `MONITOR1..3`, `NUM_WPM`, cursor |
| `~/.config/slate/hypr/monitors.lua` | yours: `hl.monitor(...)`, monitor workspace rules (after Settings → Displays) |
| `~/.config/slate/hypr/binds.lua` | yours: extra or replaced shortcuts, `hl.unbind(...)` |
| `~/.config/slate/hypr/rules.lua` | yours: window and workspace rules |
| `~/.config/slate/hypr/autostart.lua` | yours: commands at login (`hl.on("hyprland.start", …)`) |
| `~/.config/slate/hypr/hyprland.lua` | yours, loaded last: anything else (keyboard layout, devices…); wins over everything |
| `~/.config/slate/user/shell.qml` | yours: QML loaded into Slate itself (extra widgets, IPC handlers) |
| `~/.local/state/slate/keyset.lua` | written by Settings → Shortcuts: `KEYSET = "slate"`, `"hyprland"` (Hyprland's default shortcuts) or `"hyprland-extras"` (those plus Slate's on free keys); read by `binds.lua`, which then binds that set |
| `~/.local/state/slate/displays.lua` | written by Settings → Displays (loaded by `monitors.lua`; your `hyprland.lua` loads later and wins) |
| `config/slate.lua` | `slateApply({...})`: Slate sends the keyboard, mouse, touchpad, focus, cursor, animation, default-app, lid and power-button settings changed in Settings (only those; the rest stay as your files set them). Putting one back with Restore defaults reloads the config |
| `config/gestures.lua` | the touchpad gestures (Settings → Input → Gestures), made by `slateApply` through `setGestures(on, fingers, down)`; one of yours (made in your files, which load later) on the same fingers and direction is kept, and Slate's left out |

Your files are made by Slate (`scripts/user-files.sh`, at startup and by the installer)
with instructions inside, only where they don't exist yet, and the installer keeps them
(`hypr/`, `user/`). Saving one reloads it: Hyprland's config for the `.lua` files, Slate
itself for `shell.qml` (`UserFiles.qml`). A mistake in a `.lua` file skips that file (the
rest still loads) and Slate shows it in a notification, with Hyprland's own config errors;
a mistake in `shell.qml` leaves Slate running without it, and is shown the same way.

`slate-session` looks for the config in `$XDG_CONFIG_HOME/slate/session/hypr/`, your own
install: the config finds the rest of Slate there too, so that's the one place it runs from.

Inside the session `SLATE_SESSION=1` is set. `slate-greeter-sync` uses it to make Slate the
login screen's default session.

## Install / remove

```sh
~/.config/slate/bin/slate-system --root slate-session-install            # add / update
~/.config/slate/bin/slate-system --root slate-session-install --remove   # remove
```

Both ask for your password, and run the installer's root-owned copy,
`/usr/local/libexec/slate/slate-session-install` (never the one in your Slate folder, which
anything running as you could have changed; `./install.sh` puts the copy there, and
`slate-system` brings it up to date first when a version has changed it). With sudo, by hand:
`sudo /usr/local/libexec/slate/slate-session-install`.

If Slate isn't in `~/.config/slate` (`XDG_CONFIG_HOME` is set), name its folder as the last
argument (`install.sh` and Slate's own prompt do).
The folder has to be yours, and the two files are read with your permissions, not root's; a
link in their place is refused.

Only the launcher and the login entry need root. Changes to the config under
`session/hypr/` apply at the next login, or straight away with `hyprctl reload`
inside the Slate session.

## Notes

- The Slate session uses only Slate's config plus your files in `~/.config/slate/hypr`;
  your usual `~/.config/hypr` belongs to your other Hyprland session and isn't read.
- App launches use `uwsm app --` only when the session runs under uwsm.
- If the Slate session fails to start, pick another session at login, or check
  `journalctl --user -b -u 'wayland-wm@*'` (uwsm) for errors.
- Slate itself (Quickshell) runs under a small keeper that `slate` starts: a shell waiting on
  it, so it costs nothing while Slate runs, and with no systemd unit, so it works the same
  everywhere. If Slate crashes (a crash signal, SIGKILL from running out of memory, or an error
  exit) the keeper starts it again a second later and, once it's loaded, a notification says
  so. What was asked for doesn't: `slate stop` and `slate restart --full` (factory reset,
  uninstalling) stop the keeper first; a clean exit, SIGTERM or SIGHUP (`qs kill`, shutting
  down) is left alone; and so is Slate going with the session (logging out: the keeper checks
  Hyprland is still there). Three crashes within a minute and it stops trying: Hyprland's own
  notification says so, the log (`~/.cache/slate.log`) says when and why (the signal or exit
  code), and `slate` tries again. Quickshell's own crash handler is off under the keeper: with
  it on, the process the keeper waits on stays up after a crash and starts another copy itself,
  with a "Quickshell has crashed" window, and Quickshell 0.3.2 has no switch for only its
  report. So the keeper writes the crash report: `~/.cache/slate/crashes/crash-<when>-<pid>.txt`
  (yours alone, the last 5), with when and how it ended and, where systemd-coredump caught the
  crash, the backtrace from `coredumpctl info` (not the command line, user or computer's name;
  the home folder as `~`). Settings → Debug → Export recent logs adds the latest one.
