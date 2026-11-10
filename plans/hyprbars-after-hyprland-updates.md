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
2. Rebuild it when it's needed (asking first), and say so plainly when that can't be done.
3. Floating windows never lose their title bars: Slate's own title bars are the fallback
   while Hyprbars is out of date (the setting switches to them, and Hyprbars can't be
   chosen), and once it's rebuilt and reloaded, Slate asks whether to switch back.

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

## Since this was written

- Window modes are per workspace now, so "floating" below means the default mode or any
  workspace's own mode.
- Slate has its own title bars (experimental, nothing to build), used here as the fallback
  while Hyprbars is out of date; someone who chose them needs no rebuild at all.

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
(commit when both have one, else version). "Hyprbars is wanted" means: the title bar style
is Hyprbars **and** floating is in use, i.e. the default window mode or any workspace's
own mode (`Config.workspaceModes`) is Floating.

While Slate's build is out of date, **Hyprbars can't be chosen**: the Hyprbars option in
Settings → Windows → Title bars and in the window mode panel is shown but disabled, with
"Needs rebuilding for Hyprland X" and the Rebuild button (step 4) next to it.

**Out of date and wanted (login, floating, Hyprbars chosen):**
1. Change the setting to Slate's title bars (`titleBarStyle` = `slate`), so Settings and
   the panel show what's really in use. Remember that it was Slate that changed it, not the
   user: a runtime state file, e.g. `~/.local/state/slate/hyprbars-fallback`, holding the
   Hyprland version it happened for. Skip the experimental warning that choosing Slate's
   bars normally gives; this question explains them instead.
2. Ask in Slate's confirmation window (`PowerConfirm.confirmWith`, with the attention sound),
   e.g. *"Title bars need rebuilding"*: "Hyprland was updated, and the Hyprbars plugin
   was built for the old version, so it can't load. Floating windows use Slate's own title
   bars until it's rebuilt. Rebuild it now? It takes about a minute in the background."
   Buttons: **Rebuild** / **Not now**.
3. **Rebuild:** run `slate-build-hyprbars` in the background with `nice`. If game mode is
   on, wait until it ends. When it finishes, show a notification: *"Title bars rebuilt"*:
   "Reload Hyprland to finish." with a **Reload** action (`hyprctl reload`; your windows
   stay open). After the reload the build matches and loads, `checkTitleBars()` sees it,
   and Hyprbars can be chosen again.
4. **Switch back?** Once Hyprbars has loaded after that reload and the fallback file is
   there, ask in the confirmation window: *"Switch back to Hyprbars?"*: "Hyprbars has been
   rebuilt for this version of Hyprland. Floating windows have been using Slate's title
   bars in the meantime." Buttons: **Switch to Hyprbars** / **Keep Slate's**. Either answer
   removes the fallback file, so it's asked once. If the user changed the style themselves
   in the meantime, also drop the file and don't ask.
5. **Not now:** nothing builds; Slate's bars stay (it's the real setting now), and so does
   the fallback file. Ask again at the next login. Settings → Windows has the Rebuild
   button in the meantime.
6. **Failed** (no network for the clone, missing headers/compiler, the patch fails and the
   plain build fails too): a notification, `x-slate-page` = windows: "Title bars couldn't be
   rebuilt for Hyprland X", with the first error line from the build log and an action to
   open Settings → Windows. Slate's bars stay. Don't retry by itself: only when Hyprland's
   version changes again or the user asks. Keep the log in `~/.cache/slate/hyprbars-build.log`.

**Out of date, not wanted** (tiling everywhere, or Slate's title bars chosen): don't build,
don't ask and don't change the setting; just mark it stale (Hyprbars disabled in Settings,
with Rebuild). If the style is Hyprbars and the user later picks Floating, the same
question (from step 1) comes up then.

**No Slate build at all** (never built, or a distro package): do nothing, as today.

### 4. Settings → Windows
Next to the Title bars setting, show the
state and a **Rebuild title bars** button (it runs the same background build, with a
spinner and the result). States: built and loaded / being rebuilt for Hyprland X / rebuilt, reload
to use it (Reload button) / out of date (Hyprbars disabled until it's rebuilt) / couldn't be rebuilt (reason + Rebuild) / not
installed (how to get it). Search entry in `SettingsIndex.qml` ("title bars", "hyprbars",
"rebuild"). Follow the Settings page design notes.

### 5. Updates
`slate update` / the updater (`shell/scripts/update.py`): if a Slate build exists and
doesn't match, rebuild it as part of the update so the next login is clean (no question,
no override).

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
  stub `slate-build-hyprbars` and check:
  - stale + floating (default or one workspace) + Hyprbars → `titleBarStyle` becomes
    `slate`, the fallback file is written, no experimental warning, the question appears;
  - while stale, Hyprbars can't be picked (Settings and the panel);
  - Rebuild → the stub runs (not during game mode), then a notification with a Reload
    action; after reload, the "Switch back to Hyprbars?" question; Switch → `hyprbars`,
    Keep → `slate`, and either way the fallback file is gone and it isn't asked again;
  - the user changes the style themselves before the reload → no switch-back question;
  - Not now → no build, Slate's bars, asked again next login;
  - stale + tiling, or Slate's bars chosen → no question, no build, setting unchanged;
  - a failing stub → one notification, Slate's bars stay; nothing at all in test mode.
  State in the `test` IPC target: `titleBars: loaded|stale|building|built|failed|missing`
  and `hyprbarsFallback: true|false`.
- **Visual**: both question cards, and the Settings → Windows title bar row (stale with
  Hyprbars disabled, built, failed).

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
  log in in tiling mode → no error notices, no question, Slate log says it's stale.
  Switch to Floating → Slate's bars, and the question.
- Same with Floating + Hyprbars → at login, Settings says Slate's title bars (Hyprbars
  disabled) and the question appears. Rebuild → the "Title bars rebuilt" notification →
  Reload → "Switch back to Hyprbars?" → Switch → Hyprbars bars and setting. Not now →
  Slate's bars, asked again at the next login.
- Offline / headers removed → one clear notification, nothing at the next login, the
  Rebuild button works once things are back.
- A distro hyprbars only (`/usr/lib/...`) behaves as before.
