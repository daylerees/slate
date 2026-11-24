#!/usr/bin/env bash
# The three files every release carries, which Slate's updaters download and check before they
# install anything (shell/scripts/update.py, shell/bin/slate-update-install):
#
#   slate-<tag>.tar.gz           the tagged code, in a folder called slate-<tag>/
#   slate-<tag>.tar.gz.sha256    its SHA-256, as sha256sum writes it
#   slate-<tag>.tar.gz.sig       its SSH signature (ssh-keygen -Y sign, namespace slate-release),
#                                with Slate's release key; the updaters check it against
#                                shell/data/release-signers and install nothing unsigned
#
# The key is the author's: $SLATE_RELEASE_KEY, or ~/.local/share/slate-dev/release-signing/slate-release
# (kept there and in their password manager, never in the repository).
#
#   tools/release-assets.sh <tag> [folder]
#
# Run it in the repository once the tag exists. It prints the three paths and nothing else, so
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

key=${SLATE_RELEASE_KEY:-$HOME/.local/share/slate-dev/release-signing/slate-release}
if [ ! -f "$key" ]; then
    echo "There's no release key at $key, so $tag can't be signed. Put it back from the password manager." >&2
    exit 1
fi
# (the key that signs must be the one the updaters trust, or every update would be refused)
want=$(grep -v '^#' shell/data/release-signers | awk '{print $3, $4}')
have=$(ssh-keygen -y -f "$key" | awk '{print $1, $2}')
if [ "$want" != "$have" ]; then
    echo "The key at $key isn't the one in shell/data/release-signers, so nothing was signed." >&2
    exit 1
fi

out=${2:-$(mktemp -d "${TMPDIR:-/tmp}/slate-release-XXXXXX")}
mkdir -p "$out"
out=$(cd "$out" && pwd)
name="slate-$tag.tar.gz"

# (gzip -n leaves the time and name out of the file, so the same tag gives the same bytes)
git archive --format=tar --prefix="slate-$tag/" "refs/tags/$tag" | gzip -n -9 > "$out/$name"
(cd "$out" && sha256sum "$name" > "$name.sha256")
rm -f "$out/$name.sig"
ssh-keygen -q -Y sign -f "$key" -n slate-release "$out/$name" >/dev/null 2>&1 \
    || { echo "Signing $name with $key didn't work." >&2; exit 1; }
# (checked as the updaters will, before it goes anywhere)
ssh-keygen -Y verify -f shell/data/release-signers -I slate-release -n slate-release -s "$out/$name.sig" \
    < "$out/$name" >/dev/null 2>&1 || { echo "The signature on $name doesn't check out." >&2; exit 1; }

printf '%s\n' "$out/$name" "$out/$name.sha256" "$out/$name.sig"
