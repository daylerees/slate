# Conventions

The rules Slate's code and copy follow, beyond what CLAUDE.md covers. Most came from the
author noticing something drift; each says what to do and why. CLAUDE.md loads this file,
so it applies to every change.

## Look and feel

### Colours: the active colour and the muted hover

- **Active colour**: the strong accent, for things that *stay selected* (the chosen row, tab
  or option, the page you're on, a toggle that's on). In code: `Config.accent` / `pop.accent` /
  `win.accent`, with the dark `accentText` (`Config.tint("#12151a")`) for text and icons on it.
- **Muted hover**: the duller fill for whatever the *pointer is over*. In code: `Config.hover`
  (the accent at 22%). Text keeps its normal colour.

Rules:

- Hover is always the muted hover, never the active colour (right-click menus once had the
  active colour on hover, and it was put back).
- Selected is always the active colour: not a grey, a tint of the accent, or only an outline.
- Both are the same in glass and flat modes: no separate grey hover for flat, no lighter hover
  laid over a card's own colour.
- One exception: something that's on and that a click turns off again (the control centre's
  quick tiles, a connected Bluetooth device; not real switches, and not a choice that stays
  chosen) goes a little lighter under the pointer, to show it can be switched off:
  `Config.accentLit` (`RowButton.toggles` in `Popouts.qml`).
