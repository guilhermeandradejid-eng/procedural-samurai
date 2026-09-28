"""UI textures: parchment, ink brush strokes, ensō, map icons."""
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from texlib import directional_noise, fft_noise, ramp, rng, smoothstep


def _save(arr, path, mode="RGBA"):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), mode).save(path, optimize=True)


def parchment(size=1024):
    n1 = fft_noise(size, 2.0, 1)
    n2 = fft_noise(size, 1.4, 2)
    fib = directional_noise(size, 150, 20, stretch=6, seed=3)
    col = ramp(n1 * 0.5 + fib * 0.3 + n2 * 0.2, [(0.0, (0.78, 0.7, 0.54)), (0.5, (0.88, 0.82, 0.67)), (1.0, (0.94, 0.9, 0.78))])
    stains = smoothstep(0.62, 0.9, fft_noise(size, 1.8, 4))
    col = col * (1 - stains[..., None] * 0.18)
    yy, xx = np.mgrid[0:size, 0:size] / size - 0.5
    vig = smoothstep(0.35, 0.72, np.maximum(np.abs(xx), np.abs(yy)) + (n2 - 0.5) * 0.08)
    col = col * (1 - vig[..., None] * 0.35)
    return col


def brush_stroke(w=1024, h=160, seed=5, dry_end=True):
    r = rng(seed)
    yy, xx = np.mgrid[0:h, 0:w]
    u = xx / w
    v = (yy / h - 0.5) * 2.0
    # thickness profile: round start, slight belly, tapering dry end
    prof = smoothstep(0.0, 0.06, u) * (0.82 + 0.18 * np.sin(u * math.pi)) * (1 - smoothstep(0.82, 1.0, u) * 0.55)
    edge_noise = directional_noise(512, 30, 0, stretch=8, seed=seed)
    edge_noise = np.asarray(Image.fromarray((edge_noise * 255).astype(np.uint8)).resize((w, h))).astype(np.float64) / 255.0
    top = prof * (0.85 + 0.25 * (edge_noise - 0.5))
    inside = smoothstep(top, top - 0.06, np.abs(v))
    bristles = directional_noise(512, 90, 0, stretch=30, seed=seed + 1)
    bristles = np.asarray(Image.fromarray((bristles * 255).astype(np.uint8)).resize((w, h))).astype(np.float64) / 255.0
    dry = smoothstep(0.55, 1.0, u) if dry_end else np.zeros_like(u)
    gaps = smoothstep(0.35 + 0.4 * (1 - dry), 0.55 + 0.4 * (1 - dry), bristles)
    a = inside * np.clip(1.0 - dry * (1.0 - gaps) * 1.2, 0, 1)
    a = a * (0.88 + 0.12 * bristles)
    return np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), np.clip(a, 0, 1)])


def enso(size=512, seed=8):
    yy, xx = np.mgrid[0:size, 0:size] / size - 0.5
    d = np.hypot(xx, yy)
    ang = (np.arctan2(yy, xx) + math.pi * 0.62) % math.tau / math.tau  # 0..1 along the stroke
    thick = 0.035 + 0.03 * np.sin(ang * math.pi) ** 0.8 * (1 - ang * 0.5)
    radius = 0.36 + 0.015 * np.sin(ang * 9)
    bristle = directional_noise(size, 80, 0, stretch=20, seed=seed)
    inside = smoothstep(thick, thick * 0.7, np.abs(d - radius))
    tail = smoothstep(0.97, 0.8, ang)
    dry = smoothstep(0.6, 1.0, ang)
    a = inside * tail * np.clip(1 - dry * (1 - smoothstep(0.4, 0.6, bristle)), 0, 1)
    return np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a])


def ink_splash(size=512, seed=12):
    r = rng(seed)
    img = Image.new("L", (size * 2, size * 2), 0)
    dr = ImageDraw.Draw(img)
    c = size
    pts = []
    for i in range(48):
        a = i / 48 * math.tau
        rr = size * 0.3 * (1 + 0.3 * math.sin(a * 5 + 1) + 0.2 * r.random())
        pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
    dr.polygon(pts, fill=255)
    for i in range(70):
        a = r.uniform(0, math.tau)
        d = size * r.uniform(0.35, 0.95)
        rad = size * r.uniform(0.005, 0.03)
        dr.ellipse([c + math.cos(a) * d - rad, c + math.sin(a) * d - rad, c + math.cos(a) * d + rad, c + math.sin(a) * d + rad], fill=255)
    a = np.asarray(img.resize((size, size), Image.LANCZOS)).astype(np.float64) / 255.0
    return np.dstack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a])


