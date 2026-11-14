#!/usr/bin/env python3
"""Talking to Nova (Settings → Assistant → Voice): what you say, turned into text on this
computer with whisper.cpp, for Nova's box. Nothing is sent anywhere, and nothing listens
except while you hold the key or the button.

    voice.py status      what's there: {"whisper": path or "", "model": true/false, "size": bytes, "private": …}
    voice.py download    the speech model, into ~/.local/share/slate/whisper/, a JSON line at a time:
                           {"type": "progress", "done": bytes, "total": bytes}
                           {"type": "done"}  or  {"type": "error", "kind": …, "message": …}
                         checked against its SHA-256 before it's kept; stopped (SIGTERM), what
                         came so far is deleted
    voice.py delete      deletes the model
    voice.py listen      records from the default microphone (pw-record) into a WAV file in
                         $XDG_RUNTIME_DIR (yours alone) until a line "stop" on stdin, then turns
                         it into text with whisper.cpp and deletes the file:
                           {"type": "listening"}, {"type": "transcribing"},
                           {"type": "text", "text": …}  or  {"type": "error", "kind": …, "message": …}
                         stdin closing without "stop" (Slate gone), SIGTERM or anything else
                         ending it early: nothing is turned into text, and the file is deleted
                         all the same. Never in Private Mode, and never past MAX_SECONDS.

The model is whisper's "base" (multilingual, about 148 MB): small enough to download and quick
on any computer, and it understands the language you speak, which is told it from your
locale (LANG) where whisper knows it, and worked out by itself otherwise.

whisper.cpp is optional (packaging/*.txt). Its program is whisper-cli (whisper.cpp 1.7.4 and
later, every distro's package); older packages call it whisper-cpp or whisper.cpp.
"""
import hashlib
import json
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request

MODEL = {
    "name": "ggml-base.bin",
    "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
    "size": 147951465,
    "sha256": "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
}
WHISPER = ("whisper-cli", "whisper-cpp", "whisper.cpp")
MAX_SECONDS = 60          # a held key that was never let go stops here
SHORTEST = 0.4            # seconds: anything shorter was a tap, not words
# The languages whisper knows (its two-letter codes), so a locale it doesn't is left to it
LANGS = set(("en zh de es ru ko fr ja pt tr pl ca nl ar sv it id hi fi vi he uk el ms cs ro da hu ta no th ur hr bg "
             "lt la mi ml cy sk te fa lv bn sr az sl kn et mk br eu is hy ne mn bs kk sq sw gl mr pa si km sn yo so "
             "af oc ka be tg sd gu am yi lo uz fo ht ps tk nn mt sa lb my bo tl mg as tt haw ln ha ba jw su yue").split())


def say(**event):
    print(json.dumps(event), flush=True)


def data_dir():
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(base, "slate", "whisper")


def model_path():
    return os.path.join(data_dir(), MODEL["name"])


def model_there():
    """Kept only once its checksum matched (download), so its size is enough to tell."""
    try:
        return os.path.getsize(model_path()) == MODEL["size"]
    except OSError:
        return False


def runtime_dir():
    return os.environ.get("XDG_RUNTIME_DIR") or "/tmp"


def private_mode():
    """Private Mode's mark (PrivateMode.qml): nothing listens while it's on."""
    return os.path.exists(os.path.join(runtime_dir(), "slate-private"))


def tool_path():
    """Where the programs are looked for. The tests' Slate is given stand-ins (SLATE_VOICE_TOOLS)."""
    extra = os.environ.get("SLATE_VOICE_TOOLS")
    path = os.environ.get("PATH", "/usr/bin:/bin")
    return extra + ":" + path if extra else path


def find_whisper():
    for name in WHISPER:
        p = shutil.which(name, path=tool_path())
        if p:
            return p
    return ""


def language():
    """Your language, from the locale, where whisper knows it; otherwise it works it out."""
    for var in ("LC_ALL", "LC_MESSAGES", "LANG"):
        v = os.environ.get(var, "")
        if v:
            code = re.split(r"[_.@]", v)[0].lower()
            return code if code in LANGS else "auto"
    return "auto"


def status():
    say(whisper=find_whisper(), model=model_there(), size=MODEL["size"], private=private_mode(),
        recorder=bool(shutil.which("pw-record", path=tool_path())))
    return 0


# ---- The model ----------------------------------------------------------------------------

class Stopped(Exception):
    pass


def _stop(*_):
    raise Stopped()


