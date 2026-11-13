#!/usr/bin/env python3
"""tests/run --approve [scene…]: approve the screenshots a test run just took, without taking
them again.

A scene that differs from its approved picture (or has none) fails, and the run keeps what was
on screen as tests/out/visual/<scene>.actual.png, with a diff beside it. Once you've looked at
those and they're right, this makes them the approved pictures (tests/visual/baselines), all of
them or just the scenes named. Nothing is run, so the picture you looked at is exactly the one
approved.

Only pictures that are still current are approved: one taken before Slate's code (shell/) or
the scenes (tests/visual/scenes.py) last changed is left alone and named, as it may no longer
be what Slate draws. Run the visual tests again for those (tests/run --tier visual), or re-shoot
them (tests/run --update-baselines <scene>).

The page to look at them on, and pick which to approve, is tests/out/visual/review.html
(review.py); approving brings it up to date.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(os.environ.get("SLATE_TEST_OUT") or os.path.join(ROOT, "tests", "out"), "visual")
BASELINES = os.path.join(ROOT, "tests", "visual", "baselines")
SUFFIX = ".actual.png"


def newest_change():
    """When Slate's code or the scenes last changed."""
    newest = os.path.getmtime(os.path.join(ROOT, "tests", "visual", "scenes.py"))
    for d, dirs, names in os.walk(os.path.join(ROOT, "shell")):
        dirs[:] = [x for x in dirs if x != "__pycache__"]
        for n in names:
            newest = max(newest, os.path.getmtime(os.path.join(d, n)))
    return newest


def main(argv):
    from PIL import Image       # (here: review.py uses the rest, and needs no Pillow)
    force = "--stale" in argv
    wanted = [a for a in argv if not a.startswith("-")]
    taken = sorted(n[:-len(SUFFIX)] for n in os.listdir(OUT) if n.endswith(SUFFIX)) if os.path.isdir(OUT) else []
    if not taken:
        print("Nothing to approve: no test run has left a changed screenshot in tests/out/visual.")
        return 0
    unknown = [w for w in wanted if w not in taken]
    if unknown:
        print("No changed screenshot for: %s (there's %s)" % (", ".join(unknown), ", ".join(taken)), file=sys.stderr)
        return 2
    changed_at = newest_change()
    approved, added, stale = [], [], []
    for name in wanted or taken:
        actual = os.path.join(OUT, name + SUFFIX)
        if os.path.getmtime(actual) < changed_at and not force:
            stale.append(name)
            continue
        target = os.path.join(BASELINES, name + ".png")
        (approved if os.path.exists(target) else added).append(name)
        os.makedirs(BASELINES, exist_ok=True)
        # (as RGB, compressed harder: the same pixels in a smaller file for git)
        Image.open(actual).convert("RGB").save(target, optimize=True)
        os.remove(actual)
        diff = os.path.join(OUT, name + ".diff.png")
        if os.path.exists(diff):
            os.remove(diff)
    if approved:
        print("Approved: " + ", ".join(approved))
    if added:
        print("New: " + ", ".join(added))
    if stale:
        print("Left alone, taken before Slate's code last changed (run the visual tests again): " + ", ".join(stale))
    # The review page (review.py) shows only what's left to approve, or goes
    import review
    review.build(OUT, BASELINES)
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
