#!/bin/sh
# Create the files for your own tweaks in Slate's folder, from data/user-files, where they
# don't exist yet; never touches one that does. Run by Slate at startup and by install.sh.
#   hypr/env.lua, variables.lua, monitors.lua, binds.lua, rules.lua, autostart.lua,
#   hyprland.lua    loaded by the Slate session's Hyprland config (session/hypr/hyprland.lua)
#   user/shell.qml  loaded into Slate (UserFiles.qml)
# Usage: user-files.sh [slate-dir]   (default: the folder this script is in, ..)
dir="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
src="$dir/data/user-files"
[ -d "$src" ] || exit 0
cd "$src" || exit 1
find . -type f | while read -r f; do
    dest="$dir/${f#./}"
    [ -e "$dest" ] && continue
    mkdir -p "$(dirname "$dest")" && cp "$f" "$dest" && echo "created ${dest}"
done
