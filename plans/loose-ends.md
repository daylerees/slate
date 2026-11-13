# Loose ends

What was left open by plans that are now built and gone from this folder. Each is small, or
waiting on something. The plans themselves are in the repository's history
(`git log --diff-filter=D -- plans/`).

## The menu bar (arranging it, and when it doesn't fit)

- **One assistant tool for arranging the bar**, covering moving things, containers, collapse
  modes, menu item priority and what always stays, rather than a narrow tool for each. Until
  then `barLayout`, `barOverflow` and `barStay` are lists, which `settings_set` refuses, so an
  agent can't change them.
- **Seen only in the test container:** a real small screen, a bar down a side, a second
  monitor, real blur, and every drag with a real pointer.
- **Slimming:** text goes one thing at a time, longest first, by its current width; an open
  "Always" container isn't closed straight away when room runs short.
- **"Try it shorter" and the bar scrolling in edit mode** don't work together (the bar slims
  then, as it would). Whether they should is still to be thought about.
- **Undrawn items in the visual harness:** with glass switched on in the same instant as
  arranging starts, three things came up undrawn. Not reproduced with a pause between. Worth a
  scene with a settle.
- **The More panel's list** was to be refined once seen in use.
- **Per-item descriptions** (`hoverText`, `hoverCode`, `hoverTile`, `hoverImage` in `Bar.qml`)
  are mostly unused since hover descriptions went: tidy away what nothing reads.
- **The branch:** merge `menu-bar-layout` to `master`, and delete it here and on `origin`.

## The test suite

- **Hide the host's keyboard lights from the test container:** it shares the host's `/sys`, so
  `/sys/class/leds` is your real keyboard (Caps Lock on during a run changed the lock and login
  screenshots, v0.29.1). The lock screen no longer reads it under test mode; an empty mount over
  it in `tests/run` would close it for anything else too.
- A fake MPRIS player, for the dock's media controls and a scene of them.
- The switcher and overview with windows in screenshots (terminal contents vary).
- Restoring a Settings page's defaults from a test (it's a button only).
- More than one monitor.
- Making it faster: [faster-tests.md](faster-tests.md).

## Still listed elsewhere

- What only a person can check (no pointer, hardware or network in the tests): "Checked by hand" below.
- The assistant beyond its first version (Codex, Markdown, sounds, the rest of its "later"
  list): [assistant.md](assistant.md).
- Slate without systemd on a real Artix, Void or Gentoo install: [without-systemd.md](without-systemd.md).

## Full runs lose a race most times (2026-11-13)

Before v0.29.0, five full runs each had one or two failures, a different test each time, every
one passing again on its own: tests that paused a set time ("settle 0.8 s, then look") rather
than waiting for what they check, losing under four sessions side by side. Fixed: the bar-layout
blanks, Settings scenes (wallpaper thumbnails), the bar's window title, the secret workspace's
note (settle whether it still shows before toggling), and 61 pauses before a read of the bar's
or Slate's state, now LiveCase.steady (ed68a5f). Visual scenes start with no notifications.
Still to do: one full run to see whether it's clean first time (the proof); pauses before a
screenshot or a hyprctl query weren't converted (each needs a look) if anything still flakes.
Seen once in a full run, never since: `live/wallpaper › no_banding_on_screen` (19 colour steps
out), passing three times alone.

## Live capture of a closing window crashed Slate: fixed in Slate, a Quickshell bug to report (2026-11-13)
Closing several windows at once while New Space (or, less often, the overview) showed them live
killed Slate: "The Wayland connection experienced a fatal error: Invalid argument", 14 ms after
`ToplevelHandle(…) closed`. On Dayle's machine (Intel, dmabuf captures) it happened one time in
two; never in the test container. Previews off, or captured once (not live): no crash. So in
Quickshell's live mode a capture that failed as its window closed was asked for again from the
closed handle. Fixed in Slate with WindowPreview.qml (every live preview: live off, frames asked
for on a timer once the first is in): 5 of 5 runs survived (New Space 3, overview 2).
Confirmed in Quickshell itself: a 30-line config with nothing of Slate's (a panel of live
ScreencopyViews of Hyprland.toplevels, the views going with their windows) died the same way in
3 of 4 runs. Reported as quickshell-mirror/quickshell#1481; very likely the same as
#1123 (open since September). A burst of windows opening (#1123's other trigger) held too: ten at
once, then all closed at once, with the overview showing, 4 of 4. Nothing left to do here until
Quickshell fixes it. docs/ARCHITECTURE.md, "Workarounds for bugs elsewhere", says how to check a new
Quickshell and take the workaround out.
Also: the dock's visual baselines (dock-drag, dock-drag-glass, dock-magnified-glass) were
approved with a stray "Backup finished" toast from an earlier scene in the full run, so run on
their own they differ; re-shoot them with notifications cleared first.

## Checked by hand, not by the tests (moved from the old release-testing list, 2026-11-12)

Tests are now written with each change (CLAUDE.md, Tests). These are what the test machine
can't do: no pointer, no radios, cameras, battery or network, and the real login screen.

- Quick switches on real hardware: Wi-Fi, Bluetooth, the power modes, mute and mic mute, the
  charging limit (and the Power page's row); airplane mode turning radios off and back (a
  Bluetooth already off staying off, Slate started with it on).
- Private Mode: the camera helper's install (pkexec, polkit rule), the camera really off and
  back (udev rule), microphones muted and restored, screen sharing refused in a browser, on
  Arch, Debian, Fedora, openSUSE (NixOS gets the note); the first-time question; Nova's window
  saying it's off. The camera indicator with a real camera (a browser, OBS via PipeWire).
- The pointer: menus at each bar edge, the desktop's flipping near the bottom, a submenu
  flipping left near the right edge, the menu pointer's shadow; the dock still magnifying and
  opening apps under an open panel (each edge, at 125%); a drag from the Control Centre page's
  pool onto a switch, and a narrow Settings window; the launcher's slow pointer (1 px steps)
  selecting a row, a resting pointer not taking it, and held Up/Down keeping the selection in
  view in a long list and the grid.
- Floating windows below the bar: a real Super+drag, a Slate title bar drag and an app's own.
- Pointer and icon themes in Nautilus, Dolphin and the dock; a theme uninstalled after it's
  chosen; Kora and Nordzy folder colours (a colour, and from the wallpaper); once per release,
  every one-click pack still downloads and matches its fingerprint (re-pin if one changed).
- GTK 3 "save changes?" dialogs (Code - OSS), light and dark.
- Spotify's tray icon (a folder-named icon) and the tray's sizing, in colour and mono.
- The lock and login arrow after a wrong password, on the real login screen once synced.
- The docs site on a phone width.

### Not covered yet

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

### To look into

- Tests that pass alone and fail in a whole run have each turned out to be real: keep running
  the live tier several times over before a release, rather than finding them one full run at
  a time ([faster-tests.md](faster-tests.md)).
- `panel-battery` differs by a few pixels on the bar when its scene is run by itself rather
  than in sequence.
- A scene that switches glass on in the same instant as `arrange start` can show items undrawn.
- Without glass, controls whose solid fill is swapped for the muted hover animate through a
  brighter colour. `HoverFill.qml` fixes it for the three placement pickers.

