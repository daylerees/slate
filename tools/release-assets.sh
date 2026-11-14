#!/usr/bin/env bash
# The two files every release carries, which Slate's updater downloads and checks before it
# installs anything (shell/scripts/update.py):
#
#   slate-<tag>.tar.gz           the tagged code, in a folder called slate-<tag>/
#   slate-<tag>.tar.gz.sha256    its SHA-256, as sha256sum writes it
#
#   tools/release-assets.sh <tag> [folder]
#
# Run it in the repository once the tag exists. It prints the two paths and nothing else, so
# they can be handed straight to gh:
#
#   gh release create v1.2.3 --title v1.2.3 --notes-file notes.md $(tools/release-assets.sh v1.2.3)
#   gh release upload v1.2.3 $(tools/release-assets.sh v1.2.3)      # a release that's already there
#
# The archive is made from the tag itself (git archive), never from the working folder, so
# nothing uncommitted can get in. GitHub's own "Source code" downloads aren't used for this:
# they're made afresh when asked for and aren't promised to stay the same byte for byte, so a
# checksum of one could stop matching.
set -euo pipefail

tag=${1:-}
if [[ ! $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: tools/release-assets.sh <tag> [folder]   (a tag like v1.2.3)" >&2
    exit 2
fi
if ! git rev-parse --quiet --verify "refs/tags/$tag^{commit}" >/dev/null; then
    echo "There's no tag called $tag here. Tag the release first." >&2
    exit 1
fi

out=${2:-$(mktemp -d "${TMPDIR:-/tmp}/slate-release-XXXXXX")}
mkdir -p "$out"
out=$(cd "$out" && pwd)
name="slate-$tag.tar.gz"

# (gzip -n leaves the time and name out of the file, so the same tag gives the same bytes)
git archive --format=tar --prefix="slate-$tag/" "refs/tags/$tag" | gzip -n -9 > "$out/$name"
(cd "$out" && sha256sum "$name" > "$name.sha256")

printf '%s\n' "$out/$name" "$out/$name.sha256"
