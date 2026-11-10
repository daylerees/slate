# Plan: Slate's title bars by default, Hyprbars as an option

Status: **planned** (2026-11-10; rewritten the same day around Slate's own title bars).

## Context

Floating windows' title bars came from the hyprbars plugin, which Slate builds
(`slate build-hyprbars` → `~/.local/share/slate/plugins/hyprbars.so`). A Hyprland plugin
only loads in the exact Hyprland it was built for. After a Hyprland update the old build is
still there, so `shell/session/hypr/config/hyprbars.lua` asks Hyprland to load it, Hyprland
refuses ("API version mismatch") and shows its own red error notices at login. This
happens after **every** Hyprland update, on every distro, and building needs a compiler,
git and Hyprland's headers.

Slate now has its own title bars (`TitleBar.qml`): drawn by Slate, nothing to build, nothing
that breaks when Hyprland updates. They were added as an experiment.

## Decision

- **Slate's title bars are the default**, and no longer called experimental.
- **Hyprbars is optional**: more featureful (a bar on every floating window, moving as one
  with its window, focus can follow the mouse), but with risks the user accepts when they
  choose it. Like the login screen: nothing builds or installs it unless asked.
- **Slate's title bars are the fallback** whenever Hyprbars can't be used. Floating windows
  never lose their title bars and never drop back to tiling.
- User-facing text says **"after your next restart"** (not "at next login") wherever
  something waits for Hyprland to start again.

Goals:
1. Never ask Hyprland to load a hyprbars built for another Hyprland: no error notices.
2. Nobody is switched without being told, and nobody who has Hyprbars working loses it.
3. Rebuilding is asked for, runs in the background, and says plainly when it can't be done.

## What Hyprland gives us

- The Lua config has `hl.version()` (string; `/usr/share/hypr/stubs/hl.meta.lua:951`).
  **Check first** what it returns (`0.57.2`? with the commit?).
- `hyprctl version -j` gives `version`, `commit` and `tag` of the **running** Hyprland.
  Don't call it from the Lua config (it can block Hyprland while the config runs).
- `pkg-config --modversion hyprland` and Hyprland's headers describe the **installed**
  Hyprland, which is what a build is made for. After a package update and before a restart,
  installed ≠ running.
- The plugin check compares the git commit, so two `-git` builds with the same version
  number differ only by commit.

## Changes

### 1. The default and the wording
- `SettingsData.qml`: `titleBarStyle` defaults to `slate`.
- **Existing users keep what they have.** Check how settings are saved (every key, or only
  changed ones). If an existing install has no saved `titleBarStyle` and a hyprbars build
  (Slate's or a distro's) is present, write `hyprbars` once, so the new default doesn't
  switch them. Without a build they were on tiling-only anyway and get Slate's bars.
- Remove "experimental" and `Config.slateTitleBarsQuestion` (choosing Slate's bars asks
  nothing). Settings → Windows → Title bars and the window mode panel list
  **Slate's** (default) and **Hyprbars (optional)**, the panel section always shown for a
  floating workspace.
- `Config.usableMode`: floating is always usable now (no drop to tiling without the plugin).
- Slate's bars are the standard experience, so their limits are documented plainly, not as
  an experiment: a bar on the topmost floating window only; it fades out while a window
  moves, resizes or maximises; windows take focus on click in floating mode.

### 2. Choosing Hyprbars (opt-in, with the risks)
Picking Hyprbars asks in Slate's confirmation window (`win.ask` / `PowerConfirm.confirmWith`),
e.g. *"Use Hyprbars?"*: "Hyprbars is a Hyprland plugin that Slate builds on this computer.
It gives every floating window a title bar that moves with it. It stops working after each
Hyprland update until it's rebuilt, which needs a compiler, git, Hyprland's headers and an
internet connection. Until then, Slate's own title bars are used." **Build and use** /
**Cancel**.
- Already built for the running Hyprland and loaded → just switch, no build.
- Otherwise run the build (step 5). The setting stays on Slate's until Hyprbars has loaded;
  then it switches to Hyprbars by itself (they asked for it; no second question).
- **Remove Hyprbars** (Settings → Windows, shown when a Slate build exists and the style is
  Slate's): deletes Slate's builds and their records. "Gone after your next restart"
  (the loaded plugin can't be skipped mid-session, see step 4).

### 3. Builds are named for their Hyprland (`shell/bin/slate-build-hyprbars`)
- Build for the **installed** Hyprland and install as
  `~/.local/share/slate/plugins/hyprbars-<version>-<commit, 12 chars>.so` with a record next
  to it, `hyprbars-<…>.json`: `{ "version", "commit", "built", "patched": true|false }`.
  Commit from Hyprland's headers when they have one, else `hyprctl version -j` if installed
  = running, else empty. Temp file + `mv`, as now.
- Keep the build for the running Hyprland and the newest one; delete older ones.
- Keep the downloaded source (`~/.cache/slate/hyprland-plugins`) and `git fetch` it instead
  of deleting and cloning every time. With no connection: if the source already has the
  wanted release, build from it; else fail with "no internet connection".
- One build at a time: `flock` on a lock file. A second run says "already building" and
  exits.
- Write progress to `~/.local/state/slate/hyprbars-build.json`
  (`{ "state": "building|built|failed", "for": "<version>", "error": "<first line>" }`) and
  the full log to `~/.cache/slate/hyprbars-build.log`, so Slate reads the state from files.
- **A build from before this change** (`hyprbars.so`, no record): left alone. See step 4.

### 4. Load only a matching build (`session/slate-session`, `hyprbars.lua`)
- `slate-session` exports `SLATE_HYPRLAND_VERSION` and `SLATE_HYPRLAND_COMMIT` (from
  `Hyprland --version`) before starting Hyprland, so the config knows exactly what's running
  (this also tells two `-git` builds apart). Without them (another way of starting
  Hyprland), fall back to `hl.version()`.
- Slate's builds: load the one whose record matches the running Hyprland (commit when both
  have one, else version). None matches → load nothing, print one
  `[slate] no hyprbars for Hyprland X; using Slate's title bars` line, set
  `HYPRBARS_STALE = true`.
- Old `hyprbars.so` with no record: load it as today (so nobody loses a working Hyprbars
  the first time they get this change). When Slate sees it loaded, it writes a record for
  it (step 5), and from then on it's checked like the others.
- Distro packages (`/usr/lib/...`): loaded as today; their package manager keeps them in
  step. If one fails to load, Slate notices afterwards (step 5).
- Keep the "ask on every config pass" rule: a plugin that was loaded is asked for again on
  every pass for as long as that Hyprland runs, whatever has been built or removed since
  (skipping it makes Hyprland unload it and reload in a loop). Named builds make this
  safe: a new build never replaces the file the running Hyprland loaded.

### 5. Slate keeps watch (`shell/Config.qml`, next to `titleBarsCheck`)
Checked at Slate's start (not in `Config.testMode`), after each Hyprland config reload, and
when the build state file changes. From `hyprctl version -j`, `hyprctl plugin list`, the
build records and `pkg-config`:

- **The style in use.** Hyprbars only when the setting says Hyprbars **and** the plugin is
  loaded. In every other case Slate's bars, whatever the settings file says (a Spaces
  restore, a hand-edited file, a failed build).
- **Out of date and wanted** (setting = Hyprbars, floating in use on the default or any
  workspace, no build loaded for the running Hyprland):
  1. Change the setting to Slate's, and note that Slate did it:
     `~/.local/state/slate/hyprbars-fallback` holding the Hyprland version.
  2. Ask (queued, see below), *"Hyprbars needs rebuilding"*: "Hyprland was updated, and
     Hyprbars was built for the old version, so it can't load. Floating windows use Slate's
     title bars until it's rebuilt (they take focus when clicked). Rebuild it now? It takes
     about a minute in the background." **Rebuild** / **Not now**.
  3. **Rebuild** → the build, detached from Slate (it survives a Slate reload), `nice`d,
     after game mode ends if it's on, and after waiting up to a minute for a connection.
  4. **Built, for the running Hyprland** → notification *"Hyprbars rebuilt"*: "Reload
     Hyprland to finish." with **Reload** (`hyprctl reload`; windows stay open). The same
     Reload button is on Settings → Windows, in case the notification is missed.
  5. **Hyprbars seen loaded while the fallback note exists** (after that reload, or after
     any later restart) → ask *"Switch back to Hyprbars?"*: **Switch to Hyprbars** /
     **Keep Slate's**. Either answer removes the note. If the user changed the style
     themselves meanwhile, remove the note and don't ask.
  6. **Not now** → nothing builds; don't ask again for this Hyprland version (the Rebuild
     button stays in Settings). A new Hyprland version asks again.
  7. **Failed** → one notification, `x-slate-page` = windows: *"Hyprbars couldn't be
     rebuilt"* with the first error line (or "No internet connection", with **Retry**), and
     an action to open Settings → Windows. No retry by itself.
