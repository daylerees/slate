#!/bin/sh
# Inside the test container: become a normal user with the same id as whoever ran
# tests/run (Hyprland won't run as root, and tests/out stays theirs), then run the command.
set -e
uid=${HOST_UID:-1000}; gid=${HOST_GID:-1000}
getent group "$gid" >/dev/null || groupadd -g "$gid" tester
getent passwd "$uid" >/dev/null || useradd -M -d /tmp/tester -u "$uid" -g "$gid" -s /bin/sh tester
user=$(getent passwd "$uid" | cut -d: -f1)
# The display device for the live tests (tests/run passes its group id)
if [ -n "${DRI_GID:-}" ]; then
    getent group "$DRI_GID" >/dev/null || groupadd -g "$DRI_GID" dri
    usermod -aG "$(getent group "$DRI_GID" | cut -d: -f1)" "$user"
fi
mkdir -p /tmp/tester && chown "$uid:$gid" /tmp/tester
export HOME=/tmp/tester USER="$user"
exec setpriv --reuid="$uid" --regid="$gid" --init-groups "$@"
