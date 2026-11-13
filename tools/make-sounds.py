#!/usr/bin/env python3
"""Make Slate's generated sounds in shell/sounds/ (mono, 48 kHz, 16-bit, like the volume tick):

  notification.wav  a soft, quick double tap: two short, rounded tones a fourth apart (E6 then
                    A6), each starting a touch sharp and settling onto its note, dying away fast
  click.wav         a barely-there tap for buttons and menus, like a phone's light haptic:
                    one smooth, low pulse (three cycles at 210 Hz, about 14 ms)
  welcome.wav       "sunrise", a gentle welcome when you log in: a soft, open D major 9 chord
                    that swells in, opens up brighter as it rises and fades, about 3.4 s
  goodbye.wav       a closing sound for log out, restart and shut down: soft notes stepping
                    down the welcome's chord to rest on the low home note, over a warm hum, 2.6 s
  swish-left.wav,   a soft, airy swish for switching workspaces and windows: filtered noise
  swish-right.wav   sweeping up and back as it swells and fades, about 160 ms, drifting gently
                    left or right (stereo) with the direction of the move
  attention.wav     for confirmations, password prompts and warnings: a soft question, two of
                    the notification's tones stepping up a whole tone (D5, E5), unresolved,
                    the second lifting a touch at its end, about 0.7 s
  answered.wav      Nova's answer arriving while you wait: a soft bloom, a warm, rounded E5 with
                    a quiet fifth (B5) just after it, each with a faint shimmer an octave up that
                    twinkles as it fades; settled, not questioning, about 0.55 s

Run it from anywhere; it writes next to the other sounds.

    tools/make-sounds.py
"""
import math
import os
import random
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


def goodbye():
    # A closing sound, for log out, restart and shut down: soft notes stepping down through the
    # welcome's chord (E5, C#5, A4) and coming to rest on the low home note (D4), over a warm,
    # low D that swells in and fades with them. Landing on the home note sounds finished, not
    # broken. About 2.6 s.
    steps = [(0.00, 659.25, 0.55), (0.28, 554.37, 0.65), (0.56, 440.00, 0.80), (0.84, 293.66, 1.00)]

    def note(t, f, last):
        if t < 0:
            return 0.0
        decay = 0.9 if last else 0.45                               # the last one rings on
        return onset(t, 20) * math.exp(-t / decay) * (math.sin(2 * math.pi * f * t) + 0.1 * math.sin(4 * math.pi * f * t))

    n = int(RATE * 2.6)
    out = []
    for i in range(n):
        t = i / RATE
        hum = math.sin(min(1.0, t / 0.6) * math.pi / 2) ** 2 * math.exp(-max(0.0, t - 0.9) / 0.6)
        w = 2 * math.pi * t
        low = sum(0.5 * math.sin(w * (f - 0.5)) + 0.5 * math.sin(w * (f + 0.5)) for f in (146.83, 220.00))
        v = 0.35 * hum * low
        v += sum(lv * note(t - st, f, k == len(steps) - 1) for k, (st, f, lv) in enumerate(steps))
        out.append(v)
    write("goodbye.wav", out, peak=0.2, tail=0.5)


def write_stereo(name, left, right, peak, tail):
    """Like write(), for two channels (normalised together, so the balance is kept)."""
    n = len(left)
    fade_n = max(1, int(RATE * tail))
    g = [min(1.0, (n - i) / fade_n) for i in range(n)]
    top = max(max(abs(x) for x in left), max(abs(x) for x in right)) or 1.0
    k = peak * 32767 / top
    frames = b"".join(struct.pack("<hh", round(l * gi * k), round(r * gi * k)) for l, r, gi in zip(left, right, g))
    path = os.path.normpath(os.path.join(OUT, name))
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print("wrote", path)


