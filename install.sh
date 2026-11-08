#!/usr/bin/env bash
# Slate installer. Run from the Slate folder as your normal user (it asks for sudo when
# it needs it):
#
#   ./install.sh                  install everything (asks before each system change)
#   ./install.sh --yes            same, without questions
#   ./install.sh --login-screen   also make Slate's login screen the system's (greetd)
#   ./install.sh --no-deps        skip installing packages (you've done it yourself)
#   ./install.sh --link           link ~/.config/slate to this folder (for development)
#   ./install.sh --uninstall      remove Slate (keeps packages and your settings backup)
#
# What it does:
#   1. installs the packages Slate needs (packaging/<distro>.txt)
#   2. checks Hyprland (0.57+, Lua config) and Quickshell (0.3+) are new enough
#   3. installs the Geist font (bundled) for your other apps if it's missing
#   4. puts Slate in ~/.config/slate (keeping your settings) and the `slate` command in ~/.local/bin
#   5. adds "Slate" to your login screen's session list (two small files, needs sudo)
#   6. optionally (--login-screen) switches greetd to Slate's login screen
# Your current desktop and ~/.config/hypr are not changed: pick "Slate" at login to use it.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/slate"
OLD_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/slate"   # where Slate lived before
BIN_LINK="$HOME/.local/bin/slate"
HYPR_MIN="0.57"
QS_MIN="0.3"

YES=0; DEPS=1; LINK=0; LOGIN=0; UNINSTALL=0
for a in "$@"; do
    case "$a" in
        -y|--yes) YES=1 ;;
        --no-deps) DEPS=0 ;;
        --link) LINK=1 ;;
        --login-screen) LOGIN=1 ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $a (see ./install.sh --help)" >&2; exit 1 ;;
    esac
done

# ---- Output helpers ------------------------------------------------------------------
if [ -t 1 ]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'; else B=; G=; Y=; R=; N=; fi
step() { echo; echo "${B}==> $*${N}"; }
ok()   { echo "  ${G}✓${N} $*"; }
warn() { echo "  ${Y}!${N} $*"; }
die()  { echo "${R}Error:${N} $*" >&2; exit 1; }
ask() {   # ask "Question?" → 0 for yes. Default yes.
    [ "$YES" -eq 1 ] && return 0
    local r; read -r -p "  $1 [Y/n] " r </dev/tty || r=""
    case "$r" in [nN]*) return 1 ;; *) return 0 ;; esac
}
have() { command -v "$1" >/dev/null 2>&1; }
# version_ge 0.57.1 0.57 → true
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

[ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root (it uses sudo when needed)."
have sudo || die "sudo is needed for the system steps."

# ---- Uninstall ------------------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
    step "Removing Slate"
    if [ -f /usr/share/wayland-sessions/slate.desktop ]; then
        sudo rm -f /usr/share/wayland-sessions/slate.desktop /usr/local/bin/slate-session && ok "Removed the Slate login session"
    fi
    if [ -f /etc/greetd/config.toml.before-slate ]; then
        sudo cp -f /etc/greetd/config.toml.before-slate /etc/greetd/config.toml && ok "greetd is back to its previous login screen (from the next reboot)"
    fi
    have qs && qs kill -p "$DEST" >/dev/null 2>&1 || true
    [ -L "$BIN_LINK" ] && rm "$BIN_LINK" && ok "Removed the slate command"
    data="${XDG_DATA_HOME:-$HOME/.local/share}"
    rm -f "$data/applications/slate-settings.desktop" "$data"/icons/hicolor/*/apps/slate-settings.png
    [ -L "$data/icons/Slate-Cursors" ] && rm "$data/icons/Slate-Cursors" && ok "Removed Slate Cursors"
    # Folder colour: back to the icon theme it was made from (removes Slate-Icons)
    [ -x "$DEST/scripts/folder-colour.py" ] && "$DEST/scripts/folder-colour.py" default >/dev/null 2>&1 && ok "Folder icons back to the icon theme's own"
    [ -L "$OLD_DEST" ] && rm "$OLD_DEST"
    if [ -L "$DEST" ]; then rm "$DEST" && ok "Removed the link $DEST"
    elif [ -d "$DEST" ]; then
        b="$DEST.removed-$(date +%Y%m%d-%H%M%S)"; mv "$DEST" "$b" && ok "Moved $DEST to $b (your settings are in there; delete it when you're sure)"
    fi
    echo; echo "Done. Packages were left installed. Log out of Slate if you're in it."
    exit 0
fi

# ---- Which distro ---------------------------------------------------------------------
. /etc/os-release 2>/dev/null || true
family=""
for id in ${ID:-} ${ID_LIKE:-}; do
    case "$id" in
        arch|cachyos|endeavouros|manjaro|garuda) family=arch ;;
        debian|ubuntu|linuxmint|pop|elementary|zorin) family=debian ;;
        fedora|rhel|centos|nobara|ultramarine) family=fedora ;;
        opensuse*|suse|sles) family=opensuse ;;
        nixos) family=nixos ;;
    esac
    [ -n "$family" ] && break
done
echo "${B}Slate installer${N}  ·  ${PRETTY_NAME:-unknown system}${family:+ ($family family)}"

# ---- 1. Packages ----------------------------------------------------------------------
# packaging/<family>.txt: one package per line; "# comment"; a line starting with "?" is
# optional (skipped if the distro doesn't have it)
read_list() { grep -v '^\s*\(#\|$\)' "$ROOT/packaging/$1.txt" | sed 's/\s*#.*//'; }

install_arch() {
    local req=() opt=() p
    while read -r p; do case "$p" in \?*) opt+=("${p#\?}") ;; *) req+=("$p") ;; esac; done < <(read_list arch)
    sudo pacman -S --needed --noconfirm "${req[@]}"
    for p in "${opt[@]}"; do
        if pacman -Si "$p" >/dev/null 2>&1; then sudo pacman -S --needed --noconfirm "$p" || warn "Couldn't install $p"
        elif have paru; then paru -S --needed --noconfirm "$p" || warn "Couldn't install $p (AUR)"
        elif have yay; then yay -S --needed --noconfirm "$p" || warn "Couldn't install $p (AUR)"
        else warn "$p isn't in the official repos; install it from the AUR if you want it"; fi
    done
}
install_debian() {
    local req=() opt=() p
    while read -r p; do case "$p" in \?*) opt+=("${p#\?}") ;; *) req+=("$p") ;; esac; done < <(read_list debian)
    if [ "${ID:-}" = ubuntu ] || [[ " ${ID_LIKE:-} " == *" ubuntu "* ]]; then
        # Ubuntu's own Hyprland is too old; this PPA has current releases (26.04 and newer)
        if ! grep -rqs cppiber/hyprland /etc/apt/sources.list.d/; then
            sudo apt-get update
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
            sudo add-apt-repository -y ppa:cppiber/hyprland
        fi
    fi
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${req[@]}"
    for p in "${opt[@]}"; do
        if apt-cache show "$p" >/dev/null 2>&1; then sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$p" || warn "Couldn't install $p"
        else warn "$p isn't available here; skipped"; fi
    done
}
install_fedora() {
    local req=() opt=() copr=() p
    while read -r p; do
        case "$p" in copr:*) copr+=("${p#copr:}") ;; \?*) opt+=("${p#\?}") ;; *) req+=("$p") ;; esac
    done < <(read_list fedora)
    have dnf || die "dnf not found"
    sudo dnf install -y dnf-plugins-core >/dev/null 2>&1 || true
    for p in "${copr[@]}"; do sudo dnf -y copr enable "$p"; done
    # Fedora Workstation's tuned-ppd does power-profiles-daemon's job (and conflicts with it)
    if rpm -q tuned-ppd >/dev/null 2>&1; then
        local keep=(); for p in "${opt[@]}"; do [ "$p" = power-profiles-daemon ] || keep+=("$p"); done; opt=("${keep[@]}")
    fi
    sudo dnf install -y "${req[@]}"
    for p in "${opt[@]}"; do sudo dnf install -y "$p" >/dev/null 2>&1 || warn "$p isn't available here; skipped"; done
}
install_opensuse() {
    local req=() opt=() p
    while read -r p; do case "$p" in \?*) opt+=("${p#\?}") ;; *) req+=("$p") ;; esac; done < <(read_list opensuse)
    sudo zypper --non-interactive install "${req[@]}"
    for p in "${opt[@]}"; do sudo zypper --non-interactive install "$p" >/dev/null 2>&1 || warn "$p isn't available here; skipped"; done
}

