"""Human-Fall-Flat style samurai: soft rounded body parts (one object per
ragdoll part) plus armour, hats, masks and faces as attachable pieces.

Each object's origin is the pivot (or hinge) it rotates around, in rest pose
coordinates. Pieces are named "<part>__<piece>" so Godot knows where to
attach them. The rig description is written to characters/rig.json.
"""
import json
import math
import os

from mathutils import Vector

import blib
from blib import (Builder, G, box, capsule, lathe, set_origin, solidify, subsurf, superellipsoid, transform_since)

# ------------------------------------------------------------------ rig
RIG = {
    "pelvis": {"parent": "", "pivot": (0.0, 0.92, 0.0), "end": (0.0, 1.0, 0.0)},
    "belly": {"parent": "pelvis", "pivot": (0.0, 1.0, 0.0), "end": (0.0, 1.19, 0.0)},
    "chest": {"parent": "belly", "pivot": (0.0, 1.19, 0.0), "end": (0.0, 1.5, 0.0)},
    "head": {"parent": "chest", "pivot": (0.0, 1.5, 0.0), "end": (0.0, 1.83, 0.0)},
    "upper_arm_r": {"parent": "chest", "pivot": (0.225, 1.435, 0.0), "end": (0.245, 1.16, 0.0)},
    "forearm_r": {"parent": "upper_arm_r", "pivot": (0.245, 1.16, 0.0), "end": (0.258, 0.915, 0.0)},
    "hand_r": {"parent": "forearm_r", "pivot": (0.258, 0.915, 0.0), "end": (0.262, 0.8, -0.01)},
    "thigh_r": {"parent": "pelvis", "pivot": (0.105, 0.87, 0.0), "end": (0.11, 0.48, 0.0)},
    "shin_r": {"parent": "thigh_r", "pivot": (0.11, 0.48, 0.0), "end": (0.115, 0.095, 0.0)},
    "foot_r": {"parent": "shin_r", "pivot": (0.115, 0.095, 0.0), "end": (0.115, 0.03, -0.19)},
}
for k in list(RIG.keys()):
    if k.endswith("_r"):
        v = RIG[k]
        par = v["parent"].replace("_r", "_l") if v["parent"].endswith("_r") else v["parent"]
        RIG[k[:-2] + "_l"] = {"parent": par, "pivot": (-v["pivot"][0], v["pivot"][1], v["pivot"][2]),
                              "end": (-v["end"][0], v["end"][1], v["end"][2])}

# collision shapes (rest pose), mass
SHAPES = {
    "pelvis": {"type": "box", "center": (0.0, 0.915, 0.0), "size": (0.33, 0.2, 0.24), "mass": 10.0},
    "belly": {"type": "capsule", "a": (0.0, 1.03, 0.0), "b": (0.0, 1.16, 0.0), "radius": 0.13, "mass": 8.0},
    "chest": {"type": "box", "center": (0.0, 1.335, 0.0), "size": (0.4, 0.31, 0.24), "mass": 14.0},
    "head": {"type": "sphere", "center": (0.0, 1.665, 0.0), "radius": 0.14, "mass": 5.0},
    "upper_arm": {"type": "capsule", "radius": 0.062, "mass": 2.5},
    "forearm": {"type": "capsule", "radius": 0.052, "mass": 1.8},
    "hand": {"type": "capsule", "radius": 0.045, "mass": 0.6},
    "thigh": {"type": "capsule", "radius": 0.085, "mass": 7.0},
    "shin": {"type": "capsule", "radius": 0.07, "mass": 4.0},
    "foot": {"type": "box", "size": (0.1, 0.09, 0.24), "mass": 1.2},
}

MIRROR = lambda p: (-p[0], p[1], p[2])  # noqa: E731

