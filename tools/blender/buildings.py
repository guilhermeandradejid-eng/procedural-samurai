"""Architecture: torii, hokora shrine, temple hall, five-storey pagoda, minka
farmhouse, watchtower, army tent, jinmaku curtain, palisade, fences.

Collision is exported as simple boxes named '*-colonly' (Godot creates
static bodies for them on import). Materials are named slots that Godot maps
to textured, triplanar materials.
"""
import math

from mathutils import Vector

import blib
from blib import Builder, G, box, lathe, quad, set_origin, tube


def colbox(name, center, size):
    B = Builder()
    box(B, "collision", center, size)
    return B.to_object(name + "-convcolonly")


def curved_roof(B, material, cx, cy, cz, w, d, rise, lift, overhang, thick=0.18, hip=True, segs=10):
    """Japanese hipped roof with upturned eaves (sori). w/d = footprint of the
    eaves, rise = height of the ridge above the eaves, lift = corner upturn.
    The surface is concave: nearly flat at the eaves, steep near the ridge."""
    bm = B.bm
    v0, f0 = B.mark()
    nx = segs
    nz = segs
    top_verts = []
    for i in range(nx + 1):
        row = []
        for j in range(nz + 1):
            u = i / nx * 2 - 1  # -1..1
            v = j / nz * 2 - 1
            x = u * w * 0.5
            z = v * d * 0.5
            if hip:
                # normalised distance to the nearest eave edge (0 at the eave, 1 at the ridge)
                ex = (1 - abs(u)) * w * 0.5
                ez = (1 - abs(v)) * d * 0.5
                e = min(ex, ez) / (min(w, d) * 0.5)
            else:
                e = 1 - abs(v)
            e = max(0.0, min(1.0, e))
            y = rise * e ** 1.6
            corner = (abs(u) ** 6 + abs(v) ** 6) if hip else abs(u) ** 8
            y += lift * corner
            row.append(bm.verts.new(G(cx + x, cy + y, cz + z)))
        top_verts.append(row)
    for i in range(nx):
        for j in range(nz):
            a = top_verts[i][j]
            b = top_verts[i + 1][j]
            c = top_verts[i + 1][j + 1]
            d_ = top_verts[i][j + 1]
            f = bm.faces.new((a, d_, c, b))
            for loop in f.loops:
                co = Vector(blib.GB(loop.vert.co))
                loop[B.uv].uv = (co.x * 0.5, co.z * 0.5)
    B.faces_from(v0, f0, material, smooth=True)
    return B


def roof_object(name, material, cx, cy, cz, w, d, rise, lift, segs=10, thick=0.16, hip=True):
    R = Builder()
    curved_roof(R, material, cx, cy, cz, w, d, rise, lift, 0.0, segs=segs, hip=hip)
    ob = R.to_object(name)
    return blib.solidify(ob, thick, offset=-1.0)


