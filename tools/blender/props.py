"""Small props that dress shrines, villages and camps."""
import math

from mathutils import Vector

import blib
from blib import Builder, box, lathe, quad, set_origin, subsurf, superellipsoid, tube


def colbox(name, center, size):
    B = Builder()
    box(B, "collision", center, size)
    return B.to_object(name + "-convcolonly")


def stone_lantern():
    """Kasuga-doro: base, pillar, fire box with windows, curved roof, jewel."""
    B = Builder()
    lathe(B, [(0.0, 0.34), (0.12, 0.34), (0.18, 0.26)], "stone", sides=6)
    lathe(B, [(0.18, 0.1), (0.95, 0.085)], "stone", sides=12)
    lathe(B, [(0.95, 0.2), (1.05, 0.24), (1.1, 0.22)], "stone", sides=6)
    box(B, "stone", (0.0, 1.3, 0.0), (0.34, 0.36, 0.34))
    box(B, "paper_lantern", (0.0, 1.3, -0.17), (0.16, 0.18, 0.01))
    box(B, "paper_lantern", (0.0, 1.3, 0.17), (0.16, 0.18, 0.01))
    lathe(B, [(1.47, 0.42), (1.52, 0.4), (1.62, 0.22), (1.72, 0.08)], "stone", sides=6)
    superellipsoid(B, "stone", (0.0, 1.8, 0.0), (0.14, 0.18, 0.14), p=0.9, segs=10, rings=8)
    ob = B.to_object("stone_lantern")
    blib.export([ob, colbox("lantern_col", (0.0, 0.9, 0.0), (0.6, 1.8, 0.6))], "props/stone_lantern.glb")


def jizo():
    B = Builder()
    lathe(B, [(0.0, 0.22), (0.1, 0.22), (0.14, 0.18)], "stone", sides=10)
    superellipsoid(B, "stone", (0.0, 0.42, 0.0), (0.3, 0.56, 0.26), p=0.8, segs=16, rings=10)
    superellipsoid(B, "stone", (0.0, 0.78, 0.0), (0.2, 0.22, 0.2), p=0.95, segs=14, rings=10)
    # red bib (yodarekake)
    lathe(B, [(0.48, 0.16), (0.6, 0.145), (0.64, 0.12)], "cord", sides=14, cap_bottom=False, cap_top=False,
          angle_range=(-math.pi / 2 - 1.3, -math.pi / 2 + 1.3), xz_scale=(1.0, 0.9))
    lathe(B, [(0.88, 0.11), (0.93, 0.1)], "cord", sides=14, cap_bottom=False)
    ob = B.to_object("jizo")
    blib.export([ob, colbox("jizo_col", (0.0, 0.45, 0.0), (0.4, 0.9, 0.4))], "props/jizo.glb")


def campfire():
    B = Builder()
    r = blib.rng(3)
    for k in range(10):
        a = k / 10 * math.tau
        superellipsoid(B, "stone", (math.cos(a) * 0.62, 0.08, math.sin(a) * 0.62), (0.28, 0.2, 0.24), p=0.8, segs=8, rings=6,
                       deform=lambda x, y, z, k=k: (x * (1 + 0.15 * math.sin(k * 3)), y, z))
    for k in range(6):
        a = k / 6 * math.tau + 0.3
        p0 = Vector((math.cos(a) * 0.45, 0.02, math.sin(a) * 0.45))
        p1 = Vector((math.cos(a) * 0.05, 0.38, math.sin(a) * 0.05))
        tube(B, "wood_charred", [p0, p1], [0.06, 0.05], sides=6)
    superellipsoid(B, "ash", (0.0, 0.02, 0.0), (0.9, 0.06, 0.9), p=0.9, segs=12, rings=4)
    ob = B.to_object("campfire")
    blib.export([ob, colbox("fire_col", (0.0, 0.15, 0.0), (1.5, 0.3, 1.5))], "props/campfire.glb")


def barrel():
    B = Builder()
    prof = [(0.0, 0.3), (0.2, 0.34), (0.45, 0.36), (0.7, 0.34), (0.9, 0.3)]
    lathe(B, prof, "wood_light", sides=16)
    for y in (0.12, 0.78):
        lathe(B, [(y - 0.03, 0.335), (y + 0.03, 0.335)], "rope", sides=16, cap_bottom=False, cap_top=False)
    ob = B.to_object("barrel")
    blib.export([ob, colbox("barrel_col", (0.0, 0.45, 0.0), (0.66, 0.9, 0.66))], "props/barrel.glb")


