#!/usr/bin/env python3
"""A small, safe subset of Markdown, for Nova's answers (docs/ASSISTANT.md, "How answers look").

An answer is text written by a model that may have been misled by something it read, so it
never reaches a text item that interprets it: Qt's Markdown and rich text load the pictures
they name, from the network or from disk, and show links that can say one address and go to
another. Slate reads the answer here instead, understands a short list of things, and hands
the window plain data to draw with its own items. Nothing here writes HTML, and anything not
understood comes out as the characters it is.

    parse(text) -> [block, …]
        {"type": "paragraph", "runs": [run, …]}
        {"type": "heading", "runs": [run, …]}                (any level: one bold line)
        {"type": "list", "items": [{"level": 0 | 1, "marker": "•" | "3.", "runs": [run, …]}, …]}
        {"type": "code", "text": …, "lang": …, "open": bool}  (open: its fence isn't closed yet)
        {"type": "table", "text": …}                         (its rows as typed, for monospace)
    run: {"text": …} plus whichever of "bold", "italic", "code", "dim" are true

Understood: paragraphs and line breaks, **bold**, *italic* (and __ / _), `code`, fenced code
blocks, -, * , + and 1. lists with one level of nesting, # headings. Not: an image becomes
"[image: its description]" and nothing is fetched; a link becomes its words and then its
address in dim text, never something to click; raw HTML and entities stay as typed; a table
stays its rows; quotes, rules, footnotes and deeper nesting are tidied to plain text.

While an answer is still arriving, an unclosed mark (**bol) is plain characters and an
unclosed fence is a code box still being filled. Past LIMIT characters or BLOCKS blocks it
stops, with "…".

    safe_markdown.py < answer.md     the blocks, as JSON (for trying it by hand)
"""
import bisect
import json
import re
import sys

LIMIT = 20000          # characters read
BLOCKS = 200           # blocks (each list item counts as one)
MORE = "…"

