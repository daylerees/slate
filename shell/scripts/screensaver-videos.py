#!/usr/bin/env python3
"""Download scenery videos for the screensaver's Videos style (Settings → Screensaver →
Get scenery videos).

Usage: screensaver-videos.py <folder> [quality]
  quality: 2160p, 1440p or 1080p (the default): each clip comes in the largest size it has up
  to that. Clips already there in a smaller size than they could be are fetched again.

Fetches each clip below into <folder>, one at a time (Wikimedia limits quick runs of requests),
skipping any already there, and writes CREDITS.txt beside them with each clip's source and
licence (the CC BY ones need their credit shown alongside them). Any sound track is taken out
(with ffmpeg, when there is one), so they're silent wherever they're played. Prints progress as
"n/total title" lines as each clip starts, "progress 0.42" lines (the whole download, 0 to 1)
as it goes, then "done n"; a clip that fails prints "error <title>: <message>".

Every clip is public domain, CC0 or CC BY, checked by hand: a working link, the licence on its
source page, and its frames looked at for burned-in text, logos or narration. They're the VP9
webm transcodes Wikimedia Commons makes (1080p, 1440p or 4K), much smaller than the originals.
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.request

CLIPS = [
    {
        "file": "earth-from-the-iss.webm",
        "title": "View of Earth from the ISS",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/c/c3/View_of_the_Earth_from_the_ISS_%288K%29.webm/View_of_the_Earth_from_the_ISS_%288K%29.webm",
        "sizes": ["2160p", "1440p", "1080p"],   # the transcodes Commons has

        "source": "https://commons.wikimedia.org/wiki/File:View_of_the_Earth_from_the_ISS_(8K).webm",
        "licence": "Public domain (NASA)",
    },
    {
        "file": "aurora-over-lapland.webm",
        "title": "Aurora over Lapland lakes",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/d/df/Aurora_borealis_timelapse.webm/Aurora_borealis_timelapse.webm",
        "sizes": ["1080p"],   # the transcodes Commons has

        "source": "https://commons.wikimedia.org/wiki/File:Aurora_borealis_timelapse.webm",
        "licence": "\"Aurora borealis timelapse\" by Harriniva Hotels & Safaris, CC BY 3.0 "
                   "(https://creativecommons.org/licenses/by/3.0/), via Wikimedia Commons",
    },
    {
        "file": "clouds-over-bellevue-canyon.webm",
        "title": "Clouds over Bellevue Canyon",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/d/d5/Timelapse_of_Clouds_over_Bellevue_Canyon.webm/Timelapse_of_Clouds_over_Bellevue_Canyon.webm",
        "sizes": ["1080p"],   # the transcodes Commons has

        "source": "https://commons.wikimedia.org/wiki/File:Timelapse_of_Clouds_over_Bellevue_Canyon.webm",
        "licence": "CC0 (public domain)",
    },
    {
        "file": "delaneys-falls-tasmania.webm",
        "title": "Delaneys Falls, Tasmania",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/8/8b/Delaneys_Falls.webm/Delaneys_Falls.webm",
        "sizes": ["2160p", "1440p", "1080p"],   # the transcodes Commons has

        "source": "https://commons.wikimedia.org/wiki/File:Delaneys_Falls.webm",
        "licence": "CC0 (public domain)",
    },
    {
        "file": "sunrise-at-lake-bled.webm",
        "title": "Sunrise at Lake Bled",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/4/40/Sunrise_atLake_Bled.webm/Sunrise_atLake_Bled.webm",
        "sizes": ["2160p", "1440p", "1080p"],   # the transcodes Commons has

        "source": "https://commons.wikimedia.org/wiki/File:Sunrise_atLake_Bled.webm",
        "licence": "\"Sunrise @Lake Bled\" by Klemen Smolej, CC BY 3.0 "
                   "(https://creativecommons.org/licenses/by/3.0/), via Wikimedia Commons",
    },
    {
        "file": "lake-bled-at-dawn.webm",
        "title": "Lake Bled at dawn",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/c/cf/Slovenia_-_Lake_Bled_-_4K_drone_video.webm/Slovenia_-_Lake_Bled_-_4K_drone_video.webm",
        "sizes": ["2160p", "1440p", "1080p"],   # the transcodes Commons has

        "source": "https://commons.wikimedia.org/wiki/File:Slovenia_-_Lake_Bled_-_4K_drone_video.webm",
        "licence": "\"SLOVENIA | BLED LAKE | 4K DRONE VIDEO\" by Danny Rest, CC BY 3.0 "
                   "(https://creativecommons.org/licenses/by/3.0/), via Wikimedia Commons",
    },
    {
        "file": "right-whale-bay-south-georgia.webm",
        "title": "Right Whale Bay, South Georgia",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/0/06/Right_Whale_Bay%2C_South_Georgia_Island.webm/Right_Whale_Bay%2C_South_Georgia_Island.webm",
        "sizes": ["1440p", "1080p"],   # 1440p at most: its 4K file is over 300 MB

        "source": "https://commons.wikimedia.org/wiki/File:Right_Whale_Bay,_South_Georgia_Island.webm",
        "licence": "\"Right Whale Bay, South Georgia 4K\" by Blagoj Klincharski, CC BY 3.0 "
                   "(https://creativecommons.org/licenses/by/3.0/), via Wikimedia Commons",
    },
    {
        "file": "crimean-coast.webm",
        "title": "Crimean coast",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/8/8a/Crimea_Mountains_Russia_-_4K_Video.webm/Crimea_Mountains_Russia_-_4K_Video.webm",
        "sizes": ["2160p", "1440p", "1080p"],   # the transcodes Commons has

        "source": "https://commons.wikimedia.org/wiki/File:Crimea_Mountains_Russia_-_4K_Video.webm",
        "licence": "\"Crimea Mountains Russia | 4K Video\" by The View, CC BY 3.0 "
                   "(https://creativecommons.org/licenses/by/3.0/), via Wikimedia Commons",
    },
    {
        "file": "gold-harbour-south-georgia.webm",
        "title": "Gold Harbour, South Georgia",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/7/77/Time-lapse_of_Gold_Harbour%2C_South_Georgia_Island.webm/Time-lapse_of_Gold_Harbour%2C_South_Georgia_Island.webm",
        "sizes": ["2160p", "1440p", "1080p"],   # the transcodes Commons has

        "source": "https://commons.wikimedia.org/wiki/File:Time-lapse_of_Gold_Harbour,_South_Georgia_Island.webm",
        "licence": "\"Gold Harbour, South Georgia, Timelapse 4K\" by Blagoj Klincharski, CC BY 3.0 "
                   "(https://creativecommons.org/licenses/by/3.0/), via Wikimedia Commons",
    },
    {
        "file": "emperor-penguin-coulman-island.webm",
        "title": "Emperor penguin, Coulman Island",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/2/27/Emperor_penguin%2C_Coulman_Island%2C_Antarctica.webm/Emperor_penguin%2C_Coulman_Island%2C_Antarctica.webm",
        "sizes": ["2160p", "1440p", "1080p"],   # the transcodes Commons has

        "source": "https://commons.wikimedia.org/wiki/File:Emperor_penguin,_Coulman_Island,_Antarctica.webm",
        "licence": "\"Emperor penguin, Coulman Island, Antarctica 4K\" by Blagoj Klincharski, CC BY 3.0 "
                   "(https://creativecommons.org/licenses/by/3.0/), via Wikimedia Commons",
    },
    {
        "file": "black-balsam-knob.webm",
        "title": "Black Balsam Knob, North Carolina",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/8/8a/Drone_Footage_Black_Balsam_Knob_NC_4k.webm/Drone_Footage_Black_Balsam_Knob_NC_4k.webm",
        "sizes": ["1440p", "1080p"],   # 1440p at most: its 4K file is over 300 MB

        "source": "https://commons.wikimedia.org/wiki/File:Drone_Footage_Black_Balsam_Knob_NC_4k.webm",
        "licence": "\"Drone Footage Black Balsam Knob NC 4k\" by Royalty Free Drone Footage, CC BY 3.0 "
                   "(https://creativecommons.org/licenses/by/3.0/), via Wikimedia Commons",
    },
    {
        "file": "la-caleta-cadiz.webm",
        "title": "La Caleta beach, Cádiz",
        "base": "https://upload.wikimedia.org/wikipedia/commons/transcoded/4/47/Timelapse_of_beach_of_La_Caleta_in_Cadiz%2C_Spain.webm/Timelapse_of_beach_of_La_Caleta_in_Cadiz%2C_Spain.webm",
        "sizes": ["2160p", "1440p", "1080p"],   # the transcodes Commons has

        "source": "https://commons.wikimedia.org/wiki/File:Timelapse_of_beach_of_La_Caleta_in_Cadiz,_Spain.webm",
        "licence": "\"Timelapse de la playa de La Caleta 4K\" by davidyeahmonkey, CC BY 3.0 "
                   "(https://creativecommons.org/licenses/by/3.0/), via Wikimedia Commons",
    },
]

# Wikimedia asks automated clients to say who they are
USER_AGENT = "Slate-desktop/1.0 (screensaver scenery downloader; https://github.com/daylerees/slate)"


def fetch(url, dest, report):
    """Download url to dest; report(fraction of this file) as it goes (about 100 times)."""
    tmp = dest + ".part"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as r, open(tmp, "wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        done, last = 0, -1
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            f.write(chunk)
            done += len(chunk)
            if total:
                pct = done * 100 // total
                if pct != last:
                    last = pct
                    report(done / total)
    os.replace(tmp, dest)            # only a finished download gets its real name


def silence(path):
    """Take the sound track out of a video, so it's silent wherever it's played (the
    screensaver mutes it anyway). The video is copied, not re-encoded: quick and light. Needs
    ffmpeg; without it the file is left as it is."""
    if not shutil.which("ffmpeg"):
        return
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries",
                            "stream=index", "-of", "csv=p=0", path], capture_output=True, text=True)
    if probe.returncode != 0 or not probe.stdout.strip():
        return                       # no sound track to take out
    root, ext = os.path.splitext(path)
    tmp = root + ".silent" + ext
    done = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", path, "-map", "0:v",
                           "-c", "copy", "-an", tmp], stdin=subprocess.DEVNULL)
    if done.returncode == 0 and os.path.getsize(tmp) > 0:
        os.replace(tmp, path)
    elif os.path.exists(tmp):
        os.remove(tmp)


QUALITIES = ["1080p", "1440p", "2160p"]


def best_size(clip, quality):
    """The largest size the clip comes in, up to quality."""
    cap = QUALITIES.index(quality) if quality in QUALITIES else 0
    have = [q for q in clip["sizes"] if QUALITIES.index(q) <= cap]
    return max(have, key=QUALITIES.index) if have else "1080p"


# Which size each downloaded clip is, so a better quality later fetches only what improves
SIZES_FILE = ".slate-scenery.json"


def load_sizes(folder):
    try:
        with open(os.path.join(folder, SIZES_FILE)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_sizes(folder, sizes):
    with open(os.path.join(folder, SIZES_FILE), "w") as f:
        json.dump(sizes, f)


def credits(folder):
    lines = ["Scenery videos for Slate's screensaver, downloaded from Wikimedia Commons.", ""]
    for c in CLIPS:
        lines += [c["title"] + " (" + c["file"] + ")", "  " + c["licence"], "  " + c["source"], ""]
    with open(os.path.join(folder, "CREDITS.txt"), "w") as f:
        f.write("\n".join(lines))


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    folder = sys.argv[1]
    quality = sys.argv[2] if len(sys.argv) == 3 else "1080p"
    os.makedirs(folder, exist_ok=True)
    sizes = load_sizes(folder)
    got, n = 0, len(CLIPS)
    # The whole download's progress: each clip an equal share
    progress = lambda i, f: print(f"progress {min(1.0, (i - 1 + f) / n):.3f}", flush=True)
    for i, c in enumerate(CLIPS, 1):
        print(f"{i}/{n} {c['title']}", flush=True)
        progress(i, 0)
        dest = os.path.join(folder, c["file"])
        want = best_size(c, quality)
        have = sizes.get(c["file"], "1080p")     # downloaded before sizes were noted: 1080p
        if os.path.exists(dest) and QUALITIES.index(have) >= QUALITIES.index(want):
            silence(dest)            # from before sound tracks were taken out
            got += 1
            progress(i, 1)
            continue
        try:
            # (a smaller copy already there stays until the better one has fully arrived)
            fetch(f"{c['base']}.{want}.vp9.webm", dest, lambda f, i=i: progress(i, f))
            silence(dest)
            sizes[c["file"]] = want
            save_sizes(folder, sizes)
            got += 1
        except Exception as e:  # keep going: one failed clip shouldn't stop the rest
            try:
                os.remove(dest + ".part")
            except OSError:
                pass
            print(f"error {c['title']}: {e}", flush=True)
    credits(folder)
    print(f"done {got}", flush=True)


if __name__ == "__main__":
    main()