def crate():
    B = Builder()
    box(B, "wood_light", (0.0, 0.35, 0.0), (0.8, 0.7, 0.6))
    for y in (0.08, 0.62):
        box(B, "wood_dark", (0.0, y, 0.0), (0.84, 0.08, 0.64))
    ob = B.to_object("crate")
    ob = blib.bevel(ob, 0.015, 1)
    blib.export([ob, colbox("crate_col", (0.0, 0.35, 0.0), (0.84, 0.7, 0.64))], "props/crate.glb")


def rice_bales():
    B = Builder()
    for i, (x, y) in enumerate(((-0.35, 0.25), (0.35, 0.25), (0.0, 0.7))):
        lathe(B, [(-0.45, 0.18), (-0.4, 0.26), (0.0, 0.29), (0.4, 0.26), (0.45, 0.18)], "thatch", axis="x",
              center=(x * 0.0, y, x), sides=12)
        for off in (-0.25, 0.25):
            lathe(B, [(off - 0.02, 0.285), (off + 0.02, 0.285)], "rope", axis="x", center=(0.0, y, x), sides=12)
    ob = B.to_object("rice_bales")
    blib.export([ob, colbox("bales_col", (0.0, 0.45, 0.0), (1.0, 0.9, 1.3))], "props/rice_bales.glb")


def nobori(variant=0):
    B = Builder()
    tube(B, "bamboo_pole", [Vector((0.0, 0.0, 0.0)), Vector((0.0, 4.4, 0.0))], [0.03, 0.025], sides=6)
    tube(B, "bamboo_pole", [Vector((0.0, 4.2, 0.0)), Vector((0.5, 4.2, 0.0))], [0.015, 0.015], sides=5)
    ob = B.to_object("pole")
    F = Builder()
    n = 10
    for i in range(n):
        y0 = 1.3 + i * 2.9 / n
        y1 = y0 + 2.9 / n
        quad(F, "flag_%d" % variant, (0.02, y0, 0.0), (0.5, y0, 0.0), (0.5, y1, 0.0), (0.02, y1, 0.0),
             uvs=((0, i / n), (1, i / n), (1, (i + 1) / n), (0, (i + 1) / n)))
    flag = F.to_object("flag")
    blib.export([ob, flag], "props/nobori_%d.glb" % variant)


def weapon_rack():
    B = Builder()
    for x in (-0.7, 0.7):
        tube(B, "wood_dark", [Vector((x, 0.0, 0.0)), Vector((x, 1.2, 0.0))], [0.04, 0.04], sides=6)
    tube(B, "wood_dark", [Vector((-0.75, 1.15, 0.0)), Vector((0.75, 1.15, 0.0))], [0.035, 0.035], sides=6)
    tube(B, "wood_dark", [Vector((-0.75, 0.4, 0.0)), Vector((0.75, 0.4, 0.0))], [0.03, 0.03], sides=6)
    for k in range(5):
        x = -0.5 + k * 0.25
        tube(B, "wood_dark", [Vector((x, 0.05, 0.12)), Vector((x + 0.02, 2.1, -0.08))], [0.016, 0.016], sides=5)
        lathe(B, [(2.1, 0.03), (2.3, 0.0)], "metal_dark", center=(x + 0.02, 0.0, -0.08), sides=4, cap_bottom=True)
    ob = B.to_object("weapon_rack")
    blib.export([ob, colbox("rack_col", (0.0, 0.8, 0.0), (1.6, 1.6, 0.3))], "props/weapon_rack.glb")


def shimenawa():
    """Sacred straw rope ring with zig-zag paper streamers (shide)."""
    B = Builder()
    pts = []
    radii = []
    n = 36
    for i in range(n + 1):
        a = i / n * math.tau
        pts.append(Vector((math.cos(a) * 1.0, math.sin(a * 3) * 0.03, math.sin(a) * 1.0)))
        radii.append(0.07)
    tube(B, "rope", pts, radii, sides=8, cap=False)
    for k in range(6):
        a = k / 6 * math.tau
        x = math.cos(a) * 1.07
        z = math.sin(a) * 1.07
        for j in range(4):
            y0 = -0.08 - j * 0.07
            off = 0.04 if j % 2 == 0 else -0.04
            quad(B, "paper", (x + off * math.sin(a), y0 - 0.07, z - off * math.cos(a)), (x + (off + 0.06) * math.sin(a), y0 - 0.07, z - (off + 0.06) * math.cos(a)),
                 (x + (off + 0.06) * math.sin(a), y0, z - (off + 0.06) * math.cos(a)), (x + off * math.sin(a), y0, z - off * math.cos(a)))
    ob = B.to_object("shimenawa")
    blib.export([ob], "props/shimenawa.glb")


