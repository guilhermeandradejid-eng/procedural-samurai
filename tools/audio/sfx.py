"""Sound effects: swords, flesh, bodies, voices, UI and world one-shots."""
import numpy as np

from dsp import (SR, t_axis, white, pink, brown, sine, glide, exp_glide, env_exp, env_points, lowpass, highpass,
                 bandpass, sweep_filter, resonator, modal, karplus, voice, taiko, woodblock, flute, reverb_mono,
                 saturate, normalize, fade, mix, place, rng)  # noqa: F401


def whoosh(dur, f0, f1, f2, seed, q=2.5, body=0.0):
    t = t_axis(dur)
    n = white(dur, seed)
    k = np.linspace(0, 1, len(t))
    fc = np.where(k < 0.45, f0 + (f1 - f0) * (k / 0.45) ** 0.8, f1 + (f2 - f1) * ((k - 0.45) / 0.55))
    # two resonant passes make the moving band stand out from the hiss
    y = sweep_filter(sweep_filter(n, fc, q), fc, q * 0.8)
    y = lowpass(y, 5200)
    env = env_points(dur, [(0, 0), (dur * 0.3, 0.7), (dur * 0.45, 1.0), (dur * 0.62, 0.55), (dur, 0)])
    y *= env
    if body > 0:
        y += lowpass(brown(dur, seed + 3), 220) * env * body
    return y


def swing(seed):
    r = rng(seed)
    d = r.uniform(0.22, 0.3)
    y = whoosh(d, r.uniform(350, 500), r.uniform(1500, 2200), r.uniform(450, 700), seed, q=r.uniform(4.0, 6.0), body=0.25)
    return normalize(fade(y), 0.8)


def swing_heavy(seed):
    r = rng(seed)
    d = r.uniform(0.38, 0.48)
    y = whoosh(d, r.uniform(180, 260), r.uniform(800, 1200), r.uniform(220, 350), seed, q=3.5, body=0.9)
    return normalize(fade(y), 0.9)


def _strike(dur, seed, lo=2000, hi=9000, decay=0.004):
    t = t_axis(dur)
    return bandpass(white(dur, seed), lo, hi) * np.exp(-t / decay)


def clash(seed):
    """Katana on katana: bright inharmonic ring + scrape."""
    r = rng(seed)
    base = r.uniform(900, 1400)
    ratios = [1.0, 2.76, 5.40, 8.93, 13.34, 1.5]
    partials = [(base * q * r.uniform(0.98, 1.02), a, d) for q, a, d in
                zip(ratios, [1.0, 0.7, 0.5, 0.35, 0.2, 0.3], [0.5, 0.4, 0.25, 0.18, 0.1, 0.3])]
    dur = 1.1
    y = modal(dur, partials, seed) * 0.5
    y += _strike(dur, seed + 1, 1500, 12000, 0.006) * 1.2
    scrape = bandpass(white(0.25, seed + 2), 3000, 9000) * env_points(0.25, [(0, 0), (0.02, 0.6), (0.25, 0)])
    y = place(y, scrape * 0.3, 0.01)
    y = reverb_mono(y, 0.18, 0.9, seed)[: int(1.4 * SR)]
    return normalize(fade(y, 0.001, 0.2), 0.85)


def parry(seed):
    """A perfect parry rings longer and brighter, with a low punch."""
    r = rng(seed)
    base = r.uniform(1400, 1700)
    partials = [(base * q, a, d) for q, a, d in
                [(1.0, 1.0, 1.2), (2.76, 0.8, 0.9), (5.4, 0.6, 0.6), (8.93, 0.4, 0.4), (0.5, 0.35, 0.5), (11.2, 0.2, 0.25)]]
    dur = 2.0
    y = modal(dur, partials, seed) * 0.5
    y += _strike(dur, seed + 1, 2000, 14000, 0.008) * 1.5
    t = t_axis(dur)
    y += sine(exp_glide(160, 60, dur), dur) * np.exp(-t / 0.09) * 0.8
    y = reverb_mono(y, 0.3, 1.8, seed)[: int(2.3 * SR)]
    return normalize(fade(y, 0.001, 0.3), 0.95)