def icons(cell=128):
    names = ["shrine", "camp", "village", "onsen", "temple", "haiku", "landmark", "player"]
    ss = 4
    W = cell * len(names)
    img = Image.new("RGBA", (W * ss, cell * ss), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    white = (255, 255, 255, 255)
    for i, n in enumerate(names):
        ox = i * cell * ss
        s = cell * ss
        def P(x, y):
            return (ox + x * s, y * s)
        if n == "shrine":  # torii
            dr.polygon([P(0.1, 0.22), P(0.9, 0.22), P(0.95, 0.16), P(0.05, 0.16)], fill=white)
            dr.rectangle([P(0.16, 0.3), P(0.84, 0.36)], fill=white)
            dr.rectangle([P(0.24, 0.22), P(0.32, 0.9)], fill=white)
            dr.rectangle([P(0.68, 0.22), P(0.76, 0.9)], fill=white)
        elif n == "camp":  # crossed swords
            for sgn in (-1, 1):
                x0, x1 = (0.18, 0.82) if sgn > 0 else (0.82, 0.18)
                dr.line([P(x0, 0.85), P(x1, 0.15)], fill=white, width=int(s * 0.06))
                cxg = x0 + (x1 - x0) * 0.22
                dr.line([P(cxg - 0.08 * sgn, 0.72 - 0.06), P(cxg + 0.08 * sgn, 0.72 + 0.06)], fill=white, width=int(s * 0.05))
        elif n == "village":
            dr.polygon([P(0.08, 0.5), P(0.5, 0.18), P(0.92, 0.5)], fill=white)
            dr.rectangle([P(0.2, 0.5), P(0.8, 0.85)], fill=white)
            dr.rectangle([P(0.44, 0.62), P(0.56, 0.85)], fill=(0, 0, 0, 0))
        elif n == "onsen":
            dr.arc([P(0.15, 0.45), P(0.85, 0.95)], 0, 180, fill=white, width=int(s * 0.07))
            for k, x in enumerate((0.32, 0.5, 0.68)):
                pts = [P(x + 0.05 * math.sin(t * 6.28 + k), 0.62 - t * 0.45) for t in np.linspace(0, 1, 12)]
                dr.line(pts, fill=white, width=int(s * 0.05), joint="curve")
        elif n == "temple":
            for k in range(3):
                y = 0.25 + k * 0.22
                wdt = 0.28 + k * 0.1
                dr.polygon([P(0.5 - wdt, y + 0.08), P(0.5, y - 0.06), P(0.5 + wdt, y + 0.08)], fill=white)
                dr.rectangle([P(0.5 - wdt * 0.55, y + 0.08), P(0.5 + wdt * 0.55, y + 0.16)], fill=white)
            dr.line([P(0.5, 0.05), P(0.5, 0.22)], fill=white, width=int(s * 0.03))
        elif n == "haiku":
            dr.polygon([P(0.2, 0.85), P(0.72, 0.18), P(0.82, 0.26), P(0.3, 0.92)], fill=white)
            dr.polygon([P(0.14, 0.94), P(0.2, 0.85), P(0.3, 0.92)], fill=white)
        elif n == "landmark":
            dr.rectangle([P(0.45, 0.55), P(0.55, 0.92)], fill=white)
            dr.ellipse([P(0.14, 0.1), P(0.86, 0.66)], fill=white)
        elif n == "player":
            dr.polygon([P(0.5, 0.08), P(0.85, 0.9), P(0.5, 0.7), P(0.15, 0.9)], fill=white)
    return np.asarray(img.resize((W, cell), Image.LANCZOS)).astype(np.float64) / 255.0


def generate(out_dir, pool=None):
    os.makedirs(out_dir, exist_ok=True)
    Image.fromarray((np.clip(parchment(), 0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(out_dir, "parchment.jpg"), quality=90)
    _save(brush_stroke(), os.path.join(out_dir, "brush_stroke.png"))
    _save(brush_stroke(1024, 160, 21, dry_end=False), os.path.join(out_dir, "brush_fill.png"))
    _save(enso(), os.path.join(out_dir, "enso.png"))
    _save(ink_splash(), os.path.join(out_dir, "ink_splash.png"))
    _save(icons(), os.path.join(out_dir, "icons.png"))
    print("  ui textures done")
