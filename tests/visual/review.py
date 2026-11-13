#!/usr/bin/env python3
"""One page for approving screenshots: tests/out/visual/review.html.

After a visual run with changed scenes (tests/run writes it then, and prints where), it shows
for every scene the run left a picture of (<scene>.actual.png): the approved picture, the new
one and the difference, side by side, each with a tick box. Below the title is the
`tests/run --approve <scenes…>` line for the ticked ones, to copy. A scene with no approved
picture yet says so; one taken before Slate's code last changed (which --approve would leave
alone) starts unticked.

A plain static file: inline CSS and JS, no network, and the pictures by relative path. The
approved ones are copied beside the others (<scene>.approved.png), so the page shows what was
compared even after the baselines change. With nothing changed, there's no page.

    python3 tests/visual/review.py         (re)build it; prints its path, or nothing
"""
import datetime
import html
import os
import shutil
import sys
from urllib.parse import quote

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import approve  # noqa: E402  (where the pictures are, and when the code last changed)

PAGE = "review.html"
SUFFIX = approve.SUFFIX         # .actual.png
APPROVED = ".approved.png"
DIFF = ".diff.png"

STYLE = """
:root { color-scheme: dark light; --bg: #16181d; --card: #1f2229; --line: #30343d; --text: #e4e6eb;
  --dim: #9aa0ab; --accent: #8ab4f8; --warn: #e8b86a; --code: #0f1115; }
@media (prefers-color-scheme: light) {
  :root { --bg: #f4f5f7; --card: #ffffff; --line: #d9dce1; --text: #1d2025; --dim: #5f6570;
    --accent: #2f6fd6; --warn: #9a6400; --code: #eceef1; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 15px/1.5 system-ui, sans-serif; }
header { position: sticky; top: 0; z-index: 1; background: var(--bg); border-bottom: 1px solid var(--line);
  padding: 16px 24px 14px; }
h1 { font-size: 19px; font-weight: 600; margin: 0 0 2px; }
.lead { color: var(--dim); margin: 0 0 12px; }
.cmd { display: flex; gap: 8px; align-items: stretch; }
.cmd code { flex: 1; min-width: 0; max-height: 6.5em; overflow-y: auto; overflow-wrap: anywhere; background: var(--code);
  border: 1px solid var(--line); border-radius: 6px; padding: 7px 10px; font: 13px/1.5 ui-monospace, monospace; }
.cmd code.none { color: var(--dim); font-family: inherit; }
button { font: inherit; font-size: 13px; color: var(--text); background: var(--card); border: 1px solid var(--line);
  border-radius: 6px; padding: 6px 12px; cursor: pointer; }
button:hover { border-color: var(--accent); }
.bulk { margin-top: 10px; display: flex; gap: 8px; align-items: center; color: var(--dim); font-size: 13px; }
main { padding: 8px 24px 40px; }
section { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 12px 14px 14px;
  margin: 16px 0; }
section.off { opacity: .55; }
.top { display: flex; flex-wrap: wrap; gap: 4px 14px; align-items: baseline; margin-bottom: 10px; }
.top label { display: flex; gap: 8px; align-items: center; font-weight: 600; cursor: pointer; }
.top input { width: 17px; height: 17px; accent-color: var(--accent); margin: 0; }
.note { color: var(--dim); font-size: 13px; }
.note.warn { color: var(--warn); }
.shots { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 12px; }
figure { margin: 0; }
figcaption { color: var(--dim); font-size: 13px; margin-bottom: 4px; }
figure a { display: block; }
figure img { display: block; width: 100%; height: auto; border: 1px solid var(--line); border-radius: 4px; }
.missing { display: flex; align-items: center; justify-content: center; aspect-ratio: 16 / 10;
  border: 1px dashed var(--line); border-radius: 4px; color: var(--dim); font-size: 13px; text-align: center; padding: 8px; }
"""

SCRIPT = """
const boxes = [...document.querySelectorAll('input[type=checkbox]')];
const cmd = document.getElementById('cmd');
const count = document.getElementById('count');
function update() {
  const on = boxes.filter(b => b.checked).map(b => b.value);
  boxes.forEach(b => b.closest('section').classList.toggle('off', !b.checked));
  cmd.textContent = on.length ? 'tests/run --approve ' + on.join(' ') : 'Tick the scenes that look right to approve them.';
  cmd.classList.toggle('none', !on.length);
  count.textContent = on.length + ' of ' + boxes.length + ' ticked';
}
boxes.forEach(b => b.addEventListener('change', update));
document.getElementById('all').onclick = () => { boxes.forEach(b => b.checked = true); update(); };
document.getElementById('none').onclick = () => { boxes.forEach(b => b.checked = false); update(); };
document.getElementById('copy').onclick = async (e) => {
  if (cmd.classList.contains('none')) return;
  const text = cmd.textContent;
  try { await navigator.clipboard.writeText(text); }
  catch (_) {
    const t = document.createElement('textarea'); t.value = text; document.body.appendChild(t);
    t.select(); document.execCommand('copy'); t.remove();
  }
  e.target.textContent = 'Copied'; setTimeout(() => e.target.textContent = 'Copy', 1500);
};
update();
"""


