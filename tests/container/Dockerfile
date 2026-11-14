# The image Slate's tests run in (tests/run builds it). Arch, with Slate's packages
# (packaging/arch.txt) and the test tools, from a dated snapshot of the Arch archive
# (deps.lock) so a run is repeatable; `tests/run --deps latest` builds it from today's
# mirrors instead.
FROM archlinux:latest

# YYYY/MM/DD of the archive.archlinux.org snapshot, or empty for today's packages
ARG SNAPSHOT=
COPY arch.txt /tmp/arch.txt
RUN set -e; \
    if [ -n "$SNAPSHOT" ]; then \
        echo "Server=https://archive.archlinux.org/repos/$SNAPSHOT/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist; \
    fi; \
    # The archive can stall on big files: no download timeout, and a retry
    sed -i 's/^#\?DisableDownloadTimeout/DisableDownloadTimeout/; s/^#\?ParallelDownloads.*/ParallelDownloads = 4/' /etc/pacman.conf; \
    retry() { "$@" || { sleep 5; "$@"; } || { sleep 15; "$@"; }; }; \
    # The image's own packages may be newer than the snapshot: -uu lets them go back
    retry pacman -Syyuu --noconfirm; \
    # Slate's packages: required ones must install, optional ("?") ones if the repos have them
    req=$(grep -v '^\s*\(#\|$\)' /tmp/arch.txt | sed 's/\s*#.*//' | grep -v '^?'); \
    opt=$(grep -v '^\s*\(#\|$\)' /tmp/arch.txt | sed 's/\s*#.*//' | grep '^?' | tr -d '?' | \
          while read -r p; do pacman -Si "$p" >/dev/null 2>&1 && echo "$p"; done); \
    retry pacman -S --noconfirm --needed $req $opt \
        shellcheck lua mesa grim foot jq python-pillow git ttf-dejavu \
        xdg-desktop-portal ffmpeg wtype; \
    pacman -Scc --noconfirm; rm -rf /var/cache/pacman/pkg/*

# git: the checkout is owned by whoever runs the tests
RUN git config --system safe.directory '*'
COPY entry.sh /usr/local/bin/slate-test-entry
ENTRYPOINT ["/usr/local/bin/slate-test-entry"]
