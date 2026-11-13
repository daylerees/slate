# Testing

One command runs Slate's tests, in a Docker container, so nothing touches the desktop you're
using:

```sh
tests/run              # everything (a few minutes the first time: it builds the image)
tests/run -q           # only failures, and one summary line: PASS 1010/1010 or FAIL 3/1010
```

## What it checks

| Tier | Time | What |
|---|---|---|
| `static` | seconds | every QML file lints (`qmllint`: syntax errors, missing types and imports); Lua, Python and shell scripts parse (`shellcheck` errors too); Slate's Hyprland config loads (`Hyprland --verify-config`, with and without your own files); the login screen's file list matches its code and it loads; things that must agree do (every `Config.s.<key>` is a setting, every Settings page has a page, `pageKeys`, `KEEP` in `install.sh` and `update.py`, package lists, the site's links, shaders built from their sources, no other shells named) |
| `unit` | ~2 min | every script in `shell/scripts` (and `install.sh --help`, `slate-greeter-sync`), in a scratch home with fake `hyprctl`, `nmcli`, `lpstat`… (`tests/lib/stubs.py`) |
| `live` | most of a run | a real Hyprland and Slate, headless: it loads and reloads without errors; every bar panel, Settings page and full-screen part opens and closes; every setting changes and changes back; the dock's slots, badges and Waste Basket; game mode; a small (853×480) screen; two screens side by side; the login screen logging in through a fake greetd. After every test, Slate's log must have no new errors (`Binding loop`, `TypeError`…) |
| `visual` | ~3 min | screenshots of ~100 scenes (`tests/visual/scenes.py`: the bar in each look, every panel and Settings page, the launcher, lock screen, dock menus…) compared with the approved ones in `tests/visual/baselines/` |

The exit code is 0 only when everything ran and passed.

## Options

```sh
tests/run --tier static,unit        # just these tiers (static, unit, live, visual, all)
tests/run --no-container            # static + unit straight on this machine (fast; no Docker)
tests/run --filter dock             # only tests (or scenes) whose name has "dock" in it
tests/run --jobs 3                  # how many Slate sessions run side by side (1: one after another)
tests/run -v                        # every check, passes too
tests/run --json                    # a JSON line per failure, then a summary (for tools)
tests/run --deps latest             # today's Arch packages instead of the pinned snapshot (once a day)
tests/run --approve [scene…]        # approve the changed screenshots the last run took (all, or these)
tests/run --update-baselines [scene…]   # re-shoot approved screenshots (all, or these)
```

Logs, failed screenshots and their diffs go in `tests/out/` (not committed): a failure line
names the file to look at.

## Side by side

A run is split into parts that go at the same time, each in a container of its own: `static`
and `unit` are one part, and the `live` and `visual` test files are shared out over several
more, each with its own Hyprland and Slate. A whole run is about five to eight minutes this
way on an 8-core machine, where one after another it's about 24.

- `--jobs N` says how many sessions: by default half the machine's processors, four at most
  (each session draws in software, which is heavy on them). On CI, and when re-shooting
  screenshots, it's one.
- A file is never split, so its tests keep their order; which files share a session changes
  from run to run. They're shared out by how long each took last time
  (`tests/out/durations.json`), so the parts finish together.
- Failures print as they happen, from whichever part; the tier lines and the summary add all
  the parts up. Each session's logs are in `tests/out/live/<part>/`.
- A test that only fails side by side has found something (a race, or something left behind
  by another file): `--jobs 1` runs the old way for comparing, but isn't the fix.

The code is `tests/lib/parallel.py`, which starts `tests/lib/runner.py` once per part.

## The live and visual tiers need vkms

Hyprland needs a graphics device even with nothing to show, so these tiers borrow the kernel's
virtual one, `vkms`. Load it once per boot:

```sh
sudo modprobe vkms
```

It isn't used as a screen: Hyprland draws in software (llvmpipe) to a headless output inside
the container, which is why screenshots are the same on every machine. (The container shares
your `/sys`, so `tests/run` hides `/sys/class/leds` from it: your keyboard's lights, Caps Lock
among them, would otherwise show on the lock and login screens.) Your own Hyprland may
notice the virtual card appear; it doesn't put anything on it. `sudo modprobe -r vkms` takes
it away again. GitHub's runners load it the same way. One card is enough for every session
of a run: none of them needs it to itself.

## When a screenshot changes

A visual failure prints the scene and its diff (`tests/out/visual/<scene>.diff.png`, the
changes in red; `.actual.png` beside it). If the change is meant (you changed how something
looks), approve it:

```sh
# look at tests/out/visual/<scene>.actual.png first, then:
tests/run --approve panel-control settings-dock             # or no names: every changed scene
git diff --stat tests/visual/baselines
```

`--approve` runs nothing: it makes the pictures the failing run took the approved ones, so
what you looked at is exactly what's approved. It leaves alone (and names) any picture taken
before Slate's code or the scenes last changed, since it may no longer be what Slate draws:
run the visual tests again for those. `tests/run --update-baselines [scene…]` re-shoots
instead (a few minutes), for when there's no current picture to approve; look at the new
images before committing.

Approved screenshots are only ever made in the container: the software renderer there gives
the same pixels every time, where a real GPU wouldn't. Small anti-aliasing shifts are allowed
(`tests/lib/imgdiff.py`); a scene can also mask a part that changes by itself (the control
centre's uptime).

The scenes run one after another in one Slate session, and each starts with no notifications
(a pop-up or the bell's count from an earlier scene once showed up in later pictures). One thing
does carry over: Qt's text smoothing depends on what it has drawn before, so a scene run on its
own (`--filter`) can differ from the same scene in a whole visual run by faint edges on text and
icons (a "16×16 area" or a fraction of a percent, on text). The approved pictures come from whole
runs: approve from a whole visual run (`tests/run --tier visual`), not from a filtered one, and
a faint text-edge difference in a filtered run alone isn't a change. Slate sets nothing that
would pin it (Qt here ignores fontconfig's rgba and `QT_SUBPIXEL_AA_TYPE`).

## Pinned and latest packages

The image is built from a dated snapshot of the Arch archive (`tests/container/deps.lock`), so
a run today and a run next month test Slate, not the packages. `--deps latest` builds from
today's packages instead and labels its summary `[latest deps]`: it's how a coming
Hyprland/Quickshell/Qt change that breaks Slate shows up before users get it. Locally it runs
once a day: run it again the same day (same tiers, no `--filter`) and it shows that day's
result from `tests/out/latest-<tier>.txt` and exits with its code; `--fresh` runs it again.
CI always runs it. To move the
pinned date forward, change `deps.lock`, run everything, and re-approve screenshots that
changed only because of the new packages.

## CI

`.github/workflows/checks.yml`: static + unit on every push and pull request; everything on
release tags and when started by hand; and every Monday everything with `--deps latest`,
opening an issue when it fails. Failed runs keep `tests/out` as an artifact.

## Writing tests

Python's `unittest`, one file per area: `tests/<tier>/test_<name>.py`. Each `subTest` counts
as its own check.

- **unit**: subclass `slate.Case` with `scratch = True` for `self.h`, a throwaway home
  (every `XDG_*` folder inside it); run scripts with `env=self.h.env` or a `Stubs(self.h)`
  env, never your own. Commands that reach the desktop (`hyprctl`, `notify-send`,
  `systemctl`, `sudo`…) are blocked unless a test fakes them.
- **live**: subclass `live.LiveCase`. `self.ipc(target, function, …)` is
  `slate ipc call …`; `self.wait(lambda st: …)` waits for the `test` IPC's state (what's
  open, the dock's slots, Settings' page…; `Config.testMode` and `ipc call test state` in
  `shell.qml`); `self.config(key, value)` changes a setting, `self.keep_setting(key)` puts it
  back after. Each test starts with everything closed. Never a set pause before checking
  something (`self.s.settle(0.5)` then an assert): under a full run's four sessions side by
  side it's sometimes too short. Wait for what you expect with `self.wait(…)`, or, when you
  read the state to check it, `self.steady(read, floor=…)` (at least `floor` seconds, then
  until two reads agree). A check that something *doesn't* happen keeps its pause as `floor`.
- **Kinds of session.** Most live tests and every screenshot share one session: one headless
  output, `TEST`, 1440×900. A test file that needs another kind starts its own in
  `setUpClass` (after `Session.stop_shared()`) and stops it in `tearDownClass`, so the shared
  one stays as it is for the rest: `test_small_screen.py` (853×480) and `test_two_screens.py`
  (`Session(second=(1280, 800))`: `TEST`, and `TEST2` to its right at 1440,0, made one after
  the other so `TEST` is always the first screen and the main display). The two-screen tests
  check what's per screen: a bar on each, the panels, the dock, launcher and overview on the
  focused screen, each screen's workspace, the main display, and all of it again at 125%
  Interface size. They read Slate's side from the `test` state (`bars`, `focusedScreen`,
  `mainScreen`, `popoutScreen`, `dock.screen`…) and Hyprland's from `hyprctl layers`
  (which monitor each of Slate's windows is on, and where); `s.screenshot(path, output=SECOND)`
  takes the second screen.
- **visual**: add a scene to `tests/visual/scenes.py`, then
  `tests/run --tier visual --filter <scene>` (it fails: no approved picture yet), check
  `tests/out/visual/<scene>.actual.png`, and `tests/run --approve <scene>`.

A bug found by a test but not fixed yet: mark the test `@unittest.expectedFailure` (unit), or
add the log line to `KNOWN_ISSUES` in `tests/lib/session.py` (live), with a comment. Take it
out when it's fixed.

## Slate's test mode

The Slate the live tier starts has `SLATE_TEST=1`: no sounds, welcome, startup apps, update
checks or prompts, a fixed time on its clocks (`SLATE_TEST_TIME`), `$XDG_RUNTIME_DIR/slate-ready`
once loaded, and the `test` IPC target. See ARCHITECTURE.md → Test mode.