# Releases too old for Slate's Hyprland 0.57+ / Quickshell 0.3+ (see docs/INSTALL.md)
too_old=""
case "${ID:-}" in
    ubuntu) version_ge "${VERSION_ID:-0}" 26.04 || too_old="Ubuntu ${VERSION_ID:-} (needs 26.04 or newer)" ;;
    debian) [ -n "${VERSION_ID:-}" ] && [ "${VERSION_ID%%.*}" -le 13 ] && too_old="Debian ${VERSION_ID} (needs testing or sid)" ;;
    fedora) version_ge "${VERSION_ID:-0}" 44 || too_old="Fedora ${VERSION_ID:-} (needs 44 or newer)" ;;
    opensuse-leap) too_old="openSUSE Leap (needs Tumbleweed)" ;;
esac
if [ -n "$too_old" ]; then
    warn "$too_old: its Hyprland and/or Quickshell are too old for Slate. See docs/INSTALL.md."
    ask "Try anyway?" || exit 1
fi

if [ "$DEPS" -eq 1 ]; then
    step "1. Packages"
    case "$family" in
        arch|debian|fedora|opensuse)
            echo "  Slate needs these packages (packaging/$family.txt):"
            read_list "$family" | tr '\n' ' ' | fold -s -w 76 | sed 's/^/    /'; echo
            if ask "Install them now (uses sudo)?"; then "install_$family"; ok "Packages installed"
            else warn "Skipped; install them yourself before using Slate"; fi ;;
        nixos)
            warn "On NixOS, add the packages in packaging/nixos.nix to your configuration, rebuild, then run: ./install.sh --no-deps"
            exit 1 ;;
        *)
            warn "Unknown distro; install the packages listed in docs/INSTALL.md yourself, then run: ./install.sh --no-deps"
            exit 1 ;;
    esac
fi

