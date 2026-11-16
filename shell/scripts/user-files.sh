#!/bin/sh
# Create the files for your own tweaks in your Slate folder, from data/user-files, where they
# don't exist yet; never touches one that does. Run by Slate at startup and by install.sh.
#   hypr/env.lua, variables.lua, monitors.lua, binds.lua, rules.lua, autostart.lua,
#   hyprland.lua    loaded by the Slate session's Hyprland config (session/hypr/hyprland.lua)
#   user/shell.qml  loaded into Slate (UserFiles.qml)
# Usage: user-files.sh [your-slate-dir]   (default: ~/.config/slate, or $XDG_CONFIG_HOME/slate)
# (made from this Slate's data/user-files, into your own Slate folder: the same folder for an
# install of your own, apart from Slate's code when it's installed for everyone)
dir="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/slate}"
src="$(cd "$(dirname "$0")/.." && pwd)/data/user-files"
[ -d "$src" ] || exit 0
cd "$src" || exit 1
find . -type f | while read -r f; do
    dest="$dir/${f#./}"
    # yours already (a link of yours too, even one that points nowhere: never written through)
    { [ -e "$dest" ] || [ -L "$dest" ]; } && continue
    mkdir -p "$(dirname "$dest")" && cp "$f" "$dest" && echo "created ${dest}"
done