def guard_break(seed):
    dur = 1.2
    t = t_axis(dur)
    y = clash(seed)[: int(dur * SR)] * 0.7
    thud = sine(exp_glide(110, 45, dur), dur) * np.exp(-t / 0.18)
    crack = saturate(bandpass(white(dur, seed + 5), 400, 4000) * np.exp(-t / 0.05), 4.0) * 0.8
    y = mix(y, thud, crack)
    return normalize(fade(y, 0.001, 0.2), 0.95)


def flesh_cut(seed):
    r = rng(seed)
    dur = 0.55
    t = t_axis(dur)
    slice_ = bandpass(white(dur, seed), r.uniform(1200, 1800), r.uniform(4500, 7000)) * np.exp(-t / r.uniform(0.03, 0.06))
    thump = sine(exp_glide(r.uniform(110, 150), 50, dur), dur) * np.exp(-t / 0.07)
    wet = lowpass(white(dur, seed + 3), 900) * (1 + 0.8 * np.sin(2 * np.pi * r.uniform(25, 40) * t)) * np.exp(-t / 0.12)
    y = slice_ * 0.9 + thump * 0.8 + wet * 0.7
    return normalize(fade(y, 0.001, 0.08), 0.9)


def dismember(seed):
    r = rng(seed)
    dur = 1.2
    t = t_axis(dur)
    y = flesh_cut(seed)
    crack = np.zeros(int(dur * SR))
    for k in range(4):
        at = 0.02 + k * r.uniform(0.008, 0.02)
        c = resonator(np.r_[np.zeros(1), r.uniform(-1, 1, 60)], r.uniform(250, 500), 0.05) * 3.0
        place(crack, c, at)
    splat = np.zeros(int(dur * SR))
    for k in range(18):
        at = r.uniform(0.08, 0.9)
        d = r.uniform(0.02, 0.06)
        drop = bandpass(white(d, seed + 20 + k), 400, 2500) * np.exp(-t_axis(d) / (d * 0.3))
        place(splat, drop * r.uniform(0.1, 0.4) * np.exp(-at / 0.5), at)
    gush = lowpass(white(dur, seed + 9), 1200) * env_points(dur, [(0, 0), (0.05, 0.5), (0.5, 0.25), (dur, 0)])
    out = mix(y, crack * 0.8, splat, gush * 0.35)
    return normalize(fade(out, 0.001, 0.2), 0.95)


def death_grunt(seed):
    r = rng(seed)
    dur = r.uniform(0.5, 0.8)
    f0 = glide(r.uniform(120, 150), r.uniform(70, 90), dur, 0.8)
    v = voice(["uh", "a", "o"][seed % 3], f0, dur, 0.25, seed, rough=0.4)
    v *= env_points(dur, [(0, 0), (0.03, 1.0), (dur * 0.5, 0.7), (dur, 0)])
    return normalize(fade(reverb_mono(v, 0.12, 0.6, seed)), 0.8)


def scream(seed):
    r = rng(seed)
    dur = r.uniform(1.0, 1.4)
    t = t_axis(dur)
    f0 = glide(r.uniform(260, 320), r.uniform(180, 220), dur) * (1 + 0.03 * np.sin(2 * np.pi * 6.5 * t))
    v = voice("a", f0, dur, 0.35, seed, rough=0.6)
    v = saturate(v * 1.5, 1.5)
    v *= env_points(dur, [(0, 0), (0.05, 1.0), (dur * 0.7, 0.8), (dur, 0)])
    return normalize(fade(reverb_mono(v, 0.15, 0.8, seed)), 0.85)


def alert_shout(seed):
    r = rng(seed)
    dur = r.uniform(0.45, 0.6)
    f0 = env_points(dur, [(0, r.uniform(170, 200)), (dur * 0.3, r.uniform(230, 260)), (dur, r.uniform(150, 170))])
    v = voice(["e", "a", "o"][seed % 3], f0, dur, 0.2, seed, rough=0.5)
    v = saturate(v * 1.4, 1.6)
    v *= env_points(dur, [(0, 0), (0.02, 1.0), (dur * 0.6, 0.9), (dur, 0)])
    return normalize(fade(reverb_mono(v, 0.12, 0.7, seed)), 0.85)


