# Owed before the next release

Testing is done in one test/fix cycle before a release (CLAUDE.md, Tests), not as features are
shaped. This is the list of what that cycle has to cover. Add to it with each change; take
things off as they're done.

## Runs

- One full `tests/run -q`, fixing what fails (none has been run since the menu bar work began).
- Re-approve screenshots from one whole visual run, looking at each that changed: the glass,
  colour and gloss changes, the bar's containers, the panels, Settings and the dock all moved.
- New scenes with no approved picture yet: `panel-calendar-glass`, `panel-calendar-weather`.
- `tests/run -q --deps latest`, for the release notes.

## To look into

- `title_bars › maximise_keeps_room_for_the_bar` fails now and then in a whole run, and passes
  alone.
- The volume panel is an empty nub in the test container (no audio devices), so nothing in
  it can be pictured or driven there.
- A scene that switches glass on in the same instant as `arrange start` can show items undrawn.

## Tests to write

- Volume panel: the in-use stripes on the sliders (`test audioBusy` hook is there), the muted
  stripes and their cross-fade. Needs audio devices in the container, or a stand-in.
- Dock window previews are blurred behind with glass (only a static check of the rule so far).
- Control centre tiles and a connected Bluetooth device lighten under the pointer when on.
- Close buttons: the cross fades with its fill.
- Notification cards are flat in the bell panel, glossy as pop-ups.
- The priority window: a row dragged with the pointer (only the move hook is tested), the
  list scrolling under a held row.
- The squared corners during a switch from the real Super+Left/Right keys (the function is
  tested, the key isn't).
- An assistant tool for arranging the bar (items, containers, collapse, priority) and its tests.
- Power panel: battery health and the charging limit show only where reported; the resource
  bars go yellow above 70% and red above 90%.
- Settings → Power → Charging limit: shown only where UPower supports it, asks before
  charging to full. Not yet reachable from the assistant (no tool or setting for it).
- A notification from an app that sends no name shows its launcher's name (ZapZap did this).
- A notification whose picture can't be loaded falls back to the app's tile or the bell (it left a blank).
- Notification fallbacks: no app name (launcher's name, then one from its id, then "An app"), no title or body ("New notification"), no icon (tile, then bell).
- The bar's Apps, Spaces and Chalk icons are one pastel each in Colourful (screenshots of the bar will differ).
- The bar's default arrangement changed (Apps with Chalk in one container; Spaces, window mode and workspaces in another): `test_bar_layout.py`, `test_bar_length.py` and every bar screenshot assume the old one.
- Visual scenes assistant-empty and others wait for agent == claude, but the default agent is now none: update them.
- To look into: without glass, every control whose solid fill is swapped for the muted hover (buttons, tiles, cards: `Config.hoverOn`) animates through a brighter colour as the pointer comes and goes. `HoverFill.qml` fixes it for the three placement pickers; the rest could use it too.
- Position pickers (menu bar, dock): hovering and clicking an edge, including just beside it; needs a pointer in the test session.
- The hand pointer over everything clickable (Config.handCursor) is kept (2026-11-11): tests for it; the lock and login screens don't have it.
- All Settings: the search box stays put while the tiles or results scroll under it (needs a window short enough to scroll).
