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

## Sounds

Slate's sounds are one family (soft, rounded, calm; nothing alarming) and each is tied to one
kind of moment. Anything new that fits one of these moments uses its sound, the same way:

| Moment | Sound | How |
|---|---|---|
| Pressing something: buttons, menu items, switches, tiles | click | `ClickTap` instead of `TapHandler`, `ClickArea` instead of `MouseArea`. Areas that only catch clicks outside a panel, swallow clicks, or drag (sliders, scrollbars) stay silent |
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

## Releases

Releases are tagged with [Semantic Versioning](https://semver.org/): annotated tags named
`vMAJOR.MINOR.PATCH` (e.g. `git tag -a v0.2.0 -m "v0.2.0"`), pushed with `git push --tags`.

- **MAJOR** for breaking changes (a `!` / `BREAKING CHANGE` commit since the last release).
- **MINOR** for new features (any `feat` commit).
- **PATCH** for fixes and everything else.

While Slate is below 1.0.0, breaking changes bump MINOR instead of MAJOR.

When asked to tag or release, do both: create and push the annotated tag, then a GitHub
release for it with `gh release create <tag> --title <tag> --notes-file <notes>`. The tag
message and the release notes both carry a summary of the changes since the previous tag
(from `git log <previous>..HEAD`), grouped as Features, Fixes and Other, in plain words
for people using Slate rather than a list of commit subjects. Leave out site- and
docs-only changes unless they matter to users.