# ------------------------------------------------------------------ chibi warp
# The body and every piece of gear are first modelled with realistic proportions
# (simple to author) and then squashed into Human-Fall-Flat proportions: a huge
# head, a wide stubby torso, short thick limbs, mitten hands and big boots.
# Each rig part gets an affine map about its own pivot (axial / radial scale
# along its bone), chained so the joints stay connected. Gear follows the map of
# the part it is attached to, and the animation code sees the rebuilt rig.json.
#            axial, radial
CHIBI = {
    "pelvis": (1.0, 1.32), "belly": (1.0, 1.32), "chest": (1.0, 1.32),
    "head": (1.85, 1.85),
    "upper_arm": (0.95, 1.5), "forearm": (0.95, 1.5), "hand": (1.55, 1.55),
    "thigh": (0.76, 1.42), "shin": (0.76, 1.42), "foot": (1.38, 1.38),
}
PART_ORDER = ["pelvis", "belly", "chest", "head", "upper_arm_r", "forearm_r", "hand_r", "upper_arm_l", "forearm_l", "hand_l",
              "thigh_r", "shin_r", "foot_r", "thigh_l", "shin_l", "foot_l"]


def _base(name):
    return name[:-2] if name.endswith(("_r", "_l")) else name


class PartWarp:
    def __init__(self, old_p, new_p, mat):
        self.old_p = Vector(old_p)
        self.new_p = Vector(new_p)
        self.mat = mat

    def __call__(self, v):
        return self.new_p + self.mat @ (Vector(v) - self.old_p)

    def scale3(self):
        """Approximate per-axis scale (for boxes)."""
        return Vector((abs(self.mat[0][0]) + abs(self.mat[0][1]) * 0.0, abs(self.mat[1][1]), abs(self.mat[2][2])))


def build_warps():
    from mathutils import Matrix
    warps = {}
    for name in PART_ORDER:
        r = RIG[name]
        old_p = Vector(r["pivot"])
        par = r["parent"]
        new_p = old_p.copy() if par == "" else warps[par](old_p)
        d = (Vector(r["end"]) - old_p).normalized()
        ax, rad = CHIBI[_base(name)]
        outer = Matrix(((d.x * d.x, d.x * d.y, d.x * d.z), (d.y * d.x, d.y * d.y, d.y * d.z), (d.z * d.x, d.z * d.y, d.z * d.z)))
        mat = Matrix.Identity(3) * rad + outer * (ax - rad)
        warps[name] = PartWarp(old_p, new_p, mat)
    # put the soles of the boots back on the ground
    foot = warps["foot_r"]
    c = foot(Vector((RIG["foot_r"]["pivot"][0], 0.047, -0.055)))
    bottom = c.y - 0.09 * CHIBI["foot"][0] * 0.5
    dy = -bottom
    for w in warps.values():
        w.new_p = w.new_p + Vector((0.0, dy, 0.0))
    return warps


WARPS = None


def warps():
    global WARPS
    if WARPS is None:
        WARPS = build_warps()
    return WARPS


def _part(name, build):
    B = Builder()
    build(B)
    W = warps()[name]
    transform_since(B, 0, W)
    ob = B.to_object(name)
    ob = subsurf(ob, 1)
    set_origin(ob, W(RIG[name]["pivot"]))
    return ob


