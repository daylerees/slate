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
tests/run --no-container            # static + unit straight on this machine, for one without Docker
                                    # (Slate's own work never uses it: everything runs in the container)
tests/run --filter dock             # only tests (or scenes) whose name has "dock" in it
tests/run --failed                  # only the tests that failed last time
tests/run --repeat 5                # the chosen tests 5 times over: only what didn't pass every time
tests/run --only live/test_dock,live/test_bar   # just these files, in one session (a part of a run, again)
tests/run --shuffle [seed]          # files shared out and ordered by a seed (said, to run it again)
tests/run --busy [n]                # n busy loops in each part's container (1 if not said)
tests/run --jobs 3                  # how many Slate sessions run side by side (1: one after another)
tests/run -v                        # every check, passes too
tests/run --json                    # a JSON line per failure, then a summary (for tools)
tests/run --deps latest             # today's Arch packages instead of the pinned snapshot (once a day)
tests/run --approve [scene…]        # approve the changed screenshots the last run took (all, or these;
                                    # tests/out/visual/review.html shows them, to pick from)
tests/run --update-baselines [scene…]   # re-shoot approved screenshots (all, or these)
tests/run --docs-shots [name…]          # take the docs' pictures again (all, or these): see below
```

Logs, failed screenshots and their diffs go in `tests/out/` (not committed): a failure line
names the file to look at.

## Running what failed again

Every run, side by side or not, keeps the ids of the tests that failed in
`tests/out/failed.txt`, one a line (`tests.live.test_dock.Dock.test_badges`), and a run with no
failures empties it. `tests/run --failed` runs just those again, in their own tiers, side by
side as usual and with `-q`, `--json`, `--jobs` and `--filter` as ever; what still fails is
kept for the next `--failed`. A failed subtest (one screenshot scene, one QML file) runs its
whole test again: `--filter` narrows it. A failure outside any test (a class's `setUpClass`, a
file that wouldn't load, a part of a side-by-side run that never finished) runs that whole
class or file again. With nothing recorded, `--failed` says so and exits 0.

## Finding a test that fails now and then

`tests/run --repeat N` runs the chosen tests (any `--tier`, `--filter`, `--failed`, `--jobs`) N
times over, then lists only what didn't pass every time, and in how many runs it failed:

```
FLAKY live/bar › clock_opens_panel failed 2 of 5 (runs 2, 4)
FAIL live/dock › badges failed 5 of 5
FAIL 2 didn't pass every time (1 failed every time), 5 runs of 412 checks (41m02s)
```

It's meant for a quiet day in the background: `-q` prints just those lines (`PASS 412/412 every
time, 5 runs (40m11s)` when nothing failed), the default adds a line as each run ends, `--json`
gives a JSON line per test and a summary. Each run keeps its logs, screenshots and everything it
printed apart, in `tests/out/repeat/<run>/` (`output.txt`), and `tests/out/failed.txt` is left
naming every test that failed in any run, so `--failed` runs them again. The exit code is 0 only
when everything passed every time. The timings carry from run to run, so a side-by-side run
shares its files out the same way each time. One `--repeat` runs at a time: a second says so and leaves the
first alone (for load alongside one, start an ordinary run with its own `SLATE_TEST_OUT`).

### Shaking them out on purpose

Fragile tests used to be found by accident, when a change in how many sessions ran moved which
files shared one, or how busy the computer was. Two options do it on purpose:

- `--shuffle [seed]` shares the files out at random and runs each part's files in a random order
  (a file's own tests keep theirs). A test that passes only after another, or only when something
  another left isn't there, shows. The seed is said at the start, even with `-q` ("shuffled with
  seed 482913"): `--shuffle 482913` runs it the same way again. With `--repeat`, each run picks
  its own unless one is given.
- `--busy [n]` keeps n processes spinning in each part's container while its tests run (1 if not
  said), and stops them when the part ends. A test that passes only on a quiet computer shows:
  a wait on a time rather than on what it means, or a check that a busy computer can't meet.
  The load is only ever inside the containers: `tests/run` refuses `--busy` with `--no-container`.

Before a release, run them together a few times, a different seed each, in the background:
`tests/run -q --shuffle --busy` (or `--repeat 3 --shuffle --busy`). What they find is a real
race more often than not: fix the test or the code, as for any failure. One that checks something
only a quiet computer can (a smooth slide, icons ready before they're seen) is marked
`@slate.quiet` (Writing tests), not given a looser check.

## Side by side

A run is split into parts that go at the same time, each in a container of its own: the `live`
and `visual` test files are shared out over several, each with its own Hyprland and Slate, and
`static` and `unit` over as few as keep them from finishing last. A whole run is about five
minutes this way on an 8-core machine, where one after another it's about 24.

- `--jobs N` says how many sessions: by default three quarters of the machine's processors, six
  at most (each session draws in software, which is heavy on them), or on a big machine three
  eighths of its processors, as long as there's 4 GB free for each. Six on 8 processors gives the
  same results as one after another, now that the tests wait for things, not set times. On CI,
  and when re-shooting screenshots, it's one.
- Measured on a 24-thread Ryzen 9 5900X with 128 GB (2026-11-20), a full run of about 391,000
  checks: 6 sessions, 594 s; 9 (its default), 417–423 s, two clean runs in a row; 12, about
  350–360 s, but busy enough that the launcher's rows now and then came into view a frame
  before their icons (`live/test_launcher_scroll`); 16, 372 s and no faster, with the processors
  full, Slate died once in `live/test_preview_closing` (its workaround for a Quickshell crash
  depends on timing) and two assistant tests timed out.
- More sessions, and the parts sharing sessions differently, flushed out several tests that
  failed now and then (keys pressed before the keyboard moved, state left behind for the next
  test, waits that took an in-between state); the patterns are worth knowing when writing one.
- A file is never split, so its tests keep their order, except the visual scenes: one file that
  took as long as a whole part, so it's shared out in slices (`visual/test_visual@2/3`, every
  third scene from the second, still in order; `SPLIT` in `parallel.py`, and the test asks
  `slate.in_slice`). Which files share a session changes from run to run. They're shared out by
  how long each took last time (`tests/out/durations.json`), so the parts finish together.
- Failures print as they happen, from whichever part; the tier lines and the summary add all
  the parts up. Each session's logs are in `tests/out/live/<part>/`.
- A test that only fails side by side has found something (a race, or something left behind
  by another file): `--jobs 1` runs the old way for comparing, but isn't the fix.
- After each test class in a shared session, what it left on screen goes, so the next file
  starts from the same desktop (`LiveCase.tearDownClass` → `Session.tidy_after`): the windows
  it opened close, notifications and their pop-ups clear, and open panels close. What it found
  is noted, a line per class, in `tests/out/live/<part>/left-behind.txt`: the tests there are
  the ones that should tidy up after themselves. Nothing fails for it (some leave a window
  for the next test in the same class on purpose).

The code is `tests/lib/parallel.py`, which starts `tests/lib/runner.py` once per part.

## The live and visual tiers need vkms

Hyprland needs a graphics device even with nothing to show, so these tiers borrow the kernel's
virtual one, `vkms`. Load it once per boot:

```sh
sudo modprobe vkms
```

Or have it load at every boot, so you never have to think about it again (once, ever; `tests/run`
says the same when it's missing):

```sh
echo vkms | sudo tee /etc/modules-load.d/slate-tests.conf
```

`sudo rm /etc/modules-load.d/slate-tests.conf` stops that.

It isn't used as a screen: Hyprland draws in software (llvmpipe) to a headless output inside
the container, which is why screenshots are the same on every machine. (The container shares
your `/sys`, so `tests/run` hides `/sys/class/leds` from it: your keyboard's lights, Caps Lock
among them, would otherwise show on the lock and login screens.) Your own Hyprland sees
the virtual card too, as a screen called `Virtual-1`: loaded before you log in, Hyprland would
turn it on and draw to it, unseen, which keeps it busy and makes the desktop lag. Slate's
Hyprland config turns vkms's screens off (`monitors.lua`; found by the vkms device in `/sys`,
so a virtual machine's own `Virtual-1` is left alone), as they arrive too, and the tests'
session turns on the one it uses. A rule of your own for it in `~/.config/slate/hypr/monitors.lua`
still wins. `sudo modprobe -r vkms` takes it away again. GitHub's runners load it the same way. One card is enough for every session
of a run: none of them needs it to itself.

## When a screenshot changes

A visual failure prints the scene and its diff (`tests/out/visual/<scene>.diff.png`, the
changes in red; `.actual.png` beside it). A visual run with changes also writes one page to look
at them all on, and `tests/run` prints its path: `tests/out/visual/review.html`. Open it in a
browser: each changed scene has its approved picture, the new one and the difference side by
side (click one for full size), with a tick box. A scene with no approved picture yet says so,
and one taken before Slate's code last changed starts unticked (`--approve` would leave it
alone). At the top is the `tests/run --approve …` line for the ticked scenes, with a Copy
button. It's a plain file (no network; the approved pictures are copied beside the others as
`<scene>.approved.png`), dark unless your browser is set to light, and approving brings it up to
date. `python3 tests/visual/review.py` builds it again from what's in `tests/out/visual`
(the code is next to `approve.py`).

If the change is meant (you changed how something looks), approve it:

```sh
# look at tests/out/visual/review.html (or <scene>.actual.png) first, then:
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
center's uptime).