- **Destructive things hover red.** Anything that removes, clears, deletes, forgets,
  force-quits or shuts down is written in the danger red and takes `Config.hoverDanger` (that
  red at the muted hover's strength) under the pointer. In code: `destructive: true` on
  Settings' `Button` and the arranging panel's `PanelButton`, `danger: true` on the panels'
  `RowButton`/`LinkRow` and on menu rows. A new destructive control must set it; a
  confirmation's red primary button is already solid red.
- Text and icons on an active-colour fill switch to `accentText` and cross-fade
  (`Behavior on color` with `Config.ms`).
- An accepted exception: a space's chosen icon uses the space's own colour.

**Gloss (the sheen in glass mode).** Only what the author specifies is glossy: anything new is
flat, with no `Gloss` / `IconGloss`. Not glossy: selections, hover fills, buttons, text boxes,
dropdowns, switches, sliders' fills and meters, chat bubbles, weather tiles, the workspace
marker, the bar panels' rows and tiles, and the notification cards in the bell panel. Glossy:
surfaces and cards themselves (panels, the bar's containers, Settings' group cards), app icon
tiles (dock, launcher, switcher), slider knobs, the switcher's and the overview's selected card,
the dock's window-preview rows, and pop-up notifications. Don't add or remove a sheen without
asking.

**Why:** one consistent language across every menu, panel and window; a sheen on small
controls and states reads as noise.

### Rounded corners go through `Config.corner`

Settings → Appearance → Rounded UI elements (`roundedElements`, on by default) squares
everything when it's off: containers, panels, buttons, switches and their knobs, the dock's
background, menus, pictures, full circles too, and windows (Hyprland's
`decoration:rounding` goes to 0).

- Every `radius:` or per-corner radius on new or changed UI is `Config.corner(<radius>)`. A
  radius handed on from another shape (`radius: parent.radius`) needs no wrapping.
- Not wrapped, on purpose: app icons and their tiles (`Config.iconCornerFor`, the Icon shape
  setting) and the workspace dots (`Config.dotRadius`; their holder, `dotHolderRadius`, does go
  square).
- Shapes drawn another way (a Canvas arc, a shader) check `Config.s.roundedElements`
  themselves: the panels' curved joins to the bar are hidden when it's off.
- The screen's own rounded corners and the bar's flare are the separate "Rounded screen
  corners" setting. The login screen's own files (`shell/greeter/`) keep their shapes.

### Animations go through `Config.ms`

Every animation's duration is `Config.ms(t)`: `NumberAnimation { duration: Config.ms(200) }`,
`ColorAnimation { duration: Config.ms(row.fadeMs) }`, `anim.duration = Config.ms(…)` in code.
`Config.ms` returns t (Normal), t/2 (Faster) or 0 (Off, or game mode); `Config.animate` is
false when they're off.

- Every new `Behavior`, `NumberAnimation`, `ColorAnimation`, `PropertyAnimation`,
  `SmoothedAnimation`… gets `duration: Config.ms(…)`.
- `SmoothedAnimation` doesn't reliably go instant at 0: also gate its `Behavior` with
  `enabled: … && Config.animate`, and where code starts one, set the value directly when
  `!Config.animate`.
- Motion driven by a clock or a FrameAnimation (like the dock's launch hop, `bounceOf`) checks
  `Config.animate` itself.
- Left alone, on purpose: `PauseAnimation` (a wait, not motion), the screensaver's drift (it's
  the feature), busy spinners (`loops: Animation.Infinite`), a notification's countdown
  (`toast.timeout`) and scrolling glide (SmoothWheel).
- Check after adding animations: `grep -n "duration:" shell/*.qml | grep -v "Config.ms("`
  should list only those exceptions.

**Why:** Slate's own animations once kept running with Animations off and in game mode; only
Hyprland's had stopped.

### Game mode covers anything costly or interrupting

Game mode (the bar's button and panel, Settings → Menu Bar → Game mode) turns off everything
costly to draw or distracting while playing, and puts it all back afterwards. **Any new visual
effect, animation, live preview or interruption checks `Config.gameMode`**, or goes through
something that already does. What it covers today:

- Glass and its sheens: `Config.glass` is `s.glass && !gameMode`, so `Config.glassGloss`,
  `Gloss`, glossy window borders and anything built on them follow. Draw with `Config.glass`,
  never `s.glass`.
- Hyprland's blur, shadows, window opacity, animations and touchpad disable-while-typing:
  overrides in `Config.hyprSettings`; terminals' own transparency through the
  `slate-game-opaque` window rule.
- Slate's own animations, through `Config.ms()` / `Config.animate`.
- Live previews: the switcher, the overview and the Spaces panel show window shapes and app
  icons instead of screen captures.
- Notifications: no pop-ups or sounds at all (urgent ones included); they still go to history.

Never change saved settings for it: override where the value is used. Turning it off calls
`Config.reloadHyprland()` so Hyprland's own values return, then Slate's settings are pushed on
top. The login screen ignores it (`Config.isLoginScreen`). When something new is covered,
update the game mode panel's list (`Popouts.qml`), its Settings description and the site.

### Scrolling views get shades, a scrollbar and smooth wheel

Anything that scrolls shows a soft shadow along its top edge once scrolled down, and along its
bottom edge while there's more below, fading as that end is reached.

- Two `ScrollShade`s: one at the top with `distance: flick.contentY`, one with
  `atBottom: true` and `distance: flick.contentHeight - flick.height - flick.contentY`, with
  `cornerRadius` matching what they sit in.
- With them: `ThinScrollbar` (with room for it only while it shows) and `SmoothWheel`.
- Check a picture scrolled partway before calling a new scrolling view done.

### Bar panels

New panels in `shell/Popouts.qml` look like the existing ones (Wi-Fi, Bluetooth, Screenshot,
Keyboard, Battery). Read one or two first and copy their structure:

- `Column { width: 300; spacing: 10 }` (280 only for narrow lists like Keyboard).
- Title: a plain `Label { text: "…"; font.pixelSize: 15 }`, no icon. If the panel switches
  something, the switch sits on the right in an `Item { height: 26 }`: the 40×22 rounded
  `Rectangle` with a 16 px knob and a `ClickTap`, copied from the Wi-Fi or Bluetooth panel.
- Status or explanation: a `Label` with `color: pop.dim; font.pixelSize: 12;
  font.weight: Font.Normal; wrapMode: Text.Wrap`.
- Sections: `Divider {}`, then a dim heading `Label { color: pop.dim; font.pixelSize: 12 }`,
  then rows. Clickable rows are `RowButton`s holding an `Icon` (16 px, `pop.dim`,
  leftMargin 10) and a `Label` with `font.weight: Font.Normal` (leftMargin 10).
- Footer: `Divider {}`, then a `RowButton` to the related Settings page (icon 0xEB20,
  "<Thing> settings") that closes the panel and runs `bin/slate ipc call settings page <page>`.
- Tiles (like Screenshot's, or Battery's power modes) use `pop.card`, radius 10, hover
  `Config.hoverOn(pop.card)`.

**Why:** the panels read as one family; an extra icon, a bolder weight or a missing footer
stands out.

### Settings pages

New or changed pages in `SettingsWindow.qml` match the existing ones:

- Look at other pages first (Dock, Appearance, Printers & Scanners) and copy their structure,
  components (PageTitle, IntroText, GroupLabel + Group, SettingRow, ToggleSetting,
  DropdownSetting, ValueSlider, Separator, Footnote) and wording.
- Every section (Group) has a GroupLabel above it.
- A new page gets its own soft pastel icon colour (`Config.pageColour`) for Colourful mode.
- Restore defaults is the page title's button, at the top (`pageKeys` for settings in
  SettingsData; a page with its own state, like Webcam, hooks its reset into the same
  button), never a separate button at the bottom.
- The exception is All Settings (the grid of pages): no label over its grid and no Restore
  defaults.
- A setting that only works while another is on (or off) is greyed out by its row, never by an
  `enabled:` or dimming of its own: `needsMet` (whether it can be used), `needs` (the line
  saying which, "Needs Glass to be on") and `needsPage` / `needsLabel` (where that setting is,
  as `win.goTo` takes them; the line goes there when clicked). A sub-option that only makes
  sense right under its switch can be hidden instead (`visible:`).
  `tests/static/test_consistency.py::test_switched_off_settings_say_what_they_need` enforces it.

**The changed-from-default hint.** A row with a `settingKey` shows a dot once changed, with a
hint giving the default (`SettingRow.defaultShown`). It must match the default as the control
shows it:

- A slider that shows a setting in other units (a 0–1 setting as a percentage:
  `value: … * 100`, `onMoved: v => … = v / 100`) sets `per: 100` on its `ValueSlider`.
- A default the control can't show (a value meaning "not set here", like `mouseSpeed: -2`, or a
  suffix worked out from the live value) gets a `defaultText` on its row, in words
  ("Hyprland's own").
