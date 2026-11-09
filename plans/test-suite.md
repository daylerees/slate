# Plan: Slate's regression test suite

Status: **proposed, not started** (written 2026-11-09). Nothing here is implemented yet.

## Context

Slate has grown fast (dock, bar panels, Settings, lock/login, theming, game mode, …) and
almost nothing guards it: CI only checks that the login screen loads
(`.github/workflows/checks.yml` → `tools/check-greeter-files`, `slate-greeter-check`), and
`docs/REDISTRIBUTION.md:38` already lists "IPC smoke tests, screenshot checks" as missing.
Regressions are found by eye, usually by the user, sometimes after a release.

Goal: one command that tests all of Slate's features, **headless in a container** (never
touching the running desktop), with:
- an **agent-friendly quiet mode**: only failures, plus one summary line;
- **visual regression** checks (screenshots compared with approved ones);
- a **latest dependencies** mode to catch upcoming breakage from Hyprland/Quickshell/Qt;
- a **release gate**: it must pass before every tag.

Decisions: runs in Docker locally (installed, user is in the `docker` group) and in GitHub
Actions (fast tiers on every push, everything on release tags). "Latest" means the newest
packaged releases (Arch rolling), not git main.

## Shape

```
tests/
  run                     the one entry point (bash): builds/reuses the image, runs tiers in it
  container/Dockerfile    Arch base; Slate's deps from packaging/arch.txt + test tools
  container/deps.lock     the pinned Arch snapshot date (archive.archlinux.org) for "pinned"
  lib/                    python helpers: results/reporting, stub commands, session control,
                          image diff
  static/                 tier 1
  unit/                   tier 2 (one file per script)
  live/                   tier 3 (IPC-driven checks against a running Slate)
  visual/scenes.py        tier 4 scene list; visual/baselines/*.png approved screenshots
  fixtures/               settings.json, wallpaper, .desktop files, icons, hyprctl JSON,
                          lpstat/nmcli/dbus-monitor output, images
  out/                    (gitignored) logs, failure screenshots, diffs
```

Python's own `unittest` (no new dependency) under a small custom result printer, so every
check reports the same way.

### `tests/run` options
- `--tier static|unit|live|visual|all` (default `all`; comma lists allowed)
- `-q/--quiet` (agents): print only failures (name, one-line reason, path to log/diff) and a
  final `PASS 412/412` or `FAIL 3/412` line; nothing for passes. `-v` lists every pass.
- `--json`: machine output (one object per failure + summary).
- `--deps pinned|latest` (default pinned). `latest` rebuilds the image with today's Arch
  (`pacman -Syu`), runs everything, and labels the summary `[latest deps]`.
- `--update-baselines [scene…]`: re-shoot and replace approved screenshots (shows a list of
  what changed first).
- `--filter <text>`: only tests whose name matches.
- `--no-container`: static + unit tiers directly on the host (fast inner loop); live/visual
  always need the container.
- Exit code 0 only if everything ran and passed.

## Tiers

### 1. Static (seconds, no session)
- `qmllint` on every `shell/**/*.qml` with Quickshell's `qmltypes`; fail on `[syntax]` and on
  "is not a type"/unresolved import warnings (the hot-reload trap found this session).
- `luac -p` on all Lua; `Hyprland --verify-config -c shell/session/hypr/hyprland.lua` with a
  scratch `HOME`/`XDG_CONFIG_HOME` (copy of `shell/`), and the greeter's config.
- `python3 -m py_compile` on `shell/scripts/*.py`, `tools/*.py`; `sh -n` + `shellcheck`
  (errors only) on `shell/scripts/*.sh`, `shell/bin/*`, `install.sh`.
- Existing: `tools/check-greeter-files`; `slate-greeter-check --source shell`.
- Consistency: `KEEP` in `install.sh` = `KEEP` in `shell/scripts/update.py`; every package in
  `packaging/*.txt` is well-formed; `SettingsIndex.pages` ids all have a page in
  `SettingsWindow.qml`'s loader map; every `Config.s.<key>` used exists in
  `SettingsData.qml`; every `pageKeys` key exists; site links/anchors resolve
  (`site/*.html`); no "Noctalia" anywhere; shaders' `.qsb` newer than their `.frag`.

