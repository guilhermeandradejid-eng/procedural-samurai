"""Small DSP toolkit for synthesising the game's sounds with numpy/scipy.

Everything is float64 mono (or (n, 2) stereo) at SR Hz in [-1, 1].
"""
import math

import numpy as np
from scipy import signal

SR = 44100


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def rng(seed):
    return np.random.default_rng(seed)


# ---------------------------------------------------------------- sources

def white(dur, seed=0):
    return rng(seed).uniform(-1.0, 1.0, int(dur * SR))


def pink(dur, seed=0):
    n = int(dur * SR)
    w = rng(seed).standard_normal(n)
    # Voss-McCartney approximation through a 1/f filter
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    p = signal.lfilter(b, a, w)
    return p / (np.max(np.abs(p)) + 1e-9)


def brown(dur, seed=0):
    n = int(dur * SR)
    w = rng(seed).standard_normal(n)
    b = np.cumsum(w)
    b = signal.lfilter([1, -1], [1, -0.995], b)
    return b / (np.max(np.abs(b)) + 1e-9)


def sine(freq, dur, phase=0.0):
    """freq may be a scalar or an array (instantaneous frequency)."""
    n = int(dur * SR)
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,)) if np.ndim(freq) else np.full(n, float(freq))
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    return np.sin(ph)


def glide(f0, f1, dur, curve=1.0):
    t = np.linspace(0.0, 1.0, int(dur * SR))
    return f0 + (f1 - f0) * t ** curve


def exp_glide(f0, f1, dur):
    t = np.linspace(0.0, 1.0, int(dur * SR))
    return f0 * (f1 / f0) ** t


# ---------------------------------------------------------------- envelopes

def env_exp(dur, decay, attack=0.002):
    t = t_axis(dur)
    e = np.exp(-t / max(decay, 1e-4))
    if attack > 0:
        e *= np.clip(t / attack, 0.0, 1.0)
    return e


def env_adsr(dur, a=0.01, d=0.1, s=0.7, r=0.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    e = np.ones(n) * s
    e[t < a] = t[t < a] / a
    m = (t >= a) & (t < a + d)
    e[m] = 1.0 - (1.0 - s) * (t[m] - a) / d
    rel = t > dur - r
    e[rel] *= np.clip((dur - t[rel]) / r, 0.0, 1.0)
    return e


def env_points(dur, pts):
    """Piecewise-linear envelope; pts = [(time, value), ...]."""
    t = t_axis(dur)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return np.interp(t, xs, ys)


# ---------------------------------------------------------------- filters

def _sos(kind, freq, q=0.707, order=2):
    nyq = SR * 0.5
    if kind == "bandpass":
        lo, hi = freq
        return signal.butter(order, [max(lo, 10) / nyq, min(hi, nyq * 0.98) / nyq], btype="band", output="sos")
    return signal.butter(order, min(max(freq, 10), nyq * 0.98) / nyq, btype=kind, output="sos")


def lowpass(x, f, order=2):
    return signal.sosfilt(_sos("low", f, order=order), x)


def highpass(x, f, order=2):
    return signal.sosfilt(_sos("high", f, order=order), x)


def bandpass(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", (lo, hi), order=order), x)


def sweep_filter(x, f_curve, q=4.0, kind="band"):
    """Time-varying resonant filter (state-variable, per-sample)."""
    y = np.zeros_like(x)
    low = band = 0.0
    fc = np.broadcast_to(f_curve, x.shape)
    damp = 1.0 / q
    for i in range(len(x)):
        f = 2.0 * math.sin(math.pi * min(fc[i], SR * 0.24) / SR)
        low += f * band
        high = x[i] - low - damp * band
        band += f * high
        y[i] = band if kind == "band" else (low if kind == "low" else high)
    return y


def resonator(x, freq, decay):
    """Two-pole resonator ringing at `freq` with a -60 dB time of `decay`."""
    r = math.exp(-6.9 / (decay * SR))
    w = 2 * math.pi * freq / SR
    a = [1.0, -2.0 * r * math.cos(w), r * r]
    b = [1.0 - r]
    return signal.lfilter(b, a, x)


# ---------------------------------------------------------------- synthesis

def modal(dur, partials, seed=0, strike=None):
    """Sum of damped sinusoids: partials = [(freq, amp, decay), ...]."""
    t = t_axis(dur)
    out = np.zeros_like(t)
    r = rng(seed)
    for f, a, d in partials:
        ph = r.uniform(0, 2 * np.pi)
        out += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / d)
    if strike is not None:
        out[: len(strike)] += strike[: len(out)]
    # never end on a click: taper the last 15%
    k = max(1, int(len(out) * 0.15))
    out[-k:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, k))
    return out


