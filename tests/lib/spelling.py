"""Turns British spellings into American ones in the words people read.

Slate uses American spelling in everything people read. This file knows the British
words, finds them in prose and string literals, and gives the American spelling.
tests/static/test_spelling.py uses it to check nothing British is left.

Only whole words are looked at, so identifiers (`pageColour`), settings keys, file names
and flags are never touched.
"""
import re

# Stems that take -ise/-isation in British English. Anything not listed (raise,
# otherwise, noise, promise, sunrise...) is left alone.
ISE_STEMS = ("organ recogn custom priorit minim maxim normal synchron initial person optim "
             "author summar categor visual capital util real serial local final stabil sanit "
             "special digit mobil magnet apolog critic general memor random vector raster "
             "parameter token styl equal legal harmon social scrutin synthes hospital "
             "emphas fertil moderni standard material").split()
ISE = r"(?:%s)is(?:e|es|ed|ing|ation|ations|er|ers)" % "|".join(ISE_STEMS)

PLAIN = {
    "favour": "favor", "behaviour": "behavior", "neighbour": "neighbor", "honour": "honor",
    "flavour": "flavor", "harbour": "harbor", "humour": "humor", "rumour": "rumor",
    "vapour": "vapor", "centre": "center", "centred": "centered", "centring": "centering", "metre": "meter",
    "litre": "liter", "theatre": "theater", "fibre": "fiber", "calibre": "caliber",
    "grey": "gray", "licence": "license", "defence": "defense", "offence": "offense",
    "catalogue": "catalog", "programme": "program", "aeroplane": "airplane",
    "whilst": "while", "amongst": "among", "judgement": "judgment",
    "acknowledgement": "acknowledgment", "ageing": "aging", 
    "mould": "mold", "plough": "plow", "sceptic": "skeptic",
    "draught": "draft", "pyjamas": "pajamas", "artefact": "artifact", "enrol": "enroll",
    "fulfil": "fulfill", "instalment": "installment", "skilful": "skillful",
    "wilful": "willful", "colour": "color", "analyse": "analyze", "paralyse": "paralyze",
}
PLAIN_KEYS = sorted(PLAIN, key=len, reverse=True)
LL = "cancel|travel|label|model|level|signal|fuel|channel"
DOUBLE_L = r"(?:%s)l(?:ed|ing|er|ers)" % LL
# `enrol` and `fulfil` are whole words only (enrolled, fulfilled are already right).
WHOLE_ONLY = {"enrol", "fulfil"}
PLAIN_RE = "|".join(k if k not in WHOLE_ONLY else k + r"\b" for k in PLAIN_KEYS)
WORD = re.compile(r"\b[A-Za-z]*(?:%s|%s|%s)[A-Za-z]*\b" % (ISE, DOUBLE_L, PLAIN_RE), re.I)
EXT = re.compile(r"\.(py|qml|json|lua|sh|txt|md|html|js|css|conf|toml|frag|png|svg|ini|theme|hl)\b", re.I)


def american(word):
    """The American spelling of one British-looking word (unchanged if it has none)."""
    low = word.lower()
    out = re.sub(r"(%s)l(ed|ing|er|ers)" % LL, r"\1\2", low)
    out = re.sub(r"(%s)is(e|es|ed|ing|ation|ations|er|ers)" % "|".join(ISE_STEMS),
                 r"\1iz\2", out)
    for b in PLAIN_KEYS:
        if b in out and (b not in WHOLE_ONLY or out == b):
            out = out.replace(b, PLAIN[b])
            break
    if out == low:
        return word
    if word.isupper() and len(word) > 1:
        return out.upper()
    # Keep the capital letters of the original where the letters line up.
    return "".join(ch.upper() if i < len(word) and word[i].isupper() else ch
                   for i, ch in enumerate(out))