def swish():
    # A soft, airy swish for switching workspaces and windows: filtered noise whose band sweeps
    # up and back as it swells and fades, like a hand passing by. About 160 ms, and quiet.
    # Two versions drift gently across, for moving right or left; the drift is subtle (from a
    # little off-centre on one side to a little on the other), never hard over.
    rng = random.Random(11)                     # the same swish every time the sound is made
    n = int(RATE * 0.16)
    mono, y1, y2, x1, x2 = [], 0.0, 0.0, 0.0, 0.0
    for i in range(n):
        t = i / RATE
        u = t / 0.16
        env = math.sin(math.pi * min(1.0, u / 0.35) / 2) ** 2 * (1 - max(0.0, (u - 0.35) / 0.65)) ** 2
        # band-pass (RBJ), centre sweeping 700 Hz -> 2.6 kHz -> 1.6 kHz
        fc = 700 + 1900 * math.sin(math.pi * min(1.0, u / 0.7) / 2) - 1000 * max(0.0, (u - 0.7) / 0.3)
        q = 1.2
        w0 = 2 * math.pi * fc / RATE
        alpha = math.sin(w0) / (2 * q)
        b0, b2 = alpha, -alpha
        a0, a1, a2 = 1 + alpha, -2 * math.cos(w0), 1 - alpha
        x = rng.uniform(-1, 1)
        y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, x, y1, y
        mono.append(env * y)
    for name, sign in (("swish-right.wav", 1), ("swish-left.wav", -1)):
        left, right = [], []
        for i, v in enumerate(mono):
            pan = sign * 0.3 * (2 * i / (n - 1) - 1)                # -0.3 -> +0.3 (or back)
            a = (pan + 1) * math.pi / 4                             # equal-power pan
            left.append(v * math.cos(a))
            right.append(v * math.sin(a))
        write_stereo(name, left, right, peak=0.12, tail=0.02)


def attention():
    # For confirmations, password prompts and warnings: a soft question, not an alarm. Two of the
    # notification's rounded tones, lower and warmer, stepping up a whole tone (D5, E5) without
    # resolving, the second lifting a touch at its end like a spoken question. About 0.7 s.
    notes = [(0.00, 587.33, 0.80, 0.0), (0.16, 659.25, 1.00, 0.025)]   # (start s, Hz, level, lift)

    def tone(t, f, lift):
        if t < 0:
            return 0.0
        # the pitch rises by `lift` (a fraction) over the note's ring, integrated into the phase
        phase = 2 * math.pi * f * (t + lift * (t - 0.25 * (1 - math.exp(-t / 0.25))))
        return onset(t, 8) * math.exp(-t / 0.22) * (math.sin(phase) + 0.12 * math.sin(2 * phase))

    n = int(RATE * 0.7)
    out = [sum(lv * tone(i / RATE - st, f, lift) for st, f, lv, lift in notes) for i in range(n)]
    write("attention.wav", out, peak=0.3, tail=0.12)


def answered(name="answered.wav", notes=((0.0, 659.25, 1.0), (0.03, 987.77, 0.45)), attack=28, decay=0.16,
             shimmer=0.18, twinkle=4.0, length=0.55, peak=0.2):
    # Nova's answer arriving while you wait: a soft bloom, like a star coming out. A warm,
    # rounded E5 with a quiet fifth (B5) opening just after it (lower than the notification, and
    # an open, settled interval where attention asks with a rising step), each with a faint
    # shimmer an octave up, two partials `twinkle` Hz either side, so it twinkles gently as it
    # fades. A slow onset, so there's no tap to it, and quiet, so it isn't tiring when it plays
    # several times in a conversation. (start s, Hz, level) notes; the defaults are the sound
    # itself, other settings were tried (a single G5 glint; C6 falling to G5)
    def tone(t, f):
        if t < 0:
            return 0.0
        w = 2 * math.pi * f * t
        body = onset(t, attack) * math.exp(-t / decay) * (math.sin(w) + 0.06 * math.sin(2 * w))
        sparkle = onset(t, attack * 2) * math.exp(-t / (decay * 0.75)) * 0.5 * (
            math.sin(2 * math.pi * (2 * f - twinkle) * t) + math.sin(2 * math.pi * (2 * f + twinkle) * t))
        return body + shimmer * sparkle

    n = int(RATE * length)
    out = [sum(lv * tone(i / RATE - st, f) for st, f, lv in notes) for i in range(n)]
    write(name, out, peak=peak, tail=0.1)


if __name__ == "__main__":
    notification()
    click()
    welcome()
    goodbye()
    swish()
    attention()
    answered()
