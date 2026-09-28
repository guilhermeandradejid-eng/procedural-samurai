"""Procedural trees: recursive branching + alpha leaf cards, three LODs each.

Vertex colours (read by the foliage shader):
  R = sway weight (0 at the trunk base .. 1 at the outer leaves)
  G = random phase per branch / card
  B = 1 on leaf cards, 0 on bark
  A = crown occlusion (0 deep inside the crown .. 1 on the outside)
Leaf cards get spherical normals around the crown centre for soft volume.
"""
import json
import math
import os
import zlib

from mathutils import Vector

import blib
from blib import Builder, G

SPECIES = {
    "maple": {"bark": "bark_dark", "leaves": "leaves_maple", "trunk_h": 2.3, "height": 6.8, "trunk_r": 0.2,
              "lean": 0.12, "b1": 7, "b1_angle": 52, "b1_len": 3.2, "b1_start": 0.55, "b2": 4, "b2_len": 1.5,
              "up": 0.35, "cards": 95, "card": (1.15, 1.7), "crown": (3.3, 2.6), "crown_y": 4.8, "droop": 0.0},
    "ginkgo": {"bark": "bark_dark", "leaves": "leaves_ginkgo", "trunk_h": 6.0, "height": 10.5, "trunk_r": 0.24,
               "lean": 0.05, "b1": 11, "b1_angle": 62, "b1_len": 2.6, "b1_start": 0.25, "b2": 3, "b2_len": 1.1,
               "up": 0.25, "cards": 110, "card": (1.0, 1.45), "crown": (2.6, 4.0), "crown_y": 6.5, "droop": 0.0,
               "taper_crown": True},
    "pine": {"bark": "bark_pine", "leaves": "leaves_pine", "trunk_h": 7.5, "height": 9.0, "trunk_r": 0.25,
             "lean": 0.45, "b1": 7, "b1_angle": 82, "b1_len": 2.8, "b1_start": 0.35, "b2": 3, "b2_len": 1.2,
             "up": 0.05, "cards": 70, "card": (1.2, 1.7), "crown": (3.2, 2.4), "crown_y": 6.5, "droop": 0.1,
             "pads": True},
    "birch": {"bark": "bark_birch", "leaves": "leaves_birch", "trunk_h": 8.5, "height": 11.0, "trunk_r": 0.15,
              "lean": 0.06, "b1": 10, "b1_angle": 36, "b1_len": 2.3, "b1_start": 0.35, "b2": 3, "b2_len": 0.9,
              "up": 0.4, "cards": 85, "card": (0.85, 1.25), "crown": (1.9, 3.6), "crown_y": 7.2, "droop": 0.15},
    "sakura": {"bark": "bark_dark", "leaves": "leaves_sakura", "trunk_h": 1.8, "height": 5.8, "trunk_r": 0.22,
               "lean": 0.1, "b1": 6, "b1_angle": 60, "b1_len": 3.6, "b1_start": 0.75, "b2": 4, "b2_len": 1.6,
               "up": 0.15, "cards": 100, "card": (1.2, 1.75), "crown": (3.9, 2.1), "crown_y": 4.1, "droop": 0.3},
}


def sample(pts, t):
    f = t * (len(pts) - 1)
    i = min(int(f), len(pts) - 2)
    k = f - i
    return pts[i].lerp(pts[i + 1], k)


def sample_r(radii, t):
    f = t * (len(radii) - 1)
    i = min(int(f), len(radii) - 2)
    k = f - i
    return radii[i] * (1 - k) + radii[i + 1] * k


