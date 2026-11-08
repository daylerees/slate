# The Slate session

Slate shows up as its own entry, **Slate**, on the login screen (the Slate login screen,
or any other that reads `/usr/share/wayland-sessions`: SDDM, GDM, other greetd greeters).
Picking it starts Hyprland with Slate's own config. Your other sessions and
`~/.config/hypr` are left alone, so you can try Slate and go back by picking your usual
session at login. This is how Slate is meant to be installed for other people.

Until Slate draws your wallpaper, the session shows a plain dark background in the login
screen's colour (`misc.lua` turns off Hyprland's default wallpaper and logo, which some
distros replace with their own), so nothing flashes up between the login screen and Slate.

```
login screen ─ "Slate" (slate.desktop) ─▶ /usr/local/bin/slate-session
   └─ uwsm start -e -D Hyprland -N Slate -- start-hyprland -- -c <slate>/session/hypr/hyprland.lua
      (plain start-hyprland when uwsm isn't installed)
         ├─ ~/.config/slate/hypr/env.lua, variables.lua        (yours, first)
         ├─ Slate's config: colors, variables, animations, autostart, decorations,
         │  inputs, binds, misc, monitors, windowrules, workspaces
         ├─ ~/.config/slate/hypr/monitors.lua, binds.lua, rules.lua,
         │  autostart.lua, hyprland.lua                        (yours, last; they win)
         └─ autostart: slate
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

Your files are made by Slate (`scripts/user-files.sh`, at startup and by the installer)
with instructions inside, only where they don't exist yet, and the installer keeps them
(`hypr/`, `user/`). Saving one reloads it: Hyprland's config for the `.lua` files, Slate
itself for `shell.qml` (`UserFiles.qml`). A mistake in a `.lua` file skips that file (the
rest still loads) and Slate shows it in a notification, with Hyprland's own config errors;
a mistake in `shell.qml` leaves Slate running without it, and is shown the same way.

`slate-session` looks for the config in `$XDG_CONFIG_HOME/slate/session/hypr/`
first, then `/usr/share/slate/session/hypr/` (for a system-wide package).

Inside the session `SLATE_SESSION=1` is set. `slate-greeter-sync` uses it to make Slate the
login screen's default session.

## Install / remove

```sh
sudo ~/.config/slate/bin/slate-session-install            # add / update
sudo ~/.config/slate/bin/slate-session-install --remove   # remove
```

Only the launcher and the login entry need root. Changes to the config under
`session/hypr/` apply at the next login, or straight away with `hyprctl reload`
inside the Slate session.

## Notes

- The Slate session uses only Slate's config plus your files in `~/.config/slate/hypr`;
  your usual `~/.config/hypr` belongs to your other Hyprland session and isn't read.
- App launches use `uwsm app --` only when the session runs under uwsm.
- If the Slate session fails to start, pick another session at login, or check
  `journalctl --user -b -u 'wayland-wm@*'` (uwsm) for errors.
