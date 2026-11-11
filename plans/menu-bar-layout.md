# Plan: arranging the menu bar by drag and drop

Status: **planned** (2026-11-11), nothing built. What Dayle asked for, in his words, then how
I'd build it. Nothing here is decided beyond the "asked for" list.

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

## What the bar is today (checked in `shell/Bar.qml`)

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

## Built so far (branch `menu-bar-layout`)

- **The bar is one arranged line** (`771c335`): `Config.barLayout` (the saved list, tidied,
  or Slate's own), `arrange()` in `Bar.qml`, flexible spaces sharing the room left over, the
  title's room worked out from what the rest needs.
- **Every item is a cell, every container is made from the arrangement** (the commit after):
  `Segment` is now the one kind of thing on the bar (alone or in a group, with its own icon
  and value or whatever is put inside it), `Container` the rounded shape that holds one or
  several, with the tuck-away mechanics the status group had. All items are written once in
  `parked` and only ever handed to a container: an item taken off a showing line and put
  back in the same instant kept its size and place but was never painted again.
- Checked with Slate's own arrangement against the approved `desktop` and
  `bar-every-button` screenshots: pixel for pixel the same, but for the Wi-Fi and volume
  swap made just before. The bar's live tests pass.
- Carried over as they were: the tray's own tuck-away (`barTrayCollapsed`, inside the tray
  item) and the status container's (`barStatusCollapsed`, as `tuck` on that container in
  Slate's own arrangement). Both become the collapse item of 14.

## Things to settle while building

- Whether the window mode icon and the workspace dots are two items or one.
- Side bars and second screens: one layout for all (as now), unless asked otherwise.
- The assistant: `barLayout` is a list, so `settings_set` refuses it; whether a tool should
  offer "put Wi-Fi after the volume" is its own decision.
- Tests: default layout leaves every bar baseline unchanged (static proof of 4); live tests
  for moving, grouping, pooling and tucking; visual scenes for the editor.
