# The docs' pictures

The pictures on the docs pages (`site/docs/img/*.webp`) are taken here, in the test container,
from a real Slate session like the visual tier's. Nothing comes from your own screen.

```sh
tests/run --docs-shots                       # every picture (about three minutes)
tests/run --docs-shots dock launcher-grid    # just these
python3 tools/docs-shots/shoot.py --recrop dock   # crop again after changing a crop (no container)
```

It needs what the visual tier needs: Docker and the `vkms` module (`sudo modprobe vkms`; see
docs/TESTING.md). It isn't a test and compares nothing: the pictures go straight into
`site/docs/img/`, and each whole screen is kept in `tests/out/docs-shots/<name>.png` to look at.
Look at every changed picture before committing it.

## How they're made

- `scenes.py` lists the pictures: the same shape as `tests/visual/scenes.py` (settings, IPC
  steps, a wait on the `test` state, an undo), plus a `crop` in the screen's own 1440×900.
- `shoot.py` starts the session (`tests/lib/session.py`) with the screen at a scale of 2, so
  every picture has twice the pixels it's shown at, crops it and saves it as WebP.
- Slate is as it comes: dark, its own accent, flat (no glass), Slate's Cobalt (plain)
  wallpaper, and the test time (Monday, 5 January 2026, 9:41).
- Everything shown is made up: the apps are terminals with app ids of their own (Files, Mail,
  Notes…, with icons from Papirus), the windows show fixed text, and the downloads, saved
  spaces, notifications, song and weather are invented. PipeWire runs with a pretend speaker,
  so the volume shows 60%. The container has no network, so the bar says Offline.

## Adding one

1. Add it to `SHOTS` in `scenes.py`, then `tests/run --docs-shots <name>`.
2. Look at `tests/out/docs-shots/<name>.png`, set the `crop`, and `--recrop` it.
3. Put it on its page:

   ```html
   <figure class="shot">
     <img src="img/<name>.webp" width="<half its width>" height="<half its height>" loading="lazy"
       alt="What it shows, in a sentence">
     <figcaption>Only when it adds something.</figcaption>
   </figure>
   ```

`tests/static/test_docs.py` checks every picture on the docs pages is there, has alt text, a
width and height of half its pixels and `loading="lazy"`, and that nothing in `site/docs/img`
is left unused.