The scenes run one after another in one Slate session, and each starts with no notifications
(a pop-up or the bell's count from an earlier scene once showed up in later pictures). One thing
does carry over: Qt's text smoothing depends on what it has drawn before, so a scene run on its
own (`--filter`) can differ from the same scene in a whole visual run by faint edges on text and
icons (a "16×16 area" or a fraction of a percent, on text). The approved pictures come from whole
runs: approve from a whole visual run (`tests/run --tier visual`), not from a filtered one, and
a faint text-edge difference in a filtered run alone isn't a change. Slate sets nothing that
would pin it (Qt here ignores fontconfig's rgba and `QT_SUBPIXEL_AA_TYPE`).

## The docs' pictures

The pictures on the docs pages (`site/docs/img/`) come from the same container and session,
set up as Slate comes (dark, its own accent, flat) with pretend apps and data:
`tests/run --docs-shots [name…]` takes them again, straight into `site/docs/img/`. They aren't
tests and aren't compared; `tests/static/test_docs.py` only checks each one on a page exists and
is described and sized. How they're made, and adding one: `tools/docs-shots/README.md`.

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
- **Quiet tests.** A test that checks something only a quiet computer can (a slide drawn
  frame by frame, every icon ready before its row comes into view) is marked `@slate.quiet`.
  In a run of several parts side by side, every part leaves it out, and once they've all
  finished it runs in a part of its own, `quiet`, on a computer that's quiet by then; a run in
  one part (`--jobs 1`, CI) runs it where it is. Mark it, never loosen what it checks; most
  tests that fail under load have a wait to fix instead (see Shaking them out on purpose).
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
  A real pointer, pressing, moving and letting go as a mouse does (hyprctl's movecursor gives
  no hover or buttons): `with Pointer(s.env, s.width, s.height) as p: p.drag((x, y), (x2, y2))`
  from `tests/lib/pointer.py`, in Hyprland's pixels (Hyprland's virtual pointer). Use it where
  a test hook would skip what lies over the thing pressed (Nova's title and edges).
- **visual**: add a scene to `tests/visual/scenes.py`, then
  `tests/run --tier visual --filter <scene>` (it fails: no approved picture yet), check
  `tests/out/visual/<scene>.actual.png`, and `tests/run --approve <scene>`. A scene's steps
  are IPC calls, `("!command", …)` (run in the session, waited for), `("&command", …)` (left
  running in the session until the scene ends, like the pretend media player
  `tests/lib/fake_mpris.py`, or a window) and `lambda st: …` (a wait on the state). The
  undo runs its IPC calls and commands, then stops the `&` commands, then its waits (for what
  they showed to be gone). Anything that changes by itself is made fixed rather than masked
  where it can be: `fake_mpris.py --still --art <file>` keeps the track where it is, with a
  fixed cover, and the windows in the switcher and overview scenes are terminals showing a
  fixed text with the cursor hidden and no prompt (`_still_window` in scenes.py).

A bug found by a test but not fixed yet: mark the test `@unittest.expectedFailure` (unit), or
add the log line to `KNOWN_ISSUES` in `tests/lib/session.py` (live), with a comment. Take it
out when it's fixed.

## Slate's test mode

The Slate the live tier starts has `SLATE_TEST=1`: no sounds, welcome, startup apps, update
checks or prompts, a fixed time on its clocks (`SLATE_TEST_TIME`), `$XDG_RUNTIME_DIR/slate-ready`
once loaded, and the `test` IPC target. See ARCHITECTURE.md → Test mode.

The lock screen is tested for real (`tests/live/test_lock.py`): the session locks, and PAM
checks the password. `tests/container/entry.sh` gives the container's user one, and its own
`pam_faillock` count. In test mode only, the `lock` IPC target takes a password as if typed
(`submit`: PAM still decides) and a `faillock.conf` to read in place of the system's
(`faillockConf`); outside it both do nothing.
