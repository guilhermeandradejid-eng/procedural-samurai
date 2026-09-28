"""Foliage cluster cards (alpha) and bark textures for the Blender trees."""
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

from texlib import (directional_noise, fft_noise, height_to_normal, leaf_shape, ramp, rng, smoothstep, transform,
                    voronoi)

CARD = 512


def _draw_leaf(dr, shape, x, y, angle, scale, base, light, vein, ss):
    pts = transform(shape, x, y, angle, scale)
    dr.polygon([(px * ss, py * ss) for px, py in pts], fill=base)
    inner = transform(shape, x + math.sin(angle) * scale * 0.08, y - math.cos(angle) * scale * 0.08, angle, scale * 0.72)
    dr.polygon([(px * ss, py * ss) for px, py in inner], fill=light)
    # main vein from the stem towards the tip
    tipx = x + math.sin(angle) * scale * 0.9
    tipy = y - math.cos(angle) * scale * 0.9
    dr.line([(x * ss, y * ss), (tipx * ss, tipy * ss)], fill=vein, width=max(1, int(ss * scale * 0.03)))


def foliage_card(kind, seed):
    r = rng(seed)
    ss = 3
    img = Image.new("RGBA", (CARD * ss, CARD * ss), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img, "RGBA")
    cx, cy = CARD * 0.5, CARD * 0.55
    if kind in ("maple", "ginkgo", "birch", "sakura"):
        palettes = {
            "maple": [(168, 28, 20), (196, 42, 22), (214, 70, 26), (150, 22, 24), (226, 104, 34), (182, 36, 30)],
            "ginkgo": [(222, 172, 40), (236, 196, 64), (206, 150, 34), (244, 210, 90), (196, 160, 50)],
            "birch": [(206, 176, 58), (184, 168, 64), (160, 150, 58), (220, 190, 80), (140, 140, 60)],
            "sakura": [(244, 190, 206), (250, 210, 220), (236, 170, 190), (255, 226, 232), (226, 150, 176)],
        }[kind]
        # twigs radiating from the bottom centre
        twigs = []
        for i in range(7):
            a = -math.pi / 2 + r.uniform(-1.0, 1.0)
            L = r.uniform(CARD * 0.3, CARD * 0.5)
            twigs.append((a, L))
            ex = cx + math.cos(a) * L
            ey = cy + math.sin(a) * L
            dr.line([(cx * ss, (CARD - 4) * ss), (ex * ss, ey * ss)], fill=(62, 40, 28, 255), width=int(ss * 3))
        if kind == "sakura":
            shape = leaf_shape("sakura", 1.0)
            count = 150
        elif kind == "maple":
            shape = None
            count = 95
        elif kind == "ginkgo":
            shape = leaf_shape("ginkgo", 1.0)
            count = 120
        else:
            shape = leaf_shape("birch", 1.0)
            count = 170
        for i in range(count):
            # leaves fill a rounded clump; twigs are mostly hidden behind them
            rr = math.sqrt(r.uniform(0.0, 1.0))
            th = r.uniform(0, math.tau)
            px = CARD * 0.5 + math.cos(th) * rr * CARD * 0.36
            py = CARD * 0.46 + math.sin(th) * rr * CARD * 0.34
            ang = math.atan2(py - (CARD - 4), px - cx) + math.pi / 2 + r.uniform(-0.6, 0.6)
            sc = {"maple": r.uniform(36, 54), "ginkgo": r.uniform(30, 42), "birch": r.uniform(26, 36), "sakura": r.uniform(18, 26)}[kind]
            if kind == "maple":
                shape = leaf_shape("maple", 1.0, 7 if r.random() < 0.6 else 5)
            base = palettes[r.integers(0, len(palettes))]
            k = r.uniform(0.75, 1.0)
            basec = (int(base[0] * k), int(base[1] * k), int(base[2] * k), 255)
            lightc = (min(255, int(base[0] * k * 1.18)), min(255, int(base[1] * k * 1.18)), min(255, int(base[2] * k * 1.15)), 255)
            vein = (int(base[0] * 0.6), int(base[1] * 0.55), int(base[2] * 0.5), 255)
            if kind == "sakura":
                pts = transform(shape, px, py, r.uniform(0, math.tau), sc)
                dr.polygon([(x * ss, y * ss) for x, y in pts], fill=basec)
                dr.ellipse([(px - sc * 0.22) * ss, (py - sc * 0.22) * ss, (px + sc * 0.22) * ss, (py + sc * 0.22) * ss], fill=(214, 90, 120, 255))
                dr.ellipse([(px - sc * 0.08) * ss, (py - sc * 0.08) * ss, (px + sc * 0.08) * ss, (py + sc * 0.08) * ss], fill=(250, 220, 120, 255))
            else:
                _draw_leaf(dr, shape, px, py, ang, sc, basec, lightc, vein, ss)
    elif kind == "pine":
        for i in range(26):
            a = -math.pi / 2 + r.uniform(-1.3, 1.3)
            L = r.uniform(CARD * 0.2, CARD * 0.42)
            ex = cx + math.cos(a) * L
            ey = cy + math.sin(a) * L
            dr.line([(cx * ss, (CARD - 4) * ss), (ex * ss, ey * ss)], fill=(70, 46, 30, 255), width=int(ss * 3))
            # needle tufts along the twig
            for j in range(9):
                t = 0.35 + j / 9 * 0.65
                tx = cx + (ex - cx) * t
                ty = (CARD - 4) + (ey - (CARD - 4)) * t
                for k in range(26):
                    na = a + r.uniform(-1.2, 1.2)
                    nl = r.uniform(16, 34)
                    g = r.uniform(0.7, 1.1)
                    col = (int(34 * g), int(78 * g), int(40 * g), 255) if r.random() < 0.8 else (int(60 * g), int(100 * g), int(54 * g), 255)
                    dr.line([(tx * ss, ty * ss), ((tx + math.cos(na) * nl) * ss, (ty + math.sin(na) * nl) * ss)], fill=col, width=int(ss * 1.6))
    else:  # bamboo
        for i in range(14):
            a = -math.pi / 2 + r.uniform(-1.4, 1.4)
            L = r.uniform(CARD * 0.25, CARD * 0.45)
            ex = cx + math.cos(a) * L
            ey = cy + math.sin(a) * L
            dr.line([(cx * ss, (CARD - 4) * ss), (ex * ss, ey * ss)], fill=(96, 120, 48, 255), width=int(ss * 2))
            shape = leaf_shape("lance", 1.0)
            for j in range(6):
                t = 0.3 + j / 6 * 0.7
                tx = cx + (ex - cx) * t
                ty = (CARD - 4) + (ey - (CARD - 4)) * t
                ang = a + math.pi / 2 + r.uniform(-0.9, 0.9) + (0.6 if j % 2 else -0.6)
                g = r.uniform(0.75, 1.1)
                base = (int(72 * g), int(122 * g), int(44 * g), 255)
                light = (int(96 * g), int(148 * g), int(58 * g), 255)
                _draw_leaf(dr, shape, tx, ty, ang, r.uniform(70, 110), base, light, (50, 84, 30, 255), ss)
    small = img.resize((CARD, CARD), Image.LANCZOS)
    arr = np.asarray(small).astype(np.float64) / 255.0
    # bleed colour into transparent pixels so mipmaps do not get dark halos
    a = arr[..., 3]
    rgb = arr[..., :3]
    mask = a > 0.3
    if mask.any():
        idx = ndimage.distance_transform_edt(~mask, return_distances=False, return_indices=True)
        rgb = rgb[idx[0], idx[1]]
    out = np.dstack([rgb, np.where(a > 0.5, 1.0, a * 0.9)])
    return out


