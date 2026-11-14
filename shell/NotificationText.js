.pragma library
// What a notification's message may do to Slate. Its words are another program's (a web
// page's, through a browser), and the card shows them as styled text so that bold, italic,
// underline and links work, as the notification spec allows. Left as written, the same text
// could do a great deal more: Qt's styled text also reads <font>, <h1>, <img> (which loads
// whatever address it names, from the network or the disk) and links to anything at all.
// So the message goes through safeBody() first, and only this comes out the other side:
//   <b> <i> <u> <br>      kept, without anything written inside the tag
//   <a href="…">          kept when it leads to http, https or mailto; any other link (a
//                         file, a script, an app's own scheme) loses the link, keeps its words
//   <img …>               dropped: Slate shows a notification's picture, never one named in
//                         its words
//   any other tag         shown as it was typed, as are a stray < > or &
// Entities ("&lt;", "&amp;", "&#8230;") stay as they are. Tags left open are closed.
// tests/unit/test_notification_text.py and the live tests (test_overlays.py) hold it to this.

// A link Slate will open from a notification: a web page or an email address, nothing else
function openable(link) {
    return /^(https?:\/\/|mailto:)[^\s"<>\x00-\x1f]+$/i.test(String(link === undefined || link === null ? "" : link));
}

function escaped(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// The address in a link's tag, however it was quoted ("…", '…' or bare); "" if there's none
function hrefOf(attributes) {
    const m = /(?:^|[\s\/])href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/i.exec(attributes || "");
    if (!m) return "";
    return (m[1] !== undefined ? m[1] : m[2] !== undefined ? m[2] : m[3] || "").trim();
}

function safeBody(body) {
    const text = String(body === undefined || body === null ? "" : body);
    try {
        // What's open, innermost last: { tag, shown } (shown: false for a link that lost its
        // address, whose closing tag is then left out too)
        const open = [];
        const close = upTo => {
            let out = "";
            while (open.length > upTo) { const t = open.pop(); if (t.shown) out += "</" + t.tag + ">"; }
            return out;
        };
        // A tag, an entity, or a character that would start one: everything else passes as it is
        const piece = /<(\/?)([A-Za-z][A-Za-z0-9]*)((?:[\s\/][^<>]*)?)>|&(?:[A-Za-z][A-Za-z0-9]{1,31}|#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6});|[<>&]/g;
        const out = text.replace(piece, (whole, closing, name, attributes) => {
            if (name === undefined) return whole.length > 1 ? whole : escaped(whole);    // an entity; or a stray < > &
            const tag = name.toLowerCase();
            if (tag === "img") return "";
            if (tag === "br") return closing ? "" : "<br>";
            if (tag !== "b" && tag !== "i" && tag !== "u" && tag !== "a") return escaped(whole);
            if (closing) {
                // Closes the nearest one open (and anything opened inside it); with none open, it goes
                for (let k = open.length - 1; k >= 0; k--) if (open[k].tag === tag) return close(k);
                return "";
            }
            if (tag !== "a") { open.push({ tag: tag, shown: true }); return "<" + tag + ">"; }
            // A link: never one inside another, and only with an address Slate would open
            let before = "";
            for (let k = open.length - 1; k >= 0; k--) if (open[k].tag === "a") { before = close(k); break; }
            const href = hrefOf(attributes);
            const ok = openable(href);
            open.push({ tag: "a", shown: ok });
            return before + (ok ? "<a href=\"" + href + "\">" : "");
        });
        return out + close(0);
    } catch (e) {
        // (it shouldn't; but whatever happens, nothing gets through as markup)
        return escaped(text);
    }
}

// Release notes (Settings → Updates) come from the network and are shown as Markdown, which
// Qt would turn into pictures (![x](address) loads whatever it names) and links to anything.
// safeMarkdown() takes those out first: a picture becomes its description, a link to anything
// but a web page or an address loses the link and keeps its words, and link definitions
// ([x]: address) go. Headings, lists, bold, code and web links stay as they were written.
// (Qt's Markdown reader ignores raw HTML itself.) tests/unit/test_notification_text.py.
function safeMarkdown(text) {
    let out = String(text === undefined || text === null ? "" : text);
    try {
        // Reference-style definitions: nothing then points at an address, so [x][y] stays words
        out = out.replace(/^[ ]{0,3}\[[^\]\n]+\]:[^\n]*$/gm, "");
        // Pictures, innermost first, until none is left
        for (let i = 0; i < 20; ++i) {
            const next = out.replace(/!\[([^\[\]]*)\]\([^()\n]*(?:\([^()\n]*\)[^()\n]*)*\)/g, "$1");
            if (next === out) break;
            out = next;
        }
        // Links: kept only when they lead somewhere Slate would open
        out = out.replace(/\[([^\[\]]*)\]\(\s*<?((?:[^\s()<>]|\([^\s()]*\))*)>?(?:\s[^()\n]*)?\)/g, (all, words, address) => openable(address) ? all : words);
        return out;
    } catch (e) {
        return "";
    }
}
