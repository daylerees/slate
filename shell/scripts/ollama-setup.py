#!/usr/bin/env python3
"""Setting up Ollama for Nova (Settings → Assistant → Set up Ollama), so a model on this
computer can answer without a terminal.

Usage: ollama-setup.py plan          what this computer needs, as JSON: {"family", "package"
                                     ("" when the distro has none: then "link" says where to
                                     get it), "gpu", "ram", "vram", "installed", "running",
                                     "models", "model", "modelSize"}
       ollama-setup.py wait [secs]   wait for Ollama to answer (after its service is turned
                                     on); exit 1 if it doesn't within secs (default 30)
       ollama-setup.py pull <model>  download a model through Ollama, a line of JSON as it goes:
                                     {"got", "size", "status"}, then {"done": true} or {"error"}
       ollama-setup.py setup <package|-> <model>
                                     all of it, on its own (Settings starts it detached, so it
                                     carries on with Settings closed): the package and its
                                     service ("-": already running), then the model, which is
                                     then chosen for Nova. How it's going is in STATE:
                                     {"step": installing|starting|downloading|done|failed,
                                     "model", "got", "size", "problem", "at": when it was written}

Installing is the distro's own package, with an administrator's password: Settings runs
`slate-system --ollama <package>` with the package this chooses, and the root half
(bin/slate-system-root) takes only the names in PACKAGES for its family, then turns on
ollama.service. Nothing is downloaded from ollama.com: where the distro has no package,
Settings links to Ollama's own instructions instead.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slate_apps import family  # noqa: E402  (the same answer as install.sh and slate-system)
from slate_agents import ollama_url, _ollama_models  # noqa: E402

LINK = "https://ollama.com/download/linux"
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))     # (the Slate folder)
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "slate", "ollama-setup.json")
GIB = 1 << 30

# Each family's package for each kind of graphics card. Arch and openSUSE build Ollama for
# Vulkan too (small, and it works on AMD and Intel cards alike; ROCm is a much larger
# install), Arch also for CUDA (NVIDIA); Fedora's one package brings its own. Debian, Ubuntu,
# Void and the rest have none. bin/slate-system-root has the same names, and refuses others
# (tests/unit/test_ollama_setup.py holds the two together)
PACKAGES = {
    "arch": {"nvidia": "ollama-cuda", "amd": "ollama-vulkan", "intel": "ollama-vulkan", "none": "ollama"},
    "opensuse": {"nvidia": "ollama-vulkan", "amd": "ollama-vulkan", "intel": "ollama-vulkan", "none": "ollama"},
    "fedora": {"nvidia": "ollama", "amd": "ollama", "intel": "ollama", "none": "ollama"},
}

# Models that can use Slate's tools, smallest first: (name, download size in bytes). The
# largest that fits is suggested (fits)
MODELS = [("qwen3:1.7b", int(1.4e9)), ("qwen3:4b", int(2.5e9)), ("qwen3:8b", int(5.2e9)), ("qwen3:14b", int(9.3e9))]
VENDORS = {"0x10de": "nvidia", "0x1002": "amd", "0x8086": "intel"}
MODEL_NAME = re.compile(r"^[a-z0-9][a-z0-9._:/-]{0,100}$")


def choose_package(fam, gpu):
    """The package to install, or "" where the distro has none."""
    return PACKAGES.get(fam, {}).get(gpu, "")


def fits(ram, vram):
    """The largest model this computer runs comfortably: on a graphics card with its own memory
    (4 GiB or more), what fits in most of it with a gigabyte to spare; otherwise on the
    processor, in a third of the memory, and no larger than 8b (bigger ones answer too slowly
    there). The smallest when nothing's known."""
    if vram >= 4 * GIB:
        room, largest = vram * 0.85, len(MODELS)
    else:
        room, largest = ram * 0.35, 3
    best = MODELS[0]
    for m in MODELS[:largest]:
        if m[1] + GIB <= room:
            best = m
    return best


def gpu(sys_root=None):
    """The graphics card's maker (nvidia, amd, intel, or none), and its own memory in bytes
    (0 when it shares the computer's, or isn't known). A card of its own wins over one built in."""
    root = sys_root or os.environ.get("SLATE_SYS") or "/sys"
    found = []
    drm = os.path.join(root, "class", "drm")
    try:
        cards = sorted(n for n in os.listdir(drm) if re.fullmatch(r"card\d+", n))
    except OSError:
        cards = []
    for card in cards:
        dev = os.path.join(drm, card, "device")
        try:
            with open(os.path.join(dev, "vendor")) as f:
                vendor = VENDORS.get(f.read().strip().lower())
        except OSError:
            continue
        if not vendor:
            continue
        vram = 0
        try:
            with open(os.path.join(dev, "mem_info_vram_total")) as f:      # (AMD's own memory)
                vram = int(f.read().strip())
        except (OSError, ValueError):
            pass
        if vendor == "nvidia":
            vram = nvidia_memory()
        found.append((vendor, vram))
    if not found:
        return "none", 0
    # (a card with its own memory first: NVIDIA, or AMD with more than a sliver)
    found.sort(key=lambda v: (v[0] == "nvidia" or v[1] >= GIB, v[1]), reverse=True)
    return found[0]


