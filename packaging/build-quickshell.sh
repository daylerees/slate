#!/usr/bin/env bash
# Build and install Quickshell from source, for distros that don't package a new enough
# one (Ubuntu 26.04, openSUSE Tumbleweed, some Debian releases). Run as your normal user;
# it uses sudo to install build tools and the result (to /usr/local).
#
#   packaging/build-quickshell.sh            build the version below
#   QS_VERSION=v0.3.2 packaging/build-quickshell.sh
#
# Quickshell uses Qt's private APIs, so rebuild it (run this again) after your distro
# upgrades Qt, or Slate won't start.
set -euo pipefail

QS_VERSION="${QS_VERSION:-v0.3.2}"
QS_REPO="https://github.com/quickshell-mirror/quickshell"
WORK="${XDG_CACHE_HOME:-$HOME/.cache}/slate/quickshell-build"

. /etc/os-release
like=" ${ID:-} ${ID_LIKE:-} "
cmake_extra=()

case "$like" in
    *" ubuntu "*|*" debian "*)
        deps=(git cmake ninja-build pkgconf g++ qt6-base-dev qt6-declarative-dev qt6-wayland-dev
              qt6-shadertools-dev qt6-base-private-dev qt6-declarative-private-dev qt6-wayland-private-dev
              libcli11-dev libwayland-dev wayland-protocols libpipewire-0.3-dev libpam0g-dev
              libpolkit-agent-1-dev libpolkit-gobject-1-dev libglib2.0-dev libdrm-dev libgbm-dev
              libjemalloc-dev libegl-dev libgles-dev libvulkan-dev libxcb1-dev spirv-tools
              qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts qt6-svg-plugins)
        # The crash reporter needs cpptrace: Debian packages it, Ubuntu doesn't (build it in)
        if apt-cache show libcpptrace-dev >/dev/null 2>&1; then deps+=(libcpptrace-dev)
        else deps+=(libunwind-dev libdwarf-dev libzstd-dev); cmake_extra+=(-DVENDOR_CPPTRACE=ON); fi
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${deps[@]}" ;;
    *" opensuse"*|*" suse "*)
        deps=(git cmake ninja gcc-c++ pkgconf qt6-base-devel qt6-base-private-devel qt6-declarative-devel
              qt6-declarative-private-devel qt6-wayland-devel qt6-wayland-private-devel qt6-shadertools-devel
              qt6-svg-devel cli11-devel cpptrace-devel jemalloc-devel wayland-devel wayland-protocols-devel
              pipewire-devel pam-devel polkit-devel glib2-devel libdrm-devel libgbm-devel vulkan-headers
              spirv-tools libxcb-devel)
        sudo zypper --non-interactive install "${deps[@]}" ;;
    *" fedora "*)
        echo "On Fedora, install Quickshell from the COPR instead: sudo dnf copr enable errornointernet/quickshell && sudo dnf install quickshell" >&2
        exit 1 ;;
    *)
        echo "Don't know this distro's build packages; see $QS_REPO/blob/master/BUILD.md" >&2
        exit 1 ;;
esac

# Where this distro's Qt keeps QML modules (Quickshell installs its own there)
qmldir=""
for q in qtpaths6 qtpaths-qt6 /usr/lib/qt6/bin/qtpaths /usr/lib64/qt6/bin/qtpaths; do
    if command -v "$q" >/dev/null 2>&1; then qmldir=$("$q" --query QT_INSTALL_QML 2>/dev/null) && [ -n "$qmldir" ] && break; fi
done
[ -n "$qmldir" ] && cmake_extra+=(-DINSTALL_QMLDIR="$qmldir")

mkdir -p "$WORK"
rm -rf "$WORK/src"
git clone --depth 1 --branch "$QS_VERSION" "$QS_REPO" "$WORK/src"
cmake -S "$WORK/src" -B "$WORK/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DDISTRIBUTOR="Slate installer (source build)" -DX11=OFF -DI3=OFF "${cmake_extra[@]}"
cmake --build "$WORK/build"
sudo cmake --install "$WORK/build"
echo "Quickshell $QS_VERSION installed to /usr/local ($(command -v qs || echo 'qs not on PATH?'))"
