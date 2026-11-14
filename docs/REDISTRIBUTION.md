# Redistributing Slate

Where Slate stands as something other people install, what a package of it needs to know, and
what's still open.

## How it stands

- **Source**: `shell/` is Slate as it's installed to `~/.config/slate` (QML, `greeter/`,
  `session/` with its Hyprland config, `bin/` helpers, `scripts/`, the bundled fonts and emoji
  data). Work goes from here to the installed copy (`./install.sh`, or `./install.sh --link`
  to run straight from this folder), never back.
- **Public, with releases**: the code is at <https://github.com/daylerees/slate>, MIT
  (`LICENSE`), with the bundled fonts and cursors under their own licenses. Each release
  carries `slate-<tag>.tar.gz` and its checksum (`tools/release-assets.sh`), which Settings →
  Updates checks before installing.
- **Installer**: `install.sh` installs packages per distro (`packaging/*.txt`,
  `packaging/nixos.nix`), checks Hyprland's and Quickshell's versions, builds Quickshell from
  source where it isn't packaged (`packaging/build-quickshell.sh`), puts Slate in place, adds
  the "Slate" login session, and optionally Slate's login screen. `--uninstall` reverses it.
  User guide: [INSTALL.md](INSTALL.md).
- **Container tests of the installer**: `tools/test-install-docker.sh <image>` runs it in a
  clean Arch, Debian, Ubuntu, Fedora or openSUSE container and checks the result.
- **Nothing personal**: the profile card's name comes from the account; weather and sunset
  from a Location setting (Settings → General, city search); the dock pins whichever common
  apps are installed on first run; the login screen's keyboard layout is taken from the
  running Hyprland; helper scripts live in `shell/bin` (no `~/.local/bin`).
- **Self-contained**: wallpaper, polkit agent, clipboard history, emoji picker, night light,
  screenshots, media keys, app color themes, log out, icon font and tile generator are all
  part of Slate, with no other desktop shell needed.
- **Shortcuts**: three sets to choose from (Settings → Shortcuts): Slate's, Hyprland's
  defaults, or Hyprland's plus Slate's on free keys.
- **More than one screen**: a bar on every screen (dimmed on screens without focus); the
  launcher, switcher, overview, on-screen indicators and dock go to the focused screen;
  notifications and hot corners stay on the main display.
- **Version drift**: the tests run against pinned Arch packages, and weekly in CI against
  the newest (`tests/run --deps latest`), which opens an issue when a Hyprland or Quickshell
  update would break Slate.
- **Tests**: `tests/run` ([TESTING.md](TESTING.md)): lint and consistency, unit tests of every
  script, a headless session driven over IPC (including the login screen against a fake
  greetd, two screens side by side, and a fake media player for the dock's controls) and
  screenshot checks, in CI on every push (fast tiers) and release tag (all).

## Notes for packagers

- **Init systems**: Slate needs a login service: systemd's, or elogind without it (Artix,
  Void, Gentoo). Every systemd call goes through `bin/slate-init`, and `Config.system` says
  what the computer can do. Services are never enabled for the user off systemd (the command
  is shown). A package for those distros depends on elogind and the polkit built for it,
  never on systemd or uwsm. Alpine, Chimera (musl; no Hyprland 0.57) and Devuan are out for
  now.
- **Hyprbars**: floating windows' title bars are Slate's own by default, so Slate needs no
  plugin. Hyprbars, the Hyprland plugin, is optional and never installed by the installer:
  choosing it in Settings → Windows builds it (`slate build-hyprbars`), and it must be
  rebuilt for every Hyprland release, which Slate notices and asks about (falling back to its
  own title bars meanwhile). A package can leave it out entirely, or depend on a distro
  build where one exists (NixOS `hyprlandPlugins.hyprbars`, AUR `hyprland-plugin-hyprbars`):
  a build in `/usr/lib/hyprland/plugins`, or a link at
  `~/.local/share/slate/plugins/hyprbars.so`, is loaded as it is and left to its package
  manager.
- **Slate patches Hyprbars**: `shell/data/hyprbars-idle-button-color.patch` adds an
  `idle_button_color` option (title bar buttons stay a dull theme color until hovered, since
  Slate's buttons have no glyphs) and makes hover tracking work for buttons without an icon.
  `slate build-hyprbars` applies it and builds without it if it no longer applies; a build
  without the patch works too (the buttons keep their colors). Packages should apply the
  patch when building, and it needs rechecking on each hyprland-plugins release (made
  against v0.57.0). The patch is a change to hyprland-plugins code, so it is under their BSD
  3-Clause license, not Slate's MIT; worth offering upstream so the patch can go.

## Still to do

| What | Notes |
|---|---|
| Distro packages | none yet: Slate is installed from the repository or a release archive. An AUR `slate-git` package would be the natural first one |
| Init systems on real installs | elogind support (above) hasn't been tried on a real install or in the test container: an Artix test image is the next step, and it's what will answer how Hyprland's `start-hyprland` and polkit behave there |
| Brightness | `brightnessctl`, with the first backlight device and a `*kbd_backlight*` glob for the keyboard (`OSD.qml`); detect the devices instead |
| Run as a systemd user service | so Slate is restarted if it dies (matters most for the lock screen); would need an equivalent without systemd |
| Other distros in the test suite | the suite runs on Arch packages only; `tools/test-install-docker.sh` checks that the installer works elsewhere, not Slate itself |
| Light-mode GTK on Debian/Ubuntu/openSUSE | adw-gtk3 isn't packaged there ([INSTALL.md](INSTALL.md#not-packaged-everywhere) says where to get it) |
