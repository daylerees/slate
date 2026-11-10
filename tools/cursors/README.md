# Slate Cursors

Slate's cursor theme: **Bibata Modern Ice** v2.0.6 by Abdulkaiz Khatri (ful1e5),
<https://github.com/ful1e5/Bibata_Cursor>, redrawn without colour so every cursor matches
the white pointer.

## Changes from Bibata Modern Ice

- The corner resize cursors' coloured quarter-circles are white, like the side ones.
- The loading spinner's four colours are four greys.
- The coloured badges (copy, not-allowed, link, help, context menu…) are dark grey, with
  their white symbols; the crosshair's red dot is black.
- The diagonal double-arrow names (`nwse-resize`, `size_fdiag`, `nesw-resize`, `size_bdiag`)
  show the top-left and top-right corner cursors, so a diagonal resize asked for by name
  (Slate's title bar corners, which can only ask for those) looks like Hyprland's window
  corners.
- Renamed to `Slate-Cursors`.

Everything else is unchanged.

## Licence

GPL-3.0, like Bibata (see `LICENSE`). The cursors' source is the SVGs inside
`hyprcursors/*.hlc` (zip files). Slate's `tools/build-cursors.py` rebuilds the theme
from an installed Bibata Modern Ice. Slate's own code is MIT; this theme is a separate
work that ships alongside it.