def torii(name="torii", red=True):
    B = Builder()
    paint = "vermilion" if red else "wood_light"
    span = 3.6
    h = 4.4
    for sx in (-1, 1):
        # slightly leaning pillars with black bases
        tube(B, paint, [Vector((sx * span / 2, 0.0, 0.0)), Vector((sx * (span / 2 - 0.08), h, 0.0))], [0.2, 0.17], sides=16, cap=True)
        tube(B, "black_paint", [Vector((sx * span / 2, -0.05, 0.0)), Vector((sx * span / 2, 0.45, 0.0))], [0.225, 0.22], sides=16, cap=True)
    # nuki (tie beam) passing through the pillars
    box(B, paint, (0.0, h - 1.05, 0.0), (span + 1.0, 0.24, 0.16))
    # gakuzuka (centre strut) with a plaque
    box(B, paint, (0.0, h - 0.62, 0.0), (0.18, 0.62, 0.14))
    box(B, "black_paint", (0.0, h - 0.62, -0.09), (0.42, 0.52, 0.04))
    # shimaki + kasagi: curved top beams with upturned ends
    pts = []
    radii = []
    n = 14
    L = span + 2.2
    for i in range(n + 1):
        t = i / n * 2 - 1
        pts.append(Vector((t * L / 2, h + 0.22 + 0.32 * abs(t) ** 3.2, 0.0)))
        radii.append(0.2)
    for i in range(n):
        a = pts[i]
        b = pts[i + 1]
        mid = (a + b) * 0.5
        seg = (b - a)
        ang = math.atan2(seg.y, seg.x)
        v0, _ = B.mark()
        box(B, paint, (0, 0, 0), (seg.length + 0.02, 0.24, 0.3))
        blib.transform_since(B, v0, lambda q, ang=ang, mid=mid: Vector((q.x * math.cos(ang) - q.y * math.sin(ang), q.x * math.sin(ang) + q.y * math.cos(ang), q.z)) + mid)
        v0, _ = B.mark()
        box(B, "black_paint", (0, 0, 0), (seg.length + 0.02, 0.1, 0.36))
        blib.transform_since(B, v0, lambda q, ang=ang, mid=mid: Vector((q.x * math.cos(ang) - q.y * math.sin(ang), q.x * math.sin(ang) + q.y * math.cos(ang) + 0.17, q.z)) + mid)
    ob = B.to_object(name)
    cols = [colbox(name + "_pillar_l", (-span / 2, h / 2, 0), (0.44, h, 0.44)),
            colbox(name + "_pillar_r", (span / 2, h / 2, 0), (0.44, h, 0.44))]
    blib.export([ob] + cols, "buildings/%s.glb" % name)


def hokora():
    B = Builder()
    box(B, "stone", (0.0, 0.3, 0.0), (1.4, 0.6, 1.2))
    box(B, "stone", (0.0, 0.66, 0.0), (1.1, 0.12, 0.95))
    box(B, "wood_dark", (0.0, 1.1, 0.0), (0.8, 0.8, 0.7))
    box(B, "vermilion", (0.0, 1.1, -0.36), (0.6, 0.6, 0.03))
    box(B, "shoji", (0.0, 1.1, -0.38), (0.5, 0.5, 0.02))
    ob = B.to_object("hokora")
    roof = roof_object("hokora_roof", "roof_copper", 0.0, 1.48, 0.0, 1.35, 1.2, 0.5, 0.12, 8, 0.06)
    ob = blib.join([ob, roof], "hokora")
    col = colbox("hokora_col", (0.0, 0.8, 0.0), (1.4, 1.6, 1.2))
    blib.export([ob, col], "buildings/hokora.glb")


def temple_hall():
    B = Builder()
    W, D = 11.0, 8.0
    # stone platform and wooden floor on posts
    box(B, "stone", (0.0, 0.35, 0.0), (W + 2.0, 0.7, D + 2.0))
    box(B, "wood_dark", (0.0, 1.1, 0.0), (W + 1.2, 0.2, D + 1.2))
    for i in range(6):
        for j in range(4):
            x = -W / 2 + i * W / 5
            z = -D / 2 + j * D / 3
            tube(B, "vermilion", [Vector((x, 1.2, z)), Vector((x, 5.0, z))], [0.18, 0.17], sides=12, cap=False)
    # walls: shoji panels on the sides, plaster above
    box(B, "shoji", (0.0, 2.6, D / 2 - 0.1), (W - 0.4, 2.8, 0.08))
    box(B, "shoji", (-W / 2 + 0.1, 2.6, 0.0), (0.08, 2.8, D - 0.4))
    box(B, "shoji", (W / 2 - 0.1, 2.6, 0.0), (0.08, 2.8, D - 0.4))
    box(B, "plaster", (0.0, 4.4, 0.0), (W - 0.2, 1.1, D - 0.2))
    box(B, "vermilion", (0.0, 5.05, 0.0), (W + 0.4, 0.3, D + 0.4))
    # stairs at the front
    for k in range(5):
        box(B, "stone", (0.0, 0.14 + k * 0.2, -D / 2 - 1.2 - (4 - k) * 0.35), (3.0, 0.28 + k * 0.4, 0.35))
    # ridge beam
    box(B, "black_paint", (0.0, 8.85, 0.0), (W * 0.62, 0.35, 0.4))
    ob = B.to_object("temple_hall")
    ob = blib.join([ob, roof_object("hall_roof", "roof_tiles", 0.0, 5.2, 0.0, W + 4.0, D + 4.0, 3.6, 0.9, 14, 0.3)], "temple_hall")
    cols = [colbox("hall_base", (0.0, 0.6, 0.0), (W + 2.0, 1.2, D + 2.0)),
            colbox("hall_body", (0.0, 3.2, 0.0), (W, 4.0, D)),
            colbox("hall_stairs", (0.0, 0.5, -D / 2 - 1.8), (3.0, 1.0, 2.0))]
    blib.export([ob] + cols, "buildings/temple_hall.glb")