FENCE = re.compile(r"^(\s*)(`{3,}|~{3,})\s*([^`\s]*)[^`]*$")
HEADING = re.compile(r"^\s{0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$")
ITEM = re.compile(r"^(\s*)([-*+]|\d{1,9}[.)])(?:[ \t]+(.*)|[ \t]*$)")
RULE = re.compile(r"^\s{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$")
QUOTE = re.compile(r"^\s{0,3}>[ \t]?")
TABLE_RULE = re.compile(r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$|^\s*\|\s*:?-+:?\s*\|\s*$")
PUNCT = set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")


# ---- Blocks ------------------------------------------------------------------

def parse(text):
    """The blocks of an answer (see the top of this file)."""
    text = str(text or "")
    cut = len(text) > LIMIT
    text = text[:LIMIT].replace("\r\n", "\n").replace("\r", "\n").replace("\t", "    ")
    blocks, budget = [], [BLOCKS]
    lines = text.split("\n")
    i, para, items = 0, [], []

    def room():
        return budget[0] > 0

    def spend():
        budget[0] -= 1

    def end_para():
        if para and room():
            blocks.append({"type": "paragraph", "runs": inline("\n".join(para))})
            spend()
        elif para:
            budget[0] = -1          # (words left out: "…" says so)
        para.clear()

    def end_list():
        if items:
            blocks.append({"type": "list", "items": list(items)})
        items.clear()
        counters[0] = counters[1] = 0

    def end():
        end_para()
        end_list()

    counters, base = [0, 0], [0]
    # (the next line with words in it after each line, worked out once)
    after, nxt = [0] * len(lines), len(lines)
    for k in range(len(lines) - 1, -1, -1):
        after[k] = nxt
        if lines[k].strip():
            nxt = k
    while i < len(lines) and room():
        line = lines[i]
        # A fenced code block: everything to its closing fence, as typed (an indented fence,
        # as in a list's steps, takes its indent off every line)
        m = FENCE.match(line)
        if m:
            end()
            indent, fence, lang = len(m.group(1)), m.group(2), m.group(3)
            body, i, closed = [], i + 1, False
            while i < len(lines):
                ln = lines[i]
                if re.match(r"^\s*" + re.escape(fence[0]) + "{%d,}\\s*$" % len(fence), ln):
                    closed = True
                    i += 1
                    break
                body.append(ln[min(indent, len(ln) - len(ln.lstrip(" "))):])
                i += 1
            blocks.append({"type": "code", "text": "\n".join(body), "lang": lang[:20], "open": not closed})
            spend()
            continue
        if not line.strip():
            end_para()
            # (a blank line between items keeps the list going; anything else after it ends it)
            if items and not (after[i] < len(lines) and ITEM.match(lines[after[i]])):
                end_list()
            i += 1
            continue
        m = HEADING.match(line)
        if m:
            end()
            if (m.group(2) or "").strip():
                blocks.append({"type": "heading", "runs": inline(m.group(2))})
                spend()
            i += 1
            continue
        if RULE.match(line):
            end()
            i += 1
            continue
        # A table: rows starting with |, or a header row over a |---|---| row
        if line.lstrip().startswith("|") and line.count("|") >= 2 or \
                "|" in line and i + 1 < len(lines) and TABLE_RULE.match(lines[i + 1]) and not para:
            end()
            rows = []
            while i < len(lines) and "|" in lines[i] and lines[i].strip():
                rows.append(lines[i].strip())
                i += 1
            blocks.append({"type": "table", "text": "\n".join(rows)})
            spend()
            continue
        m = ITEM.match(line)
        # (a number only starts a list inside a paragraph if it's 1: "2026. was a good year")
        if m and not (para and m.group(2)[0].isdigit() and int(m.group(2)[:-1]) != 1):
            end_para()
            lead, mark = len(m.group(1)), m.group(2)
            # One level of nesting: indented further than the list's own items. Anything
            # deeper is drawn at that level too
            level = 1 if items and lead >= base[0] + 2 else 0
            if level == 0:
                base[0] = lead
                counters[1] = 0
            if mark[0].isdigit():
                counters[level] = counters[level] + 1 if counters[level] else int(mark[:-1])
                marker = "%d." % counters[level]
            else:
                counters[level] = 0
                marker = "•"
            body = [m.group(3) or ""]
            i += 1
            # Its next lines: the rest of its words
            while i < len(lines) and lines[i].strip() and not ITEM.match(lines[i]) and not FENCE.match(lines[i]) \
                    and not HEADING.match(lines[i]) and not RULE.match(lines[i]):
                body.append(QUOTE.sub("", lines[i], count=1).strip())
                i += 1
            items.append({"level": level, "marker": marker, "runs": inline("\n".join(body))})
            spend()
            continue
        if items:
            end_list()
        # Anything else is words: a quote loses its >, and the line is kept as a line
        para.append(QUOTE.sub("", line, count=1).strip())
        i += 1
    end()
    if cut or i < len(lines) or budget[0] < 0:
        blocks.append({"type": "paragraph", "runs": [{"text": MORE}]})
    return blocks


def plain(blocks):
    """The words of the blocks without their marks: for a notification's line."""
    out = []
    for b in blocks:
        if "runs" in b:
            out.append("".join(r["text"] for r in b["runs"]))
        elif "items" in b:
            out += [it["marker"] + " " + "".join(r["text"] for r in it["runs"]) for it in b["items"]]
        else:
            out.append(b.get("text", ""))
    return "\n".join(out)


# ---- Inline: bold, italic, code, and what isn't understood -------------------
# Tokens: ("text", s) | ("code", s) | ("delim", char, count, can_open, can_close) |
# ("link", [tokens' runs], address) | ("image", description). Emphasis is matched afterwards
# with a stack, as CommonMark does, so no input makes it slow.

def _brackets(s):
    """Where each [ closes: {open: close}, in one pass (a \\[ is no bracket)."""
    pairs, stack, i = {}, [], 0
    while i < len(s):
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "[":
            stack.append(i)
        elif c == "]" and stack:
            pairs[stack.pop()] = i
        i += 1
    return pairs


def _backticks(s):
    """Every run of backticks: {length: [starts]}, for finding a code span's end quickly."""
    runs = {}
    for m in re.finditer(r"`+", s):
        runs.setdefault(len(m.group()), []).append(m.start())
    return runs


ADDRESS = re.compile(r"\(\s*(<[^<>\n]*>|[^\s()<>]*(?:\([^\s()]*\)[^\s()<>]*)*)(?:\s+(?:\"[^\"\n]*\"|'[^'\n]*'|\([^()\n]*\)))?\s*\)")
TICKS = re.compile(r"`+")
DELIMS = {"*": re.compile(r"\*+"), "_": re.compile(r"_+")}


def _address(s, i):
    """A link's (address) starting at s[i]: (address, end) or None. (A regular expression with
    nothing to backtrack over, so a long run of brackets can't make it slow.)"""
    m = ADDRESS.match(s, i)
    if not m:
        return None
    url = m.group(1)
    return (url[1:-1] if url.startswith("<") else url), m.end()


def _flanking(s, i, n):
    before = s[i - 1] if i > 0 else " "
    after = s[i + n] if i + n < len(s) else " "
    left = not after.isspace() and (after not in PUNCT or before.isspace() or before in PUNCT)
    right = not before.isspace() and (before not in PUNCT or after.isspace() or after in PUNCT)
    return before, after, left, right


def _tokens(s, depth=0):
    toks, i, buf = [], 0, []
    # (links inside links inside links: past that, brackets are just brackets)
    pairs, ticks = (_brackets(s) if depth < 3 else {}), _backticks(s)

    def flush():
        if buf:
            toks.append(["text", "".join(buf)])
            buf.clear()
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s) and s[i + 1] in PUNCT:
            buf.append(s[i + 1])
            i += 2
            continue
        if c == "`":
            n = len(TICKS.match(s, i).group())
            starts = ticks.get(n, [])
            k = bisect.bisect_right(starts, i)
            if k < len(starts):
                end = starts[k]
                body = s[i + n:end].replace("\n", " ")
                if len(body) > 2 and body[0] == " " and body[-1] == " " and body.strip():
                    body = body[1:-1]
                flush()
                toks.append(["code", body])
                i = end + n
            else:
                buf.append("`" * n)
                i += n
            continue
        if c == "!" and s[i + 1:i + 2] == "[" and (i + 1) in pairs:
            close = pairs[i + 1]
            got = _address(s, close + 1)
            if got:
                flush()
                words = "".join(r["text"] for r in _runs(_tokens(s[i + 2:close], depth + 1))).strip()
                toks.append(["image", words])
                i = got[1]
                continue
        if c == "[" and i in pairs:
            close = pairs[i]
            got = _address(s, close + 1)
            if got:
                flush()
                toks.append(["link", _runs(_tokens(s[i + 1:close], depth + 1)), got[0]])
                i = got[1]
                continue
        if c in "*_":
            n = len(DELIMS[c].match(s, i).group())
            before, after, left, right = _flanking(s, i, n)
            if c == "*":
                can_open, can_close = left, right
            else:
                can_open = left and (not right or before in PUNCT)
                can_close = right and (not left or after in PUNCT)
            flush()
            toks.append(["delim", c, n, can_open, can_close, n])
            i += n
            continue
        buf.append(c)
        i += 1
    flush()
    return toks