- Toggles, dropdowns and plain values work by themselves, and a changed default in
  `SettingsData.qml` needs nothing else.
- `tests/static/test_consistency.py::test_slider_default_hints` enforces the first two; extend
  it if a new kind of control shows a transformed value.

### Dialogs reuse Slate's own

Every confirmation or question goes through Slate's confirmation window,
`PowerConfirm.confirmWith({title, body, button, code, danger}, onConfirm)`, the same one as
shutting down and emptying the Waste Basket. Settings reaches it as `win.confirmer`, passed in
from `shell.qml`. If it can't be reached from where you are, pass it in rather than drawing a
card of your own. The attention sound comes with it. Before building any dialog, find how
Slate already does that kind of thing and copy it.

## The assistant (Nova)

### New features reach the assistant

When a feature is added or changed, make it reachable through Slate's MCP server
(`shell/scripts/slate-mcp.py`, which Nova and any other agent use) in the same change, and say
which of these applied:

- **A new setting** (`SettingsData.qml`) is found automatically, but must be given what it
  takes (`VALUES` for text, `RANGES` for numbers) or put in `REFUSE`, and named in `NAMED` if
  `settings-index.py` can't link its row. `tests/unit/test_slate_mcp.py` fails until it is.
  Refuse anything that holds a command or a path, weakens locking, changes what keys do, or
  says where the person is.
- **Something you can do** (a panel, a mode, an action with IPC): a tool, or an argument to an
  existing one, with its tier (look / change / ask), a `doing()` line in Slate's words, and the
  lists the tools offer kept in step (`PANELS`, `LOOKS`, `MODES`: `test_lists_match_slate`).
  Anything that can't be undone or loses work is tier "ask".
- **Something worth knowing** (state someone might ask about): in `status` or a `*_list` /
  `*_info` tool, within what the assistant is allowed to see.
- **Never** a tool that runs a command, opens a file or URL, types or clicks, reads the
  clipboard or shows the screen without a fresh decision from the author.
- **Words:** the glossary in `shell/data/assistant-prompt.md` for a new term people will use
  (kept under 420 words), `docs/ASSISTANT.md`'s tool tables, and the site's assistant section.
- **Cost:** every tool's description goes out with every prompt (about 7,400 tokens for 34
  tools), so prefer an argument on an existing tool to a new tool.

**Why:** an assistant that can't see or do what's new falls behind the desktop it drives.

### The assistant's UI follows the theme

Anything in `Assistant.qml`, `NovaFace.qml`, Settings → Assistant, Nova's bar button or its
questions follows the theme, with nothing hard-coded. Before calling a change there done:

