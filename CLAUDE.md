# Slate

Slate is a desktop shell for Hyprland, built with Quickshell (QML). `shell/` is Slate itself
(installed to `~/.config/slate`), `site/` is the project website, and `docs/` holds the
install, architecture and session notes. See README.md for the layout.

"The author" below is Slate's author and maintainer, who decides what's built and approves it.

The conventions for Slate's look, the assistant, copy about Slate and shipping are in
docs/CONVENTIONS.md, and apply to every change:

@docs/CONVENTIONS.md

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
- `site/docs/`: the docs, a page per area (the list of pages, their sections and the Settings
  pages each covers is `site/docs/docs.js`). Change the page that describes what changed, in the
  same words Settings uses; a new area or Settings page gets a page (copy one, add it to
  `docs.js` with its `covers`). `tests/static/test_docs.py` checks every Settings page is
  covered, every page is listed, and links and headings still lead somewhere.
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
| Nova answering while you wait | answered | `Config.playSound("answered", "answered")` in `Assistant.qml`, only with the window showing (away, it's a notification) and not in game mode |
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
  scale too, as `start()` and `cover_up()` in `bin/slate` do (`ui_scale`); the login screen does
  it in `greeter/run-greeter.sh`.
- **Hyprland's pixels used as Slate's** (`hyprctl cursorpos`, a window's `at`/`size`, a
  monitor's geometry): divide by `Config.uiScale` before using them with Slate's own
  positions, and multiply what Slate hands to Hyprland in pixels. `TitleBar.qml`,
  `SpaceBadges.qml` and `WorkspaceOverview.qml` do it. Comparing Hyprland's numbers only with
  each other needs nothing; missing it once let a hot corner fire again straight after unlocking
  at any size but 100%.

Fixed pixel sizes inside QML are fine: Qt scales them.

`tests/static/test_consistency.py::test_interface_size_reaches_everything` checks both (quick:
`tests/run -q --tier static --no-container --filter interface_size`). When you add a window, a
helper process or anything that reads a position from Hyprland, think of 125%: before calling
it done, `grep -n '"cursorpos"\|\.at\[\|lastIpcObject' shell/*.qml` (every file listed uses
`Config.uiScale`, or compares Hyprland's numbers only with each other) and
`grep -n 'setsid qs' shell/bin/*` (every line carries `QT_SCALE_FACTOR`), and look at it once at
another Interface size.

## Tests

`tests/run` (docs/TESTING.md) runs every test in a container, so nothing touches the desktop.
`tests/run -q` prints only failures and a summary line. It runs in parts side by side
(`--jobs`, docs/TESTING.md): a full run is about five minutes.

- **Tests are written with the change, and run on their own.** As a feature is shaped, lint
  the QML you touched (`/usr/lib/qt6/bin/qmllint <files> 2>&1 | grep -i "syntax\|multiple"`),
  install, reload and check the log, so the author can try it; alongside, write or update its tests
  (the rules below) and run just those, in the background (`tests/run -q --tier live --filter
  <name>`, a minute or so), fixing what they find before moving on. A change is done when its
  tests are in and passing, and they go in the same commit. Nothing is saved up for later.
- **The full suite runs once, before a release** (see Releases), to catch what the change's
  own tests didn't.
- **Live and visual need the `vkms` kernel module** (Hyprland renders through it in the
  container). It's gone after every reboot, and containers share the host's kernel, so it's
  loaded on the host: `sudo modprobe vkms`. As soon as a full run or a release is asked for or
  clearly coming, check `lsmod | grep vkms` before anything else; if it isn't loaded, ask the
  author to run it straight away (sudo may not work in an agent's shell: suggest
  `! sudo modprobe vkms`, or another terminal), so it's ready by the time the tests are reached.
  Carry on with static and unit (`--tier static,unit` or `--no-container`) and other prep
  meanwhile. To load it at every boot: `echo vkms | sudo tee /etc/modules-load.d/vkms.conf`.
- The suite runs in a container and never touches the desktop, so running it needs no asking.
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
  come back: check it fails without the fix and passes with it. If a test really isn't
  practical, say why.
- Say in the summary which tests were added or changed.
- A bug a test finds but you don't fix: `@unittest.expectedFailure` (unit) or `KNOWN_ISSUES`
  in `tests/lib/session.py` (live), with a comment, and tell the user.

## Work tracking (Linear)

Slate's work is tracked in Linear, team **Slate** (key `SLT`, issues `SLT-123`), through the
`linear` MCP server. Every piece of work is an SLT issue; nothing is worked on without one. There
are no Linear projects, and no `plans/` folder (removed in d5db9bc; old plans are in git
history, `git show d5db9bc^:plans/<name>.md`). Don't recreate it to track work.

Linear structures the work, it doesn't replace the conversation: questions, approvals (asking
before every screen takeover included), progress and results still happen in the session. When
something needs the author, ask there, not only on the board.

**Linear stays out of the GitHub side.** It's fine that Linear exists, but no issue ids, links
or titles in commit messages, branch names, PRs, release notes, tags, the changelog, the site,
docs or code comments. Linear can point at the repo (commit hashes in issue comments are fine),
never the other way round. Name branches yourself, never with Linear's `gitBranchName`.

### The board

| Status | Means |
|---|---|
| Backlog | Where new issues go. Claude creates issues here. |
| Todo | The author has prioritised it for Claude. Only the author moves things here (one exception below). |
| In Progress | Claude is working on it. Move it when starting, not after. |
| In Review | Done and committed, not yet released. |
| Done | Released: move In Review issues here when tagging a release, with the version in the comment. Work with nothing to release (questions, checks, Linear-only tasks) goes straight here. |
| Canceled | Not doing it (comment why). |
| Duplicate | Same as another issue (comment which, and mark it a duplicate of it). |

- **Every move gets a short comment** saying what happened (what was done, what's left, commit
  hashes). **Every comment Claude writes starts with `(Claude)`**: the MCP acts as the author.
- The **In Review comment** is the author's pre-release checklist: what changed, how to try it, the
  commits, and which tests ran and passed.
- **Picking up work:** the author names the issue. The MCP can't read the board's order, so never guess
  one: if several are in Todo and none is named, ask. When the author says to work through Todo, pick
  the order yourself (blockers, quick wins, related work together) and pause after each. One
  issue at a time unless the author says otherwise (suggesting parallel work is fine).
- **"Watch Linear"** means poll Todo for new work and pick it up (/loop, self-paced). Otherwise
  only look at Linear when asked.
- **Relations** (blocks, related, duplicate) are Claude's call. Don't start an issue blocked by an
  unfinished one.
- **The `Blocked` label** means a problem stops progress (needs the author's decision, can't
  reproduce, something outside Slate broken, a manual step like `sudo modprobe vkms`). Add it,
  leave the issue in its column, comment what's needed; remove it with a comment when sorted,
  and move on to other work meanwhile.
- **Sub-issues** for bigger work (a plan becomes a parent with a sub-issue per step). The parent
  goes In Progress with the first sub-issue, In Review when all are In Review/Done/Canceled, and
  Done when all are.
- **Bugs found along the way** get their own issue (Bug, Area, Claude labels, related to the
  current one), not a fix inside the current one. If it breaks things for users (crash, something
  unusable, data or settings lost, a visible glitch on a common path), set its priority, put it
  straight in Todo, pick it up next and tell the author. Anything less goes in Backlog, mentioned in
  the session.

### Issues and labels

- **Descriptions:** Claude's issues have a short plain summary on top (what's wrong or wanted, and
  "Done when: …"), then the implementation detail (files, plan, repro, logs) in a collapsible
  `+++ Agent notes` … `+++` section (Linear stores it as `>>>`). The author's issues are written as
  prompts: read them as the brief.
- **Labels, sparingly:** exactly one **Work** label, every **Area** it really touches, and
  `Claude` on issues Claude creates. Nothing else, and no new labels without asking. Change labels
  with `addLabels`/`removeLabels`, never `labels` (it replaces the whole set). If the author's issue has
  no Work label, add the one that fits when picking it up and say so.
- **Work** (one): `Feature` (new or changed for users), `Bug` (broken), `Experiment`. An
  experiment never goes into a release without the author's approval: it's built on its own branch
  (`experiment/<short-name>`) from master and merged only once approved, kept contained (new
  files or one clearly marked place) with what it touches listed on the issue, and goes to In
  Review with the branch named when it's ready to judge.
- **Area** (one or more; a new setting goes under what it controls, plus Settings only if the
  Settings window itself changes; if nothing fits, suggest a new label rather than make one):

| Area | Covers |
|---|---|
| Menu bar | Bar.qml, BarEditor.qml, bar layout, tray |
| Dock | the dock, its menus, More, Downloads, now playing |
| Launcher | Launcher.qml, app search |
| Control centre | the control centre and the bar's panels (Popouts.qml) |
| Notifications | Notifications.qml, NotificationCard, OSD |
| Menus | DesktopMenu.qml, TrayMenu.qml |
| Windows & workspaces | windows, title bars, switcher, workspaces, overview, Spaces, hot corners |
| Appearance | themes, glass, shadows, wallpaper, icons, pointers, app theming, interface size, animations |
| Sound | Slate's sounds (make-sounds.py), audio settings |
| Hardware | displays, input, power and battery, network and Bluetooth, printers, webcam |
| Settings | the Settings window itself: pages, search, defaults |
| Lock & login | lock screen, login screen and greeter, screensaver, privacy |
| Session & install | bin/slate, session, reload, installer, packaging, updates |
| Welcome | the Welcome window, first login |
| Assistant | Nova, the MCP server (`slate mcp`) |
| Tests | the test suite itself and tests/run (not a feature's own tests) |
| Site & docs | site/, the site's docs, README, docs/ when they're the work itself |

## Releases

Releases are tagged with [Semantic Versioning](https://semver.org/): annotated tags named
`vMAJOR.MINOR.PATCH` (e.g. `git tag -a v0.2.0 -m "v0.2.0"`), pushed with `git push --tags`.

- **MAJOR** for breaking changes (a `!` / `BREAKING CHANGE` commit since the last release).
- **MINOR** for new features (any `feat` commit).
- **PATCH** for fixes and everything else.

While Slate is below 1.0.0, breaking changes bump MINOR instead of MAJOR.

Before tagging, the tests have to pass in one full
run. Do it efficiently:

1. Run `tests/run -q` (pinned packages) once.
2. Fix whatever fails, and confirm each fix by running just those tests
   (`tests/run -q --tier live --filter <name>`, a minute or two), not the whole suite.
3. When everything that failed passes on its own, run the full suite one final time.
4. If that fails, go back to step 2. Tag only after a full run with no failures; a test that
   fails now and then is a failure (find out why: it has been a real race more than once).
5. A small fix after the clean run (the short path): its own tests, run a few times, plus static
   and unit, not another full run. Offer the author that choice and say it plainly in the
   release notes; don't assume it (docs/CONVENTIONS.md, Keeping a release's test cycle short).

Between releases, CI runs static and unit on every push (`.github/workflows/checks.yml`). After
pushing, look at its result a few minutes later (`gh run list -L 3`) and fix a failure then, as
part of the change that caused it, so release day starts from a known list rather than a
surprise. The weekly run against today's Arch packages opens an issue when an update would break
Slate: read it at the next release.

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
`<!-- New releases go here, newest first. -->` marker) with the same notes as the GitHub
release: `<section id="<tag>" class="fp-section cl-release">`, an `<h2>` with the tag icon
(`<i class="ti">&#xEB34;</i>`), the tag and a `<time>` date, then a `.cl-grid` with one
`<article>` per Features / Fixes / Other. Copy the previous section's markup. The release
picker at the top builds itself from the sections, so it needs nothing. Commit it as `docs(site): add <tag> to the changelog`.
