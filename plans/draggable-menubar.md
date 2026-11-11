# Plan: arranging the menu bar by drag and drop

Status: **in progress** (last worked on 2026-11-11). Stages 1 and 2 of 5 are built and
committed; stage 3's groundwork is committed but nothing can change the arrangement from
the screen yet. **Picking this up in a new session? Read "Where it stands" and "Next" first.**

| | |
|---|---|
| Branch | `menu-bar-layout`, cut from `master` at `4b824e5`. Kept apart so the whole thing can be dropped or reverted ("do this work in a fresh changeset so we can undo it"). **Pushed to `origin/menu-bar-layout`** on 2026-11-11 as a backup only: nothing depends on it |
| Clean up | When this is merged to `master` (or dropped), delete the branch in both places: `git branch -d menu-bar-layout` and `git push origin --delete menu-bar-layout`. Then take this row and the Branch row out |
| Installed | `~/.config/slate` runs this branch's head. To go back to master's bar: check out `master`, copy `shell/Bar.qml`, `Config.qml`, `SettingsData.qml`, `SettingsWindow.qml`, `shell.qml`, `scripts/slate-mcp.py` over, `slate restart --full` |
| Tests owed | Only static + unit have been run on this branch (pass), plus the bar's live tests after stage 2 (45/45). **No full run yet.** Dayle: "we'll run a full changeset when done with all new work" |
| Screenshots owed | On `master` too: the shadows, Chalk, dock and Wi-Fi commits (`93ddd8e`, `38714f8`, `fdb8b23`, `0bd332c`) went in without re-approving screenshots, and shadows shift nearly every scene. Re-approve from **one whole visual run**, never a filtered one (a scene shot alone renders the bar's text slightly differently) |

## Asked for

1. A UI in Settings for the menu bar ("it could open in a new window or tab if you think
   it's better"), themed and consistent with the rest.
2. Drag and drop items onto the menu bar, and re-order them.
3. Put them inside containers together, or into a container on their own if they're single.
4. **It must not change how the menu bar looks**, only the order and place of things on it.
5. A "pool" of options to pick from: place them on the bar, or back into the pool.
6. A nice way to configure the expandable / hideable containers too, like the optional tuck
   away for the tray and the status icons.
7. Panels respond to where their button is: the panel of the rightmost or leftmost button
   blends with the screen edge.
8. Tuck-away containers are optional, and configurable: choose the button's icon, and the
   direction it opens.
9. Drag and drop on the actual bar, not a copy of it in Settings.
10. While that page of Settings is open, the menu bar is in edit mode: there's nothing to
    switch on.
11. Containers are things you place too: drag a container from the pool onto the bar, drag
    items into it, and click a part of it to edit its options (tuck away, icon).
12. The exception is the active window indicator (the focused window's icon and title): it
    doesn't go in a container, and its icon and text are one thing, not two.
13. The active window indicator isn't a fixed divider: it can be dragged like the rest. What
    pushes things apart is an element of its own that stands for expanding space, placed
    from the pool, as Firefox's toolbar customising has ("Flexible Space").
14. Tucking away is an item too: a collapse button in the pool that you drag into a
    container (a container holds at most one). Click it to choose its icon and direction.
    (Dayle, 2026-11-11: "I've figured out how to make a bar collapsable nicely".) This
    replaces the "Tuck away" switch on a container described below.
15. A gripper on each container while arranging, to move the container as a whole (the
    handle of 11).

## What the bar was before this work (`shell/Bar.qml` on master)

- A left row, the title area in the middle (it stretches), a right row. On a side bar the
  same, top to bottom.
- Left: the Slate mark (control centre), Apps, Spaces, Chalk, then one container holding the
  window mode icon and the workspace dots.
- Right: the tray (a container that can tuck away, `barTrayCollapsed`), the status group (one
  container of up to nine `Segment`s with separators, which can tuck away,
  `barStatusCollapsed`), the clock, the power button.
- A lone item is a `Capsule` (or `GlyphButton`); items sharing a container are `Segment`s in a
  group that works out its own separators and rounded ends from which are shown.
- What shows is a `barShow…` switch per item on Settings → Menu Bar; their order is fixed in
  the QML (the status group's is `switchedOn`, with a `slot` per segment).

So "containers" already exist in two forms, and "tuck away" exists for two of them. The
editor makes both general.

## How I'd build it

**The layout is one setting**, `barLayout`: a single list, in order along the bar (left to
right, or top to bottom on a side bar). Each entry is one of three things:

- a **container**: a list of item ids, and whether and how it tucks away;
- the **active window indicator** (`"title"`): bare, never in a container, its icon and text
  one piece (12);
- a **flexible space** (`"space"`): nothing drawn, takes the spare room (13). Any number of
  them; the room left over is shared equally between them.

```json
[ {"items": ["control"]}, {"items": ["apps"]}, {"items": ["spaces"]}, {"items": ["chalk"]},
  {"items": ["windowmode", "workspaces"]},
  "title", "space",
  {"items": ["tray"], "tuck": false},
  {"items": ["notifications", "clipboard", "screenshot", "gamemode", "keyboard",
             "bluetooth", "volume", "wifi", "battery"], "tuck": false},
  {"items": ["clock"]}, {"items": ["power"]} ]
```

That default is today's bar exactly: the left-hand buttons, the title straight after them,
then one flexible space pushing the rest to the far end. (Today the title area itself takes
the spare room and cuts its text to fit; as its own item it's as wide as its text, up to the
room there is, and the space after it takes the rest, which comes to the same picture.)

- **How room is shared.** Containers take what they need. The title takes what its text
  needs, and is the first thing to give way when room runs short (cut short with an
  ellipsis, as now). Whatever is left is split between the flexible spaces. With no flexible
  space at all, everything packs towards the start, as in Firefox.
- **A flexible space is only visible while arranging**: a faint outlined gap with a grip, so
  it can be seen, picked up and dropped. The pool's **Flexible space** chip never runs out,
  like the **Container** chip.
- **Hover descriptions** (the bar item under the pointer described where the title is) move
  with the title, wherever it's put; with the title in the pool they have nowhere to show,
  and the setting says so.

- **No change to how it looks** (4): the default layout is exactly today's bar, a container of
  one draws as today's lone capsule, and a container of several as today's status group
  (same separators, same rounded ends, same hover). The proof is the visual suite: with the
  default layout every existing bar screenshot must still match, untouched.
- **The pool** (5) is every item not in the layout. Today's `barShow…` switches become
  "is it on the bar": switching one off puts the item in the pool, and the keys stay, so
  existing settings carry over (an item switched off today starts in the pool).
- **Tuck away** (6, 8) becomes a property of any container with more than one item (and
  the tray, which is many icons in one item), off unless you switch it on for that
  container. `barTrayCollapsed` and `barStatusCollapsed` are read once to fill it in. Each
  tucked container also holds:
  - **its button's icon**, chosen from a grid of glyphs like the one the New Space panel
    has for a Space's icon (`Spaces.icons`): that grid made a shared piece, so there's one
    way to choose an icon in Slate, not two. Today the two buttons have fixed icons;
  - **which way it opens**: the button at the container's start or its end, the items
    sliding out from it the other way. Today both are fixed. The default follows the side
    of the bar the container is on, so it opens towards the middle and doesn't push its own
    button about.
  A container's entry in the layout is then `{"items": […], "tuck": true, "tuckIcon":
  "ea61", "tuckFrom": "end"}`.
- **The bar is drawn from the layout**: each item becomes a component keyed by its id, and
  each container a `Capsule` (one item) or a group of `Segment`s (several), in the order the
  layout gives. This is the large part: `Bar.qml` builds every item by hand today.
- Items that don't exist on this computer (battery on a desktop, keyboard layout with one
  layout, Bluetooth with no adapter) stay where they're placed and simply don't show, as now.

**Panels follow their button** (7). Today this is fixed by name in `Popouts.qml`:
`atScreenStart: displayed === "control"` and `atScreenEnd: displayed === "session"` make
those two panels sit flush against the start and end of the screen, square where they meet
the edge and rounded only on the corner out in the screen; every other panel is centred
under its button. Once any button can be first or last, it has to go by place: the bar tells
the panel whether the button that opened it is the first or last thing on the bar (it
already passes the button's position in `openPopout`), and the flush shape, the slide and
the shadow follow that. So the control centre moved to the middle opens as an ordinary
panel, and Wi-Fi moved to the far end opens flush against the edge.

**Arranging happens on the bar itself** (9), as pinned apps are already dragged about on
the real dock (`dragPop`, the `slate-dock-drag` overlay, `test dockDrag`): the same idea,
and the same way of drawing what's being dragged in a window of its own so it can leave
the bar.

- **Arrange mode is the page being open** (10): while Settings is showing the Menu Bar
  page, the bar is in arrange mode; go to another page or close Settings and it's an
  ordinary bar again. No button, no Done. While it's on:
  - every container on the bar is outlined, and its items don't do their usual thing when
    pressed (no panel opens): pressing picks one up;
  - **the pool** is at the top of the page: the items not on the bar, each its real icon
    with its name, and a line saying what to do ("Drag these onto the menu bar, and drag
    things off it back here");
  - drag an item along the bar to re-order it, onto a container to join it, onto the gap
    between two to give it a container of its own, off the bar and onto the page to take it
    off, from the pool up onto the bar to put it on. The other items make room as it's held
    over them, as the dock's do;
  - what you drop is the bar from that moment: there's nothing to apply. **Restore defaults**
    in the page's title puts it back, asking first, like every page.
- **Containers are placed like items** (11). The pool has a **Container** chip that never
  runs out: drag it to the bar for an empty container, then drag items into it. In arrange
  mode every container has a **handle** at its outer end (a small grip, drawn only while
  arranging, so the bar's ordinary look is untouched): drag the handle to move the whole
  container with what's in it, click it to choose that container for its settings on the
  page. Dragging an item onto the gap between two containers still gives it one of its own,
  so a container needn't be fetched first for a single item. An empty container shows only
  while arranging, as an outline to drop into; empty ones are dropped from the layout when
  the page is left. Dragging a container's handle to the page sends its items back to the
  pool.
- **A container's settings** are on the page too: click a container's handle on the bar and the page
  shows it under the pool, **Tuck away** (a switch, with what it does); while that's on,
  **Icon** (the picker) and **Opens** (towards the start / towards the end); and **Split
  up** (each item into a container of its own). Nothing selected: a line saying to click
  one.
- **Dragging between the page and the bar** crosses from an app window to the bar. The
  dragged item is drawn in a window of its own over everything (as the dock's is), and the
  window where the press began keeps getting the pointer while the button's held, wherever
  it goes. What a Wayland app can't know is where its own window is on the screen, which it
  needs to tell when the pointer is over the bar: Slate asks Hyprland for that (it already
  reads each window's place for previews). **To check first when building**; if it can't be
  made exact, the pool becomes a panel under the bar instead, which is all bar-side.
- **Every screen's bar** shows the same layout, so arranging one arranges them all; the pool
  opens under the bar you started from.
- **Settings → Menu Bar** keeps its rows for what the items show (values beside icons, the
  clock's format…); the "show this" switches stay too, as the same thing as dragging to and
  from the pool, for people who'd rather not drag (and for the keyboard: everything else in
  Settings works without a mouse).
- Drags are silent and drops click, per the sounds table. Not available in game mode's
  spirit of "nothing extra": it's a thing you start yourself, so it runs as normal.
- Tests: a `test barDrag <item> <place>` hook like `dockDrag` (the test session has no
  pointer to drag with), live tests for moving, grouping, pooling and tucking, and scenes
  for arrange mode.

A copy of the bar inside the Settings window was the first idea and is dropped: two
drawings of the bar to keep the same, and it could only ever be nearly right.

## Where it stands

**Stage 1, done (`771c335`): the bar is one arranged line.** `Config.barLayout` is the saved
list, tidied, or Slate's own (`barLayoutDefault`) when `s.barLayout` is empty. `arrange()` in
`Bar.qml` puts the line in that order. Flexible spaces share the room left over (`bar.flex`);
the title's room is what the rest doesn't need (`bar.lineFixed`).

**Stage 2, done (`7b5ea82`): every item is a cell, every container is made from the
arrangement.** `Segment` is the one kind of thing on the bar: it draws the same alone or in a
group, with its own icon and value or whatever is put inside it (`default property alias
inside`). `Container` is the rounded shape that holds one or several, made by `arrange()` for
each container in the list (`boxComp.createObject`), with the separators, rounded hover ends
and tuck-away the status group had. The items are: control (`flameBtn`), apps, spaces, chalk,
windowmode (`wsMode`), workspaces (`wsCap`), tray (`trayCapsule`), the nine status icons,
clock (`clockCap`), power; `left.things` maps names to them.

**Stage 3 groundwork, done (the commit this file came in with): the functions that change the arrangement**,
in `Config.qml`, used by nothing yet:

- `barItems` (id, label, icon, the `barShow…` key that says whether it shows), `barItem(id)`;
- `barArranging` (to be set by the Settings window), `barSelected` (the container picked);
- `barCopy()`, `barSave(list)`, `barWhere(list, id)`;
- `barMoveItem(id, to, slot)`: into the container at `to` before its item `slot`, or with
  `slot < 0` into a container of its own before whatever is at `to`;
- `barMoveEntry(from, to)`: a whole container, the title or a flexible space;
- `barAddSpace(to)`, `barRemoveEntry(at)`, `barSplit(at)`, `barSetTuck(at, tuck, icon, from)`;
- `barShown(id)`, `barSetShown(id, on)`.
- New settings `barShowControl` and `barShowClock` (the control centre and the clock had no
  switch), so every item can be sent to the pool.
- `Config.barLayout` now always holds every item (anything a saved list leaves out gets a
  container of its own at the end) and the title, so nothing can be lost.

**Decided along the way: the pool is each item's own switch.** An item is "in the pool" when
its `barShow…` setting is off; it keeps its place in the arrangement, so switching it back
on puts it where it was. Dragging to the pool switches it off; dragging from the pool
switches it on and moves it to where it's dropped. The switches on Settings → Menu Bar stay
and mean the same thing, which also gives the keyboard a way to do it.

**Checked:** with Slate's own arrangement, against the approved `desktop` and
`bar-every-button` screenshots, the bar is pixel for pixel what it was (but for the Wi-Fi and
volume swap made just before, on master). Compared by cropping the bar from
`tests/out/visual/<scene>.actual.png` and the baseline and counting differing pixels
(`magick compare -metric AE`), since the scenes themselves fail for the reasons under
"Screenshots owed". **Not checked:** side bars, a bottom bar, a second screen, the tray with
icons in it, tuck-away, hover descriptions.

**Things learnt that the next person needs:**

- **Write every item in `parked`, never on the line.** An item taken off a showing line and
  put back in the same instant kept its place and size, reported itself visible, and was
  never painted again. All items are declared in the hidden `parked` holder and only ever
  handed to a container.
- **The line (a `Grid`) passes over anything with no size**, and leaves a gap between every
  two things it does show. So an empty title has no gap of its own (`lineOthersCount` counts
  that way), and a flexible space keeps a sliver of size (0.01) so it always has its two.
  Getting this wrong moved the right-hand group by exactly one gap.
- **Don't read the title's size where its room is worked out**, or it loops: `lineOthers`
  and `lineOthersCount` leave the title out, `flex` reads it.
- **A left bar** shows the title after the flexible space that follows it (it reads upwards,
  growing up from the tray): `arrange()` swaps the two there.
- **Seeing the bar's state from a test**: `console.warn` from the bar didn't reach the test's
  error check. What worked was a temporary field in `test state` (`shell.qml`) and a
  throwaway live test that fails with it.
- **The window mode icon and the workspace dots are two items**, together by default. The
  icon still only shows when the dots do (`barShowWindowMode && barShowWorkspaces`), as it
  always did. Dayle hasn't answered whether they should be separable; they are.

**Stage 3a and 3b, built 2026-11-12, for Dayle to try by hand (no tests yet, at his
asking: "we'll run the tests at the end after I've manually tested"):**

- **Arrange mode is on while Settings shows the Menu Bar page** (`win.arrangingBar` →
  `Config.barArranging`). The bar stays out (no auto-hide) while it is.
- **On the bar** (`Bar.qml`): every container outlined with a gripper at its start (it's 14 px
  longer while arranging), flexible spaces outlined with arrows and wide enough to hold,
  the title outlined (a stand-in reading "Active window" when no window is focused). One
  `MouseArea` (`arranger`) lies over the line and works by where things are along it:
  `onLine()`, `cellsOf(box)`, `pick(a)`, `aim(a)`. An accent line shows where a thing will
  land and a ghost of it follows the pointer. A press without a drag picks the thing
  (`Config.barSelected`).
- **On the page** (`barPage` in `SettingsWindow.qml`): what to do; **Not on the bar** (items
  whose switch is off, clicked to put back; **Add one** for a flexible space, which lands at
  the end to be dragged into place); **The container you've picked** (Split up, Take off the
  bar, Tuck away; a picked flexible space or the title can be taken off too).
- Seen in the container's screenshot of the page: outlines, grippers, the space and the pool
  draw as meant, and the ordinary bar (page closed) still matches the approved picture.
  **Not tried**: an actual drag (the test session has no pointer). That's what Dayle is
  testing.
- Known gaps: the grippers and the outline of the title only read well on a top or bottom
  bar (side bars untested); a left bar's swapped title and space aren't allowed for when
  working out where a drop goes; the container that's picked stays picked by its place, so
  it's let go of after every move.

## Next

**Stage 3a's remaining part: the test hook and live tests** (below, step 5), once Dayle is
happy with how it behaves. What I'd worked out for 3a, for reference:

1. **Switch arrange mode on**: the Settings window sets `Config.barArranging` to "visible and
   on the Menu Bar page" (`win.section === "bar"`), and clears it when hidden.
2. **Give things their places**: in `arrange()`, each `Container` and flexible space gets its
   `index` in `Config.barLayout` (carry the real index through the left-bar swap), each
   `Segment` its `name`. Add those properties.
3. **Show it's being arranged** (only while `Config.barArranging`, so the ordinary bar is
   untouched):
   - each container: a thin accent outline (stronger when it's `Config.barSelected`), and a
     **gripper** at its start, about 12 px, which makes it that much longer while arranging
     (Tabler grip-vertical `0xEC01`, grip-horizontal `0xEC00` on a side bar);
   - each flexible space: at least about 22 px, outlined, with arrows (`0xEB59` / `0xEB5B`);
   - the title when it's empty: an outlined placeholder saying "Active window", so there's
     something to pick up.
4. **One `MouseArea` over the line**, above everything, only while arranging, so nothing
   underneath acts. Plain `MouseArea`, not `ClickArea`: drags are silent (sounds table); play
   `Config.click()` on a drop. It works by geometry:
   - on press, list what's on the line in order (`left.children` that are visible): kind
     (box / space / title), the object, its `index`, where it starts and ends along the bar;
   - a press on a container's gripper, a space or the title picks up that whole thing; a
     press on an item inside a container picks up the item (find the `Segment` under the
     pointer among the container's row's children; skip separators and the toggle);
   - a press and release without moving selects the container (`Config.barSelected`);
   - while moving, work out the target: for an item, inside a container (not within ~7 px of
     its ends) means **join it**, at the place between its showing cells; anywhere else is
     **the gap** before the first thing whose middle is past the pointer. A whole thing only
     ever goes to a gap. Show an accent line there, dim what's being dragged, and draw a
     ghost of it under the pointer (`ShaderEffectSource` of the item);
   - on release: `Config.barMoveItem(name, box.index, slotAmongItsItems)` or
     `barMoveItem(name, to, -1)` or `barMoveEntry(from, to)`. Map a slot among *showing*
     cells back to the item's index in the container's full list (hidden items are in it).
5. **A test hook** in `shell.qml`'s `test` target (the session has no pointer): calls the
   `Config.bar…` functions, and `state()` gains the arrangement and what's showing in order.
   Live tests for moving, joining, a container of its own, moving a container, adding and
   removing a space. The pixel-level dragging is for Dayle to try by hand.

**Stage 3b: the page.** At the top of Settings → Menu Bar: a line saying what to do; **the
pool** (items whose switch is off, each its icon and name from `Config.barItems`, plus
**Flexible space**, **Container** and the **collapse button** of requirement 14, which never
run out); and the selected container's options. Until 3c, clicking a pool chip puts it on
the bar. Add ordinary switch rows for the control centre and the clock (their keys exist;
`slate-mcp.py` names them in `NAMED` until the rows do).

**Stage 3c: dragging between the page and the bar.** The unknown. Settings is an app window
and isn't told where it is on the screen; ask Hyprland (`Hyprland.toplevels` /
`lastIpcObject.at`, as window previews do). If that can't be made exact, the pool becomes a
panel under the bar instead.

**Stage 4: tuck-away as an item** (14): a collapse button dragged into a container, at most
one each, clicked to choose its icon and direction. `Container` already has `tuck`,
`tuckIcon`, `tuckFrom` and a `toggle` cell of its own; this makes the toggle something in the
container's `items` and moves the tray's own tuck-away (`barTrayCollapsed`, still inside the
tray item) and the status container's (`barStatusCollapsed`, read as `tuck` in Slate's own
arrangement) onto it.

**Stage 5: panels follow their button** (7): `Popouts.qml` decides "flush against the screen
edge" by name today (`atScreenStart: displayed === "control"`, `atScreenEnd: displayed ===
"session"`). The bar should say, in `openPopout`, whether the button is the first or last
thing showing on the line.

**Then:** tests for all of it (live, visual scenes for arrange mode), the site and docs
(`site/features.html`, README, `docs/ARCHITECTURE.md`), the assistant (`barLayout` is a list,
so `settings_set` refuses it; decide whether a tool should move bar items, per the "new
features reach the assistant" rule), the one full test run, and re-approving screenshots
from a whole visual run. Only then merge to `master`, and delete the `menu-bar-layout`
branch here and on `origin` (it was pushed as a backup; see the table at the top).

## Things to settle while building

- Whether the window mode icon and the workspace dots are two items or one.
- Side bars and second screens: one layout for all (as now), unless asked otherwise.
- The assistant: `barLayout` is a list, so `settings_set` refuses it; whether a tool should
  offer "put Wi-Fi after the volume" is its own decision.
- Tests: default layout leaves every bar baseline unchanged (static proof of 4); live tests
  for moving, grouping, pooling and tucking; visual scenes for the editor.