def huh(seed):
    r = rng(seed)
    dur = 0.4
    f0 = glide(r.uniform(120, 140), r.uniform(190, 220), dur, 2.0)
    v = voice("m", f0, dur, 0.1, seed) * 0.6 + voice("uh", f0, dur, 0.1, seed) * 0.4
    v *= env_points(dur, [(0, 0), (0.04, 1.0), (0.3, 0.8), (dur, 0)])
    return normalize(fade(v), 0.7)


def body_fall(seed):
    r = rng(seed)
    dur = 0.9
    t = t_axis(dur)
    thud = sine(exp_glide(r.uniform(70, 90), 35, dur), dur) * np.exp(-t / 0.12)
    dirt = lowpass(white(dur, seed), 500) * np.exp(-t / 0.08)
    rattle = np.zeros(int(dur * SR))
    for k in range(10):
        at = r.uniform(0.0, 0.25)
        c = modal(0.12, [(r.uniform(1800, 4200), 1.0, 0.03), (r.uniform(4000, 7000), 0.5, 0.02)], seed + k)
        place(rattle, c * r.uniform(0.05, 0.2), at)
    second = sine(exp_glide(80, 40, 0.4), 0.4) * np.exp(-t_axis(0.4) / 0.08) * 0.5
    y = mix(thud, dirt * 0.6, rattle)
    place(y, second, r.uniform(0.18, 0.3))
    return normalize(fade(y, 0.001, 0.1), 0.85)


def land(seed):
    dur = 0.45
    t = t_axis(dur)
    y = sine(exp_glide(90, 40, dur), dur) * np.exp(-t / 0.07) + lowpass(white(dur, seed), 700) * np.exp(-t / 0.05) * 0.8
    return normalize(fade(y), 0.7)


def step(seed):
    r = rng(seed)
    dur = 0.22
    t = t_axis(dur)
    grass = bandpass(white(dur, seed), r.uniform(1500, 2500), r.uniform(5000, 8000)) * np.exp(-t / 0.05) * 0.5
    thud = lowpass(white(dur, seed + 1), 300) * np.exp(-t / 0.03)
    y = grass + thud
    return normalize(fade(y), 0.5)


def jump(seed):
    dur = 0.35
    y = whoosh(dur, 300, 1200, 400, seed, q=1.5) * 0.6
    t = t_axis(dur)
    breath = bandpass(white(dur, seed + 1), 600, 2500) * env_points(dur, [(0, 0), (0.03, 0.6), (0.2, 0)])
    return normalize(fade(y + breath * 0.5), 0.6)


def roll(seed):
    dur = 0.6
    t = t_axis(dur)
    cloth = bandpass(pink(dur, seed), 400, 3000) * env_points(dur, [(0, 0), (0.08, 1.0), (0.45, 0.6), (dur, 0)])
    dirt = lowpass(white(dur, seed + 1), 900) * env_points(dur, [(0, 0), (0.15, 0.8), (0.5, 0.3), (dur, 0)])
    thud = sine(exp_glide(90, 45, 0.3), 0.3) * np.exp(-t_axis(0.3) / 0.06)
    y = mix(cloth * 0.7, dirt * 0.6)
    place(y, thud * 0.6, 0.12)
    return normalize(fade(y), 0.6)


def sword_draw(seed):
    r = rng(seed)
    dur = 0.9
    t = t_axis(dur)
    slide = sweep_filter(white(dur, seed), exp_glide(2500, 7000, dur), 6.0) * env_points(dur, [(0, 0), (0.05, 0.6), (0.3, 1.0), (0.36, 0.0), (dur, 0)])
    ring = modal(dur, [(r.uniform(3200, 3800), 1.0, 0.5), (r.uniform(5200, 6000), 0.6, 0.35), (r.uniform(7800, 8600), 0.3, 0.2)], seed)
    ring *= np.clip((t - 0.3) / 0.01, 0, 1)
    click = _strike(dur, seed + 2, 2000, 8000, 0.003)
    y = mix(slide * 0.7, ring * 0.35, click * 0.5)
    y = reverb_mono(y, 0.15, 0.8, seed)[: int(1.1 * SR)]
    return normalize(fade(y, 0.001, 0.15), 0.72)