def bark(kind, seed, w=512, h=1024):
    r = rng(seed)
    if kind == "pine":
        f1, f2, cid = voronoi(w, 90, seed)
        f1 = np.asarray(Image.fromarray(f1.astype(np.float32)).resize((w, h)))
        f2 = np.asarray(Image.fromarray(f2.astype(np.float32)).resize((w, h)))
        cid = np.asarray(Image.fromarray(cid.astype(np.int32)).resize((w, h), Image.NEAREST))
        edge = f2 - f1
        fiss = smoothstep(7.0, 0.0, edge)
        tone = r.uniform(0, 1, 90)[cid]
        n = _tile_resize(fft_noise(w, 2.2, seed + 1), w, h)
        height = (1.0 - fiss) * (0.6 + 0.4 * n)
        col = ramp(tone * 0.5 + n * 0.5, [(0.0, (0.3, 0.16, 0.1)), (0.5, (0.45, 0.25, 0.15)), (1.0, (0.56, 0.35, 0.22))])
        col = col * (0.35 + 0.65 * height[..., None])
    elif kind == "birch":
        n = _tile_resize(fft_noise(w, 2.0, seed), w, h)
        col = ramp(n, [(0.0, (0.78, 0.76, 0.7)), (1.0, (0.93, 0.92, 0.88))])
        height = 0.5 + 0.2 * n
        dr_img = Image.new("L", (w, h), 0)
        dr = ImageDraw.Draw(dr_img)
        for i in range(240):
            x = r.uniform(0, w)
            y = r.uniform(0, h)
            L = r.uniform(8, 40)
            t = r.uniform(1.5, 4)
            for ox in (-w, 0, w):
                dr.line([(x + ox, y), (x + ox + L, y + r.uniform(-1, 1))], fill=255, width=int(t))
        for i in range(24):
            x = r.uniform(0, w)
            y = r.uniform(0, h)
            s = r.uniform(10, 40)
            for ox in (-w, 0, w):
                dr.ellipse([x + ox - s, y - s * 0.5, x + ox + s, y + s * 0.5], fill=200)
        marks = np.asarray(dr_img).astype(np.float64) / 255.0
        marks = ndimage.gaussian_filter(marks, 0.8)
        col = col * (1.0 - marks[..., None] * 0.85)
        height = height - marks * 0.3
    elif kind == "bamboo":
        streak = _tile_resize(directional_noise(w, 60, 0, stretch=12, seed=seed), w, h)
        col = ramp(streak, [(0.0, (0.3, 0.45, 0.16)), (1.0, (0.46, 0.6, 0.24))])
        yy = np.arange(h)[:, None] / h
        node = np.exp(-((((yy * 4.0) % 1.0) - 0.5) * 40.0) ** 2)
        col = col * (1.0 - node[..., None] * 0.35) + node[..., None] * np.array([0.08, 0.06, 0.0])
        height = 0.5 + 0.1 * streak + node * 0.4
    else:  # dark deciduous bark
        n = _tile_resize(directional_noise(w, 18, 90, stretch=7, seed=seed), w, h)
        n2 = _tile_resize(fft_noise(w, 2.3, seed + 1), w, h)
        fiss = smoothstep(0.35, 0.15, n)
        height = n * 0.7 + n2 * 0.3
        col = ramp(n2 * 0.5 + n * 0.5, [(0.0, (0.12, 0.1, 0.09)), (0.5, (0.26, 0.22, 0.19)), (1.0, (0.4, 0.36, 0.31))])
        moss = smoothstep(0.62, 0.8, _tile_resize(fft_noise(w, 2.5, seed + 2), w, h))
        col = col * (1.0 - fiss[..., None] * 0.6)
        col = col * (1 - moss[..., None] * 0.5) + moss[..., None] * np.array([0.2, 0.28, 0.1]) * 0.5
    height = (height - height.min()) / max(height.max() - height.min(), 1e-6)
    nrm = height_to_normal(height * 20, 0.9)
    return col, nrm


