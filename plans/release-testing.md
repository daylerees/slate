# Owed before the next release

Testing is done in one test/fix cycle before a release (CLAUDE.md, Tests), not as features are
shaped. This is the list of what that cycle has to cover. Add to it with each change; take
things off as they're done.

v0.28.0 (2026-11-12) cleared the list as it stood: the tests and screenshots were brought up
to date and the suite passed whole. What's below was left over from that cycle.

## For changes since v0.28.0

- **Settings → Control Centre** (the quick switches: `controlSwitches`, `SwitchBoard.qml`): a
  live test that the page opens, that changing `controlSwitches` changes the panel's tiles and
  their order (none, one, eight; unknown ids and repeats dropped), and that Restore defaults
  puts the six back; a hook in the `test` IPC target to move a switch as a drag would; scenes
  `settings-control` (new) and `panel-control` with eight; `settings-overview` re-approved (a
  new tile). The static page checks (pageKeys, pastel, index) should pick the page up by
  themselves. A unit test that `slate mcp` names the setting and refuses to change it (a list).
- **The control centre's new shape** (the clock and weather card over what's playing on the
  left; the switches on the right, the first two wide with their state, the rest two to a row):
  re-approve `panel-control` and any scene with the panel open; look at it with and without
  something playing, with no weather, with one, two, five and eight switches, at 853×480, and
  in light mode and glass. A unit-style check of `Config.controlSwitchRects` (through the
  `test` IPC target): no overlaps, all inside the column, for 0 to 8.
- **Airplane mode** (`AirplaneMode.qml`, `airplaneMode`, `airplaneRestore`): a live test
  through `slate ipc call airplane on/off` that the setting changes and nothing errors (the
  tests' computer has no radios, so what was on and comes back needs real hardware: check by
  hand, including Bluetooth that was already off staying off, and starting Slate with it on).
  The launcher's Airplane Mode toggle. Game mode and airplane mode as control centre tiles.

## Not covered yet

Most of these need a real pointer, or hardware the tests' computer hasn't got.

- Hovering: the cross on close buttons fading with its fill; the position pickers' edges; the
  lighter hover on tiles that are on; destructive things hovering red; the hand pointer.
- The volume panel: the in-use stripes on the sliders and the muted stripes (the `test
  audioBusy` hook is there; it needs audio devices or a stand-in).
- The bar's network item on a cable, and Settings → Network with real connection details.
- Settings → Power → Charging limit, and battery health in the power panel.
- Launcher → Glass, Assistant → Glass and Notifications → Glass: each window's colour and its
  own blur rule (only a static check of the rules so far).
- Interface size at anything but 100%: the reload cover, a drag from the pool in the arranging
  panel, the hot corner check after unlocking.
- The priority window: a row dragged with the pointer (only the move hook is tested).
- Squared corners during a switch from the real Super+Left/Right keys (the function is tested).
- The week's first day and the temperature unit (the date format is tested).
- Notification fallbacks: no name, no title, a picture that can't be loaded.

## To look into

- Tests that pass alone and fail in a whole run have each turned out to be real: keep running
  the live tier several times over before a release, rather than finding them one full run at
  a time ([faster-tests.md](faster-tests.md)).
- `panel-battery` differs by a few pixels on the bar when its scene is run by itself rather
  than in sequence.
- A scene that switches glass on in the same instant as `arrange start` can show items undrawn.
- Without glass, controls whose solid fill is swapped for the muted hover animate through a
  brighter colour. `HoverFill.qml` fixes it for the three placement pickers.
