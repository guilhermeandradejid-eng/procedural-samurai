"""Effect textures: blood decals, particles, flesh caps, trails, water foam."""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

from texlib import fft_noise, height_to_normal, leaf_shape, ramp, rng, smoothstep, transform


def _save(arr, path, mode="RGBA"):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), mode).save(path, optimize=True)


def blood_splat(seed, size=512):
    r = rng(seed)
    ss = 2
    W = size * ss
    img = Image.new("L", (W, W), 0)
    dr = ImageDraw.Draw(img)
    cx, cy = W * 0.5, W * 0.5
    direction = r.uniform(0, math.tau)
    # main irregular blob
    pts = []
    base_r = W * r.uniform(0.13, 0.2)
    for i in range(64):
        a = i / 64 * math.tau
        wob = 1.0 + 0.25 * math.sin(a * 3 + r.uniform(0, 6)) + 0.15 * math.sin(a * 7 + r.uniform(0, 6))
        stretch = 1.0 + 0.6 * max(0.0, math.cos(a - direction))
        rr = base_r * wob * stretch
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    dr.polygon(pts, fill=255)
    # streaks & droplets thrown along the direction
    for i in range(r.integers(18, 34)):
        a = direction + r.normal(0, 0.45)
        d = base_r * r.uniform(0.9, 2.6)
        px = cx + math.cos(a) * d
        py = cy + math.sin(a) * d
        rad = W * r.uniform(0.006, 0.03) * (1.4 - d / (base_r * 2.6))
        L = rad * r.uniform(1.0, 3.5)
        ex = px + math.cos(a) * L
        ey = py + math.sin(a) * L
        dr.line([(cx + math.cos(a) * base_r * 0.8, cy + math.sin(a) * base_r * 0.8), (px, py)], fill=255, width=max(1, int(rad * 0.7)))
        dr.ellipse([ex - rad, ey - rad, ex + rad, ey + rad], fill=255)
    for i in range(r.integers(40, 90)):
        a = r.uniform(0, math.tau)
        d = base_r * r.uniform(1.1, 3.4)
        px = cx + math.cos(a) * d
        py = cy + math.sin(a) * d
        rad = W * r.uniform(0.002, 0.009)
        dr.ellipse([px - rad, py - rad, px + rad, py + rad], fill=255)
    mask = np.asarray(img.resize((size, size), Image.LANCZOS)).astype(np.float64) / 255.0
    thick = ndimage.gaussian_filter(mask, 6)
    n = fft_noise(size, 2.2, seed)
    col = ramp(thick * 0.7 + n * 0.3, [(0.0, (0.42, 0.03, 0.02)), (0.5, (0.33, 0.02, 0.02)), (1.0, (0.2, 0.01, 0.01))])
    alpha = smoothstep(0.35, 0.6, mask)
    rgba = np.dstack([col, alpha])
    nrm = height_to_normal(ndimage.gaussian_filter(mask, 2.5) * 12.0, 1.0)
    return rgba, nrm


def blood_pool(seed, size=256):
    r = rng(seed)
    yy, xx = np.mgrid[0:size, 0:size] / size - 0.5
    a = np.arctan2(yy, xx)
    d = np.hypot(xx, yy)
    wob = 0.36 + 0.05 * np.sin(a * 3 + 1) + 0.04 * np.sin(a * 5 + 2) + 0.03 * np.sin(a * 9)
    mask = smoothstep(wob, wob - 0.03, d)
    n = fft_noise(size, 2.2, seed)
    col = ramp(n, [(0.0, (0.25, 0.01, 0.01)), (1.0, (0.38, 0.02, 0.02))])
    return np.dstack([col, mask])


def drop(size=64):
    yy, xx = np.mgrid[0:size, 0:size] / size - 0.5
    d = np.hypot(xx, yy * 0.9)
    a = smoothstep(0.48, 0.3, d)
    hl = smoothstep(0.12, 0.0, np.hypot(xx + 0.12, yy + 0.12))
    c = 0.75 + 0.25 * hl
    return np.dstack([c, c, c, a])


def soft_puff(seed, size=128):
    yy, xx = np.mgrid[0:size, 0:size] / size - 0.5
    d = np.hypot(xx, yy)
    n = fft_noise(size, 2.0, seed)
    a = smoothstep(0.5, 0.05, d + (n - 0.5) * 0.25)
    return np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a ** 1.4])


def spark(size=64):
    yy, xx = np.mgrid[0:size, 0:size] / size - 0.5
    core = np.exp(-(xx * xx * 18 + yy * yy * 800))
    glow = np.exp(-(xx * xx * 6 + yy * yy * 120)) * 0.5
    a = np.clip(core + glow, 0, 1)
    return np.dstack([np.ones_like(a), np.ones_like(a) * 0.9, np.ones_like(a) * 0.7, a])


