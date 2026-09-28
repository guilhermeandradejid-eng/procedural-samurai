"""Terrain material layers -> two Texture2DArray atlases.

terrain_albedo.jpg : RGB albedo (AO baked in), N slices of ALB x ALB side by side
terrain_nrh.png    : R,G normal xy | B roughness | A height, N slices of NRM x NRM
"""
import math
import os

import numpy as np
from PIL import Image
from scipy import ndimage

from texlib import (WrapCanvas, ambient_occlusion, band_noise, directional_noise, fft_noise, height_to_normal,
                    leaf_shape, mix, ramp, rng, smoothstep, transform, voronoi)

ALB = 1024
NRM = 512

LAYERS = ["grass", "dry_grass", "dirt", "forest_floor", "rock", "sand", "snow", "scree"]


def _strokes(canvas, r, count, length, width, colors, angle_center=None, angle_spread=math.pi, curve=0.25):
    S = canvas.size
    for _ in range(count):
        x = r.uniform(0, S)
        y = r.uniform(0, S)
        L = r.uniform(*length)
        a = r.uniform(-math.pi, math.pi) if angle_center is None else angle_center + r.uniform(-angle_spread, angle_spread)
        bend = r.uniform(-curve, curve)
        pts = []
        for k in range(5):
            t = k / 4
            aa = a + bend * t
            pts.append((x + math.cos(aa) * L * t, y + math.sin(aa) * L * t))
        c = colors[r.integers(0, len(colors))]
        jitter = r.uniform(0.85, 1.12)
        col = tuple(int(min(255, v * jitter)) for v in c[:3]) + (c[3] if len(c) > 3 else 255,)
        canvas.line(pts, col, width=r.uniform(*width))


def layer_grass(seed):
    r = rng(seed)
    n1 = fft_noise(ALB, 2.3, seed)
    n2 = band_noise(ALB, 90, seed + 1)
    soil = ramp(n1 * 0.7 + n2 * 0.3, [(0.0, (0.13, 0.11, 0.06)), (0.5, (0.22, 0.2, 0.09)), (1.0, (0.3, 0.3, 0.12))])
    cv = WrapCanvas(ALB, ss=2)
    greens = [(70, 104, 34), (88, 122, 40), (104, 132, 46), (60, 92, 30), (122, 140, 58), (96, 110, 38)]
    _strokes(cv, r, 14000, (6, 20), (0.8, 1.8), greens, curve=0.5)
    _strokes(cv, r, 3000, (4, 12), (0.8, 1.4), [(140, 150, 70), (150, 138, 70)], curve=0.4)
    top = cv.result()
    alpha = top[..., 3]
    col = mix(soil, top[..., :3], alpha)
    moss = smoothstep(0.55, 0.75, fft_noise(ALB, 2.6, seed + 3))
    col = mix(col, col * np.array([0.8, 1.05, 0.7]), moss * 0.5)
    h = n1 * 0.35 + n2 * 0.15 + alpha * 0.5
    rough = 0.88 + 0.08 * n2
    return col, rough, h


def layer_dry_grass(seed):
    r = rng(seed)
    n1 = fft_noise(ALB, 2.2, seed)
    soil = ramp(n1, [(0.0, (0.24, 0.18, 0.1)), (1.0, (0.4, 0.31, 0.18))])
    cv = WrapCanvas(ALB, ss=2)
    straw = [(196, 160, 92), (178, 140, 76), (210, 180, 110), (150, 116, 60), (224, 196, 130), (170, 128, 70)]
    _strokes(cv, r, 9000, (14, 40), (1.0, 2.4), straw, angle_center=0.4, angle_spread=0.9, curve=0.3)
    _strokes(cv, r, 4000, (8, 22), (0.8, 1.6), [(120, 110, 50), (140, 124, 58)], curve=0.5)
    top = cv.result()
    alpha = top[..., 3]
    col = mix(soil, top[..., :3], alpha)
    h = n1 * 0.3 + alpha * 0.6
    rough = 0.9 - 0.05 * alpha
    return col, rough, h


def _pebbles(size, n, seed, rmin, rmax):
    f1, f2, cid = voronoi(size, n, seed)
    r = rng(seed + 9)
    radii = r.uniform(rmin, rmax, n)
    rad = radii[cid]
    inside = np.clip(1.0 - f1 / rad, 0.0, 1.0)
    dome = np.sqrt(inside)
    tone = r.uniform(0, 1, n)[cid]
    return dome, tone, inside > 0.0