def _emphasis(toks):
    """Match * and _ runs into bold and italic: [(opener, closer, 1 | 2), …]. Unmatched ones
    stay as their characters (each delim token keeps its count left in [2])."""
    found, stack, bottom = [], [], {"*": 0, "_": 0}
    for t, tok in enumerate(toks):
        if tok[0] != "delim":
            continue
        c = tok[1]
        if tok[4]:
            while tok[2] > 0:
                j = len(stack) - 1
                while j >= bottom[c]:
                    o = toks[stack[j]]
                    # (CommonMark's rule of three, so ***a** reads as it should)
                    odd = (o[3] and o[4] or tok[3] and tok[4]) and (o[5] + tok[5]) % 3 == 0 and not (o[5] % 3 == 0 and tok[5] % 3 == 0)
                    if o[1] == c and o[2] > 0 and not odd:
                        break
                    j -= 1
                if j < bottom[c]:
                    bottom[c] = len(stack)
                    break
                o = toks[stack[j]]
                use = 2 if o[2] >= 2 and tok[2] >= 2 else 1
                found.append((stack[j], t, use))
                o[2] -= use
                tok[2] -= use
                del stack[j + 1:]
                for k in bottom:
                    bottom[k] = min(bottom[k], len(stack))
                if o[2] == 0:
                    stack.pop()
        if tok[3] and tok[2] > 0:
            stack.append(t)
    return found


def _runs(toks):
    """The tokens as runs of text with their marks, adjacent alike runs joined."""
    n = len(toks)
    bold, italic = [0] * (n + 1), [0] * (n + 1)
    for a, b, use in _emphasis(toks):
        d = bold if use == 2 else italic
        d[a + 1] += 1
        d[b] -= 1
    out, b_on, i_on = [], 0, 0

    def add(text, **marks):
        if not text:
            return
        run = {"text": text}
        run.update({k: True for k, v in marks.items() if v})
        if out and {k: v for k, v in out[-1].items() if k != "text"} == {k: v for k, v in run.items() if k != "text"}:
            out[-1]["text"] += text
        else:
            out.append(run)
    for t, tok in enumerate(toks):
        b_on += bold[t]
        i_on += italic[t]
        marks = {"bold": b_on > 0, "italic": i_on > 0}
        kind = tok[0]
        if kind == "text":
            add(tok[1], **marks)
        elif kind == "code":
            add(tok[1], code=True, **marks)
        elif kind == "delim":
            add(tok[1] * tok[2], **marks)
        elif kind == "image":
            add("[image: %s]" % tok[1] if tok[1] else "[image]", **marks)
        elif kind == "link":
            words = "".join(r["text"] for r in tok[1])
            for r in tok[1]:
                add(r["text"], bold=marks["bold"] or r.get("bold"), italic=marks["italic"] or r.get("italic"),
                    code=r.get("code"), dim=r.get("dim"))
            address = tok[2]
            if address and address != words.strip():
                add(" ", **marks)
                add(address, dim=True)
    return out


def inline(s):
    """One block's words as runs."""
    return _runs(_tokens(s))


if __name__ == "__main__":
    json.dump(parse(sys.stdin.read()), sys.stdout, ensure_ascii=False, indent=1)
    sys.stdout.write("\n")
