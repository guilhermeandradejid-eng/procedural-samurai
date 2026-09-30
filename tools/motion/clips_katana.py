"""Katana moves. The sword path is authored in character space (x right, y up,
-z forward, rig units); a reach solver twists and bends the torso as far as
needed to keep the short chibi arms comfortably bent, the hips lead the chest in
time and the head keeps looking ahead. Feet are authored explicitly (lunge step,
sliding rear foot)."""
import numpy as np

import authoring as A
from kit import K, KG, KH, STANCE, pipeline, feet, C, CG, bl, chest_pipeline

def _n(v):
    v = np.array(v, float)
    return tuple(v / np.linalg.norm(v))


def light_1():
    """yoko-giri: horizontal slash, right to left. The torso does the sweeping: the hips
    turn first, then the chest, the hands stay close in front of the body."""
    c = A.Clip("katana_light_1", 0.62)
    c.edge_auto = True
    c.auto = chest_pipeline()
    CG(c, 0.0, crouch=0.03, lean=4)
    C(c, 0.09, (0.10, 0.06, -0.14), bl(80, 10), yaw=(-16, -22), crouch=0.08, lean=2)
    C(c, 0.15, (0.07, 0.07, -0.20), bl(58, 6), yaw=(-14, -20), crouch=0.09, lean=5)
    C(c, 0.20, (0.0, 0.08, -0.26), bl(8, 2), yaw=(8, -2), crouch=0.10, lean=10)
    C(c, 0.26, (-0.03, 0.07, -0.24), bl(-40, 0), yaw=(20, 6), crouch=0.10, lean=12, left=0.8)
    C(c, 0.33, (-0.02, 0.07, -0.20), bl(-62, -2), yaw=(27, 15), crouch=0.10, lean=11, left=0.55)
    C(c, 0.44, (-0.02, 0.07, -0.18), bl(-66, -3), yaw=(27, 15), crouch=0.08, lean=9, left=0.6)
    CG(c, 0.62, crouch=0.03, lean=4)
    feet(c, 0.06, 0.22, 0.6, 0.32, 0.5)
    c.meta = {"strike": 0.24}
    return c


def light_2():
    """kesa-giri: rises overhead, diagonal cut down to the right"""
    c = A.Clip("katana_light_2", 0.68)
    c.edge_auto = True
    c.auto = chest_pipeline()
    CG(c, 0.0, crouch=0.03, lean=4)
    C(c, 0.10, (-0.02, 0.42, -0.06), _n((-0.3, 0.72, 0.62)), yaw=(14, 10), crouch=0.0, lean=-6)
    C(c, 0.16, (-0.02, 0.40, -0.20), _n((-0.1, 0.95, -0.3)), yaw=(8, 4), crouch=0.04, lean=0)
    C(c, 0.23, (0.02, 0.18, -0.34), _n((0.25, 0.1, -0.96)), yaw=(-2, -6), crouch=0.10, lean=9)
    C(c, 0.30, (0.08, 0.06, -0.24), _n((0.6, -0.7, -0.35)), yaw=(-14, -12), crouch=0.14, lean=15)
    C(c, 0.38, (0.10, 0.02, -0.20), _n((0.62, -0.75, -0.1)), yaw=(-18, -16), crouch=0.16, lean=17)
    C(c, 0.50, (0.10, 0.03, -0.20), _n((0.62, -0.72, -0.12)), yaw=(-16, -14), crouch=0.14, lean=15)
    CG(c, 0.68, crouch=0.03, lean=4)
    feet(c, 0.08, 0.25, 0.65, 0.36, 0.56)
    c.meta = {"strike": 0.26}
    return c


def light_3():
    """kaiten-zan: low coil to the right, then a one-handed whirl (the root spins in game)"""
    c = A.Clip("katana_light_3", 0.86)
    c.edge_auto = True
    c.auto = chest_pipeline(head_k=0.4)
    CG(c, 0.0, crouch=0.03, lean=4)
    C(c, 0.12, (0.30, 0.06, -0.06), bl(100, -10), yaw=(-16, -24), crouch=0.17, lean=6, left=0.4)
    C(c, 0.20, (0.46, 0.14, -0.16), bl(90, 2), yaw=(-6, -10), crouch=0.12, lean=4, left=0.0)
    C(c, 0.33, (0.48, 0.16, -0.18), bl(88, 3), yaw=(0, -14), crouch=0.10, lean=5, left=0.0)
    C(c, 0.46, (0.42, 0.14, -0.2), bl(80, 4), yaw=(4, -8), crouch=0.09, lean=4, left=0.2)
    C(c, 0.58, (0.04, 0.09, -0.28), bl(10, 5), yaw=(0, 0), crouch=0.07, lean=3, left=1.0)
    CG(c, 0.86, crouch=0.03, lean=4)
    c.key(0.0, fr_x=0.2, fr_z=-0.15, fl_x=-0.2, fl_z=0.13, cr=1, cl=1)
    c.key(0.16, fr_x=0.24, fr_z=-0.1, fl_x=-0.24, fl_z=0.2)
    c.key(0.5, fr_x=0.22, fr_z=-0.12, fl_x=-0.22, fl_z=0.16)
    c.key(0.86, fr_x=0.2, fr_z=-0.15, fl_x=-0.2, fl_z=0.13)
    c.meta = {"strike": 0.34}
    return c


