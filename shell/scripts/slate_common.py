"""Small helpers that several of Slate's scripts need, kept in one place so they can't drift
apart: writing a private file, reading a block of the assistant's prompt file, and
downloading a file with a size cap and a SHA-256.

Only scripts that run as you import this. Anything that runs as root (the helpers in
/usr/local/libexec/slate) never imports from your home folder, and keeps its own copies."""
import hashlib
import json
import os
import re
import urllib.request


def write_private(path, text):
    """Write text to path, readable by you alone: the folder is made 0700 and the file is
    created 0600 (whatever the umask), then filled."""
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def write_private_json(path, data):
    """write_private for a JSON document (indented by one space)."""
    write_private(path, json.dumps(data, indent=1))


def prompt_blocks(path, wanted):
    """The blocks of data/assistant-prompt.md whose [heading] is one of wanted, each as one
    paragraph, separated by blank lines. Raises OSError when the file can't be read."""
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    blocks, who, lines = [], None, []
    for line in text.splitlines() + ["[end]"]:
        m = re.match(r"\[(\w+)\]\s*$", line)
        if m:
            if who in wanted and "".join(lines).strip():
                blocks.append(" ".join(l.strip() for l in lines if l.strip()))     # (one paragraph each)
            who, lines = m.group(1), []
        else:
            lines.append(line)
    return "\n\n".join(blocks)


def download_to(url, dest, limit, user_agent, timeout, on_open=None, on_chunk=None):
    """Download url to dest, stopping once more than limit bytes have arrived. Returns
    (bytes received, SHA-256 hex of them, whether it went over limit). on_open(response) is
    called once the server answers, and on_chunk(bytes so far) after each piece. Network and
    file errors are left for the caller."""
    digest, got = hashlib.sha256(), 0
    req = urllib.request.Request(url, headers={"User-Agent": user_agent})
    with urllib.request.urlopen(req, timeout=timeout) as r, open(dest, "wb") as out:
        if on_open:
            on_open(r)
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            out.write(chunk)
            digest.update(chunk)
            got += len(chunk)
            if got > limit:
                return got, digest.hexdigest(), True
            if on_chunk:
                on_chunk(got)
    return got, digest.hexdigest(), False
