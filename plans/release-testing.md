# Owed before the next release

Testing is done in one test/fix cycle before a release (CLAUDE.md, Tests), not as features are
shaped. This is the list of what that cycle has to cover. Add to it with each change; take
things off as they're done.

v0.28.0 (2026-11-12) cleared the list as it stood: the tests and screenshots were brought up
to date and the suite passed whole. What's below was left over from that cycle.

## For changes since v0.28.0

- **Settings → Control Centre** (the quick switches: `controlSwitches`, `SwitchBoard.qml`): a
  live test that the page opens, that changing `controlSwitches` changes the panel's tiles and
  their order, that the panel always has eight (a short, repeated or unknown list is filled
  from `Config.controlSwitchList`), and that Restore defaults puts the default order back; a
  hook in the `test` IPC target to swap two switches as a drag would; scenes `settings-control`
  (new) and `settings-overview` re-approved (a new tile). The static page checks (pageKeys,
  pastel, index) should pick the page up by themselves. A unit test that `slate mcp` names the
  setting and refuses to change it (a list). With more than eight switches one day: a swap
  between the panel and "More switches".
- **The control centre's new shape** (the clock and weather card over what's playing on the
  left; eight switches on the right, two to a row, all one size): re-approve `panel-control`
  and any scene with the panel open; look at it with and without something playing, with no
  weather, at 853×480, and in light mode and glass. A check of `Config.controlSwitchRects`
  (through the `test` IPC target): no overlaps, all inside the column.
- **Airplane mode** (`AirplaneMode.qml`, `airplaneMode`, `airplaneRestore`): a live test
  through `slate ipc call airplane on/off` that the setting changes and nothing errors (the
  tests' computer has no radios, so what was on and comes back needs real hardware: check by
  hand, including Bluetooth that was already off staying off, and starting Slate with it on).
  The launcher's Airplane Mode toggle. Game mode and airplane mode as control centre tiles.
- **Ten more quick switches** (light, mute, micmute, saver, glass, chargelimit, dockhide,
  barhide, floating, clipboard) and **missing hardware** (`SwitchHardware.qml`,
  `Config.controlSwitchMissing`, `controlSwitchesHere`): a live test that pressing each tile
  (a `test` hook that presses a switch by id) changes what it should and back; that a switch
  in `controlSwitchMissing` leaves the panel and Settings and its place is filled; a swap from
  "More switches" into the panel. The charging limit moved from the Power page into Config
  (`chargeLimit…`, `askChargeLimit`): the Power page's row still works, by hand on a laptop
  that has it. Scene `settings-control` with "More switches" showing.
- **Menu bar shadow fade and the dock under an open panel.** The bar's shadow is darker
  (`barShadowShare` up to 1.4), tighter (blur 8) and fades (260 ms in, 360 ms out): re-approve
  the bar scenes that show it. Live: with a panel open, the dock still magnifies and opens
  apps, and a press on it closes the panel (`dockHole` in Popouts.qml, the PointHandler on the
  dock's `maskBox`); test with the dock at each edge and at 125%. Going to another workspace
  closes an open panel.
- **Lock and login avatar border** widened to 8 px (circle 140, picture 124), the middle
  lifted 4 px: re-approve `lock-preview` and `login-preview`.
- **Control Centre page: More switches beside the panel's switches**, the picture fading away
  behind them (`SwitchBoard.qml`, `side`): re-approve `settings-control`; live: a drag from the
  pool onto a switch still swaps them, and a narrow window still fits (k down to 0.6).
- **Private Mode** (`PrivateMode.qml`). Written and passing: `test_private_mode.py` (portal
  capture off/on/keep, the camera helper refusing without root), `test_screenshot.py`
  PrivateMode, `test_slate_mcp.py` Gate private mode. Owed: a live test (`private on` over
  IPC in test mode: the assistant's status says private, Nova's window says it's off, the
  control centre tile lit, the launcher toggle), and a scene of the first-time question.
  By hand only: the camera helper's install (pkexec, polkit rule), the camera really off
  and back (udev rule), microphones muted and restored, screen sharing refused in a browser,
  on Arch, Debian, Fedora, openSUSE; NixOS gets the "add it to your configuration" note.
- **Camera in use** (`scripts/camera-watch.py`, `Config.cameraOn`). Written: `test_camera_watch.py`.
  Owed: a live test that the OSD's "Camera on · <app>" / "Camera off" note shows (a test hook
  setting `Config.cameraOn`, or SLATE_DEV in the session), the bar's camera item (`barShowCamera`:
  its icon and hover both ways, no click, placing it in edit mode), and
  scenes for the note and the item. By hand: a real camera in a browser and in OBS (via
  PipeWire: shows as PipeWire).
