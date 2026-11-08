# Artwork

Originals as generated, kept so the cut-outs can be redone:

- `logo-original.jpg` — the first logo, on a dark background (no longer used).
- `shell/assets/logo.png` — the logo: the slate mark beside "slate" in Geist, drawn by
  `tools/render-logo.py shell/assets/logo.png` (made for light backgrounds, like GitHub's light theme).
- `icon-original.jpg` — app icon with a checkerboard baked into the JPG (not real transparency).
  Cut out along the squircle's outline into `shell/assets/icon/icon-<size>.png`
  (512, 256, 128, 64, 48, 32, 16 px).

For cleaner edges, regenerate with a transparent background (PNG) or a flat background colour
far from the artwork's colours.

- `shell/assets/icon/settings-<size>.png` — the Settings / app icon, drawn from the vector
  mark (not from the generated images): `tools/render-settings-icon.py <out-dir> [accent]`.