def karplus(freq, dur, decay=0.996, bright=0.5, seed=0):
    """Plucked string (Karplus-Strong) via a comb filter."""
    n = int(dur * SR)
    period = max(2, int(SR / freq))
    exc = rng(seed).uniform(-1, 1, period)
    exc = lowpass(exc, 1500 + bright * 7000)
    x = np.zeros(n)
    x[:period] = exc
    a = np.zeros(period + 2)
    a[0] = 1.0
    a[period] = -decay * 0.5
    a[period + 1] = -decay * 0.5
    return signal.lfilter([1.0], a, x)


def fm(carrier, ratio, index, dur, index_env=None):
    t = t_axis(dur)
    ie = index if index_env is None else index * index_env
    mod = np.sin(2 * np.pi * carrier * ratio * t) * ie
    return np.sin(2 * np.pi * carrier * t + mod)


def glottal(f0_curve, dur, breath=0.1, seed=0):
    """Voice source: band-limited pulse train following f0 plus breath."""
    n = int(dur * SR)
    f0 = np.broadcast_to(f0_curve, (n,)) if np.ndim(f0_curve) else np.full(n, float(f0_curve))
    ph = np.cumsum(f0) / SR
    frac = ph % 1.0
    # Rosenberg-like pulse
    pulse = np.where(frac < 0.4, 0.5 * (1 - np.cos(np.pi * frac / 0.4)), np.cos(np.pi * (frac - 0.4) / 0.2 * 0.5) ** 2 * (frac < 0.6))
    src = np.diff(pulse, prepend=0.0) * 20.0
    src += white(dur, seed)[:n] * breath
    return src


def formants(src, fmts):
    """Parallel formant filter bank: fmts = [(freq, bandwidth, gain), ...]."""
    out = np.zeros_like(src)
    for f, bw, g in fmts:
        out += g * bandpass(src, max(f - bw / 2, 30), f + bw / 2, order=2)
    return out


VOWELS = {
    "a": [(750, 120, 1.0), (1150, 140, 0.6), (2600, 200, 0.25)],
    "o": [(500, 100, 1.0), (850, 120, 0.55), (2500, 200, 0.15)],
    "u": [(350, 80, 1.0), (750, 120, 0.3), (2400, 200, 0.1)],
    "e": [(450, 100, 1.0), (1900, 160, 0.5), (2600, 200, 0.3)],
    "uh": [(600, 120, 1.0), (1100, 150, 0.4), (2500, 200, 0.15)],
    "m": [(250, 60, 1.0), (1200, 200, 0.1), (2500, 300, 0.05)],
}


def voice(vowel, f0_curve, dur, breath=0.15, seed=0, rough=0.0):
    src = glottal(f0_curve, dur, breath, seed)
    if rough > 0:
        src *= 1.0 + rough * rng(seed + 1).standard_normal(len(src)) * 0.5
    return formants(src, VOWELS[vowel])


def taiko(freq=70.0, dur=1.6, seed=0, hardness=0.5):
    t = t_axis(dur)
    f = freq * (1.0 + 0.6 * np.exp(-t / 0.03))
    body = sine(f, dur) * np.exp(-t / (0.35 + 0.2 * (1 - hardness)))
    skin = bandpass(white(dur, seed), 200, 2500) * np.exp(-t / 0.02) * hardness
    overt = sine(f * 1.58, dur) * np.exp(-t / 0.15) * 0.25
    return body + skin * 0.6 + overt


def woodblock(freq=900.0, dur=0.25, seed=0):
    t = t_axis(dur)
    return (sine(freq, dur) * np.exp(-t / 0.035) + 0.4 * sine(freq * 2.7, dur) * np.exp(-t / 0.015)
            + bandpass(white(dur, seed), 1500, 5000) * np.exp(-t / 0.004) * 0.5)


