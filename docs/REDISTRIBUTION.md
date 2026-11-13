# Redistributing Slate

Status of making Slate installable by other people.

## Done (2026-11-07)

- **Source here**: `shell/` is Slate as installed to `~/.config/slate`
  (QML, `greeter/`, `session/` with its Hyprland config, `bin/` helpers, `scripts/`,
  bundled Tabler font and emoji data). `tools/sync-from-live.sh` copies a running Slate
  back here, leaving out backups and personal `settings.json`.
- **Installer**: `install.sh` installs packages per distro (`packaging/*.txt`), checks
  Hyprland/Quickshell versions, builds Quickshell from source where it isn't packaged
  (`packaging/build-quickshell.sh`), installs Geist, puts Slate in place, adds the
  "Slate" login session, and optionally Slate's login screen. `--uninstall` reverses it.
  User guide: [INSTALL.md](INSTALL.md).
- **Container tests**: `tools/test-install-docker.sh <image>` runs the installer in a
  clean Arch, Debian, Ubuntu, Fedora or openSUSE container and checks the result.
- **Personal values removed**: profile card name from the account; weather/sunset from a
  Location setting (Settings → General, city search); dock pins whichever common apps are
  installed on first run; login-screen keyboard layout recorded from the running
  Hyprland; helper scripts live in `shell/bin` (no `~/.local/bin`).
- **Self-contained**: wallpaper, polkit agent, clipboard history, emoji picker, night
  light, screenshots, media keys, app colour themes, log out, icon font and tile
  generator are all part of Slate, with no other desktop shell needed.

## Still to do

| What | Notes |
|---|---|
| Public repo + release tarballs | INSTALL.md uses `<repo-url>` as a placeholder. Licence: MIT (`LICENSE`), with the bundled fonts under their own |
| Distro packages | an AUR `slate-git` package would be the natural first one (system path `/usr/share/slate`, which `slate-session` already falls back to) |
| Brightness | `brightnessctl` and a keyboard-backlight glob in `OSD.qml`; detect devices instead |
| Keymap | `session/hypr/config/binds.lua` is one person's keymap; consider a smaller default set |
| Run as a systemd user service | auto-restart (matters most for the lock screen); would need an equivalent without systemd |
| Init systems | Slate needs a login service: systemd's, or elogind without it (Artix, Void, Gentoo). Every systemd call goes through `bin/slate-init`, and `Config.system` says what the computer can do. Not done on real installs yet: an Artix test image (`tests/run --deps artix`) is the next step, and it's what will answer how Hyprland's `start-hyprland` and polkit behave there. Services are never enabled for the user off systemd (the command is shown). A package for those distros depends on elogind and the polkit built for it, never on systemd or uwsm. Alpine, Chimera (musl; no Hyprland 0.57) and Devuan are out for now |
| Multi-monitor | a bar on every screen (dimmed on screens without focus); the launcher, switcher, overview, OSD and dock go to the focused screen; notifications and hot corners stay on the main display |
| Version drift | Hyprland's Lua config is new; pin and test new Hyprland/Quickshell releases |
| hyprbars dependency | Floating windows' title bars are Slate's own by default, so Slate needs no plugin. Hyprbars, the Hyprland plugin, is optional and never installed by the installer: choosing it in Settings → Windows builds it (`slate build-hyprbars`), and it must be rebuilt for every Hyprland release, which Slate notices and asks about (falling back to its own title bars meanwhile). A package can leave it out entirely, or depend on a distro build where one exists (NixOS `hyprlandPlugins.hyprbars`, AUR `hyprland-plugin-hyprbars`): a build in `/usr/lib/hyprland/plugins`, or a link at `~/.local/share/slate/plugins/hyprbars.so`, is loaded as it is and left to its package manager. **Slate patches it**: `shell/data/hyprbars-idle-button-color.patch` adds an `idle_button_color` option (title bar buttons stay a dull theme colour until hovered, since Slate's buttons have no glyphs) and makes hover tracking work for buttons without an icon. `slate build-hyprbars` applies it and builds without it if it no longer applies; a build without the patch works too (the buttons keep their colours). Packages should apply the patch when building, and it needs rechecking on each hyprland-plugins release (made against v0.57.0). The patch is a change to hyprland-plugins code, so it is under their BSD 3-Clause licence, not Slate's MIT; worth offering upstream so the patch can go |
| Tests | `tests/run` (docs/TESTING.md): lint and consistency, unit tests of every script, a headless session driven over IPC (incl. the login screen against a fake greetd) and screenshot checks, in CI on every push (fast tiers) and release tag (all), plus a weekly run against the newest Arch packages. Not covered yet: other distros' packages (`tools/test-install-docker.sh` checks installs), a fake MPRIS player for the dock's media controls, multi-monitor |
| Light-mode GTK on Debian/Ubuntu/openSUSE | adw-gtk3 isn't packaged there |