def heavy_charge():
    c = A.Clip("katana_heavy_charge", 0.3)
    c.edge_auto = False
    c.auto = chest_pipeline()
    CG(c, 0.0, crouch=0.03, lean=4)
    C(c, 0.3, (0.10, 0.30, -0.02), _n((0.2, 0.85, 0.5)), yaw=(-8, -10), crouch=0.09, lean=-8)
    c.key(0.0, fr_x=0.2, fr_z=-0.15, fl_x=-0.2, fl_z=0.13, cr=1, cl=1)
    c.key(0.3, fr_x=0.2, fr_z=-0.15, fl_x=-0.2, fl_z=0.16)
    return c


def heavy():
    """ichimonji: the sword crashes down from above the head into the ground"""
    c = A.Clip("katana_heavy", 0.78)
    c.edge_auto = True
    c.auto = chest_pipeline()
    C(c, 0.0, (0.10, 0.30, -0.02), _n((0.2, 0.85, 0.5)), yaw=(-8, -10), crouch=0.09, lean=-8)
    C(c, 0.05, (0.02, 0.36, -0.02), _n((0.1, 0.95, 0.3)), yaw=(-4, -4), crouch=0.02, lean=-10)
    C(c, 0.09, (0.01, 0.30, -0.14), _n((0.0, 0.7, -0.7)), yaw=(0, -2), crouch=0.06, lean=0)
    C(c, 0.12, (0.0, 0.20, -0.26), _n((-0.05, 0.1, -0.99)), yaw=(2, 0), crouch=0.10, lean=10)
    C(c, 0.22, (0.0, 0.04, -0.24), _n((-0.05, -0.92, -0.38)), yaw=(4, 2), crouch=0.24, lean=26)
    C(c, 0.30, (0.0, 0.02, -0.24), _n((-0.05, -0.95, -0.3)), yaw=(4, 2), crouch=0.26, lean=28)
    C(c, 0.50, (0.0, 0.03, -0.24), _n((-0.05, -0.92, -0.35)), yaw=(3, 2), crouch=0.22, lean=22)
    CG(c, 0.78, crouch=0.03, lean=4)
    feet(c, 0.0, 0.16, 1.0, 0.36, 0.64, stretch=0.16)
    c.meta = {"strike": 0.16}
    return c


def counter():
    """answer after a deflect: a fast rising diagonal from low right to high left"""
    c = A.Clip("katana_counter", 0.5)
    c.edge_auto = True
    c.auto = chest_pipeline()
    CG(c, 0.0, crouch=0.03, lean=4)
    C(c, 0.05, (0.10, -0.05, -0.16), _n((0.5, -0.6, -0.6)), yaw=(-12, -14), crouch=0.12, lean=6, left=0.6)
    C(c, 0.14, (0.05, 0.10, -0.26), _n((0.1, 0.35, -0.93)), yaw=(4, -2), crouch=0.09, lean=8, left=0.6)
    C(c, 0.24, (-0.06, 0.34, -0.14), _n((-0.6, 0.7, -0.4)), yaw=(14, 10), crouch=0.04, lean=4)
    C(c, 0.34, (-0.06, 0.34, -0.12), _n((-0.65, 0.68, -0.3)), yaw=(15, 12), crouch=0.03, lean=3)
    CG(c, 0.5, crouch=0.03, lean=4)
    feet(c, 0.0, 0.14, 0.7, 0.26, 0.42)
    c.meta = {"strike": 0.14}
    return c


def iai():
    """nuki-uchi: the blade leaves the scabbard in one horizontal flash"""
    c = A.Clip("katana_iai", 0.62)
    c.grip_space = "root"
    c.auto = pipeline()
    KH(c, 0.0, crouch=0.12, lean=8)
    K(c, 0.05, (-0.08, 1.1, -0.34), (-0.87, 0.0, 0.5), crouch=0.14, lean=10, left=0.0)
    K(c, 0.10, (0.0, 1.16, -0.4), (-0.5, 0.02, -0.87), crouch=0.14, lean=12, left=0.3)
    K(c, 0.16, (0.18, 1.18, -0.36), (0.707, 0.04, -0.707), crouch=0.14, lean=14, left=0.6)
    K(c, 0.24, (0.32, 1.2, -0.2), (0.94, 0.08, 0.34), crouch=0.14, lean=14, left=0.8)
    K(c, 0.62, (0.3, 1.16, -0.12), (0.9, 0.2, 0.36), crouch=0.12, lean=10, left=1.0)
    feet(c, 0.0, 0.14, 1.4, 0.3, 0.6, stretch=0.2)
    c.meta = {"strike": 0.14}
    return c


def assassinate():
    """thrust from behind"""
    c = A.Clip("katana_assassinate", 1.25)
    c.edge_auto = True
    c.auto = chest_pipeline()
    CG(c, 0.0, crouch=0.03, lean=4)
    C(c, 0.22, (0.06, 0.16, 0.02), _n((0.0, 0.05, -1.0)), yaw=(-6, -12), crouch=0.06, lean=-2)
    C(c, 0.36, (0.04, 0.12, -0.30), _n((0.0, -0.05, -1.0)), yaw=(4, 6), crouch=0.12, lean=18)
    C(c, 0.9, (0.04, 0.10, -0.28), _n((0.0, -0.1, -1.0)), yaw=(4, 6), crouch=0.14, lean=20)
    CG(c, 1.25, crouch=0.03, lean=4)
    feet(c, 0.1, 0.3, 0.35, 0.9, 1.15)
    c.meta = {"strike": 0.34}
    return c


ALL = [light_1, light_2, light_3, heavy_charge, heavy, counter, iai, assassinate]


def build(out_dir):
    for fn in ALL:
        c = fn()
        A.bake_clip(c, out_dir)
        rr = A.REACH
        print("baked %-22s reach r %.2f l %.2f" % (c.name, rr["r"].max(), rr["l"].max()))