class Tree:
    def __init__(self, spec, seed):
        self.s = spec
        self.r = blib.rng(seed)
        self.branches = []  # (points, radii, level, phase)
        self.tips = []      # (position, direction, level)

    def grow(self):
        s = self.s
        r = self.r
        lean_dir = Vector((r.uniform(-1, 1), 0.0, r.uniform(-1, 1))).normalized()
        ph1 = r.uniform(0, 10)
        ph2 = r.uniform(0, 10)
        pts = []
        radii = []
        n = 9
        H = s["trunk_h"] + (s["height"] - s["trunk_h"]) * 0.45
        for i in range(n + 1):
            t = i / n
            bend = lean_dir * s["lean"] * H * (t ** 1.4)
            wob = Vector((math.sin(t * 5.0 + ph1) * 0.08, 0.0, math.cos(t * 4.0 + ph2) * 0.08)) * t
            pts.append(Vector((0.0, t * H, 0.0)) + bend + wob)
            radii.append(s["trunk_r"] * (1.0 - 0.72 * t) * (1.3 if i == 0 else 1.0))
        self.branches.append((pts, radii, 0, r.random()))
        count = s["b1"]
        golden = math.radians(137.5)
        base_ang = r.uniform(0, math.tau)
        for k in range(count):
            t = s["b1_start"] + (1.0 - s["b1_start"]) * (k + r.uniform(0.0, 0.6)) / count
            t = min(t, 0.97)
            p0 = sample(pts, t)
            rad0 = sample_r(radii, t) * 0.62
            az = base_ang + k * golden
            elev = math.radians(90.0 - s["b1_angle"] + r.uniform(-10, 10))
            d = Vector((math.cos(az) * math.cos(elev), math.sin(elev), math.sin(az) * math.cos(elev)))
            L = s["b1_len"] * r.uniform(0.75, 1.15)
            if s.get("taper_crown"):
                L *= 1.15 - 0.75 * t
            self._branch(p0, d, L, rad0, 1, s["up"])
        self._branch(pts[-1], (pts[-1] - pts[-2]).normalized(), (s["height"] - H) * 0.8, radii[-1] * 0.9, 1, 0.5)

    def _branch(self, p0, d, L, rad0, level, up):
        s = self.s
        r = self.r
        n = 6 if level == 1 else 4
        pts = [p0.copy()]
        radii = [rad0]
        cur = p0.copy()
        dirv = d.normalized()
        for i in range(1, n + 1):
            t = i / n
            dirv = (dirv + Vector((r.uniform(-0.25, 0.25), up * 0.35 - s["droop"] * t * 0.8, r.uniform(-0.25, 0.25)))).normalized()
            cur = cur + dirv * (L / n)
            pts.append(cur.copy())
            radii.append(max(0.012, rad0 * (1.0 - 0.8 * t)))
        self.branches.append((pts, radii, level, r.random()))
        if level == 1:
            for k in range(s["b2"]):
                t = r.uniform(0.35, 0.95)
                q0 = sample(pts, t)
                side = Vector((r.uniform(-1, 1), r.uniform(-0.2, 0.6), r.uniform(-1, 1))).normalized()
                d2 = (dirv * 0.5 + side).normalized()
                self._branch(q0, d2, s["b2_len"] * r.uniform(0.7, 1.2), sample_r(radii, t) * 0.7, 2, up)
        self.tips.append((pts[-1], dirv, level))

    def crown_center(self):
        n = max(1, len(self.tips))
        return Vector((sum(p.x for p, _, _ in self.tips) / n, self.s["crown_y"], sum(p.z for p, _, _ in self.tips) / n))

    def card_positions(self, count, rr):
        out = []
        cc = self.crown_center()
        for i in range(count):
            tip, d, lvl = self.tips[i % len(self.tips)]
            jitter = Vector((rr.gauss(0, 0.55), rr.gauss(0, 0.35), rr.gauss(0, 0.55)))
            p = tip + jitter - d * rr.uniform(0.0, 0.6)
            if self.s.get("pads"):
                p.y = tip.y + rr.gauss(0, 0.15) + 0.2
            out.append(p)
        return out, cc


def card(B, material, p, nrm, size, rot):
    ref = Vector((0, 1, 0)) if abs(nrm.y) < 0.9 else Vector((1, 0, 0))
    right = nrm.cross(ref).normalized()
    upv = right.cross(nrm).normalized()
    right, upv = right * math.cos(rot) + upv * math.sin(rot), -right * math.sin(rot) + upv * math.cos(rot)
    h = size * 0.5
    return blib.quad(B, material, p - right * h - upv * h, p + right * h - upv * h, p + right * h + upv * h, p - right * h + upv * h)


