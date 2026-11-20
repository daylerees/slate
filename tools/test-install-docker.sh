#!/usr/bin/env bash
# Try the installer in a clean container:  tools/test-install-docker.sh <image>
#   e.g. archlinux:latest  debian:sid  ubuntu:26.04  fedora:44  opensuse/tumbleweed
# Runs ./install.sh --yes as a normal user with sudo, then checks Hyprland and Quickshell
# versions and that Slate's QML loads (offscreen; no display, so only import/type errors
# are meaningful). Log: /tmp/slate-install-<image>.log
set -euo pipefail
IMAGE="$1"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOG="/tmp/slate-install-$(echo "$IMAGE" | tr '/:' '__').log"

docker run --rm -v "$ROOT:/src:ro" "$IMAGE" bash -c '
set -e
. /etc/os-release
case " $ID $ID_LIKE " in
  *" arch "*)   pacman -Syu --noconfirm --needed sudo >/dev/null ;;
  *" debian "*|*" ubuntu "*) apt-get update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y sudo >/dev/null ;;
  *" fedora "*) dnf install -y sudo >/dev/null ;;
  # The Tumbleweed image uses busybox-diffutils, which blocks Qt dev packages; real installs have diffutils
  *suse*)       zypper --non-interactive install sudo shadow >/dev/null && zypper --non-interactive install --force-resolution diffutils >/dev/null ;;
esac
useradd -m tester
echo "tester ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/tester
cp -r /src /home/tester/slate && chown -R tester: /home/tester/slate
cd /home/tester/slate
sudo -u tester -H ./install.sh --yes
echo "=== CHECKS ==="
Hyprland --version 2>/dev/null | head -1 || echo "Hyprland: missing"
command -v start-hyprland >/dev/null && echo "start-hyprland: ok" || echo "start-hyprland: missing"
qs --version 2>/dev/null | head -1 || echo "qs: missing"
test -f /usr/share/wayland-sessions/slate.desktop && echo "session entry: ok"
sudo -u tester -H fc-list : family | grep -qi "^Geist" && echo "Geist font: ok" || echo "Geist font: missing"
sudo -u tester -H fc-list : family | grep -qi "^Geist Mono" && echo "Geist Mono font: ok" || echo "Geist Mono font: missing"
command -v slate >/dev/null || test -x /home/tester/.local/bin/slate && echo "slate command: ok"
python3 -c "import PIL" && echo "python Pillow: ok" || echo "python Pillow: MISSING"
# Slate for everyone (root'"'"'s, readable by all) and only your own files in your folder
[ -f /usr/local/share/slate/shell.qml ] && [ "$(stat -c %U /usr/local/share/slate)" = root ] && echo "shared copy: ok, root'"'"'s" || echo "shared copy: MISSING or not root'"'"'s"
sudo -u nobody test -r /usr/local/share/slate/shell.qml && echo "shared copy readable by others: ok" || echo "shared copy readable by others: NO"
ls /home/tester/.config/slate | tr "\n" " " | sed "s/^/your folder: /"; echo
[ ! -e /home/tester/.config/slate/shell.qml ] && echo "no code in your folder: ok" || echo "code in your folder: WRONG"
# What Slate later does as root, with the copy for everyone being root'"'"'s (not the release it came from)
S=/usr/local/share/slate
echo "helpers vs the copy for everyone: $(sudo -u tester $S/bin/slate-helpers-install --check $S 2>&1)"
sudo -u tester -H sudo $S/bin/slate-helpers-install $S slate-session-install $S >/tmp/root-steps.log 2>&1 \
    && echo "helpers and login session from the copy for everyone: ok" \
    || { echo "helpers and login session from the copy for everyone: FAILED"; sed "s/^/    /" /tmp/root-steps.log; }
todo=$(sudo -u tester $S/bin/slate-system --check 2>&1 | tr "\n" " ")
echo "slate-system --check (as you): ${todo:-nothing to do}"
out=$(sudo /usr/local/libexec/slate/slate-update-install v0.0.1 2>&1 || true)
case "$out" in *"newer"*) echo "update helper accepts the copy for everyone: ok (refused only as not newer)" ;; *) echo "update helper: UNEXPECTED: $out" ;; esac
# The firewall helper: owned by root, told only its own words, and never run from the Slate folder
F=/usr/local/libexec/slate/slate-firewall
[ -x "$F" ] && [ "$(stat -c %U "$F")" = root ] && echo "firewall helper: ok, root'"'"'s" || echo "firewall helper: MISSING or not root'"'"'s"
sudo "$F" allow telnet >/dev/null 2>&1 && echo "firewall helper took an unknown name: WRONG" || echo "firewall helper refuses an unknown name: ok"
sudo $S/bin/slate-firewall on >/dev/null 2>&1 && echo "firewall helper ran from the Slate folder: WRONG" || echo "firewall helper refuses to run from the Slate folder: ok"
# Unlocking without the password: the same, and nothing written to pam.d by asking it wrongly
U=/usr/local/libexec/slate/slate-unlock
[ -x "$U" ] && [ "$(stat -c %U "$U")" = root ] && echo "unlock helper: ok, root'"'"'s" || echo "unlock helper: MISSING or not root'"'"'s"
sudo "$U" enable password >/dev/null 2>&1 && echo "unlock helper took an unknown method: WRONG" || echo "unlock helper refuses an unknown method: ok"
rc=0; sudo "$U" enable face >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] && echo "unlock helper refuses a method that isn'"'"'t installed: ok" || echo "unlock helper and a missing module: WRONG ($rc)"
sudo $S/bin/slate-unlock remove >/dev/null 2>&1 && echo "unlock helper ran from the Slate folder: WRONG" || echo "unlock helper refuses to run from the Slate folder: ok"
[ ! -e /etc/pam.d/slate-lock ] && echo "no slate-lock written: ok" || echo "slate-lock written: WRONG"
# Someone added later, who never ran the installer: what they get without doing anything
useradd -m newbie
echo "for someone new: slate dir = $(sudo -u newbie -H /usr/local/bin/slate dir 2>&1)"
[ -f /usr/local/share/applications/slate-settings.desktop ] && echo "for someone new: Settings entry ok" || echo "for someone new: Settings entry MISSING"
[ -f /usr/local/share/icons/Slate-Cursors/index.theme ] && echo "for someone new: cursors ok" || echo "for someone new: cursors MISSING"
sudo -u newbie -H fc-list : family | grep -qi "^Geist" && echo "for someone new: Geist font ok" || echo "for someone new: Geist font MISSING"
echo "--- QML modules Slate imports (no display here, so windows are not created) ---"
mkdir -p /tmp/qmlcheck
# (Slate'"'"'s own modules, import qs…, only resolve inside Slate: left out)
{ grep -hoE "^import [A-Za-z0-9_.]+" /usr/local/share/slate/*.qml /usr/local/share/slate/greeter/*.qml | grep -v "^import qs" | sort -u
  echo "ShellRoot { Component.onCompleted: { console.log(\"QML-IMPORTS-OK\"); Qt.quit(); } }"; } > /tmp/qmlcheck/shell.qml
chmod -R a+r /tmp/qmlcheck
sudo -u tester -H env QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR=/tmp timeout 20 qs -p /tmp/qmlcheck 2>&1 \
  | grep -E "QML-IMPORTS-OK|Configuration Loaded|not installed|is not a type|unavailable|caused by" | head -10 || true
echo "=== DONE ==="
' > "$LOG" 2>&1 && status=0 || status=$?
sed -n '/=== CHECKS ===/,$p' "$LOG"
echo "exit $status · full log: $LOG"
exit $status
