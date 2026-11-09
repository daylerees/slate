#!/bin/sh
# Open files with an app, by its desktop entry's id (files dropped on its icon in the dock):
#   open-with.sh <desktop-id> <file>...
# Finds <desktop-id>.desktop where the desktop keeps them (your own, then the system's,
# Flatpak's included) and has GLib launch it with the files, as a file manager would.
id=$1
shift
[ -n "$id" ] || exit 1
IFS=:
for dir in "${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
    file="$dir/applications/$id.desktop"
    if [ -f "$file" ]; then
        unset IFS
        exec gio launch "$file" "$@"
    fi
done
echo "open-with: no $id.desktop found" >&2
exit 1
