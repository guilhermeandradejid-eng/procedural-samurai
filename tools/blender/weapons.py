"""Katana (with saya), nodachi, kanabo and yari.

Weapons are modelled with their origin at the grip point of the leading
(right) hand, the blade/shaft along +Y and the cutting edge facing -Z.
Blade UVs: u = 0 at the edge .. 1 at the spine, v = 0 at the base .. 1 at
the tip (used by the Godot shader to draw the hamon and the blood).
"""
import math

from mathutils import Vector

import blib
from blib import Builder, G, box, lathe, set_origin, subsurf, superellipsoid, tube


def blade(B, y0, length, width, sori, thickness=0.007, stations=44, tip=0.07):
    """Lofted blade: pentagonal cross-section (edge, shinogi, spine)."""
    bm = B.bm
    v0, f0 = B.mark()
    rings = []
    for i in range(stations + 1):
        t = i / stations
        y = y0 + t * length
        zc = sori * t * t  # curvature towards the spine (+Z)
        w = width * (1.0 - 0.22 * t)
        tip_t = (t * length - (length - tip)) / tip
        edge_z = -w * 0.5
        spine_z = w * 0.5
        if tip_t > 0.0:
            # kissaki: the edge sweeps up to meet the spine at the point
            k = min(1.0, tip_t)
            edge_z = -w * 0.5 + w * (1.0 - math.sqrt(max(0.0, 1.0 - k * k)))
            spine_z = w * 0.5 - w * 0.08 * k
        th = thickness * (1.0 - 0.35 * t) * (1.0 if tip_t <= 0 else max(0.05, 1.0 - tip_t ** 2))
        shin_z = spine_z - (spine_z - edge_z) * 0.3
        pts = [
            (0.0, edge_z),
            (th * 0.5, shin_z),
            (th * 0.38, spine_z),
            (-th * 0.38, spine_z),
            (-th * 0.5, shin_z),
        ]
        ring = [bm.verts.new(G(px, y, pz + zc)) for px, pz in pts]
        u = [0.0, 0.7, 1.0, 1.0, 0.7]
        rings.append((ring, u, t))
    for i in range(stations):
        ra, ua, ta = rings[i]
        rb, ub, tb = rings[i + 1]
        for s in range(5):
            s1 = (s + 1) % 5
            f = bm.faces.new((ra[s], ra[s1], rb[s1], rb[s]))
            for loop, uv in zip(f.loops, ((ua[s], ta), (ua[s1], ta), (ub[s1], tb), (ub[s], tb))):
                loop[B.uv].uv = uv
    # close the base
    ring, u, t = rings[0]
    try:
        bm.faces.new(list(reversed(ring)))
    except ValueError:
        pass
    B.faces_from(v0, f0, "blade", smooth=False)
    return B


def tsuka(B, y_bottom, y_top, rx=0.017, rz=0.014):
    lathe(B, [(y_bottom, 0.94), (y_bottom + 0.02, 1.0), (y_top - 0.02, 1.0), (y_top, 0.97)], "tsuka_wrap",
          sides=16, xz_scale=(rx, rz), uv_scale=8.0)
    lathe(B, [(y_bottom - 0.012, 0.9), (y_bottom + 0.006, 1.05)], "habaki", sides=16, xz_scale=(rx * 1.05, rz * 1.05))


def tsuba(B, y, rx=0.042, rz=0.038):
    lathe(B, [(y, 1.0), (y + 0.007, 1.0)], "tsuba", sides=28, xz_scale=(rx, rz),
          radius_fn=lambda a, h, r: r * (1.0 + 0.04 * math.cos(a * 4.0)))
    lathe(B, [(y + 0.007, 0.011), (y + 0.035, 0.0095)], "habaki", sides=12, xz_scale=(0.9, 1.9))


def katana():
    B = Builder()
    tsuka(B, -0.255, 0.012)
    tsuba(B, 0.012)
    blade(B, 0.045, 0.705, 0.031, 0.02)
    ob = B.to_object("katana")
    set_origin(ob, (0.0, 0.0, 0.0))
    # scabbard, origin at the mouth (koiguchi)
    S = Builder()
    pts = []
    radii = []
    n = 16
    for i in range(n + 1):
        t = i / n
        pts.append(Vector((0.0, 0.02 + t * 0.73, 0.02 * t * t)))
        radii.append(0.021 - 0.004 * t)
    tube(S, "saya", pts, radii, sides=12, cap=True, uv_scale=2.0)
    lathe(S, [(0.0, 0.0215), (0.022, 0.0215)], "habaki", sides=12)
    lathe(S, [(0.745, 0.0175), (0.765, 0.013)], "tsuba", sides=12, center=(0.0, 0.0, 0.02))
    box(S, "cord", (0.0, 0.09, -0.012), (0.012, 0.04, 0.02), smooth=True)
    tube(S, "cord", [Vector((0.0, 0.1, -0.02)), Vector((0.012, 0.03, -0.07)), Vector((0.0, -0.08, -0.05))], [0.005, 0.005, 0.004], sides=5)
    saya = S.to_object("saya")
    set_origin(saya, (0.0, 0.0, 0.0))
    blib.export([ob, saya], "weapons/katana.glb")


def nodachi():
    B = Builder()
    tsuka(B, -0.44, 0.012, 0.019, 0.016)
    tsuba(B, 0.012, 0.052, 0.047)
    blade(B, 0.045, 1.08, 0.036, 0.03, thickness=0.008)
    ob = B.to_object("nodachi")
    set_origin(ob, (0.0, 0.0, 0.0))
    blib.export([ob], "weapons/nodachi.glb")


def kanabo():
    B = Builder()
    prof = [(-0.34, 0.022), (-0.33, 0.028), (-0.3, 0.026), (0.0, 0.03), (0.2, 0.048), (0.6, 0.07), (0.92, 0.078), (0.96, 0.065), (0.975, 0.0)]
    lathe(B, prof, "wood_dark", sides=8, uv_scale=2.0)
    lathe(B, [(-0.34, 0.03), (-0.3, 0.03)], "metal_dark", sides=8)
    ob = B.to_object("kanabo")
    # studs
    S = Builder()
    for ring in range(8):
        y = 0.25 + ring * 0.09
        r = 0.05 + 0.028 * (ring / 7.0)
        for k in range(8):
            a = k / 8 * math.tau + (ring % 2) * math.pi / 8
            superellipsoid(S, "metal_dark", (math.cos(a) * r, y, math.sin(a) * r), (0.022, 0.022, 0.022), p=1.0, segs=6, rings=4)
    studs = S.to_object("studs")
    ob = blib.join([ob, studs], "kanabo")
    set_origin(ob, (0.0, 0.0, 0.0))
    blib.export([ob], "weapons/kanabo.glb")


def yari():
    B = Builder()
    # held near the butt so the spear out-ranges the swords (grip at y=0)
    lathe(B, [(-0.62, 0.016), (-0.6, 0.02), (1.3, 0.018), (1.32, 0.022), (1.36, 0.02)], "wood_dark", sides=8, uv_scale=3.0)
    ob = B.to_object("yari_shaft")
    S = Builder()
    blade(S, 1.36, 0.28, 0.034, 0.0, thickness=0.012, stations=12, tip=0.12)
    tip = S.to_object("yari_tip")
    ob = blib.join([ob, tip], "yari")
    set_origin(ob, (0.0, 0.0, 0.0))
    blib.export([ob], "weapons/yari.glb")


def build():
    blib.reset()
    katana()
    blib.reset()
    nodachi()
    blib.reset()
    kanabo()
    blib.reset()
    yari()