- **Hyprland updated, not restarted yet** (installed ≠ running; Hyprbars loaded and in use):
  nothing is broken yet. Notification *"Hyprland was updated"*: "Rebuild Hyprbars now, so
  it's ready after your next restart?" **Rebuild** / **Later**. The build is for the
  installed Hyprland and sits beside the running one's. No Reload is offered; the result
  says "Ready after your next restart". If it isn't done, the "out of date" flow runs
  after the restart.
- **Out of date, not wanted** (style is Slate's, or nothing floats): no question, no build.
  Hyprbars shows as "needs rebuilding" in Settings; choosing it runs step 2.
- **Unpatched build** (`patched: false`): don't send `idle_button_color`; Settings says the
  buttons keep their colours.
- **A distro's hyprbars that didn't load** (file there, plugin not loaded): fall back the
  same way, but the question becomes a notice: "Hyprbars from your system's package doesn't
  match Hyprland. Update that package, or use Slate's build" with **Build Slate's**.
- **Questions don't overwrite each other.** `PowerConfirm` gets a small queue (today a
  second `confirmWith` replaces the first), and these questions wait until the login cover
  and the Welcome window are gone.

### 6. Settings → Windows
Title bars: **Slate's** / **Hyprbars (optional)**, with the state under it and one button:
- not built → choosing it asks (step 2)
- building for Hyprland X… (spinner)
- built, reload to use it → **Reload**
- built, ready after your next restart
- in use
- needs rebuilding for Hyprland X → **Rebuild** (Hyprbars can't be selected until then)
- couldn't be rebuilt: reason → **Retry**
- from your system's package / doesn't match Hyprland
Plus **Remove Hyprbars** (step 2). Search entries in `SettingsIndex.qml` ("title bars",
"hyprbars", "rebuild"). Follow the Settings page design notes.

### 7. Installer and updates
- `install.sh`: stop building hyprbars (step "hyprbars: title bars for floating windows").
  The compiler, git and headers become opt-in needs: `packaging/*.txt` keep them optional,
  and the build's failure message names the missing package.
- `slate update` / `shell/scripts/update.py`: nothing to build. It only runs the "Hyprland
  updated, not restarted yet" check afterwards, like Slate's start does.

## Distros (docs/REDISTRIBUTION.md)
- Arch, Debian, Fedora, openSUSE: Slate's bars need nothing. Hyprbars is the opt-in build;
  its needs are listed where the option is described.
- NixOS: Slate's bars by default. `hyprlandPlugins.hyprbars` from Nix always matches its
  Hyprland and is treated as a distro package (no Slate build, no Rebuild).

## Scenarios (each one is a test and a line in the verification)

| # | Situation | What happens |
|---|---|---|
| 1 | New install | Slate's bars. Nothing is built; no compiler needed. |
| 2 | Existing user, Hyprbars working | Stays on Hyprbars (setting written once; old build loaded and given a record). |
| 3 | Existing user, no build | Slate's bars; floating now works where it fell back to tiling. |
| 4 | Chooses Hyprbars, never built | Risk question → build → "Reload" notification → reload → Hyprbars, setting switches. |
| 5 | Chooses Hyprbars, build already loaded | Switches at once. |
| 6 | Cancels the risk question | Nothing changes. |
| 7 | Hyprland updated, then restart, Hyprbars + floating | No red errors. Slate's bars, setting shows Slate's, Hyprbars disabled, "needs rebuilding" question. |
| 8 | 7 → Rebuild | Background build → "Hyprbars rebuilt" + Reload → reload → "Switch back to Hyprbars?" |
| 9 | 8 → Switch / Keep | Hyprbars / Slate's. Asked once. |
| 10 | 7 → Not now | Slate's bars; not asked again for this Hyprland version; Rebuild in Settings. |
| 11 | 8, Reload notification missed | Reload button in Settings; else Hyprbars loads after the next restart and the switch-back question comes then. |
| 12 | Hyprland updated, then restart, tiling or Slate's bars | No question, no build, no errors. Settings shows "needs rebuilding". |
| 13 | 12 → later picks Floating with style Hyprbars | Scenario 7 from there. |
| 14 | Hyprland updated, not restarted, Hyprbars in use | Bars keep working. Offer to rebuild now; "Ready after your next restart"; no Reload offered. |
| 15 | 14 done, then restart | Hyprbars loads for the new Hyprland; no fallback, no question. |
| 16 | 14 skipped, then restart | Scenario 7. |
| 17 | Rebuild with no connection | Waits up to a minute; builds from the kept source if it can; else "No internet connection" + Retry. |
| 18 | Rebuild fails (no compiler/headers, release doesn't compile) | One notification with the reason and the missing package; Slate's bars stay; no retry by itself. |
| 19 | Slate's patch doesn't apply | Builds without it; buttons keep their colours; no config error. |
| 20 | Slate reloads or restarts mid-build | Build carries on; state read from its file. |
| 21 | Rebuild pressed twice / also run in a terminal | One build; the second says "already building". |
| 22 | Setting says Hyprbars but it isn't loaded (Spaces restore, edited file) | Slate's bars are used; the "out of date" flow runs if a build is missing. |
| 23 | Another question is on screen (Welcome, login prompts) | Queued; shown after it. |
| 24 | `-git` Hyprland, same version, new commit | Told apart by commit; treated as out of date, no red errors. |
| 25 | Distro package of hyprbars doesn't match | Slate's bars; notice to update the package or build Slate's. |
| 26 | NixOS | Slate's bars, or Nix's hyprbars; never a Slate build. |
| 27 | Game mode on | Build waits until it ends. |
| 28 | Remove Hyprbars | Builds deleted; "Gone after your next restart". |
| 29 | Hyprland downgraded | Same as updated (7 or 12). |
| 30 | Test mode | No checks, questions, builds or notifications. |

## Tests
- **Unit**: the build script (stub `git`, `make`, `pkg-config`, `hyprctl`): named build +
  record, old builds pruned, running one kept, lock, state file, no-connection path,
  unpatched flag. `hyprbars.lua` under LuaJIT with a stub `hl` and environment: matching
  record → loads that file; no match → no load and `HYPRBARS_STALE`; old `hyprbars.so`
  without a record → loads; same version, other commit → no load; `/usr/lib` only → loads.
- **Regression test for the login errors** (written first, seen failing): a build for
  another Hyprland is never passed to `hl.plugin.load`.
- **Live** (stub `slate-build-hyprbars`; state in the `test` IPC target:
  `titleBars: slate|hyprbars`, `hyprbars: none|building|built|ready|loaded|stale|failed`,
  `hyprbarsFallback`): scenarios 1, 4 to 14, 17, 18, 20, 22, 23, 27, 30. A stale build in
  the scratch HOME → the Hyprland log has no "Failed to load plugin". The settings
  migration (2, 3) as a unit test of whatever does it.
- **Visual**: the three questions (use Hyprbars, needs rebuilding, switch back) and the
  Settings → Windows title bar row in its states.
- Existing title bar tests: expectations change to Slate's bars as the default; the
  experimental warning's tests go.

## Docs and site
- `README.md`, `docs/INSTALL.md`, `docs/ARCHITECTURE.md`, `docs/REDISTRIBUTION.md`: Slate's
  title bars by default; Hyprbars optional, what it needs, what happens after Hyprland
  updates. `slate build-hyprbars` stays for doing it by hand.
- `site/features.html` (Windows section) and the index card if it mentions title bars.
- Release notes: a feature ("Slate's own title bars are the default; Hyprbars is optional")
  and a fix ("no more error messages at login after Hyprland updates"). Not breaking:
  existing Hyprbars users keep it.

## Order of work
1. Check `hl.version()`, `Hyprland --version` and what the headers expose; how settings are
   saved (for the migration).
2. Regression test, then steps 3 and 4 (named builds, load only a match). This alone stops
   the error notices.
3. Step 1 (default, wording, migration) and step 7 (installer).
4. Step 5 (watching, fallback, questions, queue) with its live tests.
5. Step 2 and 6 (opt-in, Settings), docs, site.