def pagoda():
    B = Builder()
    roofs = []
    box(B, "stone", (0.0, 0.4, 0.0), (8.0, 0.8, 8.0))
    y = 0.8
    size = 5.6
    for storey in range(5):
        h = 2.6 if storey == 0 else 2.0
        box(B, "wood_dark", (0.0, y + h / 2, 0.0), (size, h, size))
        for sx in (-1, 1):
            for sz in (-1, 1):
                tube(B, "vermilion", [Vector((sx * size / 2, y, sz * size / 2)), Vector((sx * size / 2, y + h, sz * size / 2))], [0.12, 0.12], sides=8, cap=False)
        box(B, "vermilion", (0.0, y + h - 0.12, 0.0), (size + 0.3, 0.25, size + 0.3))
        box(B, "shoji", (0.0, y + h * 0.45, -size / 2 - 0.02), (size * 0.35, h * 0.6, 0.04))
        roof_w = size + 3.4
        roofs.append(roof_object("pagoda_roof_%d" % storey, "roof_tiles", 0.0, y + h, 0.0, roof_w, roof_w, 1.0, 0.55, 10, 0.22))
        y += h + 0.75
        size *= 0.86
    # sorin spire
    tube(B, "bronze", [Vector((0.0, y - 0.5, 0.0)), Vector((0.0, y + 5.5, 0.0))], [0.16, 0.08], sides=10, cap=True)
    for k in range(9):
        lathe(B, [(y + 0.4 + k * 0.5, 0.36 - k * 0.015), (y + 0.52 + k * 0.5, 0.36 - k * 0.015)], "bronze", sides=14)
    ob = blib.join([B.to_object("pagoda")] + roofs, "pagoda")
    cols = [colbox("pagoda_col", (0.0, 8.0, 0.0), (6.0, 16.0, 6.0)), colbox("pagoda_base", (0.0, 0.4, 0.0), (8.0, 0.8, 8.0))]
    blib.export([ob] + cols, "buildings/pagoda.glb")


def minka(variant=0):
    B = Builder()
    W, D, H = 8.0, 6.0, 2.8
    box(B, "stone", (0.0, 0.25, 0.0), (W + 0.4, 0.5, D + 0.4))
    # timber frame + plaster/wood panels
    for i in range(5):
        x = -W / 2 + i * W / 4
        for z in (-D / 2, D / 2):
            box(B, "wood_dark", (x, 0.5 + H / 2, z), (0.2, H, 0.2))
    for z in (-D / 2, D / 2):
        box(B, "wood_dark", (0.0, 0.5 + H, z), (W + 0.2, 0.22, 0.24))
    for x in (-W / 2, W / 2):
        box(B, "wood_dark", (x, 0.5 + H / 2, 0.0), (0.2, H, D))
    box(B, "plaster", (0.0, 0.5 + H * 0.72, D / 2 - 0.05), (W - 0.2, H * 0.5, 0.1))
    box(B, "wood_light", (0.0, 0.5 + H * 0.25, D / 2 - 0.05), (W - 0.2, H * 0.5, 0.1))
    box(B, "shoji", (0.0, 0.5 + H * 0.45, -D / 2 + 0.05), (W - 1.0, H * 0.85, 0.1))
    box(B, "wood_dark", (0.0, 0.55, -D / 2 - 0.7), (W, 0.12, 1.2))  # engawa veranda
    roof_mat = "thatch" if variant == 0 else "roof_tiles"
    rise = 3.4 if variant == 0 else 2.2
    if variant == 0:
        box(B, "thatch", (0.0, 0.5 + H + rise - 0.1, 0.0), (W * 0.55, 0.5, 0.9))
    ob = B.to_object("minka_%d" % variant)
    roof = roof_object("minka_roof", roof_mat, 0.0, 0.5 + H, 0.0, W + 2.6, D + 2.6, rise, 0.1 if variant == 0 else 0.35, 12,
                       0.5 if variant == 0 else 0.2)
    ob = blib.join([ob, roof], "minka_%d" % variant)
    cols = [colbox("minka_col", (0.0, 1.9, 0.0), (W + 0.4, 3.8, D + 0.4))]
    blib.export([ob] + cols, "buildings/minka_%d.glb" % variant)


