# When the menu bar's contents don't fit

A plan, not yet built. Started 2026-11-11 from a conversation with Dayle, after the bar
became arrangeable (`plans/draggable-menubar.md`). The eight open questions were answered
the same day; his decisions are under "Decided" and worked into the rest.

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

## Decided

| # | Question | Decision |
|---|---|---|
| 1 | Groups that leave together, or one ranked list? | **One ranked list**, reordered by dragging in a list UI; Slate supplies the default order |
| 2 | Slate's default order | As listed under "The overflow order" below |
| 3 | The slimming order | As proposed. Step 6 kept in a new form: see 3a |
| 3a | Collapsing | Every container gets a **collapse mode: Never, Always, When needed** (replacing the on/off collapse button). **When needed is the default**, for Slate's own arrangement and for new containers |
| 4 | Inside the "more" panel | **A plain list** of rows (icon, name, value). "Might refine more when we see it" |
| 5 | Where "more" sits | **An item placed on the bar** by dragging. It **can't be removed** or sent to the pool, only repositioned |
| 6 | What never leaves | **Power, Clock and Control centre** by default. Workspaces is on the list, last. A pinned item never leaves but **slims like the rest**: the clock may shrink to `xx:xx` |
| 7 | Overflow without a "more" button? | No. **There's always a "more" button** |
| 8 | The assistant | **Later, as one tool** for arranging the bar that covers items, containers, collapse modes and the overflow order together. Not in this plan; noted in `plans/draggable-menubar.md` too |

## The idea: two ladders

**The slimming ladder** gives up the cheapest things first, and loses nothing you can't get
back by hovering or clicking. **The overflow order** only starts when slimming isn't enough,
and decides which things leave the bar for the "more" button.

### 1. The slimming ladder

Each step is tried in turn until everything fits. Coming back is the same in reverse.