def build_body():
    objs = []
    objs.append(_part("pelvis", lambda B: (
        superellipsoid(B, "cloth_bottom", (0.0, 0.915, 0.005), (0.36, 0.22, 0.265), p=0.55, segs=20, rings=12),
        lathe(B, [(-0.036, 0.168), (-0.03, 0.178), (0.03, 0.178), (0.036, 0.168)], "cloth_accent",
              center=(0.0, 1.0, 0.0), sides=28, xz_scale=(1.08, 0.82), cap_bottom=False, cap_top=False))))
    objs.append(_part("belly", lambda B: superellipsoid(B, "cloth_top", (0.0, 1.095, 0.0), (0.31, 0.26, 0.235), p=0.75, segs=20, rings=12)))

    def chest(B):
        def widen(x, y, z):
            t = y / 0.34 + 0.5
            return x * (0.86 + 0.26 * t), y, z * (0.95 + 0.08 * t)
        superellipsoid(B, "cloth_top", (0.0, 1.335, 0.0), (0.4, 0.34, 0.26), p=0.5, segs=22, rings=12, deform=widen)
        # kimono collar: two crossing bands on the front (left over right)
        for side in (1, -1):
            v0, _ = B.mark()
            box(B, "cloth_accent", (0.0, 0.0, 0.0), (0.05, 0.26, 0.012), smooth=True)

            def place(p, side=side):
                q = Vector(p)
                ang = math.radians(28 * side)
                x = q.x * math.cos(ang) - q.y * math.sin(ang)
                y = q.x * math.sin(ang) + q.y * math.cos(ang)
                return Vector((x + 0.05 * side, y + 1.36, q.z - 0.132 - (0.004 if side > 0 else 0.0)))
            transform_since(B, v0, place)
    objs.append(_part("chest", chest))

    def head(B):
        # a round bean head, a touch wider than tall (Human Fall Flat), never egg-shaped
        superellipsoid(B, "skin", (0.0, 1.66, 0.0), (0.31, 0.285, 0.295), p=0.92, segs=28, rings=18)
    objs.append(_part("head", head))

    for side, sx in (("r", 1.0), ("l", -1.0)):
        def upper(B, sx=sx, side=side):
            capsule(B, "cloth_top", RIG["upper_arm_" + side]["pivot"], RIG["upper_arm_" + side]["end"], 0.072, 0.062, sides=16, bulge=0.012)
        objs.append(_part("upper_arm_" + side, upper))

        def fore(B, sx=sx, side=side):
            capsule(B, "cloth_top", RIG["forearm_" + side]["pivot"], RIG["forearm_" + side]["end"], 0.06, 0.05, sides=16)
        objs.append(_part("forearm_" + side, fore))

        def hand(B, sx=sx, side=side):
            w = Vector(RIG["hand_" + side]["pivot"])
            superellipsoid(B, "skin", (w.x + 0.004 * sx, w.y - 0.06, w.z - 0.006), (0.068, 0.125, 0.094), p=0.72, segs=16, rings=10)
            capsule(B, "skin", (w.x - 0.012 * sx, w.y - 0.03, w.z - 0.035), (w.x - 0.02 * sx, w.y - 0.075, w.z - 0.05), 0.019, 0.017, sides=10, cap_rings=3, body_rings=3)
        objs.append(_part("hand_" + side, hand))

        def thigh(B, side=side):
            capsule(B, "cloth_bottom", RIG["thigh_" + side]["pivot"], RIG["thigh_" + side]["end"], 0.102, 0.086, sides=18, bulge=0.008)
        objs.append(_part("thigh_" + side, thigh))

        def shin(B, side=side):
            capsule(B, "cloth_bottom", RIG["shin_" + side]["pivot"], RIG["shin_" + side]["end"], 0.083, 0.095, sides=18, bulge=-0.006)
        objs.append(_part("shin_" + side, shin))

        def foot(B, side=side, sx=sx):
            a = Vector(RIG["foot_" + side]["pivot"])
            superellipsoid(B, "feet", (a.x, 0.047, -0.055), (0.106, 0.094, 0.255), p=0.62, segs=16, rings=10)
        objs.append(_part("foot_" + side, foot))
    blib.export(objs, "characters/body.glb")
    return objs


# ------------------------------------------------------------------ gear

def piece(name, build, origin, sub=1, thickness=0.0):
    B = Builder()
    build(B)
    W = warps()[name.split("__")[0]]
    transform_since(B, 0, W)
    origin = W(origin)
    ob = B.to_object(name)
    if thickness > 0.0:
        ob = solidify(ob, thickness)
    if sub:
        ob = subsurf(ob, sub)
    set_origin(ob, origin)
    return ob


def ring_band(B, material, y0, y1, rx, rz, flare=1.04, center=(0.0, 0.0, 0.0), sides=28, angle_range=None):
    lathe(B, [(y0, flare), (y1, 1.0)], material, center=(center[0], 0.0, center[2]), sides=sides,
          xz_scale=(rx, rz), cap_bottom=False, cap_top=False, smooth=True, angle_range=angle_range)


def along(B, v0, p0, p1):
    """Maps local geometry built around +Y at the origin onto segment p0->p1."""
    p0 = Vector(p0)
    d = (Vector(p1) - p0).normalized()
    rot = Vector((0, 1, 0)).rotation_difference(d).to_matrix()
    transform_since(B, v0, lambda q: rot @ q + p0)


