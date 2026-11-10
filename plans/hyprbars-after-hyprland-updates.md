# Plan: keep title bars working across Hyprland updates

Status: **planned** (2026-11-10).

## Context

Floating mode's title bars come from the hyprbars plugin, which Slate builds
(`slate build-hyprbars` → `~/.local/share/slate/plugins/hyprbars.so`). A Hyprland plugin
only loads in the exact Hyprland it was built for. After a Hyprland update the old build is
still there, so `shell/session/hypr/config/hyprbars.lua` asks Hyprland to load it, Hyprland
refuses ("API version mismatch") and shows its own red error notices at the top of the
screen at login. Our `pcall` around `hl.plugin.load` stops the config from failing, but not
those notices.

Seen on 2026-11-10: Hyprland 0.57.1 → 0.57.2 (pacman, the night before), hyprbars built for
0.57.1 (commit `acc1aa0` in the `.so`), error notices at every login. That user was in
tiling mode, where title bars aren't used at all, so they got the errors for nothing.
Fixed by hand with `slate build-hyprbars`.

This happens after **every** Hyprland update, on every distro (Arch updates Hyprland often).
Slate already copes with a missing plugin (`Config.titleBarsAvailable` keeps it tiling and
Settings hides the choice), so the issues are the error notices and having to remember to
rebuild by hand.

Goal:
1. Never ask Hyprland to load a hyprbars built for another Hyprland, so no error notices.
2. Rebuild it automatically when it's needed, and say so plainly when that can't be done.

## What Hyprland gives us

- The Lua config has `hl.version()` (string; `/usr/share/hypr/stubs/hl.meta.lua:951`).
  **Check first** what it returns (`0.57.2`? with the commit?) by printing it from a config
  pass. The plugin check itself compares the git commit, so the version alone can't tell
  two `-git` builds apart.
- `hyprctl version -j` gives `version`, `commit` and `tag`. Don't call it from the Lua
  config: Hyprland is busy running the config, so the call can block it.
- The built `.so` contains the commit it was built against as a 40-character hex string
  (`strings hyprbars.so`), but scanning a binary from Lua at every config pass is fragile.
  A sidecar file is simpler.

## Changes

### 1. Record what each build is for (`shell/bin/slate-build-hyprbars`)
After installing the `.so`, write `~/.local/share/slate/plugins/hyprbars.json`:
`{ "version": "<pkg-config --modversion hyprland>", "commit": "<from Hyprland's headers or
hyprctl version -j>", "built": "<date>" }`. Use the headers' commit if they have one
(that's what the plugin is checked against), else `hyprctl version -j`. Write a temp file and
`mv` it into place, like the `.so`.

### 2. Load only a matching build (`shell/session/hypr/config/hyprbars.lua`)
For Slate's own build (the `dataHome` candidate): read `hyprbars.json` (`io.open` + a tiny
pattern match, no JSON library) and load only when its `version` equals `hl.version()`. A
mismatch or a missing/unreadable sidecar (a build made before this change) → skip it,
quietly: `print` one `[slate] hyprbars was built for X, Hyprland is Y; not loading it`
line to the Hyprland log and set `HYPRBARS_STALE = true`.
- Distro packages (`/usr/lib/...` candidates) are updated with Hyprland by the package
  manager. Keep loading those as now.
- Keep the "ask on every config pass" rule from the comment there (skipping a load that
  was in before makes Hyprland unload it and loop). A stale build was never loaded, so not
  asking for it is safe. Check that this holds when the version changes under a running
  session, though Hyprland must restart to change version anyway.
- `-git` builds whose version string doesn't change: the version check passes and Hyprland
  may still refuse. That case stays as it is today (one error notice); step 3 fixes it at
  the next login. Note this in the comment.

