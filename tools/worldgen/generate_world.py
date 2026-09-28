#!/usr/bin/env python3
"""Procedural Samurai - open world generator.

Builds the island heightmap (with a stratovolcano inspired by Mt. Yotei,
western ridges, golden plains, a lake and coastal cliffs), runs hydraulic
+ thermal erosion, classifies biomes, places points of interest, carves
roads between them and writes everything Godot needs:

  assets/world/height.f32   raw little-endian float32 heights (N*N, meters)
  assets/world/normal.png   world-space terrain normals (RGB)
  assets/world/splat.png    R meadow grass, G golden pampas, B dirt/road, A forest floor
  assets/world/veg.png      R tree density, G tree type, B flowers, A grass height
  assets/world/world.json   metadata, POIs, roads, lakes, regions, spawn
  assets/world/map.png      painted parchment map for the in-game map screen

Usage: python3 tools/worldgen/generate_world.py [--seed 1337] [--fast]
"""
import argparse
import heapq
import json
import math
import os
import sys
import time

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from wnoise import FBM, LatticeNoise, smoothstep, lerp, bilinear  # noqa: E402
import erosion  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "world")

N = 1024
SPACING = 2.0
HALF = (N - 1) / 2.0
SEA_LEVEL = 0.0

VOLCANO = (70.0, -420.0)
LAKE = {"center": (-430.0, 330.0), "radius": 115.0, "level": 17.0, "name": "Lago Kagami"}

TREE_PINE, TREE_MAPLE, TREE_GINKGO, TREE_BIRCH, TREE_BAMBOO, TREE_SAKURA = 0, 1, 2, 3, 4, 5
TREE_CODES = {TREE_PINE: 16, TREE_MAPLE: 58, TREE_GINKGO: 100, TREE_BIRCH: 142, TREE_BAMBOO: 184, TREE_SAKURA: 226}


def world_coords():
    idx = (np.arange(N) - HALF) * SPACING
    X, Z = np.meshgrid(idx, idx)  # X varies along columns, Z along rows
    return X, Z


def to_px(x, z):
    return x / SPACING + HALF, z / SPACING + HALF


def to_world(px, py):
    return (px - HALF) * SPACING, (py - HALF) * SPACING


# ---------------------------------------------------------------------------
# Height field
# ---------------------------------------------------------------------------

def build_height(seed):
    t0 = time.time()
    X, Z = world_coords()
    warp_a = FBM(seed + 1, octaves=4)
    warp_b = FBM(seed + 2, octaves=4)
    hills_n = FBM(seed + 3, octaves=7, gain=0.48)
    ridge_n = FBM(seed + 4, octaves=6, gain=0.5)
    detail_n = FBM(seed + 5, octaves=5, gain=0.55)
    zone_n = FBM(seed + 6, octaves=3)
    coast_n = FBM(seed + 7, octaves=5)

    # --- island mask with a warped coastline --------------------------------
    wx = X + 190.0 * warp_a(X / 650.0, Z / 650.0) + 40.0 * warp_a(X / 150.0 + 70.0, Z / 150.0)
    wz = Z + 190.0 * warp_b(X / 650.0 + 13.0, Z / 650.0 + 7.0) + 40.0 * warp_b(X / 150.0, Z / 150.0 + 70.0)
    ang = np.arctan2(wz, wx)
    radius_mod = 1.0 + 0.09 * np.sin(ang * 3.0 + 0.6) + 0.06 * np.sin(ang * 5.0 + 2.1) + 0.035 * np.sin(ang * 9.0 + 1.3)
    r = np.sqrt((wx / 915.0) ** 2 + (wz / 880.0) ** 2) / radius_mod
    land = smoothstep(1.0, 0.80, r)
    cliffy = smoothstep(0.05, 0.4, coast_n(X / 500.0 + 3.0, Z / 500.0))
    cliffy *= 1.0 - smoothstep(150.0, 500.0, Z)  # the southern coast is all beaches
    inland = lerp(smoothstep(1.0, 0.58, r) ** 0.8, smoothstep(1.0, 0.93, r), cliffy)

    # --- rolling hills + central plains -------------------------------------
    hills = hills_n(X / 430.0, Z / 430.0)
    small = detail_n(X / 90.0, Z / 90.0)
    plains = smoothstep(0.35, -0.15, zone_n(X / 900.0, Z / 900.0))  # 1 = flat plains
    plains *= smoothstep(-700, -150, Z)  # plains only south of the volcano
    base = 22.0 + 26.0 * hills * (1.0 - 0.6 * plains) + 5.0 * small
    base = 0.5 * (base + 4.0 + np.sqrt((base - 4.0) ** 2 + 36.0))  # smooth max(base, 4)
    h = 2.2 + (base - 2.2) * inland

    # --- western ridges -------------------------------------------------------
    west = smoothstep(-80.0, -520.0, X + 0.25 * Z) * smoothstep(-900, -550, Z)
    ridges = ridge_n.ridged(X / 300.0, Z / 300.0, sharpness=2.2)
    h += west * (ridges * 175.0 + 12.0)

    # --- eastern highlands (gentler) -----------------------------------------
    east = smoothstep(250.0, 650.0, X) * smoothstep(650, 100, Z)
    h += east * (ridge_n.ridged(X / 210.0 + 40.0, Z / 210.0, sharpness=1.6) * 70.0)

    # --- the stratovolcano (Ezo-Fuji) ----------------------------------------
    vx, vz = VOLCANO
    dxv = X - vx
    dzv = Z - vz
    dist = np.sqrt(dxv * dxv + dzv * dzv)
    R = 610.0
    H = 385.0
    d = dist / R
    theta = np.arctan2(dzv, dxv)
    gully = ridge_n.ridged(theta * 5.0 + 50.0, d * 3.0, sharpness=1.5)
    prof = np.clip(1.0 - d, 0.0, 1.0) ** 1.65 * (1.0 + 0.12 * d)
    volcano = H * prof * (1.0 - 0.07 * gully * smoothstep(0.08, 0.5, d))
    dc = 0.075
    rim = H * (1.0 - dc) ** 1.65 * (1.0 + 0.12 * dc)
    crater = rim - 42.0 * np.clip(1.0 - (d / dc) ** 2, 0.0, 1.0) ** 1.2
    volcano = np.where(d < dc, crater, volcano)
    base_blend = smoothstep(1.05, 0.55, d)
    h = h * (1.0 - 0.6 * base_blend) + volcano

    # --- coastline: beaches (south) and cliffs (east / north-west) ----------
    sea_floor = -30.0 + 7.0 * coast_n(X / 200.0, Z / 200.0) - 12.0 * smoothstep(1.0, 1.25, r)
    shore_soft = smoothstep(1.075, 0.985, r)
    shore_hard = smoothstep(1.02, 1.0, r)
    t = lerp(shore_soft, shore_hard, cliffy)
    h = lerp(sea_floor, h, t)

    print("  base height built in %.1fs (min %.1f max %.1f)" % (time.time() - t0, h.min(), h.max()))
    return h, land


