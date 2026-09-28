"""Looping ambience beds: wind, birds, night crickets, ocean, rain and fire."""
import numpy as np

from dsp import (SR, t_axis, white, pink, brown, sine, exp_glide, glide, env_points, lowpass, highpass, bandpass,
                 sweep_filter, fm, normalize, fade, pan, place, loopify, rng)


def wind(seed=1, dur=44.0):
    t = t_axis(dur)
    chans = []
    for c in range(2):
        r = rng(seed + c)
        lfo = 0.5 + 0.5 * np.sin(2 * np.pi * t / r.uniform(9, 13) + r.uniform(0, 6)) * np.sin(2 * np.pi * t / r.uniform(3.5, 5.5))
        fc = 250 + 700 * lfo
        whistle = sweep_filter(pink(dur, seed + 10 + c), fc, 3.0) * (0.3 + 0.7 * lfo)
        bed = lowpass(brown(dur, seed + 20 + c), 400) * (0.6 + 0.4 * lfo)
        leaves = bandpass(white(dur, seed + 30 + c), 2500, 7000) * (lfo ** 2) * 0.12
        chans.append(whistle * 0.5 + bed * 0.8 + leaves)
    out = np.stack(chans, -1)
    return normalize(loopify(out, 3.0), 0.6)


def _chirp(seed):
    r = rng(seed)
    kind = r.integers(0, 3)
    if kind == 0:  # quick descending tweet
        d = r.uniform(0.06, 0.12)
        f = exp_glide(r.uniform(4000, 6000), r.uniform(2500, 3500), d)
        y = sine(f, d) * env_points(d, [(0, 0), (0.01, 1), (d, 0)])
    elif kind == 1:  # trill
        d = r.uniform(0.3, 0.6)
        t = t_axis(d)
        f = r.uniform(3000, 4500) * (1 + 0.1 * np.sin(2 * np.pi * r.uniform(18, 30) * t))
        y = sine(f, d) * (0.5 + 0.5 * np.sin(2 * np.pi * r.uniform(15, 25) * t) ** 2) * env_points(d, [(0, 0), (0.03, 1), (d, 0)])
    else:  # two-note call (like an uguisu fragment)
        d1, d2 = r.uniform(0.3, 0.5), r.uniform(0.15, 0.3)
        a = sine(glide(r.uniform(1800, 2200), r.uniform(2000, 2400), d1), d1) * env_points(d1, [(0, 0), (0.05, 1), (d1, 0.3)])
        b = sine(exp_glide(r.uniform(3200, 3800), r.uniform(2400, 2800), d2), d2) * env_points(d2, [(0, 0), (0.01, 1), (d2, 0)])
        y = np.concatenate([a, np.zeros(int(0.05 * SR)), b])
    return y


def birds(seed=2, dur=46.0):
    r = rng(seed)
    n = int(dur * SR)
    out = np.zeros((n, 2))
    at = 0.5
    while at < dur - 2.0:
        bird_pan = r.uniform(-0.9, 0.9)
        dist = r.uniform(0.2, 1.0)
        for k in range(r.integers(1, 5)):
            c = _chirp(seed * 1000 + int(at * 100) + k)
            c = lowpass(c, 9000 - 5000 * (1 - dist))
            place(out, pan(c * 0.25 * dist, bird_pan), at)
            at += len(c) / SR + r.uniform(0.05, 0.3)
        at += r.uniform(0.5, 3.5)
    t = t_axis(dur)
    rustle = bandpass(pink(dur, seed + 5), 1500, 6000) * (0.3 + 0.7 * (0.5 + 0.5 * np.sin(2 * np.pi * t / 7.0)) ** 3) * 0.05
    out += np.stack([rustle, np.roll(rustle, 3000)], -1)
    return normalize(loopify(out, 2.0), 0.5)


def crickets(seed=3, dur=32.0):
    r = rng(seed)
    t = t_axis(dur)
    out = np.zeros((len(t), 2))
    for k in range(9):
        f = r.uniform(3800, 5200)
        rate = r.uniform(25, 45)
        group = r.uniform(0.5, 1.2)
        carrier = sine(f, dur)
        pulses = (np.sin(2 * np.pi * rate * t) > 0.3).astype(float)
        grouping = (np.sin(2 * np.pi * t / group + r.uniform(0, 6)) > r.uniform(-0.2, 0.4)).astype(float)
        env = lowpass(pulses * grouping, 200)
        y = carrier * env * r.uniform(0.05, 0.15)
        out += pan(y, r.uniform(-0.9, 0.9))
    frog = np.zeros(len(t))
    for k in range(20):
        at = r.uniform(0, dur - 1)
        d = 0.18
        croak = sine(r.uniform(180, 260), d) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 40 * t_axis(d)))) * env_points(d, [(0, 0), (0.02, 1), (d, 0)])
        place(frog, lowpass(croak, 900) * 0.12, at)
    out += pan(frog, -0.3)
    return normalize(loopify(out, 2.0), 0.45)


def ocean(seed=4, dur=42.0):
    t = t_axis(dur)
    chans = []
    for c in range(2):
        r = rng(seed + c)
        swell = np.zeros(len(t))
        at = 0.0
        while at < dur:
            period = r.uniform(5.5, 8.5)
            w = env_points(period, [(0, 0), (period * 0.45, 1.0), (period * 0.55, 0.8), (period, 0)])
            place(swell, w, at)
            at += period * r.uniform(0.8, 1.0)
        body = lowpass(brown(dur, seed + 10 + c), 500) * (0.3 + swell)
        foam = bandpass(white(dur, seed + 20 + c), 1500, 8000) * swell ** 3 * 0.35
        chans.append(body + foam)
    return normalize(loopify(np.stack(chans, -1), 3.0), 0.6)


def rain(seed=5, dur=30.0):
    r = rng(seed)
    t = t_axis(dur)
    chans = []
    for c in range(2):
        hiss = highpass(pink(dur, seed + c), 1200) * 0.35
        drops = np.zeros(len(t))
        for k in range(1400):
            at = r.uniform(0, dur - 0.05)
            d = 0.03
            drop = bandpass(white(d, seed * 7 + k), r.uniform(1500, 3000), r.uniform(4000, 8000)) * np.exp(-t_axis(d) / 0.004)
            place(drops, drop * r.uniform(0.05, 0.3), at)
        rumble = lowpass(brown(dur, seed + 30 + c), 200) * 0.3
        chans.append(hiss + drops + rumble)
    return normalize(loopify(np.stack(chans, -1), 2.0), 0.55)


def fire(seed=6, dur=10.0):
    r = rng(seed)
    t = t_axis(dur)
    roar = lowpass(brown(dur, seed), 280) * (0.7 + 0.3 * lowpass(white(dur, seed + 1), 3))
    crack = np.zeros(len(t))
    for k in range(260):
        at = r.uniform(0, dur - 0.05)
        d = r.uniform(0.004, 0.02)
        c = bandpass(white(d, seed * 13 + k), r.uniform(800, 2000), r.uniform(3000, 9000)) * np.exp(-t_axis(d) / (d * 0.3))
        place(crack, c * r.uniform(0.1, 1.0) ** 2, at)
    hiss = bandpass(pink(dur, seed + 3), 2000, 6000) * 0.05
    y = roar * 0.7 + crack * 0.9 + hiss
    return normalize(loopify(y, 1.0), 0.7)