def sword_sheathe(seed):
    dur = 0.9
    t = t_axis(dur)
    slide = sweep_filter(white(dur, seed), exp_glide(6000, 2000, dur), 5.0) * env_points(dur, [(0, 0), (0.05, 0.8), (0.6, 0.5), (0.66, 0), (dur, 0)])
    clack = woodblock(1300, 0.25, seed) * 0.8
    y = mix(slide * 0.5)
    place(y, clack, 0.64)
    place(y, _strike(0.1, seed + 3, 3000, 9000, 0.004) * 0.4, 0.645)
    return normalize(fade(y, 0.001, 0.1), 0.75)


def charge(seed):
    dur = 1.0
    t = t_axis(dur)
    y = sweep_filter(white(dur, seed), exp_glide(300, 3000, dur), 5.0) * env_points(dur, [(0, 0), (0.7, 0.8), (dur, 0.2)])
    hum = sine(exp_glide(90, 180, dur), dur) * env_points(dur, [(0, 0), (0.6, 0.4), (dur, 0.1)])
    return normalize(fade(y + hum), 0.7)


def charged(seed):
    """A heavy strike reaching full charge: a rising shimmer that lands in a bright bell 'shing'."""
    dur = 1.0
    rise = sweep_filter(white(0.18, seed), exp_glide(1800, 9000, 0.18), 4.0) * env_points(0.18, [(0, 0), (0.16, 1.0), (0.18, 0)])
    bell = modal(0.8, [(1760, 1.0, 0.55), (2637, 0.6, 0.45), (3520, 0.45, 0.35), (5274, 0.25, 0.25)], seed)
    thump = sine(exp_glide(150, 55, 0.3), 0.3) * np.exp(-t_axis(0.3) / 0.09)
    y = np.zeros(int(dur * SR))
    y = place(y, rise * 0.7, 0.0)
    y = place(y, bell * 0.6, 0.16)
    y = place(y, thump * 0.8, 0.16)
    y = place(y, _strike(0.2, seed + 1, 3000, 14000, 0.004) * 0.9, 0.16)
    y = reverb_mono(y, 0.25, 1.0, seed)[: int(1.1 * SR)]
    return normalize(fade(y, 0.001, 0.25), 0.8)


def glint(seed):
    """Red glint: the telegraphed unblockable (a sharp 'ting' with shimmer)."""
    dur = 1.0
    t = t_axis(dur)
    y = modal(dur, [(4200, 1.0, 0.25), (6300, 0.6, 0.2), (8400, 0.4, 0.15), (2100, 0.3, 0.3)], seed)
    y *= 1 + 0.3 * np.sin(2 * np.pi * 14 * t)
    y += _strike(dur, seed, 5000, 15000, 0.002)
    y = reverb_mono(y, 0.3, 1.0, seed)[: int(1.3 * SR)]
    return normalize(fade(y, 0.001, 0.2), 0.8)


def perfect(seed):
    dur = 1.6
    t = t_axis(dur)
    whoom = sine(exp_glide(120, 40, dur), dur) * env_points(dur, [(0, 0), (0.05, 1.0), (dur, 0)])
    swell = sweep_filter(white(dur, seed), exp_glide(8000, 800, dur), 3.0) * env_points(dur, [(0, 0.8), (dur, 0)])
    bell = modal(dur, [(880, 0.6, 0.9), (1320, 0.4, 0.7), (2217, 0.3, 0.5)], seed)
    y = mix(whoom * 0.8, swell * 0.3, bell * 0.4)
    y = reverb_mono(y, 0.35, 2.0, seed)[: int(2.2 * SR)]
    return normalize(fade(y, 0.001, 0.3), 0.85)


def chime(freqs, dur, seed, decay=1.2):
    return modal(dur, [(f, 1.0 / (i + 1) ** 0.6, decay * (1.0 - i * 0.12)) for i, f in enumerate(freqs)], seed)