def build_gear():
    out = []
    # ---- cuirass (do): lamellar bands on chest and belly
    def do_upper(B):
        ys = [1.2, 1.255, 1.31, 1.365, 1.42]
        for i, y in enumerate(ys):
            ring_band(B, "armor_plate", y, y + 0.068, 0.232 + i * 0.004, 0.152, flare=1.05)
        # munaita (top breast plate) and shoulder straps
        box(B, "armor_trim", (0.0, 1.475, -0.143), (0.25, 0.06, 0.02), smooth=True)
        for sx in (1, -1):
            box(B, "leather", (0.13 * sx, 1.5, 0.0), (0.07, 0.03, 0.3), smooth=True)
    out.append(piece("chest__do", do_upper, RIG["chest"]["pivot"], thickness=0.012))

    def do_lower(B):
        for i, y in enumerate([1.02, 1.08, 1.14]):
            ring_band(B, "armor_plate", y, y + 0.066, 0.178 + i * 0.012, 0.137 + i * 0.006, flare=1.05)
    out.append(piece("belly__do", do_lower, RIG["belly"]["pivot"], thickness=0.011))

    # ---- kusazuri (tassets) hanging from the waist, each one swings
    for i, ang in enumerate((-38.0, 38.0, -108.0, 108.0, 180.0)):
        a = math.radians(ang)
        def tasset(B, a=a):
            for k in range(4):
                y1 = 1.01 - k * 0.058
                y0 = y1 - 0.066
                r_top = 1.0 + k * 0.07
                lathe(B, [(y0, r_top + 0.07), (y1, r_top)], "armor_plate", center=(0.0, 0.0, 0.0), sides=6,
                      xz_scale=(0.195, 0.155), cap_bottom=False, cap_top=False,
                      angle_range=(a - math.pi / 2 - 0.36, a - math.pi / 2 + 0.36))
        hinge = (math.sin(a) * 0.195, 1.01, -math.cos(a) * 0.155)
        out.append(piece("pelvis__kusazuri_%d" % i, tasset, hinge, thickness=0.01))

    # ---- sode (shoulder guards)
    for side, sx in (("r", 1.0), ("l", -1.0)):
        def sode(B, sx=sx):
            for k in range(5):
                y1 = 1.49 - k * 0.052
                y0 = y1 - 0.06
                cx = 0.2 * sx
                lathe(B, [(y0, 0.125 + k * 0.004), (y1, 0.12 + k * 0.004)], "armor_plate", center=(cx, 0.0, 0.0), sides=8,
                      cap_bottom=False, cap_top=False,
                      angle_range=((-0.9 if sx > 0 else math.pi - 0.9), (0.9 if sx > 0 else math.pi + 0.9)))
            box(B, "armor_trim", (0.32 * sx, 1.495, 0.0), (0.02, 0.022, 0.2), smooth=True)
        out.append(piece("upper_arm_%s__sode" % side, sode, (0.3 * sx, 1.49, 0.0), thickness=0.01))

        # ---- kote (armoured sleeve) along the forearm
        def kote(B, side=side):
            v0, _ = B.mark()
            prof = [(0.0, 0.07), (0.05, 0.068), (0.12, 0.064), (0.2, 0.058), (0.245, 0.054)]
            lathe(B, prof, "armor_plate", sides=14, cap_bottom=False, cap_top=False, angle_range=(-2.3, 2.3))
            along(B, v0, RIG["forearm_" + side]["pivot"], RIG["forearm_" + side]["end"])
        out.append(piece("forearm_%s__kote" % side, kote, RIG["forearm_" + side]["pivot"], thickness=0.008))

        def tekko(B, side=side, sx=sx):
            w = Vector(RIG["hand_" + side]["pivot"])
            superellipsoid(B, "metal_dark", (w.x + 0.03 * sx, w.y - 0.05, w.z), (0.022, 0.08, 0.085), p=0.6, segs=10, rings=6)
        out.append(piece("hand_%s__tekko" % side, tekko, RIG["hand_" + side]["pivot"]))

        # ---- haidate (thigh apron)
        def haidate(B, side=side):
            v0, _ = B.mark()
            prof = [(0.03, 0.118), (0.15, 0.112), (0.27, 0.104)]
            lathe(B, prof, "armor_plate", sides=10, cap_bottom=False, cap_top=False, angle_range=(-math.pi / 2 - 1.2, -math.pi / 2 + 1.2))
            along(B, v0, RIG["thigh_" + side]["pivot"], RIG["thigh_" + side]["end"])
        out.append(piece("thigh_%s__haidate" % side, haidate, RIG["thigh_" + side]["pivot"], thickness=0.009))

        # ---- suneate (shin guards) + knee cap
        def suneate(B, side=side):
            v0, _ = B.mark()
            prof = [(0.03, 0.098), (0.2, 0.1), (0.34, 0.105)]
            lathe(B, prof, "metal_dark", sides=9, cap_bottom=False, cap_top=False, angle_range=(-math.pi / 2 - 1.05, -math.pi / 2 + 1.05))
            along(B, v0, RIG["shin_" + side]["pivot"], RIG["shin_" + side]["end"])
            k = Vector(RIG["shin_" + side]["pivot"])
            superellipsoid(B, "armor_plate", (k.x, k.y - 0.02, k.z - 0.085), (0.12, 0.11, 0.035), p=0.6, segs=12, rings=6)
        out.append(piece("shin_%s__suneate" % side, suneate, RIG["shin_" + side]["pivot"], thickness=0.008))

    # ---- hats
    head_pivot = RIG["head"]["pivot"]

    def kasa(B):
        prof = [(1.772, 0.355), (1.79, 0.31), (1.83, 0.22), (1.87, 0.12), (1.898, 0.045), (1.906, 0.0)]
        lathe(B, prof, "straw", sides=40, cap_bottom=False, cap_top=False)
        lathe(B, [(1.79, 0.128), (1.83, 0.126)], "cord", sides=24, cap_bottom=False, cap_top=False)
    out.append(piece("head__kasa", kasa, head_pivot, thickness=0.012))

    def jingasa(B):
        prof = [(1.79, 0.295), (1.81, 0.26), (1.845, 0.18), (1.87, 0.09), (1.882, 0.0)]
        lathe(B, prof, "armor_plate", sides=36, cap_bottom=False, cap_top=False)
        lathe(B, [(1.878, 0.05), (1.886, 0.045)], "gold", sides=20, cap_bottom=False, cap_top=True)
    out.append(piece("head__jingasa", jingasa, head_pivot, thickness=0.01))

    def kabuto(B):
        prof = [(1.68, 0.157), (1.74, 0.155), (1.79, 0.14), (1.83, 0.108), (1.86, 0.06), (1.872, 0.0)]
        lathe(B, prof, "armor_plate", sides=48, cap_bottom=False, cap_top=False,
              radius_fn=lambda a, h, r: r * (1.0 + 0.025 * abs(math.sin(a * 16.0))))
        # shikoro: flared neck guard, open at the face
        for k in range(3):
            y1 = 1.69 - k * 0.04
            lathe(B, [(y1 - 0.05, 0.18 + k * 0.03), (y1, 0.162 + k * 0.03)], "armor_plate", sides=24,
                  cap_bottom=False, cap_top=False, angle_range=(-math.pi / 2 + 0.75, -math.pi / 2 + math.tau - 0.75))
        # fukigaeshi (turn-backs) and maedate (golden horns)
        for sx in (1, -1):
            box(B, "armor_plate", (0.15 * sx, 1.7, -0.12), (0.06, 0.07, 0.015), smooth=True)
            v0, _ = B.mark()
            pts = [Vector((0.03 * sx, 1.75, -0.16)), Vector((0.07 * sx, 1.83, -0.2)), Vector((0.12 * sx, 1.93, -0.19)), Vector((0.14 * sx, 2.02, -0.15))]
            blib.tube(B, "gold", pts, [0.012, 0.01, 0.007, 0.002], sides=6)
        box(B, "gold", (0.0, 1.765, -0.162), (0.05, 0.05, 0.012), smooth=True)
    out.append(piece("head__kabuto", kabuto, head_pivot, thickness=0.01))

    def hachimaki(B):
        lathe(B, [(1.725, 1.0), (1.755, 1.0)], "cloth_accent", sides=28, xz_scale=(0.139, 0.139), cap_bottom=False, cap_top=False)
        for sx in (1, -1):
            v0, _ = B.mark()
            pts = [Vector((0.02 * sx, 1.74, 0.135)), Vector((0.05 * sx, 1.7, 0.17)), Vector((0.07 * sx, 1.64, 0.2))]
            blib.tube(B, "cloth_accent", pts, [0.012, 0.01, 0.006], sides=5)
    out.append(piece("head__hachimaki", hachimaki, head_pivot, thickness=0.006))

    def topknot(B):
        pts = [Vector((0.0, 1.815, 0.035)), Vector((0.0, 1.845, 0.0)), Vector((0.0, 1.85, -0.055))]
        blib.tube(B, "hair", pts, [0.03, 0.024, 0.016], sides=10)
        superellipsoid(B, "hair", (0.0, 1.8, 0.0), (0.2, 0.08, 0.22), p=0.9, segs=16, rings=8)
    out.append(piece("head__topknot", topknot, head_pivot))

    def menpo(B):
        prof = [(1.555, 0.118), (1.585, 0.132), (1.62, 0.139), (1.655, 0.137)]
        lathe(B, prof, "mask", sides=14, cap_bottom=False, cap_top=False, angle_range=(-math.pi / 2 - 1.15, -math.pi / 2 + 1.15))
        superellipsoid(B, "mask", (0.0, 1.645, -0.142), (0.04, 0.05, 0.035), p=0.7, segs=10, rings=6)  # nose
        for sx in (1, -1):  # mustache
            v0, _ = B.mark()
            pts = [Vector((0.008 * sx, 1.618, -0.145)), Vector((0.05 * sx, 1.61, -0.14)), Vector((0.085 * sx, 1.585, -0.12))]
            blib.tube(B, "hair", pts, [0.01, 0.009, 0.003], sides=6)
        for i in range(5):  # teeth
            box(B, "teeth", (-0.032 + i * 0.016, 1.592, -0.138), (0.012, 0.014, 0.01), smooth=True)
    out.append(piece("head__menpo", menpo, head_pivot, thickness=0.008))

    # ---- eyes: one eyeball per side (sclera, iris, pupil, shine) that the game rotates
    # to look at things, and an eyelid dome per side that blinks and squints.
    EYE_C = (0.062, 1.682, -0.108)
    for name, sx in (("r", 1.0), ("l", -1.0)):
        c = (EYE_C[0] * sx, EYE_C[1], EYE_C[2])

        def eye(B, c=c, sx=sx):
            superellipsoid(B, "eye_white", c, (0.072, 0.082, 0.07), p=0.98, segs=20, rings=14)
            superellipsoid(B, "iris", (c[0] + 0.001 * sx, c[1] - 0.001, c[2] - 0.026), (0.046, 0.052, 0.02), p=0.9, segs=16, rings=8)
            superellipsoid(B, "eyes", (c[0] + 0.001 * sx, c[1] - 0.001, c[2] - 0.0335), (0.026, 0.03, 0.012), p=0.9, segs=12, rings=6)
            superellipsoid(B, "eye_shine", (c[0] + 0.011 * sx, c[1] + 0.013, c[2] - 0.0335), (0.012, 0.013, 0.008), p=0.9, segs=8, rings=5)
        out.append(piece("head__eye_%s" % name, eye, c, sub=0))

        def lid(B, c=c):
            R = 0.0405
            prof = []
            for k in range(0, 9):
                a = math.radians(k * 90.0 / 8.0)
                prof.append((-R * math.sin(a), R * math.cos(a) + 0.0005))
            lathe(B, prof, "skin", center=c, axis="z", sides=20, cap_bottom=False, cap_top=True, smooth=True)
        out.append(piece("head__lid_%s" % name, lid, c, sub=0))

    for style, tilt in (("calm", 6.0), ("angry", -24.0)):
        def brows(B, tilt=tilt):
            for sx in (1, -1):
                v0, _ = B.mark()
                box(B, "hair", (0.0, 0.0, 0.0), (0.058, 0.013, 0.014), smooth=True)
                ang = math.radians(tilt) * sx

                def place(p, sx=sx, ang=ang):
                    x = p.x * math.cos(ang) - p.y * math.sin(ang)
                    y = p.x * math.sin(ang) + p.y * math.cos(ang)
                    return Vector((x + 0.06 * sx, y + 1.748, p.z - 0.128))
                transform_since(B, v0, place)
        out.append(piece("head__brows_%s" % style, brows, head_pivot, sub=0))

    def beard(B):
        superellipsoid(B, "hair", (0.0, 1.575, -0.085), (0.2, 0.13, 0.13), p=0.85, segs=16, rings=10,
                       deform=lambda x, y, z: (x, y - max(0.0, -z) * 0.25, z))
    out.append(piece("head__beard", beard, head_pivot))

    def sashimono(B):
        pts = [Vector((0.0, 1.3, 0.16)), Vector((0.0, 2.35, 0.19))]
        blib.tube(B, "wood_dark", pts, [0.013, 0.011], sides=6)
        blib.quad(B, "banner", (0.0, 1.78, 0.19), (0.0, 1.78, 0.52), (0.0, 2.3, 0.52), (0.0, 2.3, 0.19),
                  uvs=((0, 0), (1, 0), (1, 1), (0, 1)))
        blib.quad(B, "banner", (0.0, 2.3, 0.19), (0.0, 2.3, 0.52), (0.0, 1.78, 0.52), (0.0, 1.78, 0.19),
                  uvs=((0, 1), (1, 1), (1, 0), (0, 0)))
    out.append(piece("chest__sashimono", sashimono, RIG["chest"]["pivot"], sub=0))

    blib.export(out, "characters/gear.glb")
    return out