def flute(freq, dur, seed=0, vibrato=5.0, breath=0.25, attack=0.12):
    """Breathy bamboo flute (shakuhachi-like) note."""
    t = t_axis(dur)
    vib = 1.0 + 0.008 * np.sin(2 * np.pi * vibrato * t) * np.clip((t - 0.25) / 0.4, 0, 1)
    f = freq * vib
    # slight scoop into the pitch (meri/kari)
    f *= 1.0 - 0.03 * np.exp(-t / 0.08)
    tone = sine(f, dur) + 0.3 * sine(f * 2, dur) + 0.08 * sine(f * 3, dur)
    br = bandpass(white(dur, seed), freq * 0.8, freq * 4.0) * breath
    br += highpass(white(dur, seed + 7), 3000) * breath * 0.3 * np.exp(-t / 0.1)
    env = env_adsr(dur, a=attack, d=0.2, s=0.75, r=min(0.35, dur * 0.4))
    return (tone * 0.6 + br) * env


# ---------------------------------------------------------------- effects

def reverb_ir(seconds=2.2, seed=0, damp=4000.0, pre=0.012, stereo=True):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    r = rng(seed)
    chans = []
    for c in range(2 if stereo else 1):
        noise = r.standard_normal(n) * np.exp(-t / (seconds / 6.9))
        noise = lowpass(noise, damp)
        ir = np.zeros(n + int(pre * SR))
        ir[int(pre * SR):] = noise
        # a few early reflections
        for k in range(6):
            d = int(r.uniform(0.005, 0.06) * SR)
            ir[d] += r.uniform(0.2, 0.5) * (1 if k % 2 else -1)
        chans.append(ir / np.sqrt(np.sum(ir ** 2)))
    return np.stack(chans, -1) if stereo else chans[0]


def reverb(x, wet=0.25, seconds=2.2, seed=0, damp=4000.0):
    """Convolution reverb; mono input -> stereo output."""
    ir = reverb_ir(seconds, seed, damp)
    if x.ndim == 1:
        x = np.stack([x, x], -1)
    out = np.zeros((len(x) + len(ir) - 1, 2))
    for c in range(2):
        out[:, c] = signal.fftconvolve(x[:, c], ir[:, c])
    out *= wet
    out[: len(x)] += x * (1.0 - wet * 0.5)
    return out


def reverb_mono(x, wet=0.2, seconds=1.2, seed=0, damp=5000.0):
    ir = reverb_ir(seconds, seed, damp, stereo=False)
    y = signal.fftconvolve(x, ir) * wet
    y[: len(x)] += x
    return y


def saturate(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def pan(x, p):
    """Constant-power pan of mono x: p in [-1, 1]."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], -1)


def fade(x, fin=0.005, fout=0.02):
    n = len(x)
    e = np.ones(n)
    a = min(int(fin * SR), n)
    b = min(int(fout * SR), n)
    if a > 0:
        e[:a] = np.linspace(0, 1, a)
    if b > 0:
        e[n - b:] = np.minimum(e[n - b:], np.linspace(1, 0, b))
    return x * (e[:, None] if x.ndim == 2 else e)


def normalize(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x * (peak / m)


def mix(*parts):
    n = max(len(p) for p in parts)
    stereo = any(p.ndim == 2 for p in parts)
    out = np.zeros((n, 2)) if stereo else np.zeros(n)
    for p in parts:
        if stereo and p.ndim == 1:
            p = np.stack([p, p], -1)
        out[: len(p)] += p
    return out


def place(buf, x, at):
    """Adds x into buf starting at time `at` (seconds), clipping at the end."""
    i = int(at * SR)
    if i < 0:
        x = x[-i:]
        i = 0
    if i >= len(buf) or len(x) == 0:
        return buf
    j = min(len(buf), i + len(x))
    if buf.ndim == 2 and x.ndim == 1:
        x = np.stack([x, x], -1)
    buf[i:j] += x[: j - i]
    return buf


def loopify(x, xfade=1.5):
    """Makes a buffer loop seamlessly by cross-fading its tail into its head."""
    n = int(xfade * SR)
    head = x[:n].copy()
    tail = x[-n:].copy()
    w = np.linspace(0, 1, n)
    if x.ndim == 2:
        w = w[:, None]
    out = x[:-n].copy()
    out[:n] = head * w + tail * (1 - w)
    return out
