"""Compare a screenshot with its approved one, tolerantly: anti-aliasing may move a little,
anything bigger is a change.

    result = compare(approved, actual)       # paths
    result.ok, result.reason, result.changed_fraction
    save_diff(approved, actual, out)         # the actual dimmed, with changes in red
"""
from dataclasses import dataclass

from PIL import Image, ImageChops

PIXEL_THRESHOLD = 24      # a channel differing by more than this counts the pixel as changed
MAX_CHANGED = 0.001       # fail when more than 0.1% of pixels change…
BLOCK = 16                # …or when any 16×16 block changes a lot
BLOCK_MAX = 0.25          # (more than a quarter of its pixels)


@dataclass
class Result:
    ok: bool
    reason: str
    changed_fraction: float = 0.0
    worst_block: tuple = None


def _load(path, masks=()):
    """The image, with each mask box (x, y, w, h: parts that change by themselves, like an
    uptime) painted over so it never counts as a change."""
    img = Image.open(path).convert("RGB")
    for x, y, w, h in masks:
        img.paste((255, 0, 255), (x, y, x + w, y + h))
    return img


def changed_mask(a, b):
    """A 1-bit image: white where a and b differ by more than the threshold."""
    diff = ImageChops.difference(a, b)
    r, g, bl = diff.split()
    m = ImageChops.lighter(ImageChops.lighter(r, g), bl)
    return m.point(lambda v: 255 if v > PIXEL_THRESHOLD else 0, mode="L")


def compare(approved_path, actual_path, masks=()):
    a, b = _load(approved_path, masks), _load(actual_path, masks)
    if a.size != b.size:
        return Result(False, f"size changed: {a.size[0]}×{a.size[1]} → {b.size[0]}×{b.size[1]}", 1.0)
    mask = changed_mask(a, b)
    w, h = mask.size
    changed = mask.histogram()[255]
    frac = changed / float(w * h)
    if changed == 0:
        return Result(True, "identical")
    # The block that changed most
    small = mask.resize((max(1, w // BLOCK), max(1, h // BLOCK)), Image.BOX)
    worst = max(range(small.size[0] * small.size[1]), key=lambda i: small.getdata()[i])
    worst_frac = small.getdata()[worst] / 255.0
    bx, by = (worst % small.size[0]) * BLOCK, (worst // small.size[0]) * BLOCK
    if frac > MAX_CHANGED:
        return Result(False, f"{frac * 100:.2f}% of pixels changed (most around {bx},{by})", frac, (bx, by))
    if worst_frac > BLOCK_MAX:
        return Result(False, f"a {BLOCK}×{BLOCK} area at {bx},{by} changed ({worst_frac * 100:.0f}% of it)", frac, (bx, by))
    return Result(True, f"{frac * 100:.3f}% of pixels moved (within tolerance)", frac)


def save_diff(approved_path, actual_path, out_path, masks=()):
    """The actual screenshot, dimmed, with every changed pixel in red (masked parts magenta)."""
    a, b = _load(approved_path, masks), _load(actual_path, masks)
    if a.size != b.size:
        b.save(out_path)
        return out_path
    mask = changed_mask(a, b)
    dim = Image.blend(b, Image.new("RGB", b.size, (0, 0, 0)), 0.6)
    red = Image.new("RGB", b.size, (255, 40, 40))
    Image.composite(red, dim, mask).save(out_path)
    return out_path
