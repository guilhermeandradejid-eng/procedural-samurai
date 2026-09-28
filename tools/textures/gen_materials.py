"""Architecture, prop, armour and cloth textures (tileable, 512^2)."""
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from texlib import (ambient_occlusion, band_noise, directional_noise, fft_noise, height_to_normal, ramp, rng,
                    smoothstep, voronoi)

S = 512


def planks(seed, dark=True):
    r = rng(seed)
    grain = directional_noise(S, 40, 90, stretch=14, seed=seed)
    grain2 = directional_noise(S, 120, 90, stretch=20, seed=seed + 1)
    n = fft_noise(S, 2.0, seed + 2)
    xx = np.arange(S)[None, :].repeat(S, 0)
    boards = 4
    bw = S // boards
    board_id = xx // bw
    tone = r.uniform(0, 1, boards)[board_id]
    gap = np.minimum(xx % bw, bw - (xx % bw))
    seam = smoothstep(2.5, 0.0, gap)
    # staggered end joints
    yy = np.arange(S)[:, None].repeat(S, 1)
    offs = (r.uniform(0, S, boards)[board_id]).astype(int)
    endj = smoothstep(2.0, 0.0, np.abs(((yy + offs) % S) - S // 2))
    if dark:
        stops = [(0.0, (0.1, 0.07, 0.05)), (0.5, (0.2, 0.14, 0.09)), (1.0, (0.3, 0.21, 0.14))]
    else:
        stops = [(0.0, (0.32, 0.24, 0.16)), (0.5, (0.48, 0.37, 0.25)), (1.0, (0.6, 0.48, 0.34))]
    col = ramp(grain * 0.5 + grain2 * 0.2 + tone * 0.3, stops)
    col = col * (1.0 - np.maximum(seam, endj)[..., None] * 0.7)
    h = 0.6 + 0.2 * grain + 0.1 * grain2 - np.maximum(seam, endj) * 0.5
    rough = 0.75 + 0.15 * n
    return col, h, rough


def vermilion(seed):
    grain = directional_noise(S, 40, 90, stretch=14, seed=seed)
    wear = fft_noise(S, 2.2, seed + 1)
    chips = smoothstep(0.7, 0.78, wear)
    paint = ramp(fft_noise(S, 2.5, seed + 2), [(0.0, (0.5, 0.08, 0.04)), (0.6, (0.66, 0.13, 0.06)), (1.0, (0.74, 0.2, 0.08))])
    wood = ramp(grain, [(0.0, (0.2, 0.13, 0.08)), (1.0, (0.36, 0.26, 0.17))])
    col = paint * (1 - chips[..., None]) + wood * chips[..., None]
    col = col * (0.9 + 0.1 * grain[..., None])
    h = 0.6 + 0.1 * grain - chips * 0.3
    rough = 0.5 + 0.35 * chips + 0.1 * wear
    return col, h, rough


def thatch(seed):
    r = rng(seed)
    img = Image.new("RGB", (S * 2, S * 2), (70, 52, 30))
    dr = ImageDraw.Draw(img)
    for i in range(16000):
        x = r.uniform(0, S * 2)
        y = r.uniform(0, S * 2)
        L = r.uniform(40, 120)
        a = math.pi / 2 + r.normal(0, 0.12)
        g = r.uniform(0.55, 1.1)
        c = (int(150 * g), int(118 * g), int(70 * g))
        for oy in (-S * 2, 0, S * 2):
            for ox in (-S * 2, 0, S * 2):
                dr.line([(x + ox, y + oy), (x + ox + math.cos(a) * L, y + oy + math.sin(a) * L)], fill=c, width=2)
    arr = np.asarray(img.resize((S, S), Image.LANCZOS)).astype(np.float64) / 255.0
    rows = 0.5 + 0.5 * np.sin(np.arange(S)[:, None] / S * 8 * math.tau)
    rows = np.repeat(rows, S, 1)
    col = arr * (0.75 + 0.25 * rows[..., None])
    lum = arr.mean(-1)
    h = lum * 0.7 + rows * 0.3
    rough = 0.95 - 0.1 * lum
    return col, h, rough


def roof_tiles(seed):
    yy, xx = np.mgrid[0:S, 0:S] / S
    cols_n = 8
    rows_n = 8
    u = (xx * cols_n) % 1.0
    v = (yy * rows_n) % 1.0
    ridge = np.cos((u - 0.5) * math.pi) ** 0.6       # rounded channel tiles
    overlap = smoothstep(0.0, 0.25, v) * (1 - 0.35 * smoothstep(0.8, 1.0, v))
    h = ridge * 0.7 + overlap * 0.3
    n = fft_noise(S, 2.3, seed)
    base = ramp(n, [(0.0, (0.16, 0.17, 0.19)), (0.5, (0.24, 0.25, 0.28)), (1.0, (0.33, 0.33, 0.36))])
    moss = smoothstep(0.65, 0.8, fft_noise(S, 2.6, seed + 1)) * (1 - ridge) * 0.6
    col = base * (0.55 + 0.45 * h[..., None])
    col = col * (1 - moss[..., None]) + moss[..., None] * np.array([0.22, 0.28, 0.12])
    rough = 0.55 + 0.25 * n
    return col, h, rough


def plaster(seed):
    n = fft_noise(S, 2.2, seed)
    n2 = fft_noise(S, 1.6, seed + 1)
    stains = smoothstep(0.6, 0.85, n2) * (np.arange(S)[:, None] / S) ** 2
    col = ramp(n, [(0.0, (0.8, 0.77, 0.7)), (1.0, (0.92, 0.9, 0.84))])
    col = col * (1 - stains[..., None] * 0.35)
    h = n * 0.3
    rough = 0.9 + 0.05 * n
    return col, h, rough


def shoji(seed):
    n = fft_noise(S, 2.0, seed)
    paper = ramp(n, [(0.0, (0.86, 0.83, 0.74)), (1.0, (0.95, 0.93, 0.86))])
    yy, xx = np.mgrid[0:S, 0:S]
    gx = np.minimum(xx % (S // 4), (S // 4) - xx % (S // 4))
    gy = np.minimum(yy % (S // 6), (S // 6) - yy % (S // 6))
    lattice = np.maximum(smoothstep(6, 3, gx), smoothstep(6, 3, gy))
    wood = np.array([0.3, 0.22, 0.15])
    col = paper * (1 - lattice[..., None]) + wood * lattice[..., None]
    h = lattice * 0.6 + n * 0.05
    rough = 0.9 - 0.2 * lattice
    return col, h, rough


def stone(seed):
    n = fft_noise(S, 2.2, seed)
    speck = rng(seed + 1).random((S, S))
    speck = ndimage.gaussian_filter(speck, 0.7, mode="wrap")
    col = ramp(n * 0.6 + speck * 0.4, [(0.0, (0.34, 0.33, 0.32)), (0.5, (0.5, 0.49, 0.47)), (1.0, (0.64, 0.62, 0.59))])
    lichen = smoothstep(0.66, 0.78, fft_noise(S, 2.5, seed + 2))
    col = col * (1 - lichen[..., None] * 0.5) + lichen[..., None] * np.array([0.45, 0.46, 0.25]) * 0.5
    h = n * 0.6 + speck * 0.4
    rough = 0.8 + 0.15 * speck
    return col, h, rough


def canvas(seed):
    yy, xx = np.mgrid[0:S, 0:S]
    weave = (np.sin(xx / S * 128 * math.tau) * np.sin(yy / S * 128 * math.tau)) * 0.5 + 0.5
    n = fft_noise(S, 2.1, seed)
    dirt = smoothstep(0.55, 0.9, fft_noise(S, 1.8, seed + 1))
    col = ramp(n, [(0.0, (0.62, 0.56, 0.44)), (1.0, (0.76, 0.7, 0.58))])
    col = col * (0.9 + 0.1 * weave[..., None]) * (1 - dirt[..., None] * 0.35)
    h = weave * 0.3 + n * 0.2
    rough = 0.92
    return col, h, rough * np.ones_like(h)


def straw_weave(seed):
    """Woven kasa (straw hat) pattern: diagonal twill."""
    yy, xx = np.mgrid[0:S, 0:S] / S
    k = 24
    a = ((xx + yy) * k) % 1.0
    b = ((xx - yy) * k) % 1.0
    over = ((np.floor((xx + yy) * k) + np.floor((xx - yy) * k)) % 2) == 0
    strand = np.where(over, np.sin(a * math.pi), np.sin(b * math.pi))
    n = fft_noise(S, 2.0, seed)
    fib = directional_noise(S, 200, 45, stretch=8, seed=seed + 1)
    col = ramp(n * 0.4 + strand * 0.4 + fib * 0.2, [(0.0, (0.42, 0.32, 0.17)), (0.5, (0.64, 0.5, 0.28)), (1.0, (0.8, 0.66, 0.4))])
    h = strand * 0.8 + fib * 0.2
    rough = 0.85 * np.ones_like(h)
    return col, h, rough


def armor_mask(seed):
    """Lamellar armour mask: R lacquer shading, G lacing, B metal rivets/trim, A plate height.
    Plates are horizontal lames laced vertically (odoshi)."""
    yy, xx = np.mgrid[0:S, 0:S] / S
    rows = 6
    v = (yy * rows) % 1.0
    lame = smoothstep(0.0, 0.06, v) * (1 - smoothstep(0.9, 1.0, v))
    bevel = 1.0 - np.abs(v - 0.5) * 0.6
    n = fft_noise(S, 2.3, seed)
    lacq = np.clip(0.55 + 0.35 * bevel + 0.1 * n, 0, 1) * (0.5 + 0.5 * lame)
    # lacing: vertical cords every 1/16, crossing the lame gaps diagonally
    cols = 16
    u = (xx * cols) % 1.0
    cord = smoothstep(0.22, 0.12, np.abs(u - 0.5))
    lacing = cord * (0.6 + 0.4 * np.sin(yy * rows * 2 * math.tau * 3) ** 2)
    rivets = np.zeros_like(xx)
    ry = smoothstep(0.035, 0.0, np.hypot(((xx * 8) % 1.0 - 0.5) / 8, (v - 0.2) / rows))
    rivets = np.maximum(rivets, ry)
    h = lame * 0.6 + lacing * 0.3 + rivets * 0.2
    return np.dstack([lacq, np.clip(lacing, 0, 1), np.clip(rivets, 0, 1), np.clip(h, 0, 1)])


def cloth_mask(seed):
    """Cloth pattern masks: R seigaiha waves, G asanoha star, B stripes, A weave."""
    yy, xx = np.mgrid[0:S, 0:S] / S
    # seigaiha: overlapping concentric semicircles
    k = 8.0
    sx = xx * k
    sy = yy * k * 2.0
    best = np.full(xx.shape, 10.0)
    ring = np.zeros_like(xx)
    for oy in range(-1, 2):
        for ox in range(-1, 2):
            cx = np.floor(sx) + 0.5 + ox + (np.floor(sy + oy) % 2) * 0.5
            cy = np.floor(sy) + oy + 1.0
            d = np.hypot(sx - cx, (sy - cy) * 0.5)
            above = sy < cy + 1e-3
            cand = np.where(above, d, 10.0)
            take = cand < best
            best = np.where(take, cand, best)
    ring = (np.sin(best * math.tau * 3.0) * 0.5 + 0.5)
    seig = smoothstep(0.55, 0.75, ring) * (best < 0.52)
    # asanoha (hemp leaf) approximated by a triangular grid of lines
    t1 = np.abs(((xx * 12 + yy * 12 * 0.57735 * 2) % 1.0) - 0.5)
    t2 = np.abs(((xx * 12 - yy * 12 * 0.57735 * 2) % 1.0) - 0.5)
    t3 = np.abs(((yy * 12 * 1.1547) % 1.0) - 0.5)
    asa = np.maximum(np.maximum(smoothstep(0.47, 0.5, t1), smoothstep(0.47, 0.5, t2)), smoothstep(0.47, 0.5, t3))
    stripes = smoothstep(0.4, 0.45, np.abs(((xx * 10) % 1.0) - 0.5))
    weave = (np.sin(xx * 256 * math.tau) * np.sin(yy * 256 * math.tau)) * 0.5 + 0.5
    return np.dstack([seig, asa, stripes, weave * 0.6 + 0.4 * fft_noise(S, 2.0, seed)])


def rope(seed):
    yy, xx = np.mgrid[0:S, 0:S] / S
    twist = np.sin((yy * 6 + xx * 2) * math.tau) * 0.5 + 0.5
    fib = directional_noise(S, 180, 70, stretch=10, seed=seed)
    col = ramp(twist * 0.6 + fib * 0.4, [(0.0, (0.46, 0.38, 0.2)), (1.0, (0.78, 0.68, 0.42))])
    h = twist * 0.8 + fib * 0.2
    return col, h, 0.9 * np.ones_like(h)


def banner(seed, crest):
    """Nobori war banner (256x1024): cloth with a painted clan crest."""
    W, H = 256, 1024
    r = rng(seed)
    base = {"red": (0.62, 0.12, 0.08), "black": (0.1, 0.09, 0.09), "white": (0.88, 0.85, 0.78)}[crest["bg"]]
    ink = {"red": (0.62, 0.12, 0.08), "black": (0.08, 0.07, 0.07), "white": (0.9, 0.87, 0.8), "gold": (0.8, 0.62, 0.25)}[crest["fg"]]
    img = Image.new("RGB", (W * 2, H * 2), tuple(int(c * 255) for c in base))
    dr = ImageDraw.Draw(img)
    cx, cy = W, H * 0.55
    ic = tuple(int(c * 255) for c in ink)
    if crest["shape"] == "tomoe":
        dr.ellipse([cx - 150, cy - 150, cx + 150, cy + 150], outline=ic, width=26)
        for k in range(3):
            a = k * math.tau / 3
            px = cx + math.cos(a) * 60
            py = cy + math.sin(a) * 60
            dr.ellipse([px - 46, py - 46, px + 46, py + 46], fill=ic)
            dr.pieslice([px - 110, py - 110, px + 110, py + 110], math.degrees(a) + 20, math.degrees(a) + 110, fill=ic)
    elif crest["shape"] == "diamond":
        for k in range(4):
            a = k * math.pi / 2
            px = cx + math.cos(a) * 70
            py = cy + math.sin(a) * 70
            dr.polygon([(px, py - 60), (px + 60, py), (px, py + 60), (px - 60, py)], fill=ic)
    else:  # circle with bar (simple mon)
        dr.ellipse([cx - 160, cy - 160, cx + 160, cy + 160], outline=ic, width=30)
        dr.rectangle([cx - 150, cy - 26, cx + 150, cy + 26], fill=ic)
    # top band
    dr.rectangle([0, 0, W * 2, 110], fill=ic)
    arr = np.asarray(img.resize((W, H), Image.LANCZOS)).astype(np.float64) / 255.0
    n = fft_noise(256, 2.0, seed)
    n = np.tile(n, (4, 1))
    arr = arr * (0.85 + 0.15 * n[..., None])
    return arr


def _save_set(out_dir, name, col, h, rough, normal_strength=1.0):
    h = (h - h.min()) / max(h.max() - h.min(), 1e-6)
    ao = ambient_occlusion(h, radius=4, strength=0.8)
    col = col * (0.7 + 0.3 * ao[..., None])
    Image.fromarray((np.clip(col, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(out_dir, name + ".jpg"), quality=90)
    nrm = height_to_normal(h * 20.0, normal_strength)
    Image.fromarray((np.clip(nrm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(out_dir, name + "_n.png"), optimize=True)


def generate(out_dir, pool=None):
    os.makedirs(out_dir, exist_ok=True)
    _save_set(out_dir, "wood_dark", *planks(11, True), 0.6)
    _save_set(out_dir, "wood_light", *planks(12, False), 0.6)
    _save_set(out_dir, "vermilion", *vermilion(13), 0.4)
    _save_set(out_dir, "thatch", *thatch(14), 1.2)
    _save_set(out_dir, "roof_tiles", *roof_tiles(15), 1.6)
    _save_set(out_dir, "plaster", *plaster(16), 0.3)
    _save_set(out_dir, "shoji", *shoji(17), 0.4)
    _save_set(out_dir, "stone", *stone(18), 0.8)
    _save_set(out_dir, "canvas", *canvas(19), 0.5)
    _save_set(out_dir, "straw_weave", *straw_weave(20), 0.9)
    _save_set(out_dir, "rope", *rope(21), 1.0)
    am = armor_mask(22)
    Image.fromarray((np.clip(am, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(out_dir, "armor_mask.png"), optimize=True)
    nrm = height_to_normal(am[..., 3] * 20.0, 0.7)
    Image.fromarray((np.clip(nrm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(out_dir, "armor_mask_n.png"), optimize=True)
    cm = cloth_mask(23)
    Image.fromarray((np.clip(cm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(out_dir, "cloth_mask.png"), optimize=True)
    crests = [
        {"bg": "black", "fg": "white", "shape": "tomoe"},
        {"bg": "red", "fg": "black", "shape": "diamond"},
        {"bg": "white", "fg": "red", "shape": "circle"},
        {"bg": "black", "fg": "gold", "shape": "circle"},
    ]
    for i, c in enumerate(crests):
        b = banner(30 + i, c)
        Image.fromarray((np.clip(b, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(out_dir, "banner_%d.jpg" % i), quality=90)
    print("  material textures done")