def layer_dirt(seed):
    n1 = fft_noise(ALB, 2.1, seed)
    n2 = band_noise(ALB, 40, seed + 1)
    base = ramp(n1 * 0.6 + n2 * 0.4, [(0.0, (0.26, 0.19, 0.12)), (0.5, (0.38, 0.29, 0.2)), (1.0, (0.47, 0.37, 0.26))])
    dome, tone, mask = _pebbles(ALB, 1400, seed + 2, 3.0, 9.0)
    stone_col = ramp(tone, [(0.0, (0.3, 0.28, 0.26)), (0.5, (0.45, 0.42, 0.38)), (1.0, (0.55, 0.5, 0.44))])
    stone_col = stone_col * (0.7 + 0.3 * dome[..., None])
    col = np.where(mask[..., None], stone_col, base)
    # soft ruts / tracks
    ruts = directional_noise(ALB, 6, 90, stretch=10, seed=seed + 4)
    col = col * (0.88 + 0.16 * ruts[..., None])
    h = n1 * 0.4 + dome * 0.5 + ruts * 0.1
    rough = 0.92 - 0.1 * dome
    return col, rough, h


def layer_forest_floor(seed):
    r = rng(seed)
    n1 = fft_noise(ALB, 2.2, seed)
    soil = ramp(n1, [(0.0, (0.09, 0.06, 0.04)), (1.0, (0.2, 0.13, 0.08))])
    cv = WrapCanvas(ALB, ss=2)
    leaf_cols = [(150, 34, 18), (176, 60, 22), (190, 110, 30), (120, 60, 28), (96, 44, 22), (200, 150, 40), (138, 28, 20)]
    shapes = [leaf_shape("maple", 1.0, 5), leaf_shape("maple", 1.0, 7), leaf_shape("ginkgo", 1.0), leaf_shape("birch", 1.3)]
    for i in range(2600):
        x, y = r.uniform(0, ALB, 2)
        s = r.uniform(9, 22)
        a = r.uniform(0, math.tau)
        shp = shapes[r.integers(0, len(shapes))]
        pts = transform(shp, x, y, a, s)
        shadow = transform(shp, x + 1.5, y + 2.0, a, s)
        cv.polygon(shadow, (10, 6, 4, 120))
        c = leaf_cols[r.integers(0, len(leaf_cols))]
        k = r.uniform(0.7, 1.1)
        cv.polygon(pts, (int(c[0] * k), int(c[1] * k), int(c[2] * k), 255))
    for i in range(500):
        x, y = r.uniform(0, ALB, 2)
        a = r.uniform(0, math.tau)
        L = r.uniform(20, 60)
        cv.line([(x, y), (x + math.cos(a) * L, y + math.sin(a) * L)], (54, 36, 22, 255), width=r.uniform(1.5, 3.0))
    top = cv.result()
    alpha = top[..., 3]
    col = mix(soil, top[..., :3], alpha)
    h = n1 * 0.4 + alpha * 0.4
    rough = 0.8 - 0.1 * alpha
    return col, rough, h


def layer_rock(seed):
    n1 = fft_noise(ALB, 2.5, seed)
    n2 = fft_noise(ALB, 1.8, seed + 1)
    f1, f2, cid = voronoi(ALB, 60, seed + 2)
    edge = f2 - f1
    cracks = smoothstep(6.0, 0.0, edge)
    f1b, f2b, _ = voronoi(ALB, 300, seed + 3)
    cracks2 = smoothstep(3.0, 0.0, f2b - f1b) * 0.5
    yy = np.arange(ALB)[:, None] / ALB
    strata = 0.5 + 0.5 * np.sin((yy * 18.0 + n2 * 2.5) * math.tau)
    crack_mask = smoothstep(0.35, 0.65, fft_noise(ALB, 1.6, seed + 7))
    cracks = cracks * crack_mask
    cracks2 = cracks2 * (1.0 - crack_mask * 0.5)
    h = n1 * 0.6 + strata * 0.2 + n2 * 0.3 - cracks * 0.25 - cracks2 * 0.12
    r = rng(seed)
    tone = r.uniform(0, 1, 60)[cid]
    base = ramp(n1 * 0.7 + tone * 0.3, [(0.0, (0.2, 0.19, 0.18)), (0.45, (0.33, 0.31, 0.29)), (0.8, (0.42, 0.39, 0.35)), (1.0, (0.5, 0.46, 0.41))])
    lichen = smoothstep(0.62, 0.72, fft_noise(ALB, 2.4, seed + 5)) * smoothstep(0.45, 0.6, h)
    col = mix(base, np.array([0.52, 0.52, 0.3]), lichen * 0.55)
    col = col * (1.0 - cracks[..., None] * 0.45 - cracks2[..., None] * 0.3)
    col = col * (0.85 + 0.25 * strata[..., None] * n2[..., None])
    rough = 0.82 + 0.1 * n2 - 0.1 * lichen
    return col, rough, h


