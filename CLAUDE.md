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

## Releases

Releases are tagged with [Semantic Versioning](https://semver.org/): annotated tags named
`vMAJOR.MINOR.PATCH` (e.g. `git tag -a v0.2.0 -m "v0.2.0"`), pushed with `git push --tags`.

- **MAJOR** for breaking changes (a `!` / `BREAKING CHANGE` commit since the last release).
- **MINOR** for new features (any `feat` commit).
- **PATCH** for fixes and everything else.

While Slate is below 1.0.0, breaking changes bump MINOR instead of MAJOR.