### 3. Rebuild when needed (`shell/Config.qml`, next to `titleBarsCheck`)
At startup (not in `Config.testMode`) and after each Hyprland config reload (where
`checkTitleBars()` already runs), compare `hyprbars.json` with `hyprctl version -j`
(commit when both have one, else version). If a Slate build exists and doesn't match:
- **Window mode is floating** (it's needed): rebuild in the background
  (`slate-build-hyprbars`, low priority with `nice`), then `hyprctl reload` so the bars
  come back. Until then Slate is tiling (as now). Hold off while game mode is on (the build
  takes a CPU core for a minute) and start it when game mode ends.
- **Tiling** (not needed now): don't build. Mark the build stale, and rebuild when the user
  picks Floating (step 4).
- Build failed (no network for the clone, missing headers/compiler, the patch fails and the
  plain build fails too): one Slate notification, `x-slate-page` = windows: "Title bars
  couldn't be rebuilt for Hyprland X", with the first error line from the build log and an
  action to open Settings → Windows. Don't retry at every login: retry when Hyprland's
  version changes again or the user asks (step 4). Keep the log in
  `~/.cache/slate/hyprbars-build.log`.
- No Slate build at all (never built, or a distro package): do nothing, as today.

### 4. Settings → Windows
Where the floating choice is hidden or explained when title bars aren't available, show the
state and a **Rebuild title bars** button (it runs the same background build, with a
spinner and the result). States: built and loaded / being rebuilt for Hyprland X / out of
date (rebuilt when you choose Floating) / couldn't be rebuilt (reason + Rebuild) / not
installed (how to get it). Search entry in `SettingsIndex.qml` ("title bars", "hyprbars",
"rebuild"). Follow the Settings page design notes.

### 5. Updates
`slate update` / the updater (`shell/scripts/update.py`): if a Slate build exists and
doesn't match, rebuild it as part of the update so the next login is clean.

## Distros (docs/REDISTRIBUTION.md)
- Arch, Debian, Fedora, openSUSE: Slate's own build. Building needs Hyprland's headers
  (`-devel`/`-dev` packages elsewhere); the failure notice says which package is missing
  (`packaging/*.txt` already list them as optional).
- NixOS: `hyprlandPlugins.hyprbars` comes from Nix and is always built for the matching
  Hyprland. No Slate build, so steps 2 to 5 do nothing there.

## Tests
- **Unit** (`tests/unit/`): the build script writes `hyprbars.json` with the right fields
  (stub `git`, `make`, `pkg-config`, `hyprctl` on `PATH`). Run `hyprbars.lua` under LuaJIT
  with a stub `hl` table (`version`, `plugin.load` that records calls,
  `get_loaded_plugins`, `config`, `get_config`) for: matching sidecar → loads; other version
  → no load and `HYPRBARS_STALE`; no sidecar → no load; only a `/usr/lib` candidate → loads.
- A **regression test for the login error**: stale build plus sidecar → `hl.plugin.load`
  is never called with it. Write it before the fix and watch it fail.
- **Live**: in the container, plant a stale `hyprbars.so` + sidecar in the scratch HOME,
  start the session and check that the Hyprland log has no "Failed to load plugin". The
  build itself stays out of the live tier (network, a minute of compiling). Fake it with a
  stub `slate-build-hyprbars` and check that Config runs it only in floating mode, not in
  test mode, and not during game mode, and that a failing stub gives one notification (state
  in the `test` IPC target: `titleBars: loaded|stale|building|failed|missing`).
- **Visual**: a scene for the new Settings → Windows title bar row (stale + failed).

## Docs and site
- `README.md:143`, `docs/INSTALL.md:131-135`, `docs/ARCHITECTURE.md:84,269`,
  `docs/REDISTRIBUTION.md:37`: title bars are rebuilt automatically after Hyprland updates
  (when floating mode is used). `slate build-hyprbars` is still there for doing it by hand.
- `site/features.html`: the Windows section (automatic rebuild, the Rebuild button).
- Release notes: a fix ("no more error messages at login after Hyprland updates").

## Order of work
1. Check what `hl.version()` returns and what Hyprland's headers expose (version/commit).
2. Regression test (stub-`hl` Lua), then steps 1 and 2. This alone stops the error notices.
3. Step 3 (automatic rebuild + failure notification), with its live test.
4. Step 4 (Settings), step 5 (updates), docs, site.

## Verification
- With a stale build (copy one built for an older Hyprland, or edit the sidecar's version):
  log in in tiling mode → no error notices, Slate log says it's stale, nothing builds.
  Switch to Floating → it rebuilds, Hyprland reloads, title bars appear.
- Same in floating mode → rebuilds on its own after login, title bars come back without
  anything clicked.
- Offline / headers removed → one clear notification, nothing at the next login, the
  Rebuild button works once things are back.
- A distro hyprbars only (`/usr/lib/...`) behaves as before.