def carve_lake(h):
    X, Z = world_coords()
    cx, cz = LAKE["center"]
    R = LAKE["radius"]
    lvl = LAKE["level"]
    wob = LatticeNoise(77)
    ang = np.arctan2(Z - cz, X - cx)
    d = np.sqrt((X - cx) ** 2 + ((Z - cz) * 1.25) ** 2) / R
    d = d * (1.0 + 0.1 * wob(np.cos(ang) * 2.0 + 5.0, np.sin(ang) * 2.0 + 5.0))
    # a gentle basin plain around the lake guarantees a closed shoreline
    plain = lvl + 1.6 + np.maximum(d - 1.0, 0.0) * 5.0
    w_plain = smoothstep(2.7, 1.25, d)
    h = lerp(h, plain, w_plain)
    bowl = lvl - 7.5 * np.clip(1.0 - d * d, 0.0, 1.0) - 0.6
    w_bowl = smoothstep(1.12, 0.92, d)
    h = lerp(h, np.minimum(h, bowl), w_bowl)
    return h


def gradient(h):
    gz, gx = np.gradient(h, SPACING)
    return gx, gz


def slope_deg(h):
    gx, gz = gradient(h)
    return np.degrees(np.arctan(np.sqrt(gx * gx + gz * gz)))


def normals(h):
    gx, gz = gradient(h)
    n = np.stack([-gx, np.ones_like(h), -gz], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n


# ---------------------------------------------------------------------------
# Points of interest
# ---------------------------------------------------------------------------

POI_NAMES = {
    "village": ["Vila Kawabata", "Vila Hamanaka", "Vila Yamakage", "Vila Tsukimi"],
    "camp": ["Forte do Corvo", "Acampamento Kurokami", "Covil dos Ronin", "Posto Akaishi",
             "Paliçada Oni", "Acampamento Sabimura", "Refúgio dos Bandidos", "Forte Takeda",
             "Acampamento da Lua Rubra", "Posto do Desfiladeiro", "Covil de Onibi", "Guarnição Hebi"],
    "shrine": ["Santuário Inari", "Santuário do Vento", "Santuário da Raposa", "Santuário Hachiman",
               "Santuário da Montanha", "Santuário do Mar"],
    "onsen": ["Fonte Termal Yuzu", "Fonte Termal do Vulcão"],
    "temple": ["Templo Shiragiku"],
    "haiku": ["Mirante das Nuvens", "Pedra do Poeta", "Falésia do Luar", "Colina Silenciosa"],
    "landmark": ["Árvore Sagrada"],
}


class Placer:
    def __init__(self, h, slope, land, flow, seed):
        self.h = h
        self.slope = slope
        self.land = land
        self.flow = flow
        self.rng = np.random.default_rng(seed)
        self.pois = []

    def _dist_ok(self, x, z, min_d):
        for p in self.pois:
            md = max(min_d, p.get("_keepout", 0.0))
            if (p["x"] - x) ** 2 + (p["z"] - z) ** 2 < md * md:
                return False
        return True

    def area_stats(self, x, z, r):
        px, py = to_px(x, z)
        rr = int(r / SPACING) + 1
        x0, x1 = int(px) - rr, int(px) + rr + 1
        y0, y1 = int(py) - rr, int(py) + rr + 1
        if x0 < 2 or y0 < 2 or x1 > N - 2 or y1 > N - 2:
            return None
        hh = self.h[y0:y1, x0:x1]
        ss = self.slope[y0:y1, x0:x1]
        return float(hh.mean()), float(hh.max() - hh.min()), float(ss.mean()), float(hh.min())

    def place(self, kind, count, radius, min_dist, score_fn, tries=6000, keepout=None):
        placed = 0
        cand = []
        for _ in range(tries):
            px = self.rng.uniform(40, N - 40)
            py = self.rng.uniform(40, N - 40)
            x, z = to_world(px, py)
            st = self.area_stats(x, z, radius)
            if st is None:
                continue
            mean_h, rng_h, mean_s, min_h = st
            if min_h < SEA_LEVEL + 3.0:
                continue
            lx, lz = LAKE["center"]
            if math.hypot(x - lx, (z - lz) * 1.25) < LAKE["radius"] * 1.35 + radius:
                continue
            s = score_fn(x, z, mean_h, rng_h, mean_s)
            if s is None:
                continue
            cand.append((s, x, z, mean_h))
        cand.sort(key=lambda c: -c[0])
        names = list(POI_NAMES.get(kind, []))
        for s, x, z, mh in cand:
            if placed >= count:
                break
            if not self._dist_ok(x, z, min_dist):
                continue
            name = names[placed % len(names)] if names else "%s %d" % (kind, placed + 1)
            self.pois.append({"id": "%s_%d" % (kind, placed), "type": kind, "name": name,
                              "x": round(float(x), 2), "z": round(float(z), 2),
                              "radius": radius, "_keepout": keepout or 0.0})
            placed += 1
        print("  placed %d/%d %s" % (placed, count, kind))


def dist_to(x, z, pt):
    return math.hypot(x - pt[0], z - pt[1])


def place_pois(h, slope, land, flow, seed):
    P = Placer(h, slope, land, flow, seed + 100)
    lake_c = LAKE["center"]

    def flatness(rng_h, mean_s):
        return -rng_h * 0.6 - mean_s * 0.5

    # landmark tree on a gentle rise in the golden plains (player start)
    P.place("landmark", 1, 10, 0, lambda x, z, mh, rh, ms: (
        None if not (-150 < x < 250 and 150 < z < 420 and 18 < mh < 70) else
        mh * 0.6 + flatness(rh, ms) - abs(x - 60) * 0.02), keepout=180)
    # temple on a hill
    P.place("temple", 1, 26, 300, lambda x, z, mh, rh, ms: (
        None if not (40 < mh < 120 and ms < 14 and dist_to(x, z, VOLCANO) > 520) else
        mh * 0.4 + flatness(rh, ms) * 2.0), keepout=160)
    # villages near water, low and flat
    P.place("village", 3, 32, 380, lambda x, z, mh, rh, ms: (
        None if not (4 < mh < 50 and ms < 12) else
        flatness(rh, ms) * 2.5 - min(dist_to(x, z, lake_c), 700) * 0.01 - mh * 0.05), keepout=150)
    # onsen on the volcano skirts
    P.place("onsen", 2, 9, 280, lambda x, z, mh, rh, ms: (
        None if not (70 < mh < 230 and ms < 26) else flatness(rh, ms) - abs(dist_to(x, z, VOLCANO) - 380) * 0.02))
    # enemy camps spread everywhere
    P.place("camp", 11, 22, 230, lambda x, z, mh, rh, ms: (
        None if not (6 < mh < 200 and ms < 15) else
        flatness(rh, ms) + P.rng.uniform(0, 6)), keepout=120)
    # shrines on high local spots
    P.place("shrine", 6, 8, 200, lambda x, z, mh, rh, ms: (
        None if not (12 < mh < 240 and ms < 24) else mh * 0.05 + P.rng.uniform(0, 3) - rh * 0.3))
    # haiku spots: high with a view (steep surroundings are fine)
    P.place("haiku", 4, 5, 300, lambda x, z, mh, rh, ms: (
        None if not (40 < mh < 260) else mh * 0.08 + ms * 0.05 - rh * 0.2 + P.rng.uniform(0, 4)))
    for p in P.pois:
        p.pop("_keepout", None)
    return P.pois


def flatten_pois(h, pois):
    X, Z = world_coords()
    for p in pois:
        r = p["radius"]
        px, py = to_px(p["x"], p["z"])
        rr = int(r * 2.2 / SPACING) + 2
        x0, x1 = max(0, int(px) - rr), min(N, int(px) + rr + 1)
        y0, y1 = max(0, int(py) - rr), min(N, int(py) + rr + 1)
        sub = h[y0:y1, x0:x1]
        dx = X[y0:y1, x0:x1] - p["x"]
        dz = Z[y0:y1, x0:x1] - p["z"]
        d = np.sqrt(dx * dx + dz * dz)
        inner = d < r
        target = float(np.median(sub[inner])) if np.any(inner) else float(sub.mean())
        if p["type"] == "haiku":
            target = float(sub[inner].max()) if np.any(inner) else target
        w = smoothstep(r * 2.1, r * 0.95, d)
        sub[:] = lerp(sub, target, w)
        p["y"] = round(target, 2)
    return h


# ---------------------------------------------------------------------------
# Roads (A* over a coarse grid, then carved into the heightmap)
# ---------------------------------------------------------------------------

def astar(cost, start, goal):
    H, W = cost.shape
    sx, sy = start
    gx, gy = goal
    openh = [(0.0, sx, sy)]
    g = {(sx, sy): 0.0}
    came = {}
    nb = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
          (-1, -1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (1, 1, 1.414)]
    while openh:
        f, x, y = heapq.heappop(openh)
        if (x, y) == (gx, gy):
            break
        gc = g[(x, y)]
        for dx, dy, dl in nb:
            nx, ny = x + dx, y + dy
            if nx < 0 or ny < 0 or nx >= W or ny >= H:
                continue
            c = cost[ny, nx]
            if not np.isfinite(c):
                continue
            ng = gc + dl * c
            if ng < g.get((nx, ny), 1e18):
                g[(nx, ny)] = ng
                came[(nx, ny)] = (x, y)
                hh = math.hypot(gx - nx, gy - ny)
                heapq.heappush(openh, (ng + hh, nx, ny))
    if (gx, gy) not in came and (gx, gy) != (sx, sy):
        return None
    path = [(gx, gy)]
    while path[-1] != (sx, sy):
        path.append(came[path[-1]])
    path.reverse()
    return path


def chaikin(pts, iters=3):
    pts = np.asarray(pts, dtype=np.float64)
    for _ in range(iters):
        if len(pts) < 3:
            break
        q = 0.75 * pts[:-1] + 0.25 * pts[1:]
        r = 0.25 * pts[:-1] + 0.75 * pts[1:]
        inter = np.empty((2 * len(q), 2))
        inter[0::2] = q
        inter[1::2] = r
        pts = np.vstack([pts[:1], inter, pts[-1:]])
    return pts


def build_roads(h, slope, pois, seed):
    C = 4  # coarse cell = 4 px = 8 m
    hc = h[::C, ::C]
    sc = slope[::C, ::C]
    cost = 1.0 + (sc / 10.0) ** 2 * 3.0
    cost[hc < SEA_LEVEL + 1.5] = np.inf
    cost[sc > 32] = np.inf
    # avoid lake
    X, Z = world_coords()
    lx, lz = LAKE["center"]
    lake_mask = (np.sqrt((X - lx) ** 2 + ((Z - lz) * 1.25) ** 2) < LAKE["radius"] * 1.1)[::C, ::C]
    cost[lake_mask] = np.inf
    nodes = [p for p in pois if p["type"] in ("village", "camp", "temple", "shrine", "landmark", "onsen")]
    # minimum spanning tree on euclidean distance + a few extra links
    import itertools
    edges = []
    for a, b in itertools.combinations(range(len(nodes)), 2):
        d = math.hypot(nodes[a]["x"] - nodes[b]["x"], nodes[a]["z"] - nodes[b]["z"])
        edges.append((d, a, b))
    edges.sort()
    parent = list(range(len(nodes)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    chosen = []
    for d, a, b in edges:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
            chosen.append((a, b))
    rng = np.random.default_rng(seed + 55)
    extra = [e for e in edges[: len(edges) // 6] if (e[1], e[2]) not in chosen]
    for d, a, b in extra[:4]:
        chosen.append((a, b))
    roads = []
    road_cost = cost.copy()
    for a, b in chosen:
        pa = nodes[a]
        pb = nodes[b]
        sa = tuple(int(v / C) for v in to_px(pa["x"], pa["z"]))
        sb = tuple(int(v / C) for v in to_px(pb["x"], pb["z"]))
        road_cost[sa[1], sa[0]] = 1.0
        road_cost[sb[1], sb[0]] = 1.0
        path = astar(road_cost, sa, sb)
        if path is None:
            continue
        for (x, y) in path:
            road_cost[y, x] = min(road_cost[y, x], 0.45)  # reuse existing roads
        pts = np.array([[(x + 0.5) * C, (y + 0.5) * C] for x, y in path], dtype=np.float64)
        # simplify (every other point) then smooth
        pts = pts[::2] if len(pts) > 6 else pts
        pts = chaikin(pts, 3)
        world = [(float((px - HALF) * SPACING), float((py - HALF) * SPACING)) for px, py in pts]
        roads.append({"from": pa["id"], "to": pb["id"], "points": world})
    print("  %d roads" % len(roads))
    return roads


def carve_roads(h, roads, width=3.2):
    mask = np.zeros_like(h, dtype=bool)
    target = np.full_like(h, np.nan)
    for rd in roads:
        pts = np.array(rd["points"])
        # dense resample along the polyline
        seg = np.diff(pts, axis=0)
        lens = np.hypot(seg[:, 0], seg[:, 1])
        total = lens.sum()
        n = max(2, int(total / 1.0))
        cum = np.concatenate([[0], np.cumsum(lens)])
        s = np.linspace(0, total, n)
        xs = np.interp(s, cum, pts[:, 0])
        zs = np.interp(s, cum, pts[:, 1])
        px, py = to_px(xs, zs)
        hs = bilinear(h, px, py)
        hs = ndimage.uniform_filter1d(hs, size=31, mode="nearest")
        hs = ndimage.uniform_filter1d(hs, size=15, mode="nearest")
        ix = np.clip(np.round(px).astype(int), 0, N - 1)
        iy = np.clip(np.round(py).astype(int), 0, N - 1)
        mask[iy, ix] = True
        target[iy, ix] = hs
        rd["length"] = round(float(total), 1)
    dist, (iy, ix) = ndimage.distance_transform_edt(~mask, return_indices=True)
    dist_m = dist * SPACING
    t = target[iy, ix]
    w = smoothstep(width + 7.0, width, dist_m)
    h = np.where(np.isfinite(t), lerp(h, t, w), h)
    road_paint = smoothstep(width + 1.6, width * 0.35, dist_m)
    return h, road_paint, dist_m


# ---------------------------------------------------------------------------
# Biomes
# ---------------------------------------------------------------------------

def build_biomes(h, slope, flow, land, road_paint, road_dist, pois, seed):
    X, Z = world_coords()
    forest_n = FBM(seed + 20, octaves=5)
    field_n = FBM(seed + 21, octaves=4)
    type_n = FBM(seed + 22, octaves=3)
    flower_n = FBM(seed + 23, octaves=4)
    bamboo_n = FBM(seed + 24, octaves=3)
    tall_n = FBM(seed + 25, octaves=3)

    above = h > SEA_LEVEL + 0.8
    sand = smoothstep(3.2, 1.2, h) * above
    wet = np.log1p(flow) / max(np.log1p(flow).max(), 1e-6)
    wet = ndimage.gaussian_filter(wet, 3.0)
    lx, lz = LAKE["center"]
    lake_d = np.sqrt((X - lx) ** 2 + ((Z - lz) * 1.25) ** 2) / LAKE["radius"]

    # distance to POIs (keep them clear of trees)
    poi_clear = np.zeros_like(h)
    for p in pois:
        d = np.sqrt((X - p["x"]) ** 2 + (Z - p["z"]) ** 2)
        poi_clear = np.maximum(poi_clear, smoothstep(p["radius"] * 1.6, p["radius"] * 0.8, d))

    # --- forest -----------------------------------------------------------------
    fnoise = forest_n(X / 260.0, Z / 260.0) + 0.35 * forest_n(X / 70.0 + 9, Z / 70.0)
    forest = smoothstep(-0.02, 0.32, fnoise + wet * 0.35)
    forest *= 1.0 - smoothstep(30.0, 40.0, slope)
    forest *= 1.0 - smoothstep(265.0, 300.0, h)
    forest *= above * (1.0 - sand)
    forest *= 1.0 - poi_clear
    forest *= smoothstep(4.0, 14.0, road_dist * 1.0)
    forest *= 1.0 - smoothstep(1.35, 1.0, lake_d)
    # the central golden plains stay open
    fields = smoothstep(-0.2, 0.2, field_n(X / 380.0, Z / 380.0)) * smoothstep(6.0, 20.0, h) * smoothstep(175.0, 125.0, h)
    fields *= 1.0 - smoothstep(18.0, 26.0, slope)
    forest *= 1.0 - fields * 0.92

    # --- tree species -------------------------------------------------------------
    tsel = type_n(X / 330.0, Z / 330.0)
    ttype = np.full(h.shape, TREE_MAPLE, dtype=np.int32)
    ttype[tsel > 0.28] = TREE_GINKGO
    ttype[tsel < -0.3] = TREE_PINE
    coastal = smoothstep(26.0, 8.0, h)
    ttype[coastal > 0.5] = TREE_PINE
    ttype[h > 150.0] = TREE_BIRCH
    ttype[(h > 150.0) & (tsel < 0.0)] = TREE_PINE
    bamboo = (bamboo_n(X / 160.0, Z / 160.0) > 0.42) & (h < 90) & (h > 6) & (slope < 22)
    ttype[bamboo] = TREE_BAMBOO
    sak = (type_n(X / 90.0 + 30, Z / 90.0) > 0.52) & (h < 120) & (h > 8)
    ttype[sak & ~bamboo] = TREE_SAKURA
    forest = np.where(bamboo, np.maximum(forest, 0.75) * (1 - poi_clear) * smoothstep(3.0, 10.0, road_dist), forest)

    # --- ground cover ---------------------------------------------------------
    rocky = smoothstep(33.0, 45.0, slope)
    snow = smoothstep(255.0, 300.0, h + 20.0 * forest_n(X / 60.0, Z / 60.0))
    alpine = smoothstep(185.0, 240.0, h)
    grass_cover = above * (1 - sand) * (1 - rocky) * (1 - snow)
    pampas = fields * grass_cover * (1.0 - alpine) * smoothstep(-0.1, 0.3, field_n(X / 120.0 + 5, Z / 120.0) + 0.3)
    pampas = np.clip(pampas * 1.5, 0, 1)
    meadow = grass_cover * (1.0 - pampas) * (1.0 - forest * 0.55)
    forest_floor = grass_cover * forest
    road = road_paint * above
    meadow *= 1 - road
    pampas *= 1 - road
    forest_floor *= 1 - road

    # POI grounds are trampled dirt near the center
    for p in pois:
        if p["type"] in ("camp", "village", "temple"):
            d = np.sqrt((X - p["x"]) ** 2 + (Z - p["z"]) ** 2)
            dirt = smoothstep(p["radius"] * 0.95, p["radius"] * 0.35, d) * (0.55 if p["type"] != "camp" else 0.85)
            road = np.maximum(road, dirt)
            meadow *= 1 - dirt * 0.8
            pampas *= 1 - dirt

    # --- flowers ------------------------------------------------------------
    fl = smoothstep(0.25, 0.55, flower_n(X / 90.0, Z / 90.0))
    fl_road = smoothstep(14.0, 5.0, road_dist) * smoothstep(0.1, 0.35, flower_n(X / 30.0, Z / 30.0))
    flowers = np.clip(fl + fl_road, 0, 1) * grass_cover * (1 - road) * (1 - forest * 0.7) * (1 - alpine)

    tall = np.clip(0.55 + 0.45 * tall_n(X / 60.0, Z / 60.0), 0, 1)
    tall = tall * (1 - alpine * 0.7)

    splat = np.stack([meadow, pampas, road, forest_floor], axis=-1)
    tree_code = np.vectorize(lambda t: TREE_CODES[int(t)])(ttype).astype(np.float64) / 255.0
    veg = np.stack([forest * grass_cover, tree_code, flowers, tall], axis=-1)
    stats = {
        "forest_frac": float((forest > 0.4).mean()),
        "pampas_frac": float((pampas > 0.4).mean()),
        "meadow_frac": float((meadow > 0.4).mean()),
        "snow_frac": float((snow > 0.5).mean()),
    }
    print("  biome coverage:", {k: round(v, 3) for k, v in stats.items()})
    return splat, veg, ttype


REGIONS = [
    {"name": "Planícies Douradas", "x": 40.0, "z": 250.0},
    {"name": "Encostas de Ezo-Fuji", "x": 70.0, "z": -420.0},
    {"name": "Bosque Carmesim", "x": -380.0, "z": -120.0},
    {"name": "Lago Kagami", "x": -430.0, "z": 330.0},
    {"name": "Costa dos Pinheiros", "x": 520.0, "z": 520.0},
    {"name": "Colinas do Leste", "x": 560.0, "z": -60.0},
    {"name": "Cordilheira Oeste", "x": -620.0, "z": -300.0},
    {"name": "Praia de Shirahama", "x": 60.0, "z": 760.0},
]


# ---------------------------------------------------------------------------
# Painted map
# ---------------------------------------------------------------------------

def paint_map(h, splat, veg, roads, pois, size=1536):
    rng = np.random.default_rng(5)
    hs = ndimage.zoom(h, size / N, order=1)
    sp = ndimage.zoom(splat, (size / N, size / N, 1), order=1)
    vg = ndimage.zoom(veg, (size / N, size / N, 1), order=1)
    gz, gx = np.gradient(hs, SPACING * N / size)
    light = np.array([-0.6, 0.7, -0.4])
    light /= np.linalg.norm(light)
    nrm = np.stack([-gx, np.ones_like(hs), -gz], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    shade = np.clip((nrm * light).sum(-1), 0, 1)
    paper = np.array([0.93, 0.87, 0.74])
    grain = ndimage.gaussian_filter(rng.random((size, size)), 1.2)
    grain2 = ndimage.gaussian_filter(rng.random((size // 8, size // 8)), 2.0)
    grain2 = ndimage.zoom(grain2, 8, order=1)[:size, :size]
    base = paper[None, None, :] * (0.92 + 0.08 * grain[..., None]) * (0.94 + 0.1 * grain2[..., None])
    land = hs > SEA_LEVEL
    img = base.copy()
    # sea: ink wash that deepens with depth
    depth = np.clip(-hs / 30.0, 0, 1)
    sea_col = np.array([0.55, 0.62, 0.62])
    img = np.where(land[..., None], img, lerp(img, sea_col[None, None, :] * (0.95 + 0.05 * grain[..., None]), (0.25 + 0.45 * depth)[..., None]))
    # land tint by biome
    meadow_c = np.array([0.72, 0.74, 0.55])
    pampas_c = np.array([0.86, 0.74, 0.47])
    forest_c = np.array([0.62, 0.42, 0.33])
    snow_c = np.array([0.97, 0.96, 0.93])
    tint = img * 1.0
    tint = lerp(tint, meadow_c, (sp[..., 0] * 0.45)[..., None])
    tint = lerp(tint, pampas_c, (sp[..., 1] * 0.55)[..., None])
    tint = lerp(tint, forest_c, (vg[..., 0] * 0.55)[..., None])
    tint = lerp(tint, snow_c, smoothstep(250, 300, hs)[..., None] * 0.8)
    img = np.where(land[..., None], tint, img)
    # hill shading as ink wash
    ink = np.array([0.18, 0.15, 0.13])
    shading = (1.0 - shade) * smoothstep(0.0, 4.0, hs)
    img = lerp(img, ink, (shading * 0.55)[..., None])
    # contour lines every 40 m
    cont = np.abs(((hs / 40.0) % 1.0) - 0.5)
    cont_line = smoothstep(0.47, 0.5, cont) * land
    img = lerp(img, ink, (cont_line * 0.18)[..., None])
    # coastline ink stroke
    coast = ndimage.binary_dilation(land, iterations=2) & ~ndimage.binary_erosion(land, iterations=1)
    coast = ndimage.gaussian_filter(coast.astype(np.float64), 0.8)
    img = lerp(img, ink, np.clip(coast * 1.4, 0, 0.85)[..., None])
    # roads: dashed dark red lines
    from PIL import ImageDraw
    pil = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    dr = ImageDraw.Draw(pil)
    sc = size / N
    for rd in roads:
        pts = [((x / SPACING + HALF) * sc, (z / SPACING + HALF) * sc) for x, z in rd["points"]]
        for i in range(0, len(pts) - 1):
            if (i // 2) % 2 == 0:
                dr.line([pts[i], pts[i + 1]], fill=(120, 52, 38), width=3)
    return pil


# ---------------------------------------------------------------------------

def save_png(arr, path, mode):
    a = np.clip(arr, 0, 1)
    Image.fromarray((a * 255.0 + 0.5).astype(np.uint8), mode).save(path, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1337)
    ap.add_argument("--fast", action="store_true", help="less erosion (for quick iteration)")
    ap.add_argument("--preview", default="", help="optional folder for debug previews")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    t0 = time.time()
    print("[1/7] height field")
    h, land = build_height(args.seed)
    h = carve_lake(h)
    print("[2/7] erosion")
    land_mask = (h > SEA_LEVEL + 1.0).astype(np.float64)
    h = erosion.thermal(h, talus_deg=48.0, iterations=12, rate=0.4)
    iters = 2 if args.fast else 7
    h_pre = h.copy()
    slope_pre = slope_deg(h_pre)
    h, flow = erosion.hydraulic(h, iterations=iters, droplets=120_000, steps=64, seed=args.seed,
                                mask=land_mask, erode_k=0.2, deposit_k=0.3, brush_radius=3)
    h = ndimage.gaussian_filter(h, 0.9) * 0.6 + h * 0.4
    # full erosion on mountains, a light touch on plains and none on the shoreline
    w = np.clip(smoothstep(35.0, 130.0, h_pre) + smoothstep(8.0, 24.0, slope_pre), 0.0, 1.0) * 0.8 + 0.2
    w *= smoothstep(1.5, 10.0, h_pre)
    h = lerp(h_pre, h, w)
    h = erosion.thermal(h, talus_deg=42.0, iterations=18, rate=0.35)
    h = carve_lake(h)
    slope = slope_deg(h)
    print("[3/7] points of interest")
    pois = place_pois(h, slope, land, flow, args.seed)
    h = flatten_pois(h, pois)
    slope = slope_deg(h)
    print("[4/7] roads")
    roads = build_roads(h, slope, pois, args.seed)
    h, road_paint, road_dist = carve_roads(h, roads)
    h = flatten_pois(h, pois)
    h = ndimage.gaussian_filter(h, 0.6) * 0.5 + h * 0.5
    slope = slope_deg(h)
    print("[5/7] biomes")
    splat, veg, ttype = build_biomes(h, slope, flow, land, road_paint, road_dist, pois, args.seed)

    print("[6/7] writing files")
    h32 = h.astype("<f4")
    h32.tofile(os.path.join(OUT, "height.f32"))
    nrm = normals(ndimage.gaussian_filter(h, 0.7))
    enc = np.stack([nrm[..., 0] * 0.5 + 0.5, nrm[..., 2] * 0.5 + 0.5, nrm[..., 1]], -1)
    save_png(enc, os.path.join(OUT, "normal.png"), "RGB")
    save_png(splat, os.path.join(OUT, "splat.png"), "RGBA")
    save_png(veg, os.path.join(OUT, "veg.png"), "RGBA")

    # spawn next to the landmark tree
    lm = next(p for p in pois if p["type"] == "landmark")
    spawn = {"x": lm["x"] + 9.0, "z": lm["z"] + 14.0}
    for p in pois:
        p["y"] = round(float(bilinear(h, np.array([to_px(p["x"], p["z"])[0]]), np.array([to_px(p["x"], p["z"])[1]]))[0]), 2)
    meta = {
        "version": 1,
        "seed": args.seed,
        "size": N,
        "spacing": SPACING,
        "half_extent": HALF * SPACING,
        "sea_level": SEA_LEVEL,
        "min_height": round(float(h.min()), 3),
        "max_height": round(float(h.max()), 3),
        "volcano": {"x": VOLCANO[0], "z": VOLCANO[1], "name": "Ezo-Fuji"},
        "lakes": [{"x": LAKE["center"][0], "z": LAKE["center"][1], "radius": LAKE["radius"],
                   "radius_z": LAKE["radius"] / 1.25, "level": LAKE["level"], "name": LAKE["name"]}],
        "regions": REGIONS,
        "spawn": spawn,
        "tree_types": {"pine": TREE_CODES[TREE_PINE], "maple": TREE_CODES[TREE_MAPLE],
                       "ginkgo": TREE_CODES[TREE_GINKGO], "birch": TREE_CODES[TREE_BIRCH],
                       "bamboo": TREE_CODES[TREE_BAMBOO], "sakura": TREE_CODES[TREE_SAKURA]},
        "pois": pois,
        "roads": [{"from": r["from"], "to": r["to"], "length": r.get("length", 0),
                   "points": [[round(x, 1), round(z, 1)] for x, z in r["points"]]} for r in roads],
    }
    with open(os.path.join(OUT, "world.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("[7/7] painted map")
    paint_map(h, splat, veg, roads, pois).save(os.path.join(OUT, "map.png"), optimize=True)

    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        write_previews(h, splat, veg, ttype, pois, roads, args.preview)
    print("done in %.1fs  (height %.1f .. %.1f)" % (time.time() - t0, h.min(), h.max()))


def write_previews(h, splat, veg, ttype, pois, roads, folder):
    nrm = normals(h)
    light = np.array([-0.5, 0.75, -0.45])
    light /= np.linalg.norm(light)
    shade = np.clip((nrm * light).sum(-1), 0, 1)
    col = np.zeros(h.shape + (3,))
    sea = h <= SEA_LEVEL
    col[...] = np.array([0.45, 0.55, 0.3])
    col = lerp(col, np.array([0.85, 0.7, 0.35]), splat[..., 1:2])
    col = lerp(col, np.array([0.5, 0.4, 0.3]), splat[..., 2:3])
    col = lerp(col, np.array([0.55, 0.2, 0.12]), (veg[..., 0:1] * (ttype[..., None] == TREE_MAPLE)))
    col = lerp(col, np.array([0.8, 0.65, 0.1]), (veg[..., 0:1] * (ttype[..., None] == TREE_GINKGO)))
    col = lerp(col, np.array([0.12, 0.3, 0.18]), (veg[..., 0:1] * (ttype[..., None] == TREE_PINE)))
    col = lerp(col, np.array([0.7, 0.75, 0.7]), (veg[..., 0:1] * (ttype[..., None] == TREE_BIRCH)))
    col = lerp(col, np.array([0.35, 0.6, 0.2]), (veg[..., 0:1] * (ttype[..., None] == TREE_BAMBOO)))
    col = lerp(col, np.array([0.95, 0.7, 0.8]), (veg[..., 0:1] * (ttype[..., None] == TREE_SAKURA)))
    col = lerp(col, np.array([0.9, 0.1, 0.1]), veg[..., 2:3] * 0.5)
    col = lerp(col, np.array([0.95, 0.95, 0.97]), smoothstep(255, 300, h)[..., None])
    col = col * (0.35 + 0.75 * shade[..., None])
    col[sea] = np.array([0.1, 0.3, 0.45]) * (0.6 + 0.4 * np.clip(1 + h[sea] / 40, 0, 1))[..., None]
    X, Z = world_coords()
    lx, lz = LAKE["center"]
    lake = (np.sqrt((X - lx) ** 2 + ((Z - lz) * 1.25) ** 2) < LAKE["radius"] * 1.6) & (h < LAKE["level"])
    col[lake] = np.array([0.15, 0.38, 0.5])
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
    from PIL import ImageDraw
    dr = ImageDraw.Draw(img)
    colors = {"camp": (255, 40, 40), "village": (255, 255, 255), "shrine": (255, 140, 0), "temple": (255, 220, 0),
              "onsen": (0, 220, 255), "haiku": (200, 120, 255), "landmark": (0, 255, 0)}
    for rd in roads:
        pts = [to_px(x, z) for x, z in rd["points"]]
        dr.line(pts, fill=(90, 60, 40), width=1)
    for p in pois:
        px, py = to_px(p["x"], p["z"])
        c = colors.get(p["type"], (255, 255, 255))
        dr.ellipse([px - 5, py - 5, px + 5, py + 5], outline=c, width=2)
    img.save(os.path.join(folder, "preview_color.png"))
    hs = (shade * 255).astype(np.uint8)
    Image.fromarray(hs).save(os.path.join(folder, "preview_hillshade.png"))


if __name__ == "__main__":
    main()
