# Plan: update the login screen automatically, safely

Status: **proposed, not started** (written 2026-11-09). Come back to it when the
"Login screen out of date" prompt feels like a chore again.

## The problem

The login screen (greetd + `greeter/`) runs a copy of Slate's code from
`/usr/local/share/slate-greeter`, owned by root. When that code changes, Slate asks for your
password (`pkexec slate-greeter-install --code-only`) to copy the new version in from
`~/.config/slate`.

Since `35afec6` the prompt only appears for the login screen's *own* files, not for the shared
`Config.qml`/`SettingsData.qml`, and "Later" waits a week. That cut it down a lot, but every
release that touches the login screen still means a password prompt.

## Why not just "always allow"

The login screen is where you type your password. Its code is copied from `~/.config/slate`,
which **any program running as you can change**. Letting that copy happen without a password
(a polkit rule, a NOPASSWD sudo line, or the greeter reading code from a folder you own) means
a malicious program running as you could rewrite the login screen to record your password at
the next login, and with it gain root (sudo). The password prompt is the only thing preventing
that, so any automation must not copy from a place you can write to.

## The idea

Approve once, and from then on the login screen updates itself from a source that programs
running as you **can't touch**:

- A small **system service** (installed once, with your password) keeps its **own copy of
  Slate in a root-owned folder**, fetched straight from GitHub, independent of `~/.config/slate`.
- When a new **release** is tagged, it fetches that release into its own copy, test-loads the
  login screen from it (the existing `slate-greeter-check`), and installs it. No prompt.
- **Optionally**, it installs only releases **signed** with the maintainer's key, so even someone
  tampering with the GitHub repository couldn't push a login screen.

Trust then rests on GitHub (or on the signing key), which is the same trust Slate's own
updater (`scripts/update.py`) already relies on, and never on files in your home folder.

## Design

### Pieces

1. **`bin/slate-greeter-autoupdate`** (new, runs as root via systemd). Steps:
   - **Fetch.** Fetch the latest release tag from `https://github.com/daylerees/slate` into
     `/var/lib/slate-greeter/src` (root-owned, `0755`, a shallow `git` clone or the release
     tarball). The repository URL is fixed in the root-owned unit, never read from user config.
   - **Check the version.** Skip if that tag is already installed (record it in
     `/var/lib/slate-greeter/src/.installed-tag`). Refuse to go *backwards* to an older tag
     (protects against a downgrade to a known-bad version).
   - **Verify (if signing is on).** Run `git verify-tag` or `ssh-keygen -Y verify` against a public
     key pinned in a root-owned file (`/etc/slate-greeter/trusted-signers`). If it doesn't
     verify, stop and log why.
   - **Install from that copy.** Run the existing install logic with `SRC` pointing at the
     root-owned copy, not `~/.config/slate`. `slate-greeter-install --code-only` needs a
     `--from <dir>` option for this; everything else (test-load, `.good` fallback) stays.
   - **Log.** Record what happened (journal, plus a small status file Settings can read).

2. **`slate-greeter-autoupdate.service` + `.timer`** (systemd, system-wide). They run the
   script daily and shortly after boot, with `Persistent=true`. Harden it:
   - fetch as a separate unprivileged step if practical (`DynamicUser=` for the download,
     root only to copy the verified files in)
   - `ProtectHome=yes` (it must never read your home folder; that's the point)
   - `ProtectSystem=strict` with `ReadWritePaths=/var/lib/slate-greeter /usr/local/share/slate-greeter`
   - `NoNewPrivileges=yes`, `PrivateTmp=yes`, and a network allow-list if possible

3. **Opting in, once.** A switch in **Settings → Lock & Idle**, "Update the login screen
   automatically", which runs
   `pkexec slate-greeter-install --enable-autoupdate` (your password, once). That installs and
   enables the unit and timer and does a first run. Turning it off
   (`--disable-autoupdate`) removes them. `install.sh` could offer it too.

4. **Slate's prompt, when on.** `slate-greeter-sync --prompt` stays quiet when auto-update is
   enabled; the service handles releases. Settings → Lock & Idle shows the login screen's
   version and when it last updated, from the status file.

### Behaviour to decide or handle

- **Developing locally.** Your own edits in `~/.config/slate` are *not* picked up
  automatically (that's the security point). The existing **Update** button (with your
  password) still installs your local version for testing. Should the service then put the
  release back on the next run? Probably not: skip while the installed code is newer than or
  different from the release, until the next release. Needs a rule (e.g. track "installed
  from: release vX / local").
- **Release vs. your Slate version.** The login screen follows the *latest release*, while
  your Slate follows whatever you've installed. They can be a release apart for a while.
  The login screen only reads settings through `SettingsData.qml`'s own copy, and unknown
  keys are ignored, so a version gap should be harmless. Worth a test.
- **Offline or GitHub down.** Just try again on the next timer run. Never leave a half-installed
  copy: install into a temporary folder, test-load it, then swap it in (what the installer
  already does).
- **A broken release.** The existing test-load refuses it, and the `.good` copy and the
  emergency login screen remain as fallbacks. Log it loudly, and maybe show a notice on next login.
- **Pre-releases.** Follow only full releases (not drafts or pre-releases).
- **Packaged installs** (`packaging/`). If Slate is installed by a distro package, the
  package manager's own post-install hook is a better place, since it already runs as root
  from a trusted source. Check `packaging/` before building this.

### Signing (optional, phase 2)

- Make one signing key (an SSH key works well: `ssh-keygen -Y sign`, no GPG setup needed).
- On release, sign the tag (`git tag -s` with `gpg.format=ssh`) or the release tarball. Add
  that step to the release section of `CLAUDE.md`.
- Ship the public key in the repo *and* have the opt-in step copy it to
  `/etc/slate-greeter/trusted-signers` (root-owned), so a compromised repo can't swap it.
- Without signing, the service trusts GitHub's copy of the release, the same as
  `update.py`. With signing, only the key holder can produce a login screen.

## Work, roughly

1. `slate-greeter-install`: a `--from <dir>` option; `--enable-autoupdate` and
   `--disable-autoupdate`.
2. `bin/slate-greeter-autoupdate`, plus the systemd unit and timer files in the repo, with the
   sandboxing above.
3. A status file, the Settings switch, and the version/last-updated line in Lock & Idle.
4. `slate-greeter-sync --prompt`: stay quiet when auto-update is on.
5. Docs: `docs/LOCK-AND-LOGIN.md` (how it works, the threat model, how to turn it off);
   the site's login screen section.
6. Tests: a fresh opt-in; a new release arrives; offline; a deliberately broken release (test-load
   refuses it); a downgrade attempt; a local dev install (left alone); turning it off.
7. Phase 2: signing (key, release step, verification).

## Open questions

- Fetch with `git` (needs git as root, easy tag verification) or the release tarball (no
  git, verify a detached signature)?
- Daily timer, or also a nudge when Slate's own updater installs a new release (it could
  `systemctl start` the service through a narrowly scoped polkit action that takes no
  arguments, which is safe because the service never reads user input)?
- Should opting in be the default for new installs, or always a choice?