| Step | What gives | Already there? |
|---|---|---|
| 1 | Flexible spaces shrink to nothing | Yes (`bar.flex`) |
| 2 | The window title shortens, fading at its end | Yes (`winTitle.room`) |
| 3 | The window title goes; its icon stays | No |
| 4 | Text beside icons goes, longest first (the network's name before a two-digit count) | A side bar drops all of it (`!bar.vert`); edit mode has `shownLabel` |
| 5 | The clock sheds its date, then its seconds, down to `xx:xx` | No |
| 6 | Containers set to **When needed** tuck away behind their collapse button, one at a time | The button exists (`Container.tuck`); the mode doesn't |

- Text goes everywhere before anything is hidden: an icon without its text is still more
  use than an icon that's gone.
- Step 6 takes containers in the order their things come in the overflow order: the one
  holding what's minded least tucks first.
- A container that happens to be open (Always, clicked open) when room runs short closes
  straight away rather than after its usual few seconds.
- Pinned things (below) slim too: that's how the clock gets to `xx:xx`.

### 2. Collapse modes

The collapse button's switch in a container's options (the arranging panel) becomes a
three-way choice:

- **Never**: always shown in full.
- **Always**: tucked behind its button until it's clicked (a container with a button today).
- **When needed**: shown in full while there's room; tucked only when the bar runs short.

The button's icon and "At the start / At the end" stay, shown for Always and When needed.

- **Default: When needed**, everywhere.
- A container holding one thing has nothing to gain (its button is as wide as the thing):
  the mode has no effect until it holds two or more, and the choice isn't offered for one.
- Saved arrangements convert themselves: a container with `"tuck"` among its items becomes
  Always; one without becomes When needed (the new default). `barStatusCollapsed` on gives
  Slate's own status container Always, as now.
- How it's saved: today the button is `"tuck"` among a container's `items`, first or last
  (which end it sits at). The mode needs a field of its own on the container (`collapse:
  "never" | "always" | "needed"`), with the button's end and icon kept as they are.

### 3. The overflow order

One ranked list, from first to leave the bar to last. When slimming isn't enough, things
leave **one at a time**, just enough to fit, and come back in the reverse order.

Slate's own order:

| # | Item | Why here |
|---|---|---|
| 1 | Tray | Other apps' icons; least yours |
| 2 | Clipboard | A tool opened now and then |
| 3 | Screenshot | The same, and it has a shortcut |
| 4 | Game mode | The same |
| 5 | Keyboard layout | Only matters if you switch layouts |
| 6 | Bluetooth | Glanced at rarely |
| 7 | Window title | The window is in front of you |
| 8 | Window icon | Goes once its title has |
| 9 | Chalk | Has a shortcut (Super+K) |
| 10 | Spaces | Reachable from the control centre |
| 11 | Apps | The launcher has its own key |
| 12 | Notifications | Glanced at |
| 13 | Battery | Matters on a laptop |
| 14 | Wi-Fi | Missed quickly |
| 15 | Volume | Used often |
| 16 | Window mode | Belongs with the workspace dots (only shown with them) |
| 17 | Workspaces | Last to go |
| Stay | **Power, Clock, Control centre** | Never leave (they slim: the clock to `xx:xx`) |

- "Stay" is a mark any item can be given or lose; those three have it to start with.
- If enough wide things are marked Stay, the bar can still run out of room with everything
  else gone: they then run off the end, as today. Dayle's view: no screen is small enough
  for the default three to do that (under 200 px between them), and marking more is a
  choice.
- A container can end up partly on the bar and partly in "more": that's accepted with a
  ranked list, and why the panel is a plain list.

Two questions stay separate, which is the point of an order of its own:

- **Dragging on the bar** answers "where does it sit?"
- **The order** answers "how much do I mind losing it?"

### 4. The "more" button and its panel

- **An item on the bar**, placed by dragging in edit mode like any other. It can't be taken
  off the bar or put in the pool. In Slate's own arrangement it starts in a container of its
  own, just before the clock.
- In everyday use it shows only when something has overflowed, so it takes no room on a bar
  where everything fits. While arranging it always shows, to be picked up and moved.
- It opens a panel under the bar, as the bar's other panels do (`Popouts.qml`): the bar's
  colour, Panel opacity and Panel blur, the curved joins, the bar's shadow.
- Inside: **a plain list**, one row for each thing that overflowed, in overflow order: its
  icon, its name, and its value on the right ("Wi-Fi … HomeNetwork"). The rows are the
  panels' own (`RowButton`): flat, the muted hover under the pointer.
- Each row works as the thing did on the bar: a click does what its click did (most open
  their own panel, from the "more" button's place), scrolling on Volume changes the volume,
  a right-click does its right-click. The tray's icons need their menus from here too.
- To be looked at again once it exists ("might refine more when we see it").

## How it would work

### Measuring

The line already knows its length (`bar.lineLength`), what the fixed things need
(`bar.lineOthers`, `bar.lineFixed`) and what's left for the title and the flexible spaces.
Needed in addition:

- what the line *would* need at each step, without laying it out at that step first
  (laying out, measuring and trying again would flicker). Each `Segment` can say its length
  with and without its text; the clock its three lengths; each `Container` its length with
  given cells showing, or tucked;
- so: a function from (how far slimmed, how many overflowed) to a needed length, and the
  least of each that fits.

### Not flapping

Something that has given way needs clear spare room to come back (its own length plus a
margin), or a title changing length would send things in and out. The same for slimming
and overflowing. Changes are also held for a moment after the last one (a short timer), and
animated through `Config.ms`. This matters more with a ranked list than it would have with
groups: single icons mustn't drift in and out.

### Per screen, per bar

Each bar works it out for itself from the same arrangement: a laptop panel and a large
monitor will differ. A side bar uses the same ladders along its length (it has no text to
drop, so it starts at step 5).

### What's saved

- `barOverflow`: the order, a list of item ids; anything missing takes its place from
  Slate's own order.
- `barStay`: the ids marked Stay (Slate's own: power, clock, control).
- The collapse mode, on each container in `barLayout` (see "Collapse modes").
- The "more" button: an item id (`more`) in `barLayout`, always present; a saved
  arrangement without it is given one before the clock's container (as a missing flexible
  space is given one).
- Nothing is saved about the current state: it's worked out from the room there is.

### Arranging (edit mode)

- A section in the arranging panel, **"If it doesn't fit"**: one ordered list of the bar's
  things, first to leave at the top, dragged to reorder (the gap-and-carry dragging the bar
  and the dock use). Each row can be marked Stay; those sit apart at the end.
- The picked container's options: its collapse mode, in place of today's switch.
- "More" on the bar: dashed like the rest, with a gripper; dragging it off the bar puts it
  back (as the last flexible space does).
- A way to see it without a small monitor: a "narrow" preview that squeezes the bar's line
  to a chosen length while arranging, so both ladders can be watched working.
- While arranging at full width nothing is slimmed or overflowed (everything's there to be
  picked up), as text is shown now.
- Design rules as everywhere: flat, the muted hover for what's pointed at and the active
  colour for what's selected, no sheen unless asked for.

### With the rest of the bar

- "Show its text" off for an item means it has no text to drop: step 4 skips it.
- An item taken off the bar (in the pool) isn't in any of this.
- Hover descriptions still show in the window title while it's on the bar; once it has
  overflowed, they don't (as when it's in the pool today).
- Window mode only shows with the workspace dots, so when Workspaces overflows it goes too
  (they're 16 and 17 for that reason).

## Stages

1. **Measuring, and the slimming ladder's steps 3 to 5**, with the hysteresis. No new
   settings. Visible on a small screen straight away. Tests: the small-screen session
   (`tests/live/test_small_screen.py`, 853×480) with everything on the bar; a test hook to
   squeeze the line; `lineState()` already says what's showing and where.
2. **Collapse modes** (Never / Always / When needed), their conversion from saved
   arrangements, the choice in the arranging panel, and step 6. Tests for the conversion and
   for tucking under a squeezed line.
3. **Overflow with Slate's own order**: the "more" item, its panel of rows, things moving
   in and out one at a time. Tests as above, plus a visual scene of the panel.
4. **The order and Stay as settings**, the "If it doesn't fit" list in the arranging panel,
   and the narrow preview.
5. Docs and the site (`site/features.html`, README, `docs/ARCHITECTURE.md`), and the full
   test run.

Each stage leaves the bar working and can be stopped after.

## Later, not here

- **The assistant**: one tool for arranging the bar (moving things, containers, collapse
  modes, the overflow order and Stay), rather than a narrow one for this. `barLayout`,
  `barOverflow` and `barStay` are lists, which `settings_set` refuses, so until then an
  agent can't change them.