### 2. Unit (seconds, scratch HOME, stub commands)
A stub harness (`tests/lib/stubs.py`) puts fake `hyprctl`, `nmcli`, `lpstat`, `lpinfo`,
`dbus-monitor`, `wl-paste`, `wl-copy`, `gio`, `gsettings`, `magick`, `notify-send` first on
`PATH`, each replaying a fixture and logging its arguments; every test gets a fresh temp
`HOME` with all `XDG_*` inside it (several QML/scripts use `$HOME` directly). One test file
per script, e.g.:
- `settings-index.py`: real `SettingsWindow.qml` parses; every label unique per page.
- `spaces.py snapshot/save/delete/session-save` against fixture `hyprctl -j` JSON.
- `appicon.py --tile`/`--tile-all`/`--preview`: fixture icons → byte hashes of the tiles
  (like this session's identical-output check) for every shape/fill.
- `apply-theme.py` with `SLATE_THEME_TEST=1`: apply → expected files; switching apps off
  restores the originals (undo log round-trip); `--apps` JSON shape.
- `folder-colour.py --list`/named colour with a fixture Papirus tree; `wallpaper-accent.py`
  on fixture images (golden accent/tone), fallback with no `magick`.
- `printers.py list/find/scanners` (fixture `lpstat`/`lpinfo`/`scanimage` output, incl. the
  multi-printer case), `safe_name`.
- `launcher-entries.py` with canned `dbus-monitor` output → expected JSON lines.
- `clipstore.py`, `image-sizes.py`, `update.py modified`, `screensaver-videos.py`
  (`best_size`, credits; no network), `netinfo.sh`, `open-with.sh`, `user-files.sh`
  (never overwrites), `install.sh --help`, `slate-greeter-sync --check` (with
  `SLATE_GREETER_DIR`).

### 3. Live (a real headless session; ~minutes)
Inside the container, as a non-root user, with `dbus-run-session`:
1. **Parent compositor**: `sway` with `WLR_BACKENDS=headless WLR_RENDERER=pixman` (no GPU, no
   display; the only way Hyprland can run without a seat: it has no headless flag of its own).
2. **Hyprland nested** in it (`LIBGL_ALWAYS_SOFTWARE=1`, `HYPRLAND_NO_CRASHREPORTER=1`),
   with a test config: Slate's session config plus one fixed headless output (1440×900,
   scale 1), animations off.
3. **Slate** from a copy of `shell/` with a scratch `HOME`, a fixture `settings.json`, fixture
   wallpaper, and `faketime` pinned to `2026-01-05 09:41` so clocks are stable.
4. **Fake world**: a few fixture apps (`foot` terminals, a GTK test window) for the dock,
   switcher and overview; `notify-send` notifications; a fake MPRIS player (small python
   D-Bus service) for the dock's media player; `gdbus emit` launcher-entry badges; files in
   the scratch Trash and Downloads.

**New in Slate, for testability (small, off unless `SLATE_TEST=1`):**
- No side effects in test mode: no greeter-sync prompt, no update check, no startup apps,
  no welcome, no sounds.
- `$XDG_RUNTIME_DIR/slate-ready` written once everything has loaded (like the greeter's
  `SLATE_GREETER_CHECK`), so tests don't sleep and guess.
- A `test` IPC target returning JSON of what's on screen: open panel, Settings section and
  scroll, dock slots (kinds, keys, badges), bar segments shown, notification count, lock state,
  game mode, launcher results. Tests assert on this rather than on pixels where they can.

Checks (each also scans the Slate log for new `ERROR`/`TypeError`/`ReferenceError`/
`Binding loop` lines, which fails the test):
- Loads clean; full restart and hot reload both clean.
- Every bar panel opens and closes (`bar panel <name>` for all 13).
- Every Settings page loads (`settings page <id>` for every id in `SettingsIndex.pages`),
  `settings find` lands on the setting; restore defaults per page resets its keys.
- `config set/get` round-trip for every key in `SettingsData.qml` (types kept).
- Launcher: open, search, results; Picker clipboard/emoji; switcher next/cancel; overview
  open/close; lock preview; screensaver start/stop; power confirm cancel; polkit preview.
- Dock: slots in the right order with dividers/media/Downloads/Waste Basket for each setting
  combination; badges from `gdbus emit`; previews IPC; Downloads grid; bin count follows the
  scratch Trash.
