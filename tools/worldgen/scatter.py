#!/usr/bin/env python3
"""Scatters trees and rocks over the generated island.

Reads assets/world/{height.f32, splat.png, veg.png, world.json} and writes

  assets/world/scatter.bin   float32 records: kind, x, y, z, yaw, scale
  assets/world/scatter.json  kind names, categories and counts

Trees follow the vegetation map (density + species), leave roads, water,
steep slopes and points of interest clear, and are thinned at forest edges
so glades look natural. Rocks gather on slopes, ridges, river beds and the
volcano; cliffs face downhill on the steepest faces.

Usage: python3 tools/worldgen/scatter.py
"""
import json
import math
import os
import sys
import time

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WORLD = os.path.join(ROOT, "assets", "world")

SPECIES = {  # code -> (name, scale range, variants)
    16: ("pine", (0.8, 1.3)),
    58: ("maple", (0.75, 1.15)),
    100: ("ginkgo", (0.8, 1.2)),
    142: ("birch", (0.8, 1.2)),
    184: ("bamboo", (0.85, 1.25)),
    226: ("sakura", (0.8, 1.1)),
}
ROCKS = ["boulder_0", "boulder_1", "boulder_2", "cliff_0", "pebbles_0", "slab_0", "spire_0"]


def main():
    t0 = time.time()
    meta = json.load(open(os.path.join(WORLD, "world.json"), encoding="utf-8"))
    n = int(meta["size"])
    sp = float(meta["spacing"])
    half = (n - 1) / 2.0
    sea = float(meta["sea_level"])
    h = np.fromfile(os.path.join(WORLD, "height.f32"), dtype="<f4").reshape(n, n).astype(np.float64)
    splat = np.asarray(Image.open(os.path.join(WORLD, "splat.png"))).astype(np.float32) / 255.0
    veg = np.asarray(Image.open(os.path.join(WORLD, "veg.png"))).astype(np.float32) / 255.0
    gy, gx = np.gradient(h, sp)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    rng = np.random.default_rng(int(meta["seed"]) + 77)

    def px(x, z):
        return x / sp + half, z / sp + half

    def sample(arr, x, z):
        fx, fz = px(x, z)
        ix = np.clip(np.round(fx).astype(int), 0, n - 1)
        iz = np.clip(np.round(fz).astype(int), 0, n - 1)
        return arr[iz, ix]

    def height(x, z):
        fx, fz = px(x, z)
        fx = np.clip(fx, 0, n - 1.001)
        fz = np.clip(fz, 0, n - 1.001)
        ix = fx.astype(int)
        iz = fz.astype(int)
        tx = fx - ix
        tz = fz - iz
        a = h[iz, ix]
        b = h[iz, ix + 1]
        c = h[iz + 1, ix]
        d = h[iz + 1, ix + 1]
        lower = a + (b - a) * tx + (c - a) * tz
        upper = d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)
        return np.where(tx + tz <= 1.0, lower, upper)

    # ---------------------------------------------------------------- masks
    extent = half * sp
    keep = np.ones((n, n), bool)
    keep &= h > sea + 1.2
    for lk in meta["lakes"]:
        X = (np.arange(n) - half) * sp
        XX, ZZ = np.meshgrid(X, X)
        d2 = ((XX - lk["x"]) ** 2 + ((ZZ - lk["z"]) * 1.25) ** 2)
        keep &= ~((d2 < (lk["radius"] * 1.6) ** 2) & (h < lk["level"] + 0.8))
    road = splat[..., 2] > 0.3
    road = ndimage.binary_dilation(road, iterations=2)
    keep &= ~road
    poi_mask = np.zeros((n, n), bool)
    X = (np.arange(n) - half) * sp
    XX, ZZ = np.meshgrid(X, X)
    for p in meta["pois"]:
        r = float(p.get("radius", 12)) + (6.0 if p["type"] != "landmark" else 3.0)
        poi_mask |= (XX - p["x"]) ** 2 + (ZZ - p["z"]) ** 2 < r * r
    s = meta["spawn"]
    poi_mask |= (XX - s["x"]) ** 2 + (ZZ - s["z"]) ** 2 < 10.0 ** 2
    keep &= ~poi_mask

    # ---------------------------------------------------------------- trees
    cell = 5.0
    g = np.arange(-extent + cell * 0.5, extent, cell)
    cx, cz = np.meshgrid(g, g)
    cx = cx.ravel() + rng.uniform(-0.45, 0.45, cx.size) * cell
    cz = cz.ravel() + rng.uniform(-0.45, 0.45, cz.size) * cell
    dens = sample(veg[..., 0], cx, cz)
    # soft, noisy forest edges and small glades
    blur = ndimage.gaussian_filter(veg[..., 0], 6.0)
    edge = sample(blur, cx, cz)
    prob = np.clip(dens * 1.15, 0.0, 1.0) ** 1.35 * np.clip(0.35 + edge * 1.1, 0.0, 1.0)
    # lone trees in the meadows (Tsushima-style silhouettes on the hills)
    meadow = sample(splat[..., 0], cx, cz) + sample(splat[..., 1], cx, cz) * 0.5
    prob = np.maximum(prob, (meadow > 0.4) * 0.0035)
    ok = rng.random(cx.size) < prob
    ok &= sample(keep, cx, cz)
    ok &= sample(slope, cx, cz) < 34.0
    tx, tz = cx[ok], cz[ok]
    codes = np.round(sample(veg[..., 1], tx, tz) * 255.0).astype(int)
    lone = sample(veg[..., 0], tx, tz) < 0.08
    # lone trees: maples and sakura, sometimes a great pine
    lr = rng.random(tx.size)
    codes = np.where(lone, np.where(lr < 0.45, 58, np.where(lr < 0.8, 226, 16)), codes)
    records = []
    kinds = []
    kind_index = {}

    def kind(name):
        if name not in kind_index:
            kind_index[name] = len(kinds)
            kinds.append(name)
        return kind_index[name]

    for name in ["pine", "maple", "ginkgo", "birch", "bamboo", "sakura"]:
        kind(name + "_0")
        kind(name + "_1")
    for r in ROCKS:
        kind(r)
    known = np.array(sorted(SPECIES.keys()))
    nearest = known[np.abs(codes[:, None] - known[None, :]).argmin(1)]
    ty = height(tx, tz)
    for i in range(tx.size):
        name, (s0, s1) = SPECIES[int(nearest[i])]
        var = int(rng.integers(0, 2))
        scale = rng.uniform(s0, s1)
        if lone[i]:
            scale *= 1.15
        yaw = rng.uniform(0, math.tau)
        records.append((kind_index["%s_%d" % (name, var)], tx[i], ty[i] - 0.12 * scale, tz[i], yaw, scale))
    n_trees = len(records)

    # ---------------------------------------------------------------- rocks
    rcell = 9.0
    g = np.arange(-extent + rcell * 0.5, extent, rcell)
    rx, rz = np.meshgrid(g, g)
    rx = rx.ravel() + rng.uniform(-0.45, 0.45, rx.size) * rcell
    rz = rz.ravel() + rng.uniform(-0.45, 0.45, rz.size) * rcell
    rs = sample(slope, rx, rz)
    rh = sample(h, rx, rz)
    rkeep = sample(keep, rx, rz)
    # rocky where slopes are steep, on high ground and scattered in forests
    p_rock = np.clip((rs - 14.0) / 30.0, 0.0, 1.0) * 0.55
    p_rock += np.clip((rh - 150.0) / 120.0, 0.0, 1.0) * 0.25
    p_rock += sample(veg[..., 0], rx, rz) * 0.05 + 0.012
    rok = (rng.random(rx.size) < p_rock) & rkeep
    rx, rz, rs, rh = rx[rok], rz[rok], rs[rok], rh[rok]
    ry = height(rx, rz)
    gxs = sample(gx, rx, rz)
    gzs = sample(gy, rx, rz)
    for i in range(rx.size):
        r = rng.random()
        s_ = rs[i]
        if s_ > 36.0 and r < 0.55:
            name = "cliff_0"
            scale = rng.uniform(0.8, 1.6)
            # face downhill
            yaw = math.atan2(gxs[i], gzs[i]) + rng.uniform(-0.3, 0.3)
            sink = 0.9 * scale
        elif rh[i] > 170.0 and r < 0.2:
            name = "spire_0"
            scale = rng.uniform(0.8, 1.8)
            yaw = rng.uniform(0, math.tau)
            sink = 0.5 * scale
        elif s_ < 12.0 and r < 0.18:
            name = "slab_0"
            scale = rng.uniform(0.6, 1.2)
            yaw = rng.uniform(0, math.tau)
            sink = 0.25 * scale
        else:
            name = ROCKS[int(rng.integers(0, 3))]
            scale = rng.uniform(0.5, 1.7) * (1.3 if s_ > 25 else 1.0)
            yaw = rng.uniform(0, math.tau)
            sink = 0.3 * scale
        records.append((kind_index[name], rx[i], ry[i] - sink, rz[i], yaw, scale))
        # small companions around the bigger rocks
        if name.startswith("boulder") and rng.random() < 0.5:
            for _ in range(int(rng.integers(1, 3))):
                ox = rx[i] + rng.uniform(-3.5, 3.5)
                oz = rz[i] + rng.uniform(-3.5, 3.5)
                oy = float(height(np.array([ox]), np.array([oz]))[0])
                records.append((kind_index["pebbles_0" if rng.random() < 0.5 else "boulder_1"], ox, oy - 0.1,
                                oz, rng.uniform(0, math.tau), rng.uniform(0.35, 0.8)))
    # pebbles along roads and river banks
    pcell = 7.0
    g = np.arange(-extent + pcell * 0.5, extent, pcell)
    px_, pz_ = np.meshgrid(g, g)
    px_ = px_.ravel() + rng.uniform(-0.5, 0.5, px_.size) * pcell
    pz_ = pz_.ravel() + rng.uniform(-0.5, 0.5, pz_.size) * pcell
    near_road = sample(ndimage.binary_dilation(splat[..., 2] > 0.3, iterations=4), px_, pz_) & ~sample(road, px_, pz_)
    shore = (sample(h, px_, pz_) < sea + 3.0) & (sample(h, px_, pz_) > sea + 0.3)
    pk = ((near_road & (rng.random(px_.size) < 0.12)) | (shore & (rng.random(px_.size) < 0.25))) & sample(~poi_mask, px_, pz_)
    py_ = height(px_[pk], pz_[pk])
    for x, y, z in zip(px_[pk], py_, pz_[pk]):
        records.append((kind_index["pebbles_0"], x, y - 0.08, z, rng.uniform(0, math.tau), rng.uniform(0.5, 1.2)))

    arr = np.array(records, dtype="<f4")
    arr.tofile(os.path.join(WORLD, "scatter.bin"))
    counts = {k: int((arr[:, 0] == i).sum()) for i, k in enumerate(kinds)}
    info = {"record": ["kind", "x", "y", "z", "yaw", "scale"], "kinds": kinds,
            "category": {k: ("rock" if k in ROCKS else "tree") for k in kinds}, "counts": counts,
            "trees": n_trees, "total": len(records)}
    with open(os.path.join(WORLD, "scatter.json"), "w", encoding="utf-8") as f:
        json.dump(info, f, indent=1)
    print("scatter: %d trees, %d rocks in %.1fs" % (n_trees, len(records) - n_trees, time.time() - t0))
    for k, c in counts.items():
        print("  %-10s %6d" % (k, c))


if __name__ == "__main__":
    sys.exit(main())