def paper_lantern():
    B = Builder()
    prof = [(0.0, 0.1), (0.05, 0.16), (0.2, 0.2), (0.35, 0.16), (0.4, 0.1)]
    lathe(B, prof, "paper_lantern", sides=14)
    lathe(B, [(-0.02, 0.1), (0.0, 0.1)], "black_paint", sides=14)
    lathe(B, [(0.4, 0.1), (0.42, 0.1)], "black_paint", sides=14)
    tube(B, "rope", [Vector((0.0, 0.42, 0.0)), Vector((0.0, 0.7, 0.0))], [0.008, 0.008], sides=4)
    ob = B.to_object("paper_lantern")
    blib.export([ob], "props/paper_lantern.glb")


def onsen_ring():
    B = Builder()
    r = blib.rng(8)
    n = 16
    for k in range(n):
        a = k / n * math.tau
        rad = 4.2 + r.uniform(-0.3, 0.3)
        s = r.uniform(0.7, 1.1)
        superellipsoid(B, "rock", (math.cos(a) * rad, 0.15, math.sin(a) * rad), (1.2 * s, 0.8 * s, 1.0 * s), p=0.75,
                       segs=10, rings=6)
    ob = B.to_object("onsen_ring")
    blib.export([ob], "props/onsen_ring.glb")


def sake_jar():
    B = Builder()
    prof = [(0.0, 0.12), (0.1, 0.2), (0.3, 0.22), (0.48, 0.15), (0.55, 0.07), (0.62, 0.07), (0.64, 0.09)]
    lathe(B, prof, "ceramic", sides=14, cap_top=False)
    ob = B.to_object("sake_jar")
    blib.export([ob], "props/sake_jar.glb")


def makiwara():
    B = Builder()
    tube(B, "wood_raw", [Vector((0.0, -0.3, 0.0)), Vector((0.0, 1.9, 0.0))], [0.06, 0.055], sides=7)
    lathe(B, [(0.7, 0.13), (0.75, 0.16), (1.55, 0.16), (1.6, 0.13)], "thatch", sides=12)
    for y in (0.85, 1.15, 1.45):
        lathe(B, [(y - 0.02, 0.165), (y + 0.02, 0.165)], "rope", sides=12, cap_bottom=False, cap_top=False)
    ob = B.to_object("makiwara")
    blib.export([ob, colbox("makiwara_col", (0.0, 1.0, 0.0), (0.35, 2.0, 0.35))], "props/makiwara.glb")


def bench():
    B = Builder()
    box(B, "wood_dark", (0.0, 0.42, 0.0), (1.6, 0.06, 0.4))
    for x in (-0.65, 0.65):
        box(B, "wood_dark", (x, 0.2, 0.0), (0.08, 0.4, 0.34))
    ob = B.to_object("bench")
    blib.export([ob, colbox("bench_col", (0.0, 0.22, 0.0), (1.6, 0.45, 0.4))], "props/bench.glb")


def well():
    B = Builder()
    lathe(B, [(0.0, 0.62), (0.75, 0.6)], "stone", sides=16, cap_top=False)
    lathe(B, [(0.0, 0.5), (0.72, 0.5)], "stone", sides=16, cap_top=False, cap_bottom=False)
    for x in (-0.7, 0.7):
        tube(B, "wood_dark", [Vector((x, 0.0, 0.0)), Vector((x, 2.1, 0.0))], [0.05, 0.05], sides=6)
    ob = B.to_object("well")
    roof = Builder()
    quad(roof, "roof_tiles", (-0.95, 1.95, -0.7), (0.95, 1.95, -0.7), (0.95, 2.4, 0.0), (-0.95, 2.4, 0.0))
    quad(roof, "roof_tiles", (0.95, 1.95, 0.7), (-0.95, 1.95, 0.7), (-0.95, 2.4, 0.0), (0.95, 2.4, 0.0))
    r = roof.to_object("well_roof")
    r = blib.solidify(r, 0.06)
    ob = blib.join([ob, r], "well")
    blib.export([ob, colbox("well_col", (0.0, 0.4, 0.0), (1.3, 0.8, 1.3))], "props/well.glb")


def build():
    for fn in (stone_lantern, jizo, campfire, barrel, crate, rice_bales, lambda: nobori(0), lambda: nobori(1),
               weapon_rack, shimenawa, paper_lantern, onsen_ring, sake_jar, makiwara, bench, well):
        blib.reset()
        fn()