def nvidia_memory():
    if not shutil.which("nvidia-smi"):
        return 0
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=memory.total", "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=5).stdout
        return max(int(v) for v in out.split()) * (1 << 20)
    except (OSError, ValueError, subprocess.SubprocessError):
        return 0


def memory(meminfo="/proc/meminfo"):
    try:
        with open(meminfo) as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    return int(line.split()[1]) * 1024
    except (OSError, ValueError, IndexError):
        pass
    return 0


def plan():
    fam = family()
    maker, vram = gpu()
    ram = memory()
    models = _ollama_models(ollama_url())
    model, size = fits(ram, vram)
    package = choose_package(fam, maker)
    return {"family": fam, "package": package, "link": "" if package else LINK, "gpu": maker, "ram": ram, "vram": vram,
            "installed": bool(shutil.which("ollama")) or models is not None, "running": models is not None,
            "models": [m["name"] for m in models or [] if m["tools"]], "model": model, "modelSize": size}


def wait(secs):
    end = time.monotonic() + secs
    while time.monotonic() < end:
        if _ollama_models(ollama_url()) is not None:
            return True
        time.sleep(1)
    return False


def say(d):
    print(json.dumps(d), flush=True)


def save(st):
    """(with the time: Settings takes a step that's gone quiet for long, the setting up cut short
    by a restart, as over)"""
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(dict(st, at=int(time.time())), f)
    os.replace(tmp, STATE)


def setup(package, model):
    """Install (unless "-"), wait for it to answer, download the model and choose it, saying how
    it's going in STATE all the way."""
    st = {"step": "installing", "model": model, "got": 0, "size": 0, "problem": ""}
    if not MODEL_NAME.match(model) or not (package == "-" or re.fullmatch(r"ollama(-cuda|-vulkan|-rocm)?", package)):
        save(dict(st, step="failed", problem="Slate couldn't make sense of what to set up."))
        return 1
    if package != "-":
        save(st)
        p = subprocess.run([os.path.join(HERE, "bin", "slate-system"), "--ollama", package],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True)
        if p.returncode != 0:
            said = (p.stderr.strip().splitlines() or [""])[-1][:120]
            # (pkexec: 126 when the password prompt was closed)
            save(dict(st, step="failed", problem="The password prompt was closed, so nothing changed." if p.returncode == 126
                      else "Slate couldn't install Ollama. Check you're online, then try again." + (" (%s)" % said if said else "")))
            return 1
        save(dict(st, step="starting"))
        if not wait(30):
            save(dict(st, step="failed", problem="Ollama is installed, but didn't start. Restarting the computer usually sorts it out, then try again."))
            return 1
    st["step"] = "downloading"
    save(st)

    def heard(d):
        if "got" in d:
            st.update(got=d["got"], size=d["size"])
            save(st)
        elif d.get("error"):
            st.update(step="failed", problem=d["error"])
        elif d.get("done"):
            st.update(step="done", got=st["size"])
    code = pull(model, heard)
    if code == 0:
        # Nova uses it from now on (as choosing it in Settings → Assistant does)
        subprocess.run([os.path.join(HERE, "bin", "slate"), "ipc", "call", "config", "set", "assistantLocalModel", model],
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    save(st)
    return code


def pull(model, heard=say):
    """Download through Ollama's own API (it fetches from its library itself). Progress is the
    sum over the model's parts, as Ollama reports each one."""
    if not MODEL_NAME.match(model):
        heard({"error": "That isn't a model's name."})
        return 1
    req = urllib.request.Request(ollama_url() + "/api/pull", data=json.dumps({"model": model, "stream": True}).encode(),
                                 headers={"Content-Type": "application/json"})
    parts, last = {}, 0.0
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            for line in r:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(d, dict):
                    continue
                if d.get("error"):
                    heard({"error": "Ollama couldn't download %s: %s" % (model, str(d["error"])[:200])})
                    return 1
                if d.get("digest") and isinstance(d.get("total"), int):
                    parts[d["digest"]] = (d.get("completed") or 0, d["total"])
                if d.get("status") == "success":
                    heard({"done": True})
                    return 0
                now = time.monotonic()
                if now - last >= 0.25:
                    last = now
                    heard({"got": sum(p[0] for p in parts.values()), "size": sum(p[1] for p in parts.values()),
                         "status": str(d.get("status") or "")[:80]})
    except (OSError, urllib.error.URLError) as e:
        heard({"error": "Slate couldn't reach Ollama to download %s (%s). Check you're online, then try again."
                      % (model, getattr(e, "reason", None) or e)})
        return 1
    heard({"error": "Ollama stopped before %s finished downloading. Try again." % model})
    return 1


def main(args):
    if args[:1] == ["plan"] and len(args) == 1:
        say(plan())
        return 0
    if args[:1] == ["wait"] and len(args) <= 2:
        return 0 if wait(int(args[1]) if len(args) == 2 and args[1].isdigit() else 30) else 1
    if args[:1] == ["pull"] and len(args) == 2:
        return pull(args[1])
    if args[:1] == ["setup"] and len(args) == 3:
        return setup(args[1], args[2])
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
