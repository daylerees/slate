# Slate

Slate is a desktop shell for Hyprland, built with Quickshell (QML). `shell/` is Slate itself
(installed to `~/.config/slate`), `site/` is the project website, and `docs/` holds the
install, architecture and session notes. See README.md for the layout.

## Commits

Every change is committed with a [Conventional Commits](https://www.conventionalcommits.org/)
message:

```
<type>(<optional scope>): <summary in the imperative, lower case, no full stop>

<optional body: what changed and why>
```

- Types: `feat` (a new feature), `fix` (a bug fix), `docs`, `style` (formatting only),
  `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- Scope is the area touched, when it helps: `feat(dock): …`, `fix(launcher): …`,
  `docs(site): …`.
- A breaking change gets a `!` after the type or scope (`feat(settings)!: …`) and a
  `BREAKING CHANGE:` footer saying what users need to do.
- One logical change per commit; don't mix a fix with unrelated changes.

## Docs and the site

After any change that adds, removes or changes something users can see or do, update the
docs and the site to match, in the same commit or one right after it:

- `site/features.html`: the full feature list (settings, panels, shortcuts and so on).
- `site/index.html`: the feature cards and tour, when it's a headline feature.
- `README.md` and `docs/` (INSTALL, ARCHITECTURE, SESSION, …) wherever they describe it.

Only the text: screenshots and recordings are retaken only when asked.

## Voice

Everything Slate says to people (Settings, questions, notifications, empty screens, the
Welcome window, the site) is warm and friendly: a calm, kind companion, not a manual and not a
mascot.

- Talk to the person: "you" and "your", contractions, plain everyday words. Slate speaks as
  "Slate" (or "we" in the Welcome window and on the site), never "the system".
- Warm, not chirpy: no exclamation marks, no emoji, no jokes, no "Oops". Slate is calm.
- Reassure where there's something to worry about: say what stays safe ("your apps and windows
  stay open", "you can change this at any time") and that a choice can be undone when it can.
- When something goes wrong, say what happened and what to do next, kindly, without blame
  ("Slate couldn't…", not "You failed to…" or "Error:").
- Empty screens are a gentle nudge, not a dead end ("Nothing here yet. Things you copy will
  show up here").
- Stay accurate and brief: warmth never costs a fact, a warning or a shortcut, and a
  description is still one or two short sentences. Buttons stay short verbs ("Restart",
  "Remove"), and setting names stay plain nouns.
- British spelling (colour, favourite, tidy).

## Sounds

Slate's sounds are one family (soft, rounded, calm; nothing alarming) and each is tied to one
kind of moment. Anything new that fits one of these moments uses its sound, the same way:

| Moment | Sound | How |
|---|---|---|
| Pressing something: buttons, menu items, switches, tiles | click | `ClickTap` instead of `TapHandler`, `ClickArea` instead of `MouseArea` (they also turn the pointer into a hand over it, except in menus, the dock and the desktop, which keep the arrow: `hand: false` on a `ClickTap`, `cursorShape: Qt.ArrowCursor` on a `ClickArea`). Areas that only catch clicks outside a panel, swallow clicks, or drag (sliders, scrollbars) stay silent |
| Asking you something or warning you: confirmations, password prompts, questions, urgent notifications | attention | `Config.attention()` when it appears |
| Moving between workspaces or through a switcher | swish | `Config.swish(step)`, with step < 0 for left/back; nothing when there's only one item, since nothing moves |
| A notification popping up | notification | handled in `Notifications.qml` |
| Volume keys | volume-tick | handled in `OSD.qml` |
| Logging in / out, restarting, shutting down | welcome / goodbye | welcome is once per session in `Config.qml`; session actions go through `Config.sessionAction()` so goodbye plays first |

- Always play through `Config.playSound(name, which)` (or the helpers above), never `pw-play`
  or a `SoundEffect` of your own: it applies the sound's volume from Settings and loads it
  once, so it plays without delay.
- A new kind of sound gets: a generator in `tools/make-sounds.py` in the same style (the files
  in `shell/sounds/` are made by it, never edited by hand); an entry in `Config.soundSettings`
  and a `…Volume` setting in `SettingsData.qml`; a `SoundSetting` slider on Settings → Sound
  (0 = off) and a search entry in `SettingsIndex.qml`; and a line on the site.
- The lock and login screens stay silent (the login screen has no `sounds/`).
- New sounds are played for the user to approve before they're committed.

## Menus

Every right-click menu is `shell/DesktopMenu.qml`, one menu with one look: the desktop's, the
menu bar's, the dock's empty space and the dock's app menus all use it. A new menu is a
`DesktopMenu { items: … }`, never a menu window or row style of its own; anything a menu needs
that it can't do yet is added to `DesktopMenu.qml`, for every menu. (`TrayMenu.qml`, for apps'
own menus, is the one exception.)

- Items: `{ label, icon, run }`, with `{ separator: true }` between groups. `danger: true` for
  what's destructive (red hover), `active: true` for a dot (the window you're in),
  `submenu: [items]` for a menu beside it (an arrow at its end; it closes with the menu). The
  current choice is ticked with `icon: 0xEA5E`, as `Config.edgeMenu` does for Position.
- It points at what it's for: `openFrom(x, y, edge, gap)` from just off the bar or the dock (the
  dock's via `win.menuPoint`), `openAt(x, y)` with the pointer's tip on the cursor (the desktop).
- Content above the items (the dock's Downloads grid): `extra` and `menuWidth`.

## Interface size

Settings → Appearance → Interface size scales all of Slate by starting it with
`QT_SCALE_FACTOR` (`bin/slate`), so anything drawn inside the main Slate process scales by
itself. `Config.uiScale` is the factor in use. Two things escape it, and both have happened:

- **Another process that draws** (a second `qs -p …`, like the reload cover): start it with the
  scale too, as `start()` and `cover_up()` in `bin/slate` do.
- **Hyprland's pixels used as Slate's** (`hyprctl cursorpos`, a window's `at`/`size`, a
  monitor's geometry): divide by `Config.uiScale` before using them with Slate's own
  positions, and multiply what Slate hands to Hyprland in pixels.

`tests/static/test_consistency.py::test_interface_size_reaches_everything` checks both. When
you add a window, a helper process or anything that reads a position from Hyprland, think of
125%.

## Tests

`tests/run` (docs/TESTING.md) runs every test in a container, so nothing touches the desktop.
`tests/run -q` prints only failures and a summary line. It runs in parts side by side
(`--jobs`, docs/TESTING.md): a full run is five to eight minutes.

- **While features are being shaped, don't run the tests.** Lint the QML you touched
  (`/usr/lib/qt6/bin/qmllint <files> 2>&1 | grep -i "syntax\|multiple"`), install, reload and
  check the log; Dayle tries things himself as they change. The commit hook's quick unit run
  (a few seconds) is all that runs per commit. Run a test mid-way only when it's the quickest
  way to pin down a bug, or when asked.
- **Testing happens in one test/fix cycle before a release** (see Releases). Until then, note
  what each change will need in `plans/release-testing.md` as you make it: new tests to
  write, tests to update, screenshots to re-approve, things only checked by eye or not at all.
  The rules below say what's owed; the cycle is when it's written, run and fixed (live and
  visual need `sudo modprobe vkms` once per boot: ask the user to run it if `tests/run` says so).
- A visual difference you meant: look at the picture the failing run took
  (`tests/out/visual/<scene>.actual.png`, with a `.diff.png` beside it), then
  `tests/run --approve <scene>` makes it the approved one without running anything again (it
  leaves alone pictures taken before the code last changed), and commit it with the change.
  `tests/run --update-baselines <scene>` re-shoots instead, when there's no current picture.
  One you didn't mean is a regression: fix it.
- New features get tests: a script → a unit test; something on screen → a live test (and
  its state in the `test` IPC target in `shell.qml` if needed) and a scene in
  `tests/visual/scenes.py`. Anything that starts a side effect at login (sounds, prompts,
  network) checks `Config.testMode`.
- A changed feature gets its tests changed with it: new expectations, re-approved
  screenshots, tests for removed things removed. Never loosen a test just to make it pass.
- A bug gets a test that reproduces it, written before the fix where possible, so it can't
  come back.
- A bug a test finds but you don't fix: `@unittest.expectedFailure` (unit) or `KNOWN_ISSUES`
  in `tests/lib/session.py` (live), with a comment, and tell the user.

## Releases

Releases are tagged with [Semantic Versioning](https://semver.org/): annotated tags named
`vMAJOR.MINOR.PATCH` (e.g. `git tag -a v0.2.0 -m "v0.2.0"`), pushed with `git push --tags`.

- **MAJOR** for breaking changes (a `!` / `BREAKING CHANGE` commit since the last release).
- **MINOR** for new features (any `feat` commit).
- **PATCH** for fixes and everything else.

While Slate is below 1.0.0, breaking changes bump MINOR instead of MAJOR.

Before tagging comes the test/fix cycle: first write and update everything listed in
`plans/release-testing.md` (and empty it as you go), then the tests have to pass in one full
run. Do it efficiently:

1. Run `tests/run -q` (pinned packages) once.
2. Fix whatever fails, and confirm each fix by running just those tests
   (`tests/run -q --tier live --filter <name>`, a minute or two), not the whole suite.
3. When everything that failed passes on its own, run the full suite one final time.
4. If that fails, go back to step 2. Tag only after a full run with no failures; a test that
   fails now and then is a failure (find out why: it has been a real race more than once).

Then run
`tests/run -q --deps latest` (once a day: a second run that day shows the first's result;
`--fresh` only if something changed that needs it); don't block on it, but list what fails in the release notes'
Other section as a heads-up (it may break with the next Hyprland/Quickshell update).

When asked to tag or release, do both: create and push the annotated tag, then a GitHub
release for it with `gh release create <tag> --title <tag> --notes-file <notes>`. The tag
message and the release notes both carry a summary of the changes since the previous tag
(from `git log <previous>..HEAD`), grouped as Features, Fixes and Other, in plain words
for people using Slate rather than a list of commit subjects. Leave out site- and
docs-only changes unless they matter to users.

Each release also gets a section at the top of `site/changelog.html` (newest first, below the
`<!-- New releases go here -->` marker) with the same notes as the GitHub release: the tag
as its heading with the date, Features / Fixes / Other as cards, and a link to it in the
row of release links at the top. Commit it as `docs(site): add <tag> to the changelog`.