def _skip_context(text, s, e, word):
    """True when the word sits in a path, file name, flag or code access, not in prose."""
    if word.isupper() and len(word) > 1:
        return True            # GREY: a constant or a format code, not a word
    if re.search(r"[a-z][A-Z]", word):
        return True            # pageColour: an identifier, not a word
    before = text[s - 1] if s else " "
    after = text[e] if e < len(text) else " "
    if before in "_/$#@\\" or after in "_/@=(":
        return True
    if before == "." and s >= 2 and text[s - 2].isalnum():
        return True            # Config.colour
    a, b = s, e
    while a > 0 and re.match(r"[\w.\-/]", text[a - 1]):
        a -= 1
    while b < len(text) and re.match(r"[\w.\-/]", text[b]):
        b += 1
    chunk = text[a:b].rstrip(".")
    return "/" in chunk or chunk.startswith(("-", "X-")) or (chunk != word and bool(EXT.search(chunk)))


def fix_text(text):
    """Fix prose: whole words only, never inside paths, flags, file names or code access."""
    def sub(m):
        if _skip_context(text, m.start(), m.end(), m.group(0)):
            return m.group(0)
        return american(m.group(0))
    return WORD.sub(sub, text)


def british_words(text):
    """The British words left in prose (those fix_text would change)."""
    return [m.group(0) for m in WORD.finditer(text)
            if not _skip_context(text, m.start(), m.end(), m.group(0))
            and american(m.group(0)) != m.group(0)]


# A lower-case run with no spaces is a key or an id (`colourful`), not a word people read.
IDENT_LIKE = re.compile(r"^[a-z0-9_\-./:#]+$")


def literal_ok(body):
    return not IDENT_LIKE.match(body)


C_TOKENS = re.compile(
    r'''//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`''', re.S)


def c_literals(src):
    """(start, end, body) of every string literal in QML/JS source, comments excluded."""
    for m in C_TOKENS.finditer(src):
        t = m.group(0)
        if t[0] != "/":
            yield m.start() + 1, m.end() - 1, t[1:-1]


PY_TOKENS = re.compile(
    r'''#[^\n]*|"""(?:\\.|[^\\])*?"""|\'\'\'(?:\\.|[^\\])*?\'\'\'|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*\'''',
    re.S)


def py_literals(src):
    """(start, end, body) of every string literal in Python source, except comments and
    docstrings (a string alone on its line is a comment in all but name)."""
    for m in PY_TOKENS.finditer(src):
        t = m.group(0)
        if t[0] == "#":
            continue
        n = 3 if t[:3] in ('"""', "'''") else 1
        line_start = src.rfind("\n", 0, m.start()) + 1
        if n == 3 and src[line_start:m.start()].strip() == "":
            continue
        yield m.start() + n, m.end() - n, t[n:-n]


def rewrite(src, literals, fix=fix_text):
    """src with `fix` applied to the body of every literal that reads as words."""
    out, pos = [], 0
    for s, e, body in literals(src):
        out.append(src[pos:s])
        out.append(fix(body) if literal_ok(body) else body)
        pos = e
    out.append(src[pos:])
    return "".join(out)


HTML_PARTS = re.compile(r"<!--.*?-->|<(script|style|code|pre|kbd)\b.*?</\1>|<[^>]+>|[^<]+", re.S | re.I)
ATTR = re.compile(r'''\b(title|alt|placeholder|aria-label|content)=("[^"]*")''', re.I)


def html_texts(src):
    """(start, end) of every stretch of HTML that people read: text and the words in
    title/alt/placeholder/aria-label/content attributes. Code, scripts and comments excluded."""
    for m in HTML_PARTS.finditer(src):
        t = m.group(0)
        if t.startswith("<!--") or re.match(r"<(script|style|code|pre|kbd)\b", t, re.I):
            continue
        if t.startswith("<"):
            for a in ATTR.finditer(t):
                yield m.start() + a.start(2) + 1, m.start() + a.end(2) - 1
        else:
            yield m.start(), m.end()


MD_PARTS = re.compile(r"```.*?```|`[^`\n]*`|\]\([^)]*\)|<[^>]+>|[^`\]<]+|[`\]<]", re.S)


def md_texts(src):
    """(start, end) of every stretch of Markdown that people read: no code, no link targets."""
    for m in MD_PARTS.finditer(src):
        t = m.group(0)
        if t[0] in "`<" or t.startswith("]("):
            continue
        yield m.start(), m.end()


def rewrite_spans(src, spans, fix=fix_text):
    out, pos = [], 0
    for s, e in spans(src):
        out.append(src[pos:s])
        out.append(fix(src[s:e]))
        pos = e
    out.append(src[pos:])
    return "".join(out)
