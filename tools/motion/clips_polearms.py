"""Kanabo (iron club) and yari (spear) moves for the brutes and spearmen, authored in
the chest frame like the katana moves (see clips_katana.py)."""
import numpy as np

import authoring as A
from kit import feet, C, bl, chest_pipeline

STANCE = dict(fr_x=0.2, fr_z=-0.15, fl_x=-0.2, fl_z=0.13)


def _n(v):
    v = np.array(v, float)
    return tuple(v / np.linalg.norm(v))


KANABO_GUARD = dict(hand=(0.04, 0.19, -0.18), blade=_n((0.1, 0.92, 0.3)))
YARI_GUARD = dict(hand=(0.05, 0.02, -0.02), blade=_n((-0.05, 0.25, -0.96)))


def CGK(c, t, **kw):
    C(c, t, KANABO_GUARD["hand"], KANABO_GUARD["blade"], **kw)


def CGY(c, t, **kw):
    C(c, t, YARI_GUARD["hand"], YARI_GUARD["blade"], **kw)


def smash():
    """overhead slam"""
    c = A.Clip("kanabo_smash", 1.35)
    c.edge_auto = True
    c.left_off = -0.12
    c.auto = chest_pipeline()
    CGK(c, 0.0, crouch=0.03, lean=4)
    C(c, 0.5, (0.0, 0.46, 0.04), _n((0.0, 0.4, 0.92)), yaw=(0, 0), crouch=0.0, lean=-14)
    C(c, 0.62, (0.0, 0.48, 0.06), _n((0.0, 0.3, 0.95)), yaw=(0, 0), crouch=0.0, lean=-16)
    C(c, 0.71, (0.0, 0.40, -0.10), _n((0.0, 0.98, -0.2)), yaw=(0, 0), crouch=0.08, lean=6)
    C(c, 0.8, (0.0, 0.12, -0.22), _n((0.0, -0.4, -0.92)), yaw=(0, 0), crouch=0.2, lean=22, left=0.85)
    C(c, 1.0, (0.0, 0.06, -0.22), _n((0.0, -0.8, -0.6)), yaw=(0, 0), crouch=0.24, lean=26, left=0.85)
    CGK(c, 1.35, crouch=0.03, lean=4)
    feet(c, 0.52, 0.8, 0.8, 1.0, 1.25)
    c.meta = {"strike": 0.78}
    return c


def sweep():
    """wide horizontal swing"""
    c = A.Clip("kanabo_sweep", 1.1)
    c.edge_auto = True
    c.left_off = -0.12
    c.auto = chest_pipeline()
    CGK(c, 0.0, crouch=0.03, lean=4)
    C(c, 0.4, (0.16, 0.10, -0.06), _n((0.85, 0.2, 0.45)), yaw=(-20, -26), crouch=0.06, lean=-4)
    C(c, 0.58, (0.0, 0.10, -0.24), _n((-0.2, 0.0, -0.98)), yaw=(0, -4), crouch=0.08, lean=6)
    C(c, 0.72, (-0.02, 0.08, -0.16), _n((-0.9, -0.1, 0.4)), yaw=(26, 16), crouch=0.08, lean=8, left=0.7)
    CGK(c, 1.1, crouch=0.03, lean=4)
    feet(c, 0.4, 0.58, 0.5, 0.8, 1.0)
    c.meta = {"strike": 0.56}
    return c


def thrust():
    c = A.Clip("yari_thrust", 0.8)
    c.edge_auto = False
    c.left_off = 0.2
    c.auto = chest_pipeline()
    CGY(c, 0.0, crouch=0.03, lean=4)
    C(c, 0.28, (0.10, 0.0, 0.16), _n((-0.05, 0.25, -0.97)), yaw=(-10, -14), crouch=0.05, lean=-2)
    C(c, 0.42, (0.05, 0.02, -0.14), _n((-0.02, 0.12, -0.99)), yaw=(6, 8), crouch=0.10, lean=12, left=0.6)
    CGY(c, 0.8, crouch=0.03, lean=4)
    feet(c, 0.24, 0.42, 0.7, 0.55, 0.7)
    c.meta = {"strike": 0.42}
    return c


def spear_sweep():
    c = A.Clip("yari_sweep", 1.0)
    c.edge_auto = False
    c.left_off = 0.2
    c.auto = chest_pipeline()
    CGY(c, 0.0, crouch=0.03, lean=4)
    C(c, 0.36, (0.20, 0.08, 0.02), _n((0.8, 0.3, -0.5)), yaw=(-14, -22), crouch=0.04, lean=0, left=0.6)
    C(c, 0.52, (0.0, 0.06, -0.12), _n((-0.5, 0.15, -0.85)), yaw=(4, 0), crouch=0.06, lean=6, left=0.5)
    C(c, 0.66, (-0.06, 0.05, -0.06), _n((-0.95, 0.1, -0.1)), yaw=(22, 16), crouch=0.06, lean=6, left=0.3)
    CGY(c, 1.0, crouch=0.03, lean=4)
    feet(c, 0.34, 0.52, 0.3, 0.7, 0.9)
    c.meta = {"strike": 0.5}
    return c


ALL = [smash, sweep, thrust, spear_sweep]


def build(out_dir):
    for fn in ALL:
        c = fn()
        A.bake_clip(c, out_dir)
        print("baked %-14s reach r %.2f l %.2f" % (c.name, A.REACH["r"].max(), A.REACH["l"].max()))