- **Sound and Webcam pages in Private Mode**: a "Private Mode is on" card with Turn off at the
  top of each; the microphone's mute switch held on; the Webcam page's camera groups hidden and
  looked at again after it's off. Owed: scenes of both pages with `privateMode` on, and a live
  check that Turn off turns it off.
- **One right-click menu, with submenus and a pointer** (`DesktopMenu.qml`, now also the dock's
  app menus and its empty space). Owed: live tests that the bar's menu has Position with the
  four edges (the current one ticked) and picking one moves the bar; the dock's empty space
  opens Auto-hide / Position / Dock settings; the submenu closes with the menu (Escape, a
  click outside); the dock's app menus still work (windows, actions, Pin, Close, Force Quit,
  Downloads' grid, trash). Re-approve `dock-menu` and any scene with a menu (the pointer and
  the icon column moved). By eye: the pointer on the bar's menu at each edge, the desktop's
  at the cursor (and flipped near the screen's bottom), a submenu flipping left near the right edge.
  Also: an open menu (desktop, bar, dock, tray) closes on a workspace change and when the
  launcher, Nova, a picker, the switcher or the overview opens (`Config.closeMenus`); the
  pointer's shadow follows it (`Shadow.pointAt`), no gap and nothing showing through.
  The bar's menu also has Clock (12/24-hour, Seconds) and Menu bar settings; the dock's empty
  space Hover effect, Icon size (32/40/52) and Show (`Config.choiceMenu`, `Config.tickItem`):
  live checks that each sets its setting and the tick follows. Separators: faint text colour
  (visible over glass).
- **Launcher selection** (`Launcher.qml`): quicker slide (110 ms, eased in 35 ms; 50 ms when the
  pointer moves it), and `keepInView` (the row's own place, checked again once a scroll ends).
  Owed: a live test that holds Down/Up through a long list (and after typing, and with the
  grid) and checks the current item is inside the list's view at the end; it was seen leaving
  the top now and then.
  Bug, owed a regression test: a slow pointer (1 px per event) never selected a row, as each
  event was measured against the one before (`lastPointer`); now against the last one acted
  on. Live: move the pointer over a row in 1 px steps and check it's selected; and a pointer
  resting where the launcher opens doesn't take the selection. Also: a wrap (held Up/Down,
  Tab) jumps (`jumpTo`), and the pointer's highlight doesn't slide.

- **Chalk renamed Nova, with a north-star icon (0xF014)**: every word people see, the bar item
  id (`nova`; saved `chalk` mapped by `Config.barId`), the test IPC (`test nova`), the briefing's
  `[nova]` blocks. Re-approve `bar-nova` (was `bar-chalk`, renamed) and every assistant scene,
  the Settings → Assistant scenes and any confirmation showing its icon. A live test that a
  saved layout with "chalk" still shows the button.

- **Floating windows kept below the menu bar** (`slateKeepUnderBar`, windowrules.lua; a
  non-consuming left-button release bind in binds.lua). Owed: a live test that drags (or moves
  with hyprctl, then a synthesised release) a floating window to y = 0 and checks it ends at
  the bar's bottom plus the title bar's height, with Slate Bars and with hyprbars, at 125%; and
  that a click on anything still works (the bind takes nothing). By hand: Super+drag, a Slate
  Bar drag and an app's own title bar drag.

- **GTK 3 message dialogs square inside Hyprland's rounding** (`gtk_css`, slate_apps.py: adw-gtk3
  rounds them 15 px, Hyprland 10 px, and the gap showed at the bottom corners). Owed: a line in
  `test_apply_theme.py` that the GTK 3 slate.css has the rule (and GTK 4's doesn't). By eye: a
  Code - OSS "save changes?" dialog, light and dark.

