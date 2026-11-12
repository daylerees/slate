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

- A fake MPRIS player, for the dock's media controls and a scene of them.
- The switcher and overview with windows in screenshots (terminal contents vary).
- Restoring a Settings page's defaults from a test (it's a button only).
- More than one monitor.
- Making it faster: [faster-tests.md](faster-tests.md).

## Still listed elsewhere

- What the next release's test cycle owes: [release-testing.md](release-testing.md).
- The assistant beyond its first version (Codex, Markdown, sounds, the rest of its "later"
  list): [assistant.md](assistant.md).
- Slate without systemd on a real Artix, Void or Gentoo install: [without-systemd.md](without-systemd.md).

## Closing windows while New Space shows them crashes Slate (2026-11-12)
Reproducible: windows on two new workspaces (two terminals side by side, a photo in mpv),
Spaces → New Space open, all three closed at once → Slate dies with "The Wayland connection
experienced a fatal error: Invalid argument". One window closing on its own doesn't do it.
The log ends: closewindow, destroyworkspace (the closed windows' workspace), then
`ToplevelHandle(…) closed`, then the crash.
Not the live previews: pausing every capture on Hyprland's closewindow (all capture buffers
destroyed first) still crashed. Likely Quickshell's handling of a closed wlr toplevel handle
something in New Space still holds (wsWin.toplevel from Hyprland.toplevels, its .wayland),
or the destroyed workspace. Next: reproduce with New Space's cards stripped down (no
ScreencopyView, no WallBlur, no toplevel lookup) to find which part; check the overview and
the switcher the same way; report upstream if it's Quickshell.