- Game mode on/off puts Hyprland options back (via `hyprctl getoption`).
- Small screens: rerun a subset on an 853×480 output (the "fit small screens" regressions).
- Greeter: existing `slate-greeter-check`, plus `SLATE_GREETER_TEST=1` login flow against a
  fake greetd socket (`docs/LOCK-AND-LOGIN.md:133-139`).

### 4. Visual (screenshots vs approved)
`tests/visual/scenes.py` lists scenes as small IPC scripts: bar (each look: flat, glass,
light mode), each bar panel, each Settings page (top), launcher list/grid, switcher, overview,
dock (with media, badges, Downloads grid, previews), lock screen preview, notifications,
picker, power confirm, welcome. For each: drive the state, wait for `test` to report it,
`grim -o TEST` → compare with `tests/visual/baselines/<scene>.png`:
- tolerant diff (`tests/lib/imgdiff.py`, Pillow): per-pixel threshold for anti-aliasing,
  fail if more than 0.1% of pixels change or any 16×16 block changes a lot;
- on failure save `out/visual/<scene>.{actual,diff}.png` (diff highlights changes in red) and
  print just the scene name and the path;
- baselines are made only in the container (software rendering is deterministic there; the
  host GPU would differ), approved with `--update-baselines`, reviewed in the commit.

## Release gate and CI
- `CLAUDE.md` → Releases: "run `tests/run -q` (pinned) and stop if it fails; run
  `tests/run -q --deps latest` and report its failures in the release notes' Other section
  as a heads-up, without blocking".
- `checks.yml`: static + unit on every push/PR (in the same container image); live + visual on
  `v*` tags and manual dispatch; upload `tests/out` as an artifact on failure. A weekly
  scheduled `--deps latest` run opens an issue when it fails.
- `.githooks/pre-commit`: add `tests/run -q --tier static --no-container` (fast).
- A memory note: run `tests/run -q` before releases and after big changes.

## Order of work
1. **Spike** (do first; it decides tier 3/4): container with headless sway → nested Hyprland
   on software rendering → `qs` → `grim`. If nested Hyprland won't render without a GPU,
   fall back to passing `/dev/dri` through locally and using GitHub's software Mesa, or to
   running Hyprland directly on a `vkms` device; record what works in this plan.
2. `tests/run` + reporting (quiet/verbose/json) + static tier + Dockerfile (pinned).
3. Unit tier with the stub harness, script by script.
4. `SLATE_TEST` mode, `slate-ready`, `test` IPC target in Slate (+ docs).
5. Live tier, area by area (bar, Settings, dock, launcher, …).
6. Visual tier + first baselines.
7. `--deps latest`, CI workflow, release gate in `CLAUDE.md`, pre-commit hook, docs
   (`docs/TESTING.md`, README, ARCHITECTURE).

## Files touched in Slate itself
- `shell/shell.qml`, `shell/Config.qml` (test mode, ready file, `test` IPC target); small
  `SLATE_TEST` guards where side effects start (`Updates.qml`, greeter sync in `shell.qml`,
  startup apps in `Config.qml`, `Welcome.qml`, sounds in `Config.playSound`).
- `.github/workflows/checks.yml`, `.githooks/pre-commit`, `.gitignore` (`tests/out`),
  `CLAUDE.md` (release gate), `docs/TESTING.md` (new), `docs/REDISTRIBUTION.md` (update).
- Reuses: `slate-greeter-check`, `tools/check-greeter-files`, `tools/test-install-docker.sh`
  (kept as the separate, slower per-distro install test), `SLATE_THEME_TEST`,
  `SLATE_GREETER_TEST`/`SLATE_GREETER_DIR`/`SLATE_DIR`.

## Verification
- `tests/run -q` on a clean checkout passes with one summary line; break something on
  purpose (rename a Settings key, add a syntax error, nudge a bar colour, remove a panel
  name) and confirm each is caught by the right tier with a short failure line and, for the
  colour, a diff image.
- Confirm it never touches the host: run it while watching `hyprctl clients` on the desktop
  (no new windows) and with `~/.config/slate` unchanged (checksum before/after).
- `--deps latest` builds a fresh image and labels its result; the CI workflow runs on a test
  tag; the release section in `CLAUDE.md` is followed for the next release.