def resolve(seed):
    y = chime([659.3, 987.8, 1318.5, 1975.5], 2.0, seed, 1.0) * 0.6
    y = reverb_mono(y, 0.4, 2.0, seed)[: int(2.4 * SR)]
    return normalize(fade(y, 0.002, 0.3), 0.7)


def heal(seed):
    dur = 1.4
    breath = bandpass(white(dur, seed), 300, 1600) * env_points(dur, [(0, 0), (0.3, 0.4), (0.9, 0.2), (dur, 0)])
    y = chime([523.3, 784.0, 1046.5], dur, seed, 0.9) * 0.4 + breath * 0.5
    y = reverb_mono(y, 0.3, 1.6, seed)[: int(1.8 * SR)]
    return normalize(fade(y, 0.01, 0.3), 0.6)


def shrine_bell(seed):
    """Temple bell (bonsho): low inharmonic partials with slow beating."""
    dur = 7.0
    t = t_axis(dur)
    f = 98.0
    parts = [(f * q, a, d) for q, a, d in [(0.5, 0.5, 6.0), (1.0, 1.0, 5.0), (1.004, 0.8, 5.0), (2.0, 0.6, 3.5),
                                            (2.44, 0.5, 3.0), (3.0, 0.35, 2.5), (4.18, 0.3, 1.8), (5.43, 0.25, 1.2)]]
    y = modal(dur, parts, seed)
    # the wooden beam (shumoku) striking the bronze
    thud = sine(exp_glide(90, 60, 0.3), 0.3) * np.exp(-t_axis(0.3) / 0.06)
    place(y, thud * 0.8, 0.0)
    y += lowpass(white(dur, seed), 300) * np.exp(-t / 0.05) * 0.6
    y = reverb_mono(y, 0.25, 3.0, seed)[: int(7.5 * SR)]
    return normalize(fade(y, 0.002, 1.0), 0.8)


def banner(seed):
    y = taiko(62.0, 1.8, seed, 0.6)
    swish = bandpass(pink(0.5, seed), 800, 5000) * env_points(0.5, [(0, 0), (0.15, 0.6), (0.5, 0)])
    out = mix(y)
    place(out, swish * 0.4, 0.05)
    out = reverb_mono(out, 0.25, 1.8, seed)[: int(2.2 * SR)]
    return normalize(fade(out, 0.001, 0.3), 0.85)


def victory_sting(seed):
    """Taiko hit + rising shakuhachi phrase (miyako-bushi)."""
    dur = 4.0
    out = np.zeros(int(dur * SR))
    place(out, taiko(58, 2.0, seed, 0.7), 0.0)
    place(out, taiko(58, 2.0, seed + 1, 0.5) * 0.7, 0.42)
    notes = [(293.7, 0.35, 0.5), (311.1, 0.9, 0.4), (392.0, 1.3, 0.5), (440.0, 1.8, 1.8)]
    for f, at, d in notes:
        place(out, flute(f, d + 0.3, seed + int(f)) * 0.5, at)
    place(out, karplus(146.8, 2.0, 0.998, 0.6, seed) * 0.4, 1.8)
    out = reverb_mono(out, 0.35, 2.5, seed)[: int(4.5 * SR)]
    return normalize(fade(out, 0.001, 0.6), 0.85)


def ui_move(seed):
    return normalize(fade(woodblock(1500, 0.12, seed)), 0.4)


def ui_select(seed):
    y = karplus(587.3, 0.8, 0.994, 0.7, seed) + karplus(880.0, 0.8, 0.994, 0.7, seed + 1) * 0.5
    return normalize(fade(y, 0.001, 0.2), 0.5)


def map_open(seed):
    dur = 0.7
    y = bandpass(pink(dur, seed), 1200, 7000) * env_points(dur, [(0, 0), (0.05, 0.9), (0.25, 0.4), (0.4, 0.7), (dur, 0)])
    y *= 1 + 0.6 * rng(seed).standard_normal(len(y)).clip(-1, 1)
    return normalize(fade(y, 0.002, 0.1), 0.5)