def leaves_atlas(size=256):
    half = size // 2
    ss = 4
    img = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    specs = [("maple", (176, 30, 20), 7), ("maple", (214, 96, 26), 5), ("ginkgo", (232, 186, 50), 0), ("sakura", (246, 196, 210), 0)]
    for i, (kind, col, lobes) in enumerate(specs):
        ox = (i % 2) * half + half / 2
        oy = (i // 2) * half + half / 2
        shape = leaf_shape(kind, 1.0, lobes or 5) if kind != "sakura" else leaf_shape("lance", 1.0)
        if kind == "sakura":
            # single petal: short wide lance
            shape = [(x * 2.6, y * 0.7 + 0.35) for x, y in leaf_shape("lance", 1.0)]
        scale = half * 0.42
        pts = transform(shape, ox, oy + scale * 0.5, 0.0, scale)
        dr.polygon([(x * ss, y * ss) for x, y in pts], fill=col + (255,))
        light = tuple(min(255, int(c * 1.2)) for c in col) + (255,)
        pts2 = transform(shape, ox, oy + scale * 0.35, 0.0, scale * 0.7)
        dr.polygon([(x * ss, y * ss) for x, y in pts2], fill=light)
    return np.asarray(img.resize((size, size), Image.LANCZOS)).astype(np.float64) / 255.0


def flesh_cap(size=256):
    yy, xx = np.mgrid[0:size, 0:size] / size - 0.5
    d = np.hypot(xx, yy) * 2.0
    n = fft_noise(size, 2.0, 7)
    meat = ramp(n, [(0.0, (0.45, 0.04, 0.04)), (0.5, (0.62, 0.1, 0.08)), (1.0, (0.72, 0.18, 0.14))])
    fibers = 0.5 + 0.5 * np.sin(np.arctan2(yy, xx) * 40 + n * 6)
    meat = meat * (0.85 + 0.15 * fibers[..., None])
    fat = smoothstep(0.78, 0.84, d) * smoothstep(0.98, 0.9, d)
    col = meat * (1 - fat[..., None]) + np.array([0.86, 0.72, 0.52]) * fat[..., None]
    skin = smoothstep(0.9, 0.95, d)
    col = col * (1 - skin[..., None]) + np.array([0.9, 0.8, 0.72]) * skin[..., None]
    bone = smoothstep(0.24, 0.2, np.hypot(xx - 0.04, yy + 0.02) * 2.0)
    marrow = smoothstep(0.1, 0.07, np.hypot(xx - 0.04, yy + 0.02) * 2.0)
    col = col * (1 - bone[..., None]) + np.array([0.93, 0.9, 0.82]) * bone[..., None]
    col = col * (1 - marrow[..., None]) + np.array([0.55, 0.12, 0.1]) * marrow[..., None]
    alpha = smoothstep(1.0, 0.97, d)
    return np.dstack([col, alpha])


def slash_trail(w=512, h=64):
    yy, xx = np.mgrid[0:h, 0:w]
    u = xx / w
    v = yy / h - 0.5
    core = np.exp(-(v * v) * 140.0)
    edge = np.exp(-(v * v) * 18.0) * 0.4
    fade = u ** 1.6
    streaks = 0.75 + 0.25 * np.sin(v * 90 + u * 3)
    a = np.clip((core + edge) * fade * streaks, 0, 1)
    return np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a])


def rain_streak(w=16, h=128):
    yy, xx = np.mgrid[0:h, 0:w]
    u = xx / w - 0.5
    v = yy / h
    a = np.exp(-u * u * 60) * smoothstep(0.0, 0.3, v) * smoothstep(1.0, 0.6, v) * 0.8
    return np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a])


def ripple(size=128):
    yy, xx = np.mgrid[0:size, 0:size] / size - 0.5
    d = np.hypot(xx, yy) * 2.0
    ring = np.exp(-((d - 0.8) ** 2) * 200) + np.exp(-((d - 0.55) ** 2) * 300) * 0.5
    return np.dstack([np.ones_like(d), np.ones_like(d), np.ones_like(d), np.clip(ring, 0, 1)])


def foam(size=256):
    n1 = fft_noise(size, 1.6, 3)
    n2 = fft_noise(size, 2.4, 4)
    cells = smoothstep(0.55, 0.65, n1) * (0.6 + 0.4 * n2)
    bubbles = (rng(5).random((size, size)) > 0.985).astype(np.float64)
    bubbles = ndimage.maximum_filter(bubbles, 2, mode="wrap") * 0.8
    a = np.clip(cells + bubbles * smoothstep(0.4, 0.6, n1), 0, 1)
    return np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a])


def generate(out_dir, pool=None):
    os.makedirs(out_dir, exist_ok=True)
    for i in range(4):
        rgba, nrm = blood_splat(900 + i)
        _save(rgba, os.path.join(out_dir, "blood_splat_%d.png" % i))
        _save(nrm, os.path.join(out_dir, "blood_splat_%d_n.png" % i), "RGB")
    _save(blood_pool(950), os.path.join(out_dir, "blood_pool.png"))
    _save(drop(), os.path.join(out_dir, "drop.png"))
    _save(soft_puff(960), os.path.join(out_dir, "smoke.png"))
    _save(spark(), os.path.join(out_dir, "spark.png"))
    _save(leaves_atlas(), os.path.join(out_dir, "leaves_atlas.png"))
    _save(flesh_cap(), os.path.join(out_dir, "flesh_cap.png"))
    _save(slash_trail(), os.path.join(out_dir, "slash_trail.png"))
    _save(rain_streak(), os.path.join(out_dir, "rain_streak.png"))
    _save(ripple(), os.path.join(out_dir, "ripple.png"))
    _save(foam(), os.path.join(out_dir, "foam.png"))
    print("  fx textures done")
