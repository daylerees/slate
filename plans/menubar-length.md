# When the menu bar's contents don't fit

A plan, not yet built. Started 2026-11-11 from a conversation with Dayle, after the bar
became arrangeable (`plans/draggable-menubar.md`). Nothing here is decided until the
"To settle" list at the end is answered.

## The problem

The bar is one line: containers, flexible spaces, and the window title, which takes the
room nothing else needs. Today, when there's too little room:

- the flexible spaces shrink to nothing;
- the window title shortens and fades out at its end;
- after that, things simply run off the end of the bar.

It happens when text grows (a long network name, the date, values switched on for
everything), when more is put on the bar in edit mode, and when the same arrangement meets
a smaller screen: a laptop panel after a large monitor, a bigger Interface size, a side bar.

Dayle, in his words: "I'd like us to do something graceful in this instance, like hide some
of the content, or put it into a button that shows overflow (below the bar in its own
container) or something like that. Not sure what makes a sensible order to pick which ones
to put in the overflow though." And then: "Maybe the overflow has its own ladder?"

## The idea: two ladders

**The slimming ladder** gives up the cheapest things first, and loses nothing you can't get
back by hovering or clicking. **The overflow ladder** only starts when slimming isn't
enough, and decides which things leave the bar for a "more" button.

### 1. The slimming ladder

Each rung is tried in turn until everything fits. Coming back is the same in reverse.

| Rung | What gives | Already there? |
|---|---|---|
| 1 | Flexible spaces shrink to nothing | Yes (`bar.flex`) |
| 2 | The window title shortens, fading at its end | Yes (`winTitle.room`) |
| 3 | The window title goes; its icon stays | No |
| 4 | Text beside icons goes, longest first (the network's name before a two-digit count) | A side bar drops all of it (`!bar.vert`); edit mode has `shownLabel` |
| 5 | The clock sheds its date, then its seconds | No |
| 6 | Containers that have a collapse button tuck themselves away | The button exists (`Container.tuck`); doing it by itself doesn't |

Text goes everywhere before anything is hidden: an icon without its text is still more use
than an icon that's gone.

### 2. The overflow ladder

An ordered list of rungs. Everything on a rung leaves the bar together, lowest rung first,
so the bar changes in a few clean steps rather than one icon at a time. What's left
overflows into one "more" button, and comes back in the reverse order when there's room.

Slate's own, to start with (to be settled):

| Rung | Leaves the bar | Why here |
|---|---|---|
| 1 | Tray | Other apps' icons; least yours |
| 2 | Clipboard, Screenshot, Game mode | Tools reached for now and then |
| 3 | Keyboard layout, Bluetooth | Status glanced at rarely |
| 4 | Window title, then Window icon | Nice to have; the window is in front of you |
| 5 | Notifications, Wi-Fi, Battery, Volume | Status you do glance at |
| 6 | Apps, Spaces, Chalk | Launchers; each has a shortcut |
| Never | Control centre, Workspaces, Clock, Power | The bar's skeleton |

Two questions stay separate, which is the point of a ladder of its own:

- **Dragging on the bar** answers "where does it sit?"
- **The ladder** answers "how much do I mind losing it?"

(An earlier idea, overflowing by position from the flexible space outward, tied the two
together: putting something in the middle of the bar quietly made it the first to go.)

### The "more" button and its panel

- One button, where the first things left from (beside the flexible space, or at the end
  that's fuller). Drawn as a bar item in a container of its own.
- It opens a panel under the bar, as the bar's other panels do (`Popouts.qml`): the bar's
  colour, Panel opacity and Panel blur, the curved joins, the shadow from the bar.
- Inside: the things that overflowed, in rung order, still in their containers, with their
  text back (there's room for it now). Each works as on the bar: click, scroll, right-click,
  and its own panel opens from the bar as usual.
- Hover descriptions and the tray's menus have to work from inside it.

## How it would work

### Measuring

The line already knows its length (`bar.lineLength`), what the fixed things need
(`bar.lineOthers`, `bar.lineFixed`) and what's left for the title and the flexible spaces.
Needed in addition:

- what the line *would* need at each rung, without laying it out at that rung first
  (laying out, measuring and trying again would flicker). Each `Segment` can say its length
  with and without its text; each `Container` its length with given cells showing or tucked;
- so: a function from (rung of slimming, rung of overflow) to a needed length, and the lowest
  pair that fits.

### Not flapping

Something that has given way needs clear spare room to come back (its own length plus a
margin), or a title changing length would send things in and out. The same for both ladders.
Changes are also held for a moment after the last one (a short timer), and animated through
`Config.ms`.

### Per screen, per bar

Each bar works it out for itself from the same arrangement: a laptop panel and a large
monitor will differ. A side bar uses the same ladders along its length (it has no text to
drop, so it starts at rung 5).

### What's saved

- `barOverflow`: the overflow ladder, a list of rungs, each a list of item ids; missing
  items take Slate's own rung; an item in no rung and marked kept never leaves.
  (Shape to settle: rungs, or one ranked list.)
- Nothing is saved about the current state: it's worked out from the room there is.
- The assistant: the list is a list, so `settings_set` refuses it, as it does `barLayout`;
  decide whether a tool should set it (the "new features reach the assistant" rule).

### Arranging (edit mode)

- A section in the arranging panel, "If it doesn't fit": the rungs as rows of chips (the
  same `BarChip`s as the pool), dragged between rungs or into "Never". Flat, the muted hover
  and the active colour as everywhere.
- A way to see it without a small monitor: a "narrow" preview that squeezes the bar's line
  to a chosen length while arranging, so the ladders can be watched working.
- While arranging at full width nothing is slimmed or overflowed (everything's there to be
  picked up), as text is shown now.

### With the rest of the bar

- The collapse button (`tuck`) stays a choice of its own; rung 6 only tucks containers that
  have one.
- "Show its text" off for an item means it has no text to drop: rung 4 skips it.
- An item taken off the bar (in the pool) isn't in any of this.
- Hover descriptions still show in the window title while it's on the bar; once it has
  overflowed, they don't (as when it's in the pool today).

## Stages

1. **Measuring, and the slimming ladder's new rungs** (3 to 6), with the hysteresis. No new
   settings. Visible on a small screen straight away. Tests: the small-screen session
   (`tests/live/test_small_screen.py`, 853×480) with everything on the bar; a test hook to
   squeeze the line; `lineState()` already says what's showing and where.
2. **Overflow with Slate's own ladder**: the "more" button, its panel, items moving in and
   out. Tests as above, plus a visual scene of the panel.
3. **The ladder as a setting**, and its section in the arranging panel, with the narrow
   preview.
4. Docs and the site (`site/features.html`, README, `docs/ARCHITECTURE.md`), the assistant,
   and the full test run.

Each stage leaves the bar working and can be stopped after.

## To settle

1. Rungs (groups that leave together) or one list ranked item by item?
2. Slate's own overflow rungs above: right, or which move?
3. Does the slimming ladder's order feel right: the window title before the status text,
   the clock's date after it?
4. In the overflow panel: things in their containers, or one plain list?
5. Where the "more" button sits when things have left from both sides of the flexible space.
6. Should a kept ("Never") item still slim (lose its text), or stay whole?
7. Whether overflow should exist with no "more" button at all as an option: things simply
   hide, and come back when there's room.
8. Whether the assistant gets a tool to change the ladder.