def guiding_wind(seed):
    dur = 3.0
    t = t_axis(dur)
    gust = sweep_filter(pink(dur, seed), 400 + 1200 * np.sin(np.pi * t / dur) ** 2, 1.2) * env_points(dur, [(0, 0), (0.9, 1.0), (2.2, 0.7), (dur, 0)])
    breath = flute(587.3, 2.2, seed, breath=0.5) * 0.25
    out = mix(gust)
    place(out, breath, 0.6)
    out = reverb_mono(out, 0.3, 2.0, seed)[: int(3.4 * SR)]
    return normalize(fade(out, 0.01, 0.4), 0.7)


def blood_splat(seed):
    r = rng(seed)
    dur = 0.5
    y = np.zeros(int(dur * SR))
    for k in range(10):
        d = r.uniform(0.02, 0.05)
        drop = bandpass(white(d, seed + k), 300, 2200) * np.exp(-t_axis(d) / (d * 0.3))
        place(y, drop * r.uniform(0.3, 1.0), r.uniform(0, 0.3))
    return normalize(fade(y), 0.5)


def thunder(seed):
    r = rng(seed)
    dur = 6.0
    t = t_axis(dur)
    crack = saturate(bandpass(white(dur, seed), 300, 5000) * np.exp(-t / 0.08), 3.0) * 0.6
    rumble = lowpass(brown(dur, seed + 1), 160) * env_points(dur, [(0, 0), (0.1, 1.0), (1.5, 0.7), (dur, 0)])
    rolls = np.zeros(len(t))
    for k in range(6):
        at = r.uniform(0.3, 3.5)
        d = r.uniform(0.8, 1.8)
        roll_ = lowpass(brown(d, seed + 10 + k), 220) * env_points(d, [(0, 0), (d * 0.3, 1.0), (d, 0)])
        place(rolls, roll_ * r.uniform(0.3, 0.7), at)
    y = mix(crack, rumble * 1.2, rolls)
    y = reverb_mono(y, 0.3, 3.0, seed)[: int(7 * SR)]
    return normalize(fade(y, 0.002, 1.0), 0.9)


def boing(seed):
    """Cartoon spring: a sine whose pitch wobbles down as it decays."""
    r = rng(seed)
    dur = 0.9
    t = t_axis(dur)
    base = r.uniform(180, 240)
    f = base * (1.0 + 1.1 * np.exp(-t / 0.35) * np.sin(2 * np.pi * (9.0 + 4.0 * np.exp(-t / 0.4)) * t + 0.6) * 0.5 + 0.8 * np.exp(-t / 0.18))
    y = sine(f, dur) + 0.35 * sine(f * 2.01, dur) + 0.12 * sine(f * 3.0, dur)
    y *= np.exp(-t / 0.32) * np.clip(t / 0.004, 0, 1)
    return normalize(fade(y, 0.001, 0.15), 0.7)


def squish(seed):
    r = rng(seed)
    dur = 0.5
    t = t_axis(dur)
    n = lowpass(white(dur, seed), 1400)
    wob = 0.6 + 0.4 * np.sin(2 * np.pi * r.uniform(14, 22) * t)
    y = n * wob * env_points(dur, [(0, 0), (0.02, 1.0), (0.2, 0.5), (dur, 0)])
    y += sine(exp_glide(220, 70, dur), dur) * np.exp(-t / 0.08) * 0.5
    return normalize(fade(y, 0.001, 0.1), 0.75)


def pop(seed):
    dur = 0.18
    t = t_axis(dur)
    y = sine(exp_glide(900, 120, dur), dur) * np.exp(-t / 0.03)
    y += _strike(dur, seed, 800, 5000, 0.004) * 0.6
    return normalize(fade(y, 0.0005, 0.05), 0.7)


def peril(seed):
    """Warning of a perilous attack: a sharp two-tone sting over a low pulse."""
    dur = 0.9
    t = t_axis(dur)
    y = sine(exp_glide(1480, 1330, dur), dur) * np.exp(-t / 0.35) * 0.55
    y += sine(exp_glide(990, 880, dur), dur) * np.exp(-t / 0.4) * 0.4
    y += saturate(sine(exp_glide(90, 55, dur), dur) * np.exp(-t / 0.25), 2.0) * 0.6
    y += _strike(dur, seed, 2500, 12000, 0.006) * 0.7
    y = reverb_mono(y, 0.25, 1.2, seed)[: int(1.2 * SR)]
    return normalize(fade(y, 0.001, 0.2), 0.85)


