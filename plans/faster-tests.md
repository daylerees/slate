# Faster tests

A full `tests/run -q` takes about 24 minutes. This is a plan for bringing that down, mostly by
running things at the same time. Nothing here is built yet.

Written 2026-11-11, during the test cycle for the release after v0.27.0.

## Where the time goes

Measured over four full runs that day (3,916 tests):

| Tier | Time | How it runs |
|---|---|---|
| static + unit | about 1.5 min | one Python process, no display |
| live | about 18 min | 19 test files, one after another, in one Hyprland + Slate session |
| visual | about 3.5 min | 97 scenes, one after another, in a session of its own |

So nearly all of it is the live tier, and nearly all of that is waiting: for Slate to settle, for
a window to open, for a fixed pause to pass.

## What stands in the way

- **One virtual card.** Hyprland renders through the `vkms` card (`tests/run` finds it and passes
  it in as `SLATE_TEST_CARD`; `AQ_DRM_DEVICES` in `tests/lib/session.py`). A session takes the
  card for itself: a second one at the same time can't use it. So two sessions need two cards.
- **Software rendering.** Each session draws with llvmpipe, which is heavy on the processor. On
  an 8-core machine three or four sessions at once is probably the most that helps.
- **One shared session.** `Session.shared()` starts one session per run and every live test
  reuses it. Tests lean on that: several of the failures in the 2026-11-11 cycle were one test
  leaving something behind for the next (arranging mode left on, a notification still up, a
  window on another workspace). Splitting the tests up changes what runs before what.
- **Fixed pauses.** Many live tests wait a fixed half second or second (`self.s.settle(…)`)
  where they could wait for the thing they're waiting for.

## Steps, easiest first

Each step stands on its own and can be measured before going on to the next.

### 1. Run the tier with no display beside the others

Static and unit need no card. Run them in one container while live runs in another, and collect
both results at the end. Visual still waits for the card.

- Change: `tests/run` starts two containers for `--tier all` and merges their summaries (the
  failure lines, the pass count, the exit code).
- Gain: about 1.5 minutes. Small, but nearly free, and it builds the "several containers, one
  result" plumbing the next step needs.

### 2. Several virtual cards, and the live tier in shards

This is the big one.

- **Cards.** The kernel here (7.3) has vkms's configfs support (`/sys/kernel/config/vkms`
  exists), which makes extra vkms devices. It needs root, once per boot, like `modprobe vkms`
  does now. A small script (`tests/vkms-cards <n>`) that the user runs with sudo, and
  `tests/run` using however many cards it finds: one card, today's behaviour; three cards,
  three shards. On machines or kernels without it, nothing changes.
- **Shards.** `tests/run --shards N` (or by itself when it finds N cards) splits the live test
  files into N groups, one container and one card each. Split by file, not by test, so a
  file's tests keep their order and its own `setUp`. Balance the groups by how long each file
  took last time (kept in `tests/out/`), so one shard isn't left with all the slow ones.
- **Visual** goes in as one more group, on whichever card frees up first, or as its own shard.
- Gain: live from about 18 minutes to about 7 with three shards. The whole run to about 9 or 10.

Before building it, check one thing: whether Hyprland can run entirely headless here, with no
DRM card at all. If it can, the cards aren't needed and any number of sessions can run side by
side. `session.py` notes that vkms has no render node and buffers go through shared memory, so
the card may be doing less than it seems. Half a day's experiment could remove the need for
root altogether.

### 3. Tests that don't depend on the one before

Sharding only gives trustworthy results if a file passes whatever ran before it.

- `Session.reset()` closes Slate's own windows between tests. Add what it misses: end arranging
  mode, dismiss notifications, close app windows, go back to workspace 1, clear each
  workspace's mode, put the workspace animation back.
- Run each live file on its own once (`--filter <file>`) and fix whatever only passed because of
  an earlier file. Then run the files in a shuffled order once (`--shuffle`, to add) and fix what
  that shows.
- Keep one sequential run as the last step before a release for now (CLAUDE.md, Releases), until
  the shards have agreed with it for a few releases.

### 4. Wait for the thing, not for the clock

- Replace fixed `settle()` pauses with `wait(lambda st: …)` on Slate's state wherever the test
  is waiting for something Slate can report. Where it can't yet, add it to the `test state`
  output in `shell.qml`.
- Do this file by file, slowest first, measuring each. No test should get looser: the condition
  waited for has to be the one the pause was standing in for.
- Gain: unknown until tried. A guess from reading the tests is a third off the live tier, on
  top of what sharding gives.

### 5. Smaller wins

- **Start the session once for both tiers.** Visual starts a session of its own after live has
  stopped one. Sharing it saves a start-up, a few seconds.
- **Only what changed.** A `--changed` option that maps changed files to the tests that cover
  them, for use while working. Not for releases.
- **`--deps latest`** already keeps its result for the day. Leave as is.

## What not to do

- Don't run two sessions on one card to "see if it works": they fail in ways that look like
  real failures.
- Don't shard by individual test. Start-up per shard and lost ordering inside a file cost more
  than it saves.
- Don't loosen a test to make it pass in a new order. A test that fails out of order has found
  something, in itself or in the one before it.

## Order of work, and what "done" looks like

1. Step 1, measured. (An afternoon.)
2. The headless experiment from step 2. (Half a day.) It decides whether the cards script is
   needed.
3. Step 3's reset and the file-by-file pass. (A day or two: it's where the surprises are.)
4. Step 2's shards.
5. Step 4, as time allows.

Done is: `tests/run -q` gives the same pass and fail lines as a sequential run, in under ten
minutes on this machine, on three consecutive runs; and `docs/TESTING.md` says how to set up the
cards and what `--shards` does.