def watchtower():
    B = Builder()
    Hh = 6.0
    for sx in (-1, 1):
        for sz in (-1, 1):
            tube(B, "wood_raw", [Vector((sx * 1.4, 0.0, sz * 1.4)), Vector((sx * 1.05, Hh + 1.8, sz * 1.05))], [0.13, 0.11], sides=8, cap=True)
    for y in (1.8, 3.8):
        for sx in (-1, 1):
            box(B, "wood_raw", (sx * 1.2, y, 0.0), (0.12, 0.12, 2.6))
            box(B, "wood_raw", (0.0, y, sx * 1.2), (2.6, 0.12, 0.12))
    box(B, "wood_raw", (0.0, Hh, 0.0), (2.9, 0.15, 2.9))
    for sx in (-1, 1):
        box(B, "wood_raw", (sx * 1.35, Hh + 0.55, 0.0), (0.08, 0.9, 2.9))
        box(B, "wood_raw", (0.0, Hh + 0.55, sx * 1.35), (2.9, 0.9, 0.08))
    # ladder
    for sx in (-1, 1):
        tube(B, "wood_raw", [Vector((sx * 0.25, 0.0, -2.1)), Vector((sx * 0.25, Hh, -1.35))], [0.04, 0.04], sides=5, cap=False)
    for k in range(12):
        t = (k + 0.5) / 12
        box(B, "wood_raw", (0.0, t * Hh, -2.1 + t * 0.75), (0.55, 0.05, 0.06))
    ob = blib.join([B.to_object("watchtower"), roof_object("tower_roof", "thatch", 0.0, Hh + 1.8, 0.0, 3.6, 3.6, 1.0, 0.1, 6, 0.25)], "watchtower")
    cols = [colbox("tower_platform", (0.0, Hh, 0.0), (2.9, 0.2, 2.9))]
    for sx in (-1, 1):
        for sz in (-1, 1):
            cols.append(colbox("tower_leg", (sx * 1.25, Hh / 2, sz * 1.25), (0.3, Hh, 0.3)))
    blib.export([ob] + cols, "buildings/watchtower.glb")


def tent():
    B = Builder()
    L, W, H = 4.2, 3.4, 2.4
    quad(B, "canvas", (-L / 2, 0.0, -W / 2), (L / 2, 0.0, -W / 2), (L / 2, H, 0.0), (-L / 2, H, 0.0))
    quad(B, "canvas", (L / 2, 0.0, W / 2), (-L / 2, 0.0, W / 2), (-L / 2, H, 0.0), (L / 2, H, 0.0))
    quad(B, "canvas", (-L / 2, 0.0, W / 2), (-L / 2, 0.0, -W / 2), (-L / 2, H, 0.0), (-L / 2, H, 0.0 + 0.001))
    tube(B, "wood_raw", [Vector((-L / 2 - 0.2, H + 0.05, 0.0)), Vector((L / 2 + 0.2, H + 0.05, 0.0))], [0.05, 0.05], sides=6)
    for sx in (-1, 1):
        tube(B, "wood_raw", [Vector((sx * (L / 2 + 0.1), 0.0, 0.0)), Vector((sx * (L / 2 + 0.1), H + 0.1, 0.0))], [0.05, 0.05], sides=6)
    ob = B.to_object("tent")
    blib.solidify(ob, 0.02)
    cols = [colbox("tent_col", (0.0, H * 0.4, 0.0), (L, H * 0.8, W * 0.7))]
    blib.export([ob] + cols, "buildings/tent.glb")


