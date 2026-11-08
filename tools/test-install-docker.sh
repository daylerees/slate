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
command -v slate >/dev/null || test -x /home/tester/.local/bin/slate && echo "slate command: ok"
python3 -c "import PIL" && echo "python Pillow: ok" || echo "python Pillow: MISSING"
echo "--- QML modules Slate imports (no display here, so windows are not created) ---"
mkdir -p /tmp/qmlcheck
{ grep -hoE "^import [A-Za-z0-9_.]+" /home/tester/.config/slate/*.qml /home/tester/.config/slate/greeter/*.qml | sort -u
  echo "ShellRoot { Component.onCompleted: { console.log(\"QML-IMPORTS-OK\"); Qt.quit(); } }"; } > /tmp/qmlcheck/shell.qml
chmod -R a+r /tmp/qmlcheck
sudo -u tester -H env QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR=/tmp timeout 20 qs -p /tmp/qmlcheck 2>&1 \
  | grep -E "QML-IMPORTS-OK|Configuration Loaded|not installed|is not a type|unavailable|caused by" | head -10 || true
echo "=== DONE ==="
' > "$LOG" 2>&1 && status=0 || status=$?
sed -n '/=== CHECKS ===/,$p' "$LOG"
echo "exit $status · full log: $LOG"
exit $status
