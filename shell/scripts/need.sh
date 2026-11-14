#!/bin/sh
# Runs a command that needs a tool Slate doesn't always come with, or says what's missing:
#   need.sh <tool> <what it's for> -- <command line…>
#   need.sh hyprpicker 'The colour picker' -- hyprpicker -a -n
# hyprpicker and btop are optional on several distros (packaging/*.txt), and a shortcut that
# starts one that isn't installed used to do nothing at all (binds.lua: Super+P, Ctrl+Shift+Esc).
# With the tool installed the command runs exactly as it would have, in place of this script;
# without it nothing is run, and Slate shows a notification naming what to install.
[ $# -ge 4 ] && [ "$3" = "--" ] || { echo "usage: $0 <tool> <what it's for> -- <command line…>" >&2; exit 2; }
tool=$1
what=$2
shift 3
if command -v "$tool" >/dev/null 2>&1; then exec "$@"; fi

here=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
notify-send -a Slate -i "$here/../assets/icon/icon-64.png" "$what needs $tool" \
    "$tool isn't installed yet. Install it with your package manager, then try the shortcut again." 2>/dev/null
exit 0
