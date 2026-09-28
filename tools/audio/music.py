"""Procedural score: an ambient exploration piece (shakuhachi, koto, drone)
and a taiko combat layer that the game fades in on top of it."""
import numpy as np

from dsp import (SR, t_axis, white, pink, brown, sine, exp_glide, env_points, lowpass, highpass, bandpass, modal,
                 karplus, taiko, woodblock, flute, reverb, saturate, normalize, fade, pan, place, loopify, rng)

# miyako-bushi scale on D (D Eb G A Bb), several octaves
SCALE = [146.83, 155.56, 196.00, 220.00, 233.08,
         293.66, 311.13, 392.00, 440.00, 466.16,
         587.33, 622.25, 783.99, 880.00, 932.33]


def _stereo(n):
    return np.zeros((n, 2))


def exploration(seed=1, dur=104.0):
    r = rng(seed)
    n = int(dur * SR)
    out = _stereo(n)
    t = t_axis(dur)
    # drone: D and A, slowly breathing
    drone = (sine(73.42, dur) * 0.5 + sine(73.42 * 1.003, dur) * 0.4 + sine(110.0, dur) * 0.25
             + sine(146.83 * 0.998, dur) * 0.12)
    swell = 0.55 + 0.45 * np.sin(2 * np.pi * t / 26.0) ** 2
    drone = lowpass(drone * swell, 600) * 0.16
    air = bandpass(pink(dur, seed), 200, 900) * 0.04 * (0.5 + 0.5 * np.sin(2 * np.pi * t / 17.0 + 1.0))
    out += np.stack([drone + air, drone * 0.96 + air * 0.9], -1)
    # koto: phrases of plucked arpeggios
    at = 2.0
    while at < dur - 6.0:
        phrase_len = r.integers(4, 9)
        base = r.integers(3, 8)
        step_t = r.choice([0.28, 0.36, 0.45])
        p = r.uniform(-0.6, 0.6)
        for k in range(phrase_len):
            idx = int(np.clip(base + r.integers(-2, 3), 0, len(SCALE) - 1))
            f = SCALE[idx]
            note = karplus(f, 3.0, 0.9975, r.uniform(0.3, 0.7), seed + int(at * 100) + k)
            note = fade(note, 0.001, 0.6)
            vel = r.uniform(0.25, 0.45) * (1.0 if k == 0 else 0.8)
            place(out, pan(note * vel, p + r.uniform(-0.15, 0.15)), at + k * step_t + r.uniform(-0.02, 0.02))
        at += phrase_len * step_t + r.uniform(3.0, 7.0)
    # shakuhachi phrases
    at = 9.0
    while at < dur - 10.0:
        length = r.integers(2, 5)
        idx = int(r.integers(5, 12))
        cur = at
        for k in range(length):
            idx = int(np.clip(idx + r.choice([-2, -1, 1, 2]), 5, 13))
            d = r.uniform(1.2, 3.2) if k == length - 1 else r.uniform(0.6, 1.6)
            note = flute(SCALE[idx], d + 0.4, seed + int(cur * 10), vibrato=r.uniform(4.5, 6.0), breath=0.3)
            place(out, pan(note * 0.32, r.uniform(-0.2, 0.2)), cur)
            cur += d * r.uniform(0.85, 1.0)
        at = cur + r.uniform(8.0, 14.0)
    # distant temple bell now and then
    for bt in [20.0, 61.0, 93.0]:
        bell = modal(6.0, [(98 * q, a, d) for q, a, d in [(1.0, 1.0, 4.0), (2.0, 0.5, 3.0), (2.44, 0.4, 2.5), (3.0, 0.3, 2.0), (4.18, 0.25, 1.5)]], seed + int(bt))
        place(out, pan(lowpass(bell, 1800) * 0.12, r.uniform(-0.5, 0.5)), bt)
    out = reverb(out, wet=0.45, seconds=4.0, seed=seed, damp=3500.0)[: n]
    out = loopify(out, 4.0)
    return normalize(fade(out, 0.01, 0.01), 0.7)


def combat(seed=2, bpm=112.0, bars=24):
    r = rng(seed)
    beat = 60.0 / bpm
    dur = bars * 4 * beat
    n = int(dur * SR) + int(3 * SR)
    out = _stereo(n)
    # pre-render drum voices
    odaiko = [taiko(48.0 * r.uniform(0.97, 1.03), 2.2, seed + k, 0.7) for k in range(3)]
    nagado = [taiko(78.0 * r.uniform(0.95, 1.05), 1.4, seed + 10 + k, 0.6) for k in range(4)]
    shime = [taiko(310.0 * r.uniform(0.97, 1.03), 0.25, seed + 20 + k, 1.0) for k in range(4)]
    kake = woodblock(1100, 0.12, seed + 30)
    # the main pattern (16 steps per bar): D = don (nagado), k = ka (rim), s = shime
    patterns = [
        "D...D.k.D.D.k.s.",
        "D..kD.k.D..kD.s.",
        "D.D.k.D.D.k.D.ss",
        "D...D...DkDkD.ss",
    ]
    for bar in range(bars):
        pat = patterns[(bar // 2) % len(patterns)] if bar % 8 != 7 else "D.D.D.DDD.DDDDss"
        t0 = bar * 4 * beat
        if bar % 4 == 0:
            place(out, pan(odaiko[bar % 3] * 0.9, 0.0), t0)
        for i, ch in enumerate(pat):
            at = t0 + i * beat / 4 + r.uniform(-0.004, 0.004)
            if ch == "D":
                place(out, pan(nagado[r.integers(0, 4)] * r.uniform(0.5, 0.7), r.uniform(-0.3, 0.3)), at)
            elif ch == "k":
                place(out, pan(kake * 0.25, 0.4), at)
            elif ch == "s":
                place(out, pan(shime[r.integers(0, 4)] * 0.3, -0.35), at)
        # shime 8ths ostinato
        if bar >= 4:
            for i in range(8):
                place(out, pan(shime[i % 4] * (0.16 if i % 2 else 0.22), -0.5), t0 + i * beat / 2)
    # shamisen-like riff (bright plucks with buzz) from bar 8
    riff = [0, None, 2, 3, None, 2, 0, None, 1, None, 0, None, 3, 4, 3, None]
    low = [146.83, 155.56, 196.0, 220.0, 233.08]
    for bar in range(8, bars):
        t0 = bar * 4 * beat
        for i, idx in enumerate(riff):
            if idx is None:
                continue
            f = low[idx] * (2.0 if (bar // 4) % 2 else 1.0)
            pl = karplus(f, 0.8, 0.992, 0.95, seed + bar * 16 + i)
            pl = saturate(pl * 2.5, 2.0) * 0.18
            place(out, pan(fade(pl, 0.001, 0.2), 0.3), t0 + i * beat / 4)
    # low pulse
    t = t_axis(dur)
    pulse = sine(73.42, dur) * (0.5 + 0.5 * np.cos(2 * np.pi * t / beat)) ** 4 * 0.12
    place(out, np.stack([pulse, pulse], -1), 0.0)
    out = reverb(out, wet=0.25, seconds=2.5, seed=seed, damp=5000.0)[: int(dur * SR)]
    return normalize(fade(out, 0.002, 0.002), 0.85)