def layer_sand(seed):
    n1 = fft_noise(ALB, 2.0, seed)
    n2 = fft_noise(ALB, 1.5, seed + 1)
    yy, xx = np.mgrid[0:ALB, 0:ALB] / ALB
    ripple = 0.5 + 0.5 * np.sin((xx * 0.4 + yy) * 38.0 * math.pi + n1 * 5.0)
    ripple = ripple ** 1.5
    grain = rng(seed).random((ALB, ALB))
    grain = ndimage.gaussian_filter(grain, 0.6, mode="wrap")
    h = ripple * 0.35 + n2 * 0.4 + grain * 0.15
    col = ramp(n2 * 0.6 + ripple * 0.2 + grain * 0.2, [(0.0, (0.62, 0.55, 0.41)), (0.5, (0.74, 0.66, 0.5)), (1.0, (0.82, 0.76, 0.6))])
    shells = smoothstep(0.985, 0.995, rng(seed + 4).random((ALB, ALB)))
    shells = ndimage.maximum_filter(shells, 2, mode="wrap")
    col = mix(col, np.array([0.92, 0.9, 0.85]), shells * 0.8)
    rough = 0.95 - 0.05 * grain
    return col, rough, h


def layer_snow(seed):
    n1 = fft_noise(ALB, 3.0, seed)
    n2 = fft_noise(ALB, 2.0, seed + 1)
    h = n1 * 0.7 + n2 * 0.3
    col = ramp(h, [(0.0, (0.72, 0.78, 0.88)), (0.5, (0.88, 0.91, 0.96)), (1.0, (0.97, 0.98, 1.0))])
    sparkle = rng(seed + 2).random((ALB, ALB)) > 0.997
    rough = 0.62 + 0.15 * n2
    rough = np.where(sparkle, 0.12, rough)
    return col, rough, h


def layer_scree(seed):
    dome, tone, mask = _pebbles(ALB, 4200, seed, 4.0, 11.0)
    dome2, tone2, mask2 = _pebbles(ALB, 9000, seed + 3, 2.0, 5.0)
    n1 = fft_noise(ALB, 2.2, seed + 1)
    base = ramp(n1, [(0.0, (0.1, 0.09, 0.09)), (1.0, (0.2, 0.18, 0.17))])
    c1 = ramp(tone, [(0.0, (0.16, 0.15, 0.15)), (0.6, (0.27, 0.25, 0.24)), (0.85, (0.33, 0.22, 0.18)), (1.0, (0.4, 0.36, 0.33))])
    c2 = ramp(tone2, [(0.0, (0.14, 0.13, 0.13)), (1.0, (0.3, 0.28, 0.26))])
    col = np.where(mask2[..., None], c2 * (0.6 + 0.4 * dome2[..., None]), base)
    col = np.where(mask[..., None], c1 * (0.55 + 0.45 * dome[..., None]), col)
    h = np.maximum(dome, dome2 * 0.6) * 0.8 + n1 * 0.2
    rough = 0.9 - 0.15 * dome
    return col, rough, h


BUILDERS = {
    "grass": layer_grass,
    "dry_grass": layer_dry_grass,
    "dirt": layer_dirt,
    "forest_floor": layer_forest_floor,
    "rock": layer_rock,
    "sand": layer_sand,
    "snow": layer_snow,
    "scree": layer_scree,
}

NORMAL_STRENGTH = {"grass": 3.0, "dry_grass": 3.0, "dirt": 5.0, "forest_floor": 3.5, "rock": 7.0, "sand": 3.0,
                   "snow": 2.5, "scree": 6.0}


def build_layer(args):
    name, seed = args
    col, rough, h = BUILDERS[name](seed)
    h = (h - h.min()) / max(h.max() - h.min(), 1e-6)
    ao = ambient_occlusion(h, radius=5, strength=1.2)
    col = col * (0.55 + 0.45 * ao[..., None])
    small_h = np.asarray(Image.fromarray((h * 65535).astype(np.uint16)).resize((NRM, NRM), Image.LANCZOS)).astype(np.float64) / 65535.0
    small_r = np.asarray(Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8)).resize((NRM, NRM), Image.LANCZOS)).astype(np.float64) / 255.0
    nrm = height_to_normal(small_h * 20.0, NORMAL_STRENGTH[name] * 0.2)
    nrh = np.dstack([nrm[..., 0], nrm[..., 1], small_r, small_h])
    return name, col, nrh


def generate(out_dir, pool):
    os.makedirs(out_dir, exist_ok=True)
    jobs = [(name, 100 + i * 17) for i, name in enumerate(LAYERS)]
    results = dict((n, (c, x)) for n, c, x in pool.map(build_layer, jobs))
    alb = np.concatenate([results[n][0] for n in LAYERS], axis=1)
    nrh = np.concatenate([results[n][1] for n in LAYERS], axis=1)
    Image.fromarray((np.clip(alb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(
        os.path.join(out_dir, "terrain_albedo.jpg"), quality=92, subsampling=0)
    Image.fromarray((np.clip(nrh, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(
        os.path.join(out_dir, "terrain_nrh.png"), optimize=True)
    print("  terrain arrays: %d layers" % len(LAYERS))
