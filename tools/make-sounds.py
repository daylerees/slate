#!/usr/bin/env python3
"""Make Slate's generated sounds in shell/sounds/ (mono, 48 kHz, 16-bit, like the volume tick):

  notification.wav  a soft, quick double tap: two short, rounded tones a fourth apart (E6 then
                    A6), each starting a touch sharp and settling onto its note, dying away fast
  click.wav         a barely-there tap for buttons and menus, like a phone's light haptic:
                    one smooth, low pulse (three cycles at 210 Hz, about 14 ms)
  welcome.wav       "sunrise", a gentle welcome when you log in: a soft, open D major 9 chord
                    that swells in, opens up brighter as it rises and fades, about 3.4 s

Run it from anywhere; it writes next to the other sounds.

    tools/make-sounds.py
"""
import math
import os
import struct
import wave

RATE = 48000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shell", "sounds")


def write(name, samples, peak, tail):
    """Normalise to `peak` of full scale, fade the last `tail` seconds to silence, and save."""
    n = len(samples)
    fade_n = max(1, int(RATE * tail))
    samples = [s * min(1.0, (n - i) / fade_n) for i, s in enumerate(samples)]
    top = max(abs(s) for s in samples) or 1.0
    frames = b"".join(struct.pack("<h", round(s / top * peak * 32767)) for s in samples)
    path = os.path.normpath(os.path.join(OUT, name))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print("wrote", path)


def onset(t, ms):
    """A rounded fade-in over `ms` milliseconds, so nothing starts with a click."""
    return math.sin(min(1.0, t / (ms / 1000)) * math.pi / 2)


def notification():
    notes = [(0.000, 1318.51, 0.70), (0.070, 1760.00, 1.00)]    # (start s, Hz, level): E6, A6
    glide, glide_time, decay = 0.04, 0.012, 0.065               # 4% sharp, settling in 12 ms

    def tone(t, f):
        if t < 0:
            return 0.0
        phase = 2 * math.pi * f * (t + glide * glide_time * (1 - math.exp(-t / glide_time)))
        return onset(t, 6) * math.exp(-t / decay) * (math.sin(phase) + 0.08 * math.sin(2 * phase))

    n = int(RATE * 0.38)
    samples = [sum(lv * tone(i / RATE - st, f) for st, f, lv in notes) for i in range(n)]
    write("notification.wav", samples, peak=0.32, tail=0.05)


def click():
    # Like a phone's light haptic tap: a single smooth pulse, a few cycles of a low tone with a
    # rounded (Hann) envelope, no edge and no noise, so it's felt more than heard
    freq, cycles = 210.0, 3
    n = int(RATE * cycles / freq)
    samples = [0.5 * (1 - math.cos(2 * math.pi * i / n)) * math.sin(2 * math.pi * freq * i / RATE)
               for i in range(n)]
    samples += [0.0] * int(RATE * 0.005)         # a moment of silence after it
    write("click.wav", samples, peak=0.035, tail=0.001)


def welcome():
    # Like light coming up: a soft, open D major 9 chord (D3, A3, F#4, C#5, E5), each voice a
    # gently chorused pair, that swells in over about a second, opens up brighter as it rises,
    # and fades slowly.
    voices = [146.83, 220.00, 369.99, 554.37, 659.25]
    levels = [1.0, 0.8, 0.6, 0.45, 0.35]
    n = int(RATE * 3.4)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.sin(min(1.0, t / 0.9) * math.pi / 2) ** 2 * math.exp(-max(0.0, t - 1.3) / 0.8)
        bright = min(1.0, t / 1.4)                                  # opens up as it swells
        w = 2 * math.pi * t
        v = 0.0
        for f, lv in zip(voices, levels):
            for d in (-0.5, 0.5):
                v += lv * (math.sin(w * (f + d)) + 0.25 * bright * math.sin(2 * w * (f + d))
                           + 0.08 * bright * math.sin(3 * w * (f + d)))
        out.append(env * v)
    write("welcome.wav", out, peak=0.2, tail=0.6)


if __name__ == "__main__":
    notification()
    click()
    welcome()