def jinmaku(crest=0):
    """Camp curtain segment (6 m) on poles, with the clan crest texture."""
    B = Builder()
    L = 6.0
    H = 2.1
    for k in range(4):
        x = -L / 2 + k * L / 3
        tube(B, "wood_dark", [Vector((x, 0.0, 0.0)), Vector((x, H + 0.35, 0.0))], [0.04, 0.035], sides=6, cap=True)
    # sagging cloth (both faces)
    n = 12
    for i in range(n):
        x0 = -L / 2 + i * L / n
        x1 = x0 + L / n
        s0 = 0.08 * math.sin((i / n * 3 % 1) * math.pi)
        s1 = 0.08 * math.sin(((i + 1) / n * 3 % 1) * math.pi)
        u0 = i / n * 3
        u1 = (i + 1) / n * 3
        quad(B, "curtain_%d" % crest, (x0, 0.35, 0.0), (x1, 0.35, 0.0), (x1, H - s1, 0.0), (x0, H - s0, 0.0),
             uvs=((u0, 0), (u1, 0), (u1, 1), (u0, 1)))
        quad(B, "curtain_%d" % crest, (x1, 0.35, 0.0), (x0, 0.35, 0.0), (x0, H - s0, 0.0), (x1, H - s1, 0.0),
             uvs=((u1, 0), (u0, 0), (u0, 1), (u1, 1)))
    ob = B.to_object("jinmaku")
    cols = [colbox("jinmaku_col", (0.0, 1.1, 0.0), (L, 2.2, 0.2))]
    blib.export([ob] + cols, "buildings/jinmaku_%d.glb" % crest)


def palisade():
    B = Builder()
    r = blib.rng(9)
    for k in range(14):
        x = -3.0 + k * 0.43
        h = r.uniform(2.5, 3.0)
        pts = [Vector((x, -0.3, 0.0)), Vector((x + r.uniform(-0.04, 0.04), h, 0.0))]
        tube(B, "wood_raw", pts, [0.14, 0.13], sides=7, cap=False)
        lathe(B, [(h, 0.13), (h + 0.35, 0.0)], "wood_raw", center=(pts[1].x, 0.0, 0.0), sides=7, cap_bottom=False)
    for y in (0.8, 2.0):
        tube(B, "wood_raw", [Vector((-3.2, y, 0.16)), Vector((3.2, y, 0.16))], [0.06, 0.06], sides=6)
    ob = B.to_object("palisade")
    cols = [colbox("palisade_col", (0.0, 1.4, 0.0), (6.2, 2.8, 0.35))]
    blib.export([ob] + cols, "buildings/palisade.glb")


def bamboo_fence():
    B = Builder()
    for k in range(3):
        x = -2.0 + k * 2.0
        tube(B, "wood_dark", [Vector((x, 0.0, 0.0)), Vector((x, 1.25, 0.0))], [0.06, 0.06], sides=8)
    for y in (0.35, 0.75, 1.1):
        tube(B, "bamboo_pole", [Vector((-2.1, y, 0.06)), Vector((2.1, y, 0.06))], [0.03, 0.03], sides=6)
    for k in range(40):
        x = -2.0 + k * 0.1
        tube(B, "bamboo_pole", [Vector((x, 0.0, 0.0)), Vector((x, 1.18, 0.0))], [0.022, 0.022], sides=5)
    ob = B.to_object("bamboo_fence")
    cols = [colbox("fence_col", (0.0, 0.6, 0.0), (4.2, 1.2, 0.2))]
    blib.export([ob] + cols, "buildings/bamboo_fence.glb")


def build():
    for fn in (lambda: torii("torii", True), lambda: torii("torii_wood", False), hokora, temple_hall, pagoda,
               lambda: minka(0), lambda: minka(1), watchtower, tent, lambda: jinmaku(0), lambda: jinmaku(1),
               palisade, bamboo_fence):
        blib.reset()
        fn()