def known_scenes():
    """The scenes there are now (scenes.py), or None if it can't be read here."""
    try:
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
        import scenes as defined  # noqa: E402
        return set(defined.SCENES)
    except Exception:       # (the page still works, listing every picture)
        return None


def scenes(out):
    """Every scene the last runs left a picture of, by name: only scenes that still exist (a
    picture left by a scene since renamed or removed would otherwise stay on the page for good)."""
    if not os.path.isdir(out):
        return []
    known = known_scenes()
    return sorted(n[:-len(SUFFIX)] for n in os.listdir(out)
                  if n.endswith(SUFFIX) and (known is None or n[:-len(SUFFIX)] in known))


def approve_line(names):
    return "tests/run --approve " + " ".join(names) if names else "Tick the scenes that look right to approve them."


def picture(out, file, caption, alt, missing):
    if not os.path.exists(os.path.join(out, file)):
        return f'<figure><figcaption>{caption}</figcaption><div class="missing">{missing}</div></figure>'
    src = html.escape(quote(file))
    return (f'<figure><figcaption>{caption}</figcaption><a href="{src}" target="_blank">'
            f'<img src="{src}" alt="{html.escape(alt)}" loading="lazy"></a></figure>')


def build(out=approve.OUT, baselines=approve.BASELINES):
    """Write the page for the scenes in `out` (tests/out/visual); returns its path, or None
    (and no page) when there's nothing to approve."""
    names = scenes(out)
    page = os.path.join(out, PAGE)
    # Copies of approved pictures for scenes that are done with go
    if os.path.isdir(out):
        for n in os.listdir(out):
            if n.endswith(APPROVED) and n[:-len(APPROVED)] not in names:
                os.remove(os.path.join(out, n))
    if not names:
        if os.path.exists(page):
            os.remove(page)
        return None
    changed_at = approve.newest_change()
    rows, ticked = [], []
    for name in names:
        actual = os.path.join(out, name + SUFFIX)
        baseline = os.path.join(baselines, name + ".png")
        if os.path.exists(baseline):
            shutil.copyfile(baseline, os.path.join(out, name + APPROVED))
        elif os.path.exists(os.path.join(out, name + APPROVED)):
            os.remove(os.path.join(out, name + APPROVED))
        taken = os.path.getmtime(actual)
        stale = taken < changed_at
        notes = []
        if not os.path.exists(baseline):
            notes.append('<span class="note">New: no approved picture yet</span>')
        notes.append(f'<span class="note">Taken {datetime.datetime.fromtimestamp(taken):%d %b, %H:%M}</span>')
        if stale:
            notes.append('<span class="note warn">Taken before Slate\'s code last changed: --approve leaves it '
                         'alone, so run the visual tests again for it</span>')
        else:
            ticked.append(name)
        e = html.escape(name)
        rows.append(f"""<section id="{e}">
<div class="top"><label><input type="checkbox" value="{e}"{'' if stale else ' checked'}> {e}</label>{''.join(notes)}</div>
<div class="shots">
{picture(out, name + APPROVED, "Approved", f"{name}, approved", "No approved picture yet")}
{picture(out, name + SUFFIX, "New", f"{name}, new", "")}
{picture(out, name + DIFF, "Difference (changes in red)", f"{name}, difference", "Nothing to compare it with")}
</div>
</section>""")
    count = f"{len(names)} scene{'s' if len(names) != 1 else ''} to look at"
    text = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Screenshots to approve</title>
<style>{STYLE}</style>
</head>
<body>
<header>
<h1>Screenshots to approve</h1>
<p class="lead">{count}. Tick the ones that look right, then run this line in Slate's folder:
nothing runs again, the pictures here become the approved ones.</p>
<div class="cmd"><code id="cmd">{html.escape(approve_line(ticked))}</code><button id="copy" type="button">Copy</button></div>
<div class="bulk"><button id="all" type="button">Tick all</button><button id="none" type="button">Untick all</button>
<span id="count"></span></div>
</header>
<main>
{chr(10).join(rows)}
</main>
<script>{SCRIPT}</script>
</body>
</html>
"""
    with open(page, "w", encoding="utf-8") as f:
        f.write(text)
    return page


def main():
    page = build()
    if page:
        print(os.path.relpath(page) if page.startswith(os.getcwd()) else page)
    return 0


if __name__ == "__main__":
    sys.exit(main())
