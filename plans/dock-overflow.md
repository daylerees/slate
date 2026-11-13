# The dock when it doesn't fit

With lots of apps open (or something playing), the dock can grow longer than the screen's edge
and run off it. This plan makes it always fit: first by shrinking the right amount, then by
folding away what matters least, in the order below, never what you pinned.

## Where it stands

- `win.base` (`shell/shell.qml`, "Icon size at rest") shrinks the icons when they wouldn't fit
  along the edge, down to 16px. It divides the room by the **number** of slots, as if each
  were one icon wide.
- They aren't (`slotWidth(i)`): what's playing is `mediaWide` icons (3.2 with album art, 2.4
  without, 1 on a side dock), and a divider is `dividerWide` (0.35). So with something playing,
  the dock comes out about 2.2 icons longer than the shrink allowed for, and runs off the
  screen while the icons still look a sensible size. Dividers err the safe way.
- Past the 16px floor (about 45 slots on a 1080p screen along the bottom, fewer down a side)
  nothing stops it at all.

## Step 1: the shrink adds up the real widths (a fix)

- `base` sums `slotWidth(i)` for every slot, instead of using `count`. `slotWidth` is in icons
  and doesn't depend on `base`, so there's no loop.
- Keep the 48px left at the ends for magnified icons, and check it still covers the biggest
  magnification (`dockMagnification` up to its Settings maximum) at the ends; widen it if not.
- **Test first (it reproduces the bug):** a live test in `tests/live/test_dock.py` with a narrow
  strip (a side dock on the test screen, or enough pinned apps) and something playing, checking
  the dock's drawn length (`slotStarts`' end + padding) is no longer than `stripLength`. That
  needs something playing in the session: either the fake MPRIS player from `loose-ends.md`
  (worth doing now, since the media controls want it too), or a `test` IPC hook that pretends
  `mediaShown` with a title, the way `audioBusy` pretends PipeWire.
- Its own commit: `fix(dock): keep the dock on screen while something's playing`.

## Step 2: fold away what doesn't fit (a feature)

The icons shrink as now, but only to **24px**: WCAG 2.2's minimum target size (2.5.8, AA), so
nothing on the dock gets too small to hit (Small is 32). Once they're there and it still
doesn't fit, things fold away one at a time, least important first,
recomputing each time:

1. **What's playing goes compact:** the one-icon form the side dock already uses (art or a
   music note; its controls on click / its menu). `mediaWide` reads a `mediaCompact` flag.
2. **Running apps you haven't pinned go into More:** the oldest first (opened longest ago, which
   are likelier finished with), as many as needed, into one **More** slot at the end of the running apps,
   before the divider and Downloads. The folded apps keep their order among themselves, and the
   ones left on the dock keep theirs. Its tile is a **plain stack**, as Downloads' is (not a
   folder of tiny icons), with **three dots in a row** on it (a horizontal ellipsis, the same
   size and weight as the dock's other glyphs), and a badge only when a folded app has one.
3. **Pinned apps fold last, and only as a last resort:** if every unpinned app is in More and
   it still doesn't fit at 24px, the oldest-pinned go in too, rather than the icons getting
   smaller than can be used (about 33 pinned apps down the side of a 1080p screen, so it should
   hardly ever happen). The Apps button, Downloads and the Waste Basket never fold. The old
   16px floor goes.

- **The word is More**, as the menu bar's overflow already is.
- **However many fold, More stays one slot** on the dock. Its grid is laid out as Downloads' is:
  four across, three rows shown, and it scrolls past twelve (`ScrollShade` top and bottom,
  `ThinScrollbar`, `SmoothWheel`), so it never outgrows the screen. Fewer than twelve, it's just
  as tall as it needs to be. With that many open, the switcher and overview still list them all.
- **More opens a grid** of the folded apps, the same way Downloads does: a `DesktopMenu` with the
  grid as `extra` (`menuWidth` for its width), from `win.menuPoint`. Each app in it shows its
  running dot, opens/focuses on click, and its right-click is the usual app menu (as a
  `submenu`, or the same items). Nothing new to design.
- **What stays the same for folded apps:** badges still count (More shows the sum, or a dot if
  any are urgent), the switcher and overview still have them, and dragging one out of the grid
  onto the dock pins it (the dock's pin-on-drop).
- **Nothing to switch on.** It only happens when the dock wouldn't fit, so it's always on, with
  no setting. Settings → Dock gets one line of description under Icon size: "When the dock gets
  too long for your screen, Slate makes the icons smaller, then puts apps you haven't pinned in
  More."
- **Animations** go through `Config.ms` (an app sliding into More, More appearing); game mode
  needs nothing extra.
- **Interface size:** the room is `stripLength`, already in Slate's own pixels, so 125% just
  means things fold sooner. Check a scene at 125%.

## Tests (written with it, run with `--filter dock`)

- **Live** (`tests/live/test_dock.py`): with the strip made short, unpinned apps go into More
  oldest first and come back out as room returns (closing apps, a wider screen); pinned
  apps fold only once every unpinned one has, and icons never go below 24px; what's playing goes compact before any app folds; the dock's drawn length
  always fits the strip; More's grid lists the folded apps, and choosing one focuses it. Its
  state in the `test` IPC target's `dock` (`folded`, `mediaCompact`).
- **Visual** (`tests/visual/scenes.py`): `dock-more` (the dock with More showing),
  `dock-more-open` (its grid open), on the bottom and on a side, and `dock-more-scrolled` (more
  than twelve folded, scrolled part way, so the scroll shadows show).
- **Unit**, if the fold order is pulled into a plain function that's easy to test without a
  session.

## Docs, site and the assistant

- `site/docs/` (the dock's page) and `site/features.html`: what happens when the dock is too
  long, in the words Settings uses.
- The MCP server: nothing to set, but the dock's description in what Nova is told should say
  apps that don't fit are in More, so it can answer "where's my app gone?".
- `docs/ARCHITECTURE.md` if it describes how the dock sizes itself.

## Open questions

- "Oldest" means opened longest ago, which the dock doesn't track yet for running apps: record
  when each app's first window appeared (from Hyprland's `openwindow` events; for apps already
  open when Slate starts, keep the order they're listed in).

Settled with Dayle: a 24px floor (accessible), the oldest unpinned apps fold first, and More is
a plain stack with three dots in a row, whose grid scrolls past twelve as Downloads' does.