def download(url=None, size=None, sha256=None, dest=None, every=0.25):
    """Fetch the model to a .part file, check its size and SHA-256, then keep it. Returns 0 when
    it's there."""
    url, size, sha256 = url or MODEL["url"], size or MODEL["size"], sha256 or MODEL["sha256"]
    dest = dest or model_path()
    os.makedirs(os.path.dirname(dest), mode=0o700, exist_ok=True)
    part = dest + ".part"
    signal.signal(signal.SIGTERM, _stop)
    done, last = 0, 0.0
    digest = hashlib.sha256()
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Slate"})
        with urllib.request.urlopen(req, timeout=30) as r, open(part, "wb") as f:
            total = int(r.headers.get("Content-Length") or 0) or size
            say(type="progress", done=0, total=total)
            while True:
                chunk = r.read(1 << 16)
                if not chunk:
                    break
                f.write(chunk)
                digest.update(chunk)
                done += len(chunk)
                if done > size:
                    break
                now = time.monotonic()
                if now - last >= every:
                    last = now
                    say(type="progress", done=done, total=total)
        if done != size or digest.hexdigest() != sha256:
            os.remove(part)
            say(type="error", kind="checksum",
                message="The speech model Slate downloaded wasn't the one it expected, so it wasn't kept. You can try again.")
            return 4
        os.replace(part, dest)
        say(type="progress", done=done, total=done)
        say(type="done")
        return 0
    except Stopped:
        _gone(part)
        say(type="error", kind="stopped", message="Stopped. Nothing was kept.")
        return 5
    except (urllib.error.URLError, OSError, ValueError) as e:
        _gone(part)
        say(type="error", kind="offline", detail=str(e)[:200],
            message="Slate couldn't download the speech model. Check you're online, and try again.")
        return 3


def _gone(path):
    try:
        os.remove(path)
    except OSError:
        pass


def delete():
    for p in (model_path(), model_path() + ".part"):
        _gone(p)
    say(type="done")
    return 0


# ---- Listening ----------------------------------------------------------------------------

def clean_text(out):
    """whisper's words, without what it notes that isn't words ([BLANK_AUDIO], (music)…)."""
    text = re.sub(r"\[[^\]]*\]|\([^)]*\)|\*[^*]*\*", " ", out)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:2000]


def wait_for_stop(rec, limit):
    """Until "stop" (True), stdin closing (False: cancelled), the recorder ending by itself
    (None) or the limit (True)."""
    end = time.monotonic() + limit
    buf = b""
    fd = sys.stdin.fileno()
    while True:
        left = end - time.monotonic()
        if left <= 0:
            return True
        if rec.poll() is not None:
            return None
        ready, _, _ = select.select([fd], [], [], min(0.1, left))
        if not ready:
            continue
        chunk = os.read(fd, 256)
        if not chunk:
            return False
        buf += chunk
        if b"stop" in buf:
            return True
        if b"cancel" in buf:
            return False


def listen(limit=MAX_SECONDS):
    if private_mode():
        say(type="error", kind="private", message="Nova doesn't listen while Private Mode is on.")
        return 2
    whisper = find_whisper()
    if not whisper:
        say(type="error", kind="no-whisper",
            message="Slate needs whisper.cpp to turn what you say into text. Install it (whisper-cpp on most systems) and try again.")
        return 2
    if not model_there():
        say(type="error", kind="no-model",
            message="Slate needs its speech model first. You can download it in Settings → Assistant → Voice.")
        return 2
    recorder = shutil.which("pw-record", path=tool_path())
    if not recorder:
        say(type="error", kind="no-recorder",
            message="Slate needs pw-record (part of PipeWire's tools) to hear your microphone.")
        return 2
    wav = os.path.join(runtime_dir(), "slate-voice-%d.wav" % os.getpid())
    signal.signal(signal.SIGTERM, _stop)
    rec = None
    old = os.umask(0o077)
    try:
        rec = subprocess.Popen([recorder, "--rate", "16000", "--channels", "1", "--format", "s16", wav],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.umask(old)
        started = time.monotonic()
        say(type="listening")
        go = wait_for_stop(rec, limit)
        held = time.monotonic() - started
        if go is None:
            say(type="error", kind="no-mic",
                message="Slate couldn't hear your microphone. Check it's plugged in and not muted, and try again.")
            return 3
        rec.send_signal(signal.SIGINT)          # (pw-record finishes the file as it stops)
        try:
            rec.wait(timeout=3)
        except subprocess.TimeoutExpired:
            rec.kill()
            rec.wait()
        if not go:
            return 5
        if held < SHORTEST or not os.path.exists(wav) or os.path.getsize(wav) <= 44:
            say(type="error", kind="nothing-heard", message="Hold the key or the microphone while you talk, and let go when you're done.")
            return 4
        say(type="transcribing")
        threads = str(max(1, min(4, os.cpu_count() or 1)))
        try:
            p = subprocess.run([whisper, "-m", model_path(), "-f", wav, "-l", language(), "-t", threads, "-nt", "-np"],
                               stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120)
        except subprocess.TimeoutExpired:
            say(type="error", kind="failed", message="Turning what you said into text took too long. You can try again, a little shorter.")
            return 3
        text = clean_text(p.stdout)
        if p.returncode != 0:
            say(type="error", kind="failed", detail=(p.stderr or "").strip()[-200:],
                message="Slate couldn't turn what you said into text. You can try again.")
            return 3
        if not text:
            say(type="error", kind="nothing-heard", message="Slate didn't catch any words. You can try again, a little closer to the microphone.")
            return 4
        say(type="text", text=text)
        return 0
    except Stopped:
        return 5
    finally:
        os.umask(old)
        if rec and rec.poll() is None:
            rec.kill()
            rec.wait()
        _gone(wav)


def main(argv):
    what = argv[1] if len(argv) > 1 else ""
    if what == "status":
        return status()
    if what == "download":
        return download()
    if what == "delete":
        return delete()
    if what == "listen":
        return listen()
    sys.stderr.write(__doc__)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