def write_rig():
    W = warps()
    rig = {"parts": {}, "shapes": {}, "meta": {}}
    for k, v in RIG.items():
        w = W[k]
        rig["parts"][k] = {"parent": v["parent"], "pivot": list(w(v["pivot"])), "end": list(w(v["end"]))}
    for k, v in RIG.items():
        base = _base(k)
        w = W[k]
        ax, rad = CHIBI[base]
        sh = dict(SHAPES[base])
        if sh["type"] == "capsule" and "a" not in sh:
            sh["a"] = v["pivot"]
            sh["b"] = v["end"]
        if k.startswith("foot"):
            sh["center"] = (v["pivot"][0], 0.047, -0.055)
        out = {"type": sh["type"], "mass": round(sh["mass"] * rad * rad * ax, 2)}
        if sh["type"] == "capsule":
            out["a"] = list(w(sh["a"]))
            out["b"] = list(w(sh["b"]))
            out["radius"] = sh["radius"] * rad
        elif sh["type"] == "sphere":
            out["center"] = list(w(sh["center"]))
            out["radius"] = sh["radius"] * rad
        else:
            out["center"] = list(w(sh["center"]))
            out["size"] = [sh["size"][0] * rad, sh["size"][1] * (ax if k.startswith("foot") else 1.0 if base in ("pelvis", "chest") else ax), sh["size"][2] * rad]
        rig["shapes"][k] = out
    # numbers the animation code needs to remap its human-scale constants
    old_chest = RIG["chest"]["pivot"][1]
    new_chest = rig["parts"]["chest"]["pivot"][1]
    rig["meta"] = {
        "upper_shift": round(new_chest - old_chest, 4),
        "ankle_height": round(rig["parts"]["foot_r"]["pivot"][1], 4),
        "hand_grip_drop": round(0.064 * CHIBI["hand"][0], 4),
        "head_center_y": round(rig["shapes"]["head"]["center"][1], 4),
        "hip_height": round(rig["parts"]["thigh_r"]["pivot"][1], 4),
        "height": round(rig["shapes"]["head"]["center"][1] + rig["shapes"]["head"]["radius"], 4),
    }
    path = os.path.join(blib.MODELS, "characters", "rig.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(rig, f, indent=1)
    print("    rig.json written", rig["meta"])


def build():
    blib.reset()
    build_body()
    blib.reset()
    build_gear()
    write_rig()