def _tile_resize(a, w, h):
    """Resize a square tileable field to w x h keeping it tileable (wrap padding)."""
    if a.shape == (h, w):
        return a
    reps_y = int(math.ceil(h / a.shape[0]))
    reps_x = int(math.ceil(w / a.shape[1]))
    tiled = np.tile(a, (reps_y, reps_x))
    return tiled[:h, :w]


def pampas_plume(seed=880, w=128, h=256):
    """Feathery susuki plume (alpha card): drooping silky strands off a stem."""
    r = rng(seed)
    ss = 3
    img = Image.new("RGBA", (w * ss, h * ss), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    cx = w * 0.5
    for i in range(420):
        t = r.uniform(0.0, 1.0)
        y0 = h * (0.97 - t * 0.9)
        side = -1 if r.random() < 0.5 else 1
        L = w * r.uniform(0.12, 0.42) * (0.4 + 0.6 * math.sin(t * math.pi) ** 0.5)
        droop = r.uniform(0.2, 0.9)
        pts = []
        for k in range(6):
            u = k / 5
            pts.append(((cx + side * L * u) * ss, (y0 + droop * L * u * u * 0.9 - (1 - t) * 4 * u) * ss))
        g = r.uniform(0.82, 1.0)
        col = (int(250 * g), int(236 * g), int(206 * g), int(r.uniform(150, 255)))
        dr.line(pts, fill=col, width=max(1, int(ss * r.uniform(0.7, 1.4))), joint="curve")
    dr.line([(cx * ss, h * ss), (cx * ss, h * 0.05 * ss)], fill=(200, 176, 120, 255), width=int(ss * 2))
    small = img.resize((w, h), Image.LANCZOS)
    arr = np.asarray(small).astype(np.float64) / 255.0
    a = arr[..., 3]
    mask = a > 0.25
    idx = ndimage.distance_transform_edt(~mask, return_distances=False, return_indices=True)
    rgb = arr[..., :3][idx[0], idx[1]]
    return np.dstack([rgb, a])


def generate(out_dir, pool=None):
    os.makedirs(out_dir, exist_ok=True)
    plume = pampas_plume()
    Image.fromarray((np.clip(plume, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(out_dir, "pampas_plume.png"), optimize=True)
    kinds = ["maple", "ginkgo", "pine", "birch", "bamboo", "sakura"]
    for i, k in enumerate(kinds):
        card = foliage_card(k, 500 + i)
        Image.fromarray((np.clip(card, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(out_dir, "foliage_%s.png" % k), optimize=True)
    for i, k in enumerate(["pine", "dark", "birch", "bamboo"]):
        col, nrm = bark(k, 700 + i)
        Image.fromarray((np.clip(col, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(out_dir, "bark_%s.jpg" % k), quality=90)
        Image.fromarray((np.clip(nrm, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(out_dir, "bark_%s_n.png" % k), optimize=True)
    print("  vegetation textures done")
