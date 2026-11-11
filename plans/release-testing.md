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