# ---- 2. Hyprland and Quickshell -------------------------------------------------------
step "2. Checking Hyprland and Quickshell"
problems=0
if have Hyprland; then
    hv=$(Hyprland --version 2>/dev/null | grep -oP 'Hyprland \K[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
    # Some environments refuse to run Hyprland outside a session; ask the package manager instead
    if [ -z "$hv" ]; then
        hv=$({ pacman -Q hyprland 2>/dev/null | awk '{print $2}'; dpkg-query -W -f='${Version}' hyprland 2>/dev/null; rpm -q --qf '%{VERSION}' hyprland 2>/dev/null; } | grep -oP '^[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
    fi
    if [ -n "$hv" ] && version_ge "$hv" "$HYPR_MIN"; then ok "Hyprland $hv"
    else warn "Hyprland ${hv:-(unknown version)} is too old: Slate needs $HYPR_MIN or newer (the Lua config). See docs/INSTALL.md"; problems=1; fi
    have start-hyprland || { warn "start-hyprland (Hyprland's launcher) wasn't found; the Slate session needs it"; problems=1; }
else
    warn "Hyprland isn't installed. See docs/INSTALL.md for your distro"; problems=1
fi
if have qs; then
    qv=$(qs --version 2>/dev/null | grep -oP 'Quickshell \K[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
    if [ -n "$qv" ] && version_ge "$qv" "$QS_MIN"; then ok "Quickshell $qv"
    else warn "Quickshell ${qv:-(unknown version)} is too old: Slate needs $QS_MIN or newer"; problems=1; fi
else
    warn "Quickshell isn't installed."
    if { [ "$family" = debian ] || [ "$family" = opensuse ]; } && ask "Your distro doesn't package Quickshell 0.3. Build it from source now (about 5–10 minutes)?"; then
        "$ROOT/packaging/build-quickshell.sh" && ok "Quickshell built and installed" || { warn "Quickshell build failed"; problems=1; }
    else
        warn "See docs/INSTALL.md for your distro"; problems=1
    fi
fi
if [ "$problems" -ne 0 ]; then
    echo
    ask "Some requirements are missing (above). Carry on and put Slate in place anyway?" || exit 1
fi

# ---- 3. Fonts -------------------------------------------------------------------------
# Geist (interface + mono) and the Tabler icons ship with Slate in shell/fonts, and Slate loads
# them itself. Geist is also installed for your other apps if it isn't there already.
step "3. Fonts"
if fc-list : family 2>/dev/null | grep -qi '^Geist\b\|^Geist,'; then ok "Geist is installed"
else
    fontdir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/Geist"
    mkdir -p "$fontdir"
    cp "$ROOT"/shell/fonts/Geist*-Variable.ttf "$ROOT"/shell/fonts/Geist-LICENSE.txt "$fontdir/"
    fc-cache -f "$fontdir" >/dev/null 2>&1 || true
    ok "Installed Geist (bundled with Slate) to $fontdir"
fi
ok "Icon font: bundled with Slate"

# ---- 4. Slate itself ------------------------------------------------------------------
# ~/.config/slate holds Slate's code plus your own files, which are always kept:
#   settings.json (Slate's settings), hypr/ (your Hyprland tweaks) and user/ (your own QML)
step "4. Slate"
KEEP=(settings.json hypr user)
mkdir -p "$(dirname "$DEST")"
# Slate used to live in ~/.config/quickshell/slate: bring its settings along
if [ -d "$OLD_DEST" ] && [ ! -L "$OLD_DEST" ] && [ ! -e "$DEST/settings.json" ] && [ -f "$OLD_DEST/settings.json" ]; then
    mkdir -p "$DEST"; cp "$OLD_DEST/settings.json" "$DEST/settings.json"; ok "Brought your settings over from $OLD_DEST"
fi
if [ -L "$DEST" ] && [ "$(readlink -f "$DEST")" = "$ROOT/shell" ]; then
    ok "$DEST already links to this folder"
else
    keep=""
    if [ -e "$DEST" ]; then
        keep=$(mktemp -d)
        for k in "${KEEP[@]}"; do [ -e "$DEST/$k" ] && cp -a "$DEST/$k" "$keep/"; done
        b="$DEST.backup-$(date +%Y%m%d-%H%M%S)"
        mv "$DEST" "$b"; ok "Backed up the previous Slate to $b"
    fi
    if [ "$LINK" -eq 1 ]; then
        ln -s "$ROOT/shell" "$DEST"; ok "Linked $DEST -> $ROOT/shell"
    else
        cp -a "$ROOT/shell" "$DEST"; ok "Copied Slate to $DEST"
    fi
    if [ -n "$keep" ]; then
        for k in "${KEEP[@]}"; do [ -e "$keep/$k" ] && cp -a "$keep/$k" "$DEST/"; done
        rm -rf "$keep"; ok "Kept your settings and your own tweaks"
    fi
fi
# Files for your own tweaks, with instructions in them, where they don't exist yet
sh "$DEST/scripts/user-files.sh" "$DEST" >/dev/null && ok "Your own tweaks go in $DEST/hypr and $DEST/user (instructions inside)"
chmod +x "$DEST"/bin/* "$DEST"/scripts/*.sh "$DEST"/scripts/*.py "$DEST"/greeter/run-greeter.sh "$DEST"/session/slate-session 2>/dev/null || true
mkdir -p "$(dirname "$BIN_LINK")"
ln -sfn "$DEST/bin/slate" "$BIN_LINK"; ok "The slate command: $BIN_LINK"
# Slate Settings' window icon: a (hidden) desktop entry plus the icon in the user's icon theme
data="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$data/applications"
sed "s|@SLATE@|$DEST/bin/slate|" "$DEST/data/slate-settings.desktop" > "$data/applications/slate-settings.desktop"
for s in 512 256 128 64 48 32 16; do
    install -D -m 644 "$DEST/assets/icon/settings-$s.png" "$data/icons/hicolor/${s}x${s}/apps/slate-settings.png"
done
have gtk-update-icon-cache && gtk-update-icon-cache -q -t "$data/icons/hicolor" 2>/dev/null || true
ok "Settings icon and desktop entry"
# Slate Cursors (the session's mouse cursor): linked where Hyprland and apps look for themes
mkdir -p "$data/icons"
ln -sfn "$DEST/cursors/Slate-Cursors" "$data/icons/Slate-Cursors"; ok "Slate Cursors"
# hyprbars: title bars for floating windows (Settings → Windows → Window mode), built for
# this Hyprland into ~/.local/share/slate/plugins. Optional: without it, no title bars.
if have g++ && have git && have make; then
    echo "  Building hyprbars (title bars for floating windows)…"
    if "$DEST/bin/slate-build-hyprbars" >/tmp/slate-hyprbars.log 2>&1; then ok "hyprbars built"
    else warn "Couldn't build hyprbars (see /tmp/slate-hyprbars.log); floating windows won't have title bars. Retry later with: slate build-hyprbars"; fi
else
    warn "Skipped hyprbars (needs git, make and g++); floating windows won't have title bars until you run: slate build-hyprbars"
fi
# Icon theme: Papirus-Dark (its coloured folders back Settings → Appearance → Folder colour),
# unless you've already picked an icon theme of your own
if have gsettings && { [ -d /usr/share/icons/Papirus-Dark ] || [ -d /run/current-system/sw/share/icons/Papirus-Dark ]; }; then
    cur=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
    case "$cur" in
        ""|Adwaita|AdwaitaLegacy|hicolor|default|gnome|breeze|breeze-dark|Yaru*|elementary)
            "$DEST/scripts/folder-colour.py" --icon-theme Papirus-Dark \
                && ok "Icon theme: Papirus-Dark${cur:+ (was $cur)}" || warn "Couldn't set the icon theme to Papirus-Dark" ;;
        Papirus*|ePapirus*|Slate-Icons) ok "Icon theme: $cur" ;;
        *) ok "Icon theme: keeping yours ($cur); Papirus-Dark is installed if you want it (Folder colour needs it)" ;;
    esac
fi
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "~/.local/bin isn't on your PATH; add it to use the slate command in a terminal" ;; esac
# If Slate is running (updating from inside it), restart it on the new code
if have qs && pgrep -x qs >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then "$DEST/bin/slate" restart && ok "Restarted Slate"; fi

# ---- 5. Login session -----------------------------------------------------------------
step "5. \"Slate\" on the login screen"
echo "  Adds two files: /usr/local/bin/slate-session and /usr/share/wayland-sessions/slate.desktop"
if ask "Add the Slate session (uses sudo)?"; then
    sudo "$DEST/bin/slate-session-install" | sed 's/^/  /'
else
    warn "Skipped. Later: sudo $DEST/bin/slate-session-install"
fi

# ---- 6. Slate's login screen (optional) -----------------------------------------------
if [ "$LOGIN" -eq 1 ]; then
    step "6. Slate's login screen (greetd)"
    if ! have greetd && [ ! -x /usr/bin/greetd ] && [ ! -x /usr/sbin/greetd ]; then
        warn "greetd isn't installed; install it, then run: sudo $DEST/bin/slate-greeter-install"
    else
        echo "  This replaces your current login screen with Slate's (greetd). Your old setup is kept"
        echo "  and can be restored with: sudo $DEST/bin/slate-greeter-install --revert"
        if ask "Switch the login screen to Slate's (uses sudo)?"; then
            sudo "$DEST/bin/slate-greeter-install" | sed 's/^/  /'
            echo "  If your distro used another display manager (GDM, SDDM, LightDM), switch to greetd:"
            echo "    sudo systemctl disable <your-dm> && sudo systemctl enable greetd"
        fi
    fi
fi

echo
echo "${G}${B}Slate is installed.${N} Log out, pick \"Slate\" on the login screen, and log in."
echo "  Settings: Super+Z   ·   Apps: Super+Space   ·   Keys and more: docs/INSTALL.md"
echo "  Your own Hyprland tweaks (keyboard layout, monitors, apps): ~/.config/slate/hypr/hyprland.lua"