def build_lod(tree, lod, name):
    s = tree.s
    B = Builder()
    col = B.bm.loops.layers.color.new("Col")
    height = s["height"]
    sides_by_level = {0: [10, 6, 4][lod], 1: [6, 4, 3][lod], 2: [4, 3, 3][lod]}
    max_level = [2, 1, 0][lod]
    for pts, radii, level, phase in tree.branches:
        if level > max_level:
            continue
        v0, f0 = B.mark()
        blib.tube(B, s["bark"], pts, radii, sides=sides_by_level[level], cap=level > 0, uv_scale=1.0)
        for f in B.new_faces_since(f0):
            for loop in f.loops:
                p = Vector(blib.GB(loop.vert.co))
                sway = min(1.0, max(0.0, p.y / height) ** 1.6 * (0.3 + 0.35 * level))
                loop[col] = (sway, phase, 0.0, 0.6)
    count = [s["cards"], max(10, s["cards"] // 3), max(6, s["cards"] // 9)][lod]
    size_mul = [1.0, 1.55, 2.4][lod]
    rr = blib.rng(zlib.crc32(name.encode()) & 0xFFFF)
    positions, cc = tree.card_positions(count, rr)
    crown_rx, crown_ry = s["crown"]
    for p in positions:
        sz = rr.uniform(*s["card"]) * size_mul
        outward = (p - cc)
        outward.y *= 0.6
        if outward.length < 0.01:
            outward = Vector((0, 1, 0))
        outward.normalize()
        if s.get("pads"):
            nrm = (Vector((0, 1, 0)) * 0.8 + outward * 0.3 + Vector((rr.uniform(-.3, .3), 0, rr.uniform(-.3, .3)))).normalized()
        else:
            nrm = (outward + Vector((rr.uniform(-.6, .6), rr.uniform(-.4, .6), rr.uniform(-.6, .6)))).normalized()
        f = card(B, s["leaves"], p, nrm, sz, rr.uniform(0, math.tau))
        phase = rr.random()
        for loop in f.loops:
            q = Vector(blib.GB(loop.vert.co))
            d = q - cc
            occl = min(1.0, max(0.0, Vector((d.x / crown_rx, d.y / crown_ry, d.z / crown_rx)).length))
            sway = min(1.0, 0.55 + 0.45 * max(0.0, q.y / height))
            loop[col] = (sway, phase, 1.0, 0.35 + 0.65 * occl)
    ob = B.to_object(name)
    me = ob.data
    if me.color_attributes:
        me.color_attributes.active_color = me.color_attributes[0]
    leaf_slot = me.materials.find(s["leaves"])
    normals = []
    for poly in me.polygons:
        pass
    normals = [None] * len(me.loops)
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            if poly.material_index == leaf_slot:
                q = Vector(blib.GB(me.vertices[vi].co))
                n = q - cc
                n.y = n.y * 0.7 + 0.25
                n.normalize()
                normals[li] = tuple(G(n))
            else:
                normals[li] = tuple(me.vertices[vi].normal)
    me.normals_split_custom_set(normals)
    return ob


def bamboo_clump(seed, name):
    objs = []
    for lod in range(3):
        B = Builder()
        col = B.bm.loops.layers.color.new("Col")
        rr = blib.rng(seed)
        n_culms = [9, 6, 4][lod]
        for c in range(n_culms):
            base = Vector((rr.gauss(0, 0.45), 0.0, rr.gauss(0, 0.45)))
            H = rr.uniform(8.5, 12.5)
            lean = Vector((rr.uniform(-1, 1), 0, rr.uniform(-1, 1))).normalized() * rr.uniform(0.2, 0.9)
            rad = rr.uniform(0.035, 0.055)
            pts = []
            radii = []
            segs = [10, 6, 3][lod]
            for i in range(segs + 1):
                t = i / segs
                pts.append(base + Vector((0, t * H, 0)) + lean * t * t)
                radii.append(rad * (1.0 - 0.45 * t))
            v0, f0 = B.mark()
            blib.tube(B, "bamboo", pts, radii, sides=[7, 5, 4][lod], cap=True, uv_scale=1.0 / (H / 4.0))
            phase = rr.random()
            for f in B.new_faces_since(f0):
                for loop in f.loops:
                    p = Vector(blib.GB(loop.vert.co))
                    loop[col] = (max(0.0, p.y / H) ** 1.5, phase, 0.0, 0.7)
            cards = [9, 4, 2][lod]
            for k in range(cards):
                t = rr.uniform(0.55, 1.0)
                p = sample(pts, t) + Vector((rr.gauss(0, 0.5), rr.uniform(-0.2, 0.3), rr.gauss(0, 0.5)))
                sz = rr.uniform(1.1, 1.6) * [1.0, 1.5, 2.3][lod]
                nrm = Vector((rr.uniform(-1, 1), rr.uniform(-0.3, 0.6), rr.uniform(-1, 1))).normalized()
                f = card(B, "leaves_bamboo", p, nrm, sz, rr.uniform(0, math.tau))
                ph = rr.random()
                for loop in f.loops:
                    loop[col] = (min(1.0, 0.6 + 0.4 * t), ph, 1.0, 0.8)
        ob = B.to_object("lod%d" % lod)
        me = ob.data
        if me.color_attributes:
            me.color_attributes.active_color = me.color_attributes[0]
        objs.append(ob)
    blib.export(objs, "trees/%s.glb" % name)
    return {"height": 11.0, "trunk_radius": 0.5, "crown_radius": 2.0}


def build():
    meta = {}
    for sp, spec in SPECIES.items():
        for v in range(2):
            blib.reset()
            seed = 1000 + zlib.crc32(sp.encode()) % 1000 + v * 77
            tree = Tree(spec, seed)
            tree.grow()
            name = "%s_%d" % (sp, v)
            lods = [build_lod(tree, lod, "lod%d" % lod) for lod in range(3)]
            blib.export(lods, "trees/%s.glb" % name)
            meta[name] = {"height": spec["height"], "trunk_radius": spec["trunk_r"] * 1.1,
                          "crown_radius": spec["crown"][0], "species": sp}
    for v in range(2):
        blib.reset()
        name = "bamboo_%d" % v
        meta[name] = bamboo_clump(5000 + v, name)
        meta[name]["species"] = "bamboo"
    path = os.path.join(blib.MODELS, "trees", "trees.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(meta, f, indent=1)
    print("    trees.json written (%d models)" % len(meta))
