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
| `unit` | seconds | every script in `shell/scripts` (and `install.sh --help`, `slate-greeter-sync`), in a scratch home with fake `hyprctl`, `nmcli`, `lpstat`… (`tests/lib/stubs.py`) |
| `live` | ~2 min | a real Hyprland and Slate, headless: it loads and reloads without errors; every bar panel, Settings page and full-screen part opens and closes; every setting changes and changes back; the dock's slots, badges and Waste Basket; game mode; a small (853×480) screen; the login screen logging in through a fake greetd. After every test, Slate's log must have no new errors (`Binding loop`, `TypeError`…) |
| `visual` | ~2 min | screenshots of ~60 scenes (`tests/visual/scenes.py`: the bar in each look, every panel and Settings page, the launcher, lock screen, dock menus…) compared with the approved ones in `tests/visual/baselines/` |

The exit code is 0 only when everything ran and passed.

## Options

```sh
tests/run --tier static,unit        # just these tiers (static, unit, live, visual, all)
tests/run --no-container            # static + unit straight on this machine (fast; no Docker)
tests/run --filter dock             # only tests (or scenes) whose name has "dock" in it
tests/run -v                        # every check, passes too
tests/run --json                    # a JSON line per failure, then a summary (for tools)
tests/run --deps latest             # today's Arch packages instead of the pinned snapshot (once a day)
tests/run --update-baselines [scene…]   # re-shoot approved screenshots (all, or these)
```

Logs, failed screenshots and their diffs go in `tests/out/` (not committed): a failure line
names the file to look at.

## The live and visual tiers need vkms

Hyprland needs a graphics device even with nothing to show, so these tiers borrow the kernel's
virtual one, `vkms`. Load it once per boot:

```sh
sudo modprobe vkms
```

It isn't used as a screen: Hyprland draws in software (llvmpipe) to a headless output inside
the container, which is why screenshots are the same on every machine. Your own Hyprland may
notice the virtual card appear; it doesn't put anything on it. `sudo modprobe -r vkms` takes
it away again. GitHub's runners load it the same way.

## When a screenshot changes

A visual failure prints the scene and its diff (`tests/out/visual/<scene>.diff.png`, the
changes in red; `.actual.png` beside it). If the change is meant (you changed how something
looks), approve it:

```sh
tests/run --update-baselines panel-control settings-dock    # or no names: every scene
git diff --stat tests/visual/baselines                      # then look at the images before committing
```

Approved screenshots are only ever made in the container: the software renderer there gives
the same pixels every time, where a real GPU wouldn't. Small anti-aliasing shifts are allowed
(`tests/lib/imgdiff.py`); a scene can also mask a part that changes by itself (the control
centre's uptime).

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
  back after. Each test starts with everything closed.
- **visual**: add a scene to `tests/visual/scenes.py`, then
  `tests/run --update-baselines <scene>` and check the new image.

A bug found by a test but not fixed yet: mark the test `@unittest.expectedFailure` (unit), or
add the log line to `KNOWN_ISSUES` in `tests/lib/session.py` (live), with a comment. Take it
out when it's fixed.

## Slate's test mode

The Slate the live tier starts has `SLATE_TEST=1`: no sounds, welcome, startup apps, update
checks or prompts, a fixed time on its clocks (`SLATE_TEST_TIME`), `$XDG_RUNTIME_DIR/slate-ready`
once loaded, and the `test` IPC target. See ARCHITECTURE.md → Test mode.