def issen(seed):
    """Onimusha-style flash: rising shimmer, a heavy thud, and a cut."""
    dur = 1.6
    t = t_axis(dur)
    rise = sweep_filter(white(dur, seed), exp_glide(300, 9000, dur * 0.25).tolist() + [9000.0] * (int(dur * SR) - int(dur * 0.25 * SR)), 5.0)
    rise = np.asarray(rise) * env_points(dur, [(0, 0), (0.25, 1.0), (0.3, 0.0), (dur, 0.0)])
    thud = sine(exp_glide(140, 38, dur), dur) * np.exp(-t / 0.3) * np.clip((t - 0.25) / 0.005, 0, 1)
    cut = _strike(dur, seed + 1, 1500, 14000, 0.02) * np.clip((t - 0.25) / 0.002, 0, 1)
    ring = modal(dur, [(1760, 0.6, 0.9), (2637, 0.4, 0.7), (3520, 0.25, 0.5)], seed) * np.clip((t - 0.28) / 0.003, 0, 1)
    y = mix(rise * 0.5, thud * 1.1, cut * 0.9, ring * 0.35)
    y = reverb_mono(y, 0.3, 2.0, seed)[: int(2.0 * SR)]
    return normalize(fade(y, 0.001, 0.4), 0.95)


def soul(seed):
    dur = 0.6
    t = t_axis(dur)
    y = sine(exp_glide(700, 1500, dur), dur) * env_points(dur, [(0, 0), (0.05, 1.0), (dur, 0)])
    y += sine(exp_glide(1400, 3000, dur), dur) * 0.3 * env_points(dur, [(0, 0), (0.05, 1.0), (dur, 0)])
    return normalize(fade(y, 0.002, 0.15), 0.5)


def deathblow(seed):
    dur = 2.0
    t = t_axis(dur)
    thud = sine(exp_glide(120, 36, dur), dur) * np.exp(-t / 0.35)
    slash = _strike(dur, seed, 800, 12000, 0.03)
    gong = modal(dur, [(196, 1.0, 1.6), (392, 0.5, 1.2), (588, 0.3, 0.9), (833, 0.2, 0.6)], seed)
    flesh = lowpass(white(dur, seed + 2), 900) * np.exp(-t / 0.2)
    y = mix(thud * 1.2, slash * 0.9, gong * 0.45, flesh * 0.7)
    y = reverb_mono(y, 0.3, 2.2, seed)[: int(2.4 * SR)]
    return normalize(fade(y, 0.001, 0.4), 0.95)


# name -> (generator, variations)
SFX = {
    "swing": (swing, 5), "swing_heavy": (swing_heavy, 3), "clash": (clash, 4), "parry": (parry, 3),
    "guard_break": (guard_break, 2), "flesh_cut": (flesh_cut, 5), "dismember": (dismember, 3),
    "death_grunt": (death_grunt, 5), "scream": (scream, 3), "alert_shout": (alert_shout, 3), "huh": (huh, 3),
    "body_fall": (body_fall, 3), "land": (land, 2), "step": (step, 6), "jump": (jump, 2), "roll": (roll, 2),
    "sword_draw": (sword_draw, 2), "sword_sheathe": (sword_sheathe, 2), "charge": (charge, 1), "charged": (charged, 1), "glint": (glint, 1),
    "perfect": (perfect, 1), "resolve": (resolve, 1), "heal": (heal, 1), "shrine_bell": (shrine_bell, 1),
    "banner": (banner, 1), "victory_sting": (victory_sting, 1), "ui_move": (ui_move, 1), "ui_select": (ui_select, 1),
    "map_open": (map_open, 1), "guiding_wind": (guiding_wind, 1), "blood_splat": (blood_splat, 3),
    "thunder": (thunder, 2), "peril": (peril, 1), "issen": (issen, 1), "soul": (soul, 3), "deathblow": (deathblow, 1), "boing": (boing, 3), "squish": (squish, 3), "pop": (pop, 2),
}
