#!/usr/bin/env bash
# Copy the running Slate (~/.config/slate) into shell/ for release, leaving out backups
# (*.bak*), caches and your own files (settings.json, hypr/ tweaks).
#   tools/sync-from-live.sh          copy
#   tools/sync-from-live.sh --dry    show what would change
# Not needed if ~/.config/slate is a link to shell/ (./install.sh --link).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIVE="${XDG_CONFIG_HOME:-$HOME/.config}/slate"
[ -d "$LIVE" ] || { echo "No Slate at $LIVE" >&2; exit 1; }
if [ "$(readlink -f "$LIVE")" = "$ROOT/shell" ]; then echo "$LIVE already is shell/; nothing to copy."; exit 0; fi
dry=(); [ "${1:-}" = "--dry" ] && dry=(--dry-run --itemize-changes)
rsync -a --delete "${dry[@]}" \
    --exclude '*.bak*' --exclude '*.backup*' --exclude '__pycache__/' --exclude '*.pyc' \
    --exclude '/settings.json' --exclude '/hypr/' --exclude '*.removed-*' --exclude '*.backup-*' --exclude '.slate-tmp*' --exclude '*.slate-tmp' \
    "$LIVE/" "$ROOT/shell/"
[ ${#dry[@]} -eq 0 ] && echo "Copied $LIVE -> $ROOT/shell"