- **Colours** come from the theme: `Config.tint("#…")`, `Config.surface` / `Config.raised`,
  `Config.accent`, `Config.pageColour("assistant")`, `Config.hover` / `hoverOn`,
  `Config.shadowColour`. No bare hex, "black" or "white":
  `grep -n '"#[0-9a-fA-F]\{6,8\}"\|"black"\|"white"' shell/Assistant.qml shell/NovaFace.qml | grep -v 'Config.tint("#'`
  prints nothing.
- **Light mode** and **Tint from wallpaper** follow from `tint()`; text on the accent uses the
  window's `accentText`.
- **Colourful off**: Nova's icon and name are one colour like everything else (`pageColour`
  falls back to the accent; `NovaFace` hides itself).
- **Glass**: no translucent shape laid over another (it shows as a lighter patch); a new
  window's namespace goes in both glass lists.
- **Fonts**: `Config.s.fontFamily` and the bundled Tabler font, never a named font.
- **Motion**: `Config.ms` and game mode; looping indicators (typing dots, spinners) keep their
  own timing but stop when animations are off or in game mode.

## Words about Slate

What Slate is, the basis for anything that describes it (the site, README, the Welcome window,
Settings → About):

- A calm and premium-feeling desktop for Linux, made to give Linux a premium feel.
- All the features you'd expect from a desktop environment, and more, with everything where
  you'd expect to find it.
- Friendly to people moving from other operating systems, and to Linux hardcores.
- Sensible defaults that work out of the box, but highly configurable: Linux pros can still
  add their own overrides and configs, and for everyone else all the settings are in one
  place, the Settings app.
- The best parts, inspired by a number of operating systems and window managers.
- Blends into your personal choices (the wallpaper shapes the theme).
- As automatic as possible.

Never "premium" on its own (it suggests it costs money): say "a premium feel" or
"premium-feeling". Don't name macOS in openings (the homepage's first paragraph): say "modern
operating systems"; naming it where the inspirations are listed is fine. CLAUDE.md's Voice
rules apply on top.

## Building and shipping

### Slate is redistributed

People install Slate on Arch (and CachyOS and the like), Debian/Ubuntu, Fedora, openSUSE and
NixOS (`packaging/*.txt` and `packaging/nixos.nix`; `install.sh` reads them, "?" means
optional). What's installed on the computer you're working on says nothing about theirs.

- Every dependency a feature needs has an answer, decided when the feature is written: a
  package in every `packaging/*.txt` list (the right name per distro) and in `nixos.nix`, an
  `install.sh` step, or something bundled in `shell/` (like the Geist font). Distro packages
  are preferred over bundling large files.
- That covers commands, Python modules, QML/Qt modules, fonts referenced by name, icon and
  cursor themes, D-Bus services, and default apps the Hyprland config starts.
- Optional ones are checked at run time (`command -v`, try/except, `status === Ready`) and
  degrade gracefully with a message saying what to install, never a silent blank.
- New dependencies go in `docs/ARCHITECTURE.md`'s dependency table.
- Prefer portable interfaces (CUPS, systemd, D-Bus, gio, xdg-*, pkexec) to distro-specific
  helpers, and never hard-code paths or names from your own machine.

### Hot reload and new inline components

Adding an inline component (`component Foo: Rectangle { … }`) to a QML file Slate already has
loaded makes the hot reload fail with "Foo is not a type" (and "Type … unavailable" in
`shell.qml`). Quickshell keeps the previous version running, so nothing visibly breaks, but
the change isn't live; `slate restart --full` loads it. So after installing a change, check
the log for "Failed to load configuration", not only that qmllint passed.

Files the login screen copies (listed in `shell/greeter/files`) make Slate offer to update the
login screen even for comment-only edits, so leave them alone unless they need changing.

### Keeping a release's test cycle short

- After the first full run's failures are fixed, run the live tier several times back to back
  (or the suspect files three to five times each) before the next full run, to flush every
  intermittent test at once. A test that fails one run in three needs repeats to show.
- A test that passes alone and fails in a whole run is explained the day it's seen, not at
  release time. Every one so far has been real (a stale-position race, a watch ending too soon,
  a test leaving a mode on).
- Nothing is committed between the clean full run and the tag but the tag itself. Tidying goes
  before the run or after the release.
- When a late fix is small and its own tests have passed repeatedly, offer the author the
  choice of tagging on that plus the earlier clean run, said plainly in the release notes.
  Ask; don't assume.
- `--deps latest` can be skipped when neither Hyprland nor Quickshell has released since it
  last ran; say so in the notes.
- During long runs, give progress every few minutes without being asked.