- **Default apps reach Hyprland once the apps have loaded** (`hyprSettings` depends on
  `DesktopEntries`; before, Slate started before the entries loaded and FILE_MANAGER stayed
  Hyprland's first guess, Dolphin). Bug, owed a regression test: live, with
  `defaultFileManager` set, FILE_MANAGER in Hyprland is that app's command after a start and
  after a Hyprland reload.

- **Pointer style and Icons** (`cursorTheme`, `iconTheme`; `icon-themes.py`, `appicon.py` theme
  chain, `slateApply` cursor_theme, apply-theme's cursor name). Written and passing:
  `test_icon_themes.py`, `test_apply_theme.py` cursor test. Owed: a live test that setting
  `cursorTheme` changes Hyprland's CURSOR_THEME (and "" brings back the session's), and that
  `iconTheme` moves `Config.tileDir` and redraws; scenes of Settings → Input and Appearance with
  the new rows. By hand: a Breeze or Adwaita choice in Nautilus, Dolphin and the dock; a theme
  uninstalled after choosing it.

- **One-click pointer and icon packs** (`theme-packs.py`, `ThemePacks` in SettingsWindow.qml).
  Written and passing: `test_theme_packs.py` (install, fingerprint, nothing outside, links
  within the pack, a zip's links, every real pack pinned). Owed: a live check that Install → "Installing…" → "Installed", the
  dropdown above lists it, and a failure (no network) says so kindly; scenes of the two new
  sections. By hand, once per release: every real pack still downloads and its fingerprint
  matches (GitHub archives are meant to stay byte-identical; if one changes, re-pin it).

- **Folder colour for themes with plain coloured folders** (Kora, Nordzy: `simple_root`,
  `build_simple`, `vivid` in folder-colour.py). Written and passing: three tests in
  `test_folder_colour.py`. By hand: Kora and Nordzy chosen in Icons, with a colour and with
  "From the wallpaper", in Nautilus. Also the Icons default listed by name ("Papirus (default)").

- **Wallpaper and Icons as pages of their own** (from Appearance's top section; `wallpaperPage`,
  `iconsPage`; "settings page wallpaper" is the page now, not Appearance scrolled). New scenes
  `settings-wallpaper` and `settings-icons` need first baselines; re-approve `settings-appearance`
  and `square-settings-appearance` (and any scene of the dock's launcher menu). Live: the
  desktop's "Change wallpaper…", the dock launcher menu's Wallpaper and `slate ipc call settings
  page wallpaper` open the Wallpaper page; Restore defaults on each new page. Also fixed:
  search found nothing on Control Centre (the switch board has a label now).

- **One shadow look, set in Settings → Appearance** (darkness, softness, spread, distance,
  direction: `shadowDarkness`…`shadowDirection`; spread in shadow.frag). Owed: a unit/static
  check that the five reach Shadow, MultiEffect, RectangularShadow and Hyprland; scenes at the
  defaults and at a far setting (soft, spread, 90°).
- **One shadow look, closer and harder, and a Shadows switch** (an experiment: `Config.shadowReach`
  10, `shadowDrop` 2, `shadowEffectBlur`; Hyprland's range 10, render_power 4; `Config.shadowsOn`
  = `s.shadows` and not game mode). Every scene with a shadow needs re-approving (most of them).
  Owed: a static test that no Shadow sets its own blur or dropY (only direction), and that every
  MultiEffect/RectangularShadow shadow follows `Config.shadowsOn`; a live test that the switch
  turns Hyprland's shadow off and back. Login screen: needs the greeter synced to show it.

- **Workspace dots: a limit, and scrolling** (`WorkspaceDots.qml`, used by the bar (6), OSD,
  switcher and overview (10)). Owed: a live test with 13 workspaces that the bar's row is 6 dots
  wide, holds the active one in the middle, and reaches the end at the first/last; scenes with
  many workspaces (bar, OSD), circles and squares, and a side bar. Bug fixed on the way: `first`
  set in onCompleted cut its binding (the row never scrolled): a regression test for that.
- **Docs site** (`site/docs/`, `tests/static/test_docs.py`): checked by the static test; by eye,
  a few pages on a phone width.

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

## Menu keys and tray icon sizing (2026-11-12)
- Live: open a DesktopMenu (bar right-click), Down/Down/Enter runs the second item; separators skipped; Right enters a submenu (Session), Left/Escape back out, Escape again closes; Home/End.
- Live: a tray item whose icon has a wide transparent margin is grown (trayBox.grow > 1) and one that fills its square stays at 1; needs a test tray item (StatusNotifierItem) with a padded icon.
- By eye: Spotify's tray icon (Kora panel icon) matches the others, in colour and in mono.

## Launcher keeps the top result selected as results arrive (2026-11-12)
- Live: search "24*7" a character at a time, quickly; the "= 168" answer row is selected (it used to end on "Search the web", the answer arriving after and going in above). Moving the selection by key or pointer, then a late result, keeps your choice.

## Overview: moving a workspace keeps its layout and previews (2026-11-12)
- Live: overview with live previews, lift a card (hold) and move it along. The two workspaces swap numbers (Config.swapWorkspaces, Hyprland's workspace.change_id) rather than their windows moving: each keeps its split as it was (it used to come out flipped) and its previews keep updating (they went blank). Their names and window modes go with them.
- Unit/static: swapWorkspaces swaps workspaceNames and workspaceModes entries.

## Desktop pointer (2026-11-12)
- Static: Wallpaper.qml's desktop-wide right-click area is a MouseArea, not a ClickArea (a full-screen area turning the pointer into a hand). Maybe a consistency check: a ClickArea that fills a whole window is suspect.
- Static: menus (DesktopMenu, TrayMenu) and the dock (its pointer ClickArea, preview cards, Downloads grid) keep the arrow: ClickTap `hand: false`, the dock's ClickArea `cursorShape: Qt.ArrowCursor`; ClickTap's `hand` defaults to true elsewhere.
