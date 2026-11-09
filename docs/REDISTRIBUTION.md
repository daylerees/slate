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
| Run as a systemd user service | auto-restart (matters most for the lock screen) |
| Multi-monitor | a bar on every screen (dimmed on screens without focus); the launcher, switcher, overview, OSD and dock go to the focused screen; notifications and hot corners stay on the main display |
| Version drift | Hyprland's Lua config is new; pin and test new Hyprland/Quickshell releases |
| hyprbars dependency | Floating mode's title bars come from the hyprbars Hyprland plugin, which must be rebuilt for every Hyprland release (`slate build-hyprbars`, run by the installer). Packages would want to build it too, or depend on a distro build where one exists (NixOS `hyprlandPlugins.hyprbars`, AUR `hyprland-plugin-hyprbars`). **Slate patches it**: `shell/data/hyprbars-idle-button-color.patch` adds an `idle_button_color` option (title bar buttons stay a dull theme colour until hovered, since Slate's buttons have no glyphs) and makes hover tracking work for buttons without an icon. `slate build-hyprbars` applies it and builds without it if it no longer applies; Floating mode is optional and needs the patched build: Slate checks for hyprbars and the option (`hyprctl plugin list`, `hyprctl getoption plugin:hyprbars:idle_button_color`), and without either it stays tiling and Settings hides the window mode, so a package can leave hyprbars out. Packages should apply the patch when building, and it needs rechecking on each hyprland-plugins release (made against v0.57.0). The patch is a change to hyprland-plugins code, so it is under their BSD 3-Clause licence, not Slate's MIT; worth offering upstream so the patch can go |
| Tests | `tests/run` (docs/TESTING.md): lint and consistency, unit tests of every script, a headless session driven over IPC (incl. the login screen against a fake greetd) and screenshot checks, in CI on every push (fast tiers) and release tag (all), plus a weekly run against the newest Arch packages. Not covered yet: other distros' packages (`tools/test-install-docker.sh` checks installs), a fake MPRIS player for the dock's media controls, multi-monitor |
| Light-mode GTK on Debian/Ubuntu/openSUSE | adw-gtk3 isn't packaged there |
