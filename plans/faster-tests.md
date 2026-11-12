# Faster tests, and a shorter release day

Two aims: a full `tests/run -q` in a few minutes, and a release cycle that is one run and a
few fixes. v0.28.0 took three and a half hours from "release" to the tag; a run was 24 minutes
and there were five of them.

Written 2026-11-11, rewritten 2026-11-12 after the first parallel run.

## What's been found

- **The vkms module is needed.** Hyprland 0.57 (aquamarine 0.16) won't start without a display
  card, even for a headless output: with none it stops at "Cannot open backend: no allocator
  available". There's no headless-only switch in this build, and running it inside another
  compositor was ruled out in the first spike.
- **One card is enough.** Several sessions can use the same vkms card at once: the card's own
  screen is switched off and everything is drawn on a headless output, so no session needs the
  card to itself. Tried with three, then four, all passing. So no extra cards, and no script
  to make them. (A comment in `tests/lib/session.py` says a session gets the card to itself on
  CI. Not checked again; CI stays one after another until it is.)
- **Sessions side by side don't slow each other much** on this 8-core machine: the files'
  times added up to about the same with four at once as one after another.

## Done

`tests/run` runs in parts: static and unit in one container, and the live and visual files
shared out over `--jobs` containers, each with its own session (`tests/lib/parallel.py`; the
runner's `--only` and `--part`). Files are never split. They're shared out by how long each
took last time (`tests/out/durations.json`). Default: half the processors, four at most; one
on CI, when re-shooting screenshots, and for static/unit alone.

| Run | Time | Result |
|---|---|---|
| One after another (before) | about 24 min | |
| Four at once, nothing known about durations | 7 min 58 s | 3881 of 3883 |
| Four at once, shared out by the first run's durations | 5 min 42 s | 3883 of 3883 |

The four parts of the second run finished within 26 seconds of each other. (3883, where the
release run counted 3943: the 60 are the switcher checks that were collected twice until the
last commit of v0.28.0, 36 + 24 of them.)

Still open:

- `live/settings › back_on_its_page_after_a_reload` timed out once in the first run (Settings
  wasn't back 14 seconds after a reload) and passed in the second, and on its own. Either the
  reload is slow with four sessions drawing, or it's a real race: find out with repeated runs
  under load (`--repeat`, below), don't just lengthen the wait.
- A third run, and `--jobs 6`, not tried yet.

## Next, in order

Times are how long the building takes me; what really takes time is in the last column.

| # | What | Build | What takes the time |
|---|---|---|---|
| 1 | Finish parallel running: a third full run, try `--jobs 6`, the Settings reload test | 10 min | two full runs, about 6 min each |
| 2 | **No per-boot `modprobe`.** `tests/run` says how to make it permanent when the module's missing: `echo vkms \| sudo tee /etc/modules-load.d/slate-tests.conf` (once, ever). In `docs/TESTING.md` too | 5 min | Dayle running one command |
| 3 | **`tests/run --failed`**: run again only what failed last time (the runner keeps the names in `tests/out/failed.txt`), in parallel | 15 min | one small run |
| 4 | **The short path after a late fix**, in CLAUDE.md → Releases: after one clean full run, a fix to one area needs that area's tests plus static and unit, not another full run | 5 min | nothing |
| 5 | **CI between releases.** After each push, look at the run's result (`gh run list`) and put failures in `plans/release-testing.md`, so release day starts from a known list. Try `--jobs 2` on CI once, and keep it if two sessions share the card there | none | a look after each push |
| 6 | **Tests when a feature settles**, not at release: when Dayle's happy with something, write its tests then and push; CI runs them. Nothing runs locally, so "no tests while iterating" holds. CLAUDE.md → Tests | none | a few minutes per feature |
| 7 | **`tests/run --repeat N`**: the live tier N times over, reporting only what didn't pass every time. Run in the background on quiet days, so intermittent tests are found before release day | 15 min | the runs, unattended |
| 8 | **One page for approving screenshots**: before, after and difference for every changed scene, on one page, with the `--approve` line for the ones ticked | 30 min | Dayle looking once to say if it suits |
| 9 | **Wait for the thing, not the clock.** Replace fixed `settle()` pauses with `wait(…)` on Slate's state, slowest file first (`bar_layout`, `hyprbars`, `bar_length`, `switcher_animations`, `workspace_modes`, `settings` are 780 of the live tier's 1040 seconds). Needs 7 first, to catch a test turned intermittent | 1–2 h | several hours of repeated runs, unattended |

Smaller, if they turn out to matter once the above is in:

- `unit/test_slate_mcp` is 38 s of the unit tier's two minutes; unit could be split in two parts.
- Visual is one file of 97 scenes (200 s) and can't be shared out. Split the scenes over two or
  three files, or let the runner split that one file by scene.
- Start one session for live and visual in the same part (saves a start-up per part).

## What a release should look like after this

1. CI is green on the last push (5), and the tests for what changed are already written (6).
2. `tests/run -q`: about five minutes.
3. Fix what fails, `tests/run -q --failed` after each fix: a minute or two.
4. One more full run: five minutes. Approve screenshots on one page (8).
5. A late small fix takes the short path (4).

That's a release in well under an hour, most of it fixing rather than waiting.

## What not to do

- Don't shard by individual test. Start-up per part and lost ordering inside a file cost more
  than it saves.
- Don't loosen a test to make it pass in a new order or under load. A test that fails that way
  has found something, in itself, in the one before it, or in Slate.
- Don't raise `--jobs` past what the processors carry: a starved session turns pauses into
  failures that look real.

## Done is

`tests/run -q` gives the same pass and fail lines as `--jobs 1`, in about five minutes on this
machine, on three runs in a row; `docs/TESTING.md` says what `--jobs` does and how to load vkms
for good.
