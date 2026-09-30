"""Authored non-combat clips: idles, air, sitting/kneeling/praying, reactions and the
weapon handling moves (draw, sheathe, guard). Numbers are rig units and degrees,
see authoring.py for the conventions."""
import authoring as A
from kit import K, KG, KH, STANCE, GUARD, HILT, pipeline

def idle():
    c = A.Clip("idle", 3.2, loop=True)
    c.key(0.0, py=0.0, s_lean=0, p_roll=0.0, h_yaw=0, px=0.0, ar_swing=0, al_swing=0)
    c.key(0.8, py=-0.004, s_lean=1.6, p_roll=0.8, h_yaw=2.0, px=0.006, ar_swing=1.5, al_swing=-1.0, h_pitch=1.0)
    c.key(1.6, py=0.0, s_lean=0.4, p_roll=0.0, h_yaw=0, px=0.0, ar_swing=0, al_swing=0)
    c.key(2.4, py=-0.004, s_lean=1.6, p_roll=-0.8, h_yaw=-2.0, px=-0.006, ar_swing=-1.0, al_swing=1.5, h_pitch=1.0)
    return c


def guard_idle():
    c = A.Clip("guard_idle", 2.4, loop=True)
    base = dict(STANCE, py=-0.03, p_lean=3, s_lean=4, h_pitch=-2)
    c.key(0.0, **base)
    c.key(0.6, **dict(base, py=-0.036, s_lean=5.5, px=0.006, p_roll=0.8))
    c.key(1.2, **base)
    c.key(1.8, **dict(base, py=-0.036, s_lean=5.5, px=-0.006, p_roll=-0.8))
    return c


def crouch_idle():
    c = A.Clip("crouch_idle", 3.0, loop=True)
    base = dict(py=-0.22, p_lean=10, s_lean=16, fr_x=0.19, fl_x=-0.19, fr_z=-0.06, fl_z=0.06, h_pitch=-8, ar_abduct=14, ar_elbow=28, al_abduct=14, al_elbow=28)
    c.key(0.0, **base)
    c.key(1.0, **dict(base, py=-0.226, s_lean=17.5))
    c.key(2.0, **base)
    return c


def air():
    c = A.Clip("air", 1.2, loop=True)
    base = dict(py=-0.05, p_lean=6, s_lean=6, fr_x=0.17, fr_y=0.2, fr_z=-0.14, fl_x=-0.17, fl_y=0.14, fl_z=0.05, cr=0, cl=0,
                ar_swing=30, ar_abduct=35, ar_elbow=40, al_swing=30, al_abduct=35, al_elbow=40, fr_pitch=-15, fl_pitch=-10)
    c.key(0.0, **base)
    c.key(0.6, **dict(base, fr_y=0.16, fl_y=0.2, fr_z=-0.05, fl_z=-0.12, ar_swing=36, al_swing=24))
    c.key(1.2, **base)
    return c


def sit():
    c = A.Clip("sit", 2.0, loop=True)
    base = dict(py=-0.5, p_lean=6, s_lean=8, fr_x=0.24, fr_z=-0.5, fl_x=-0.24, fl_z=-0.5, h_pitch=-3,
                ar_swing=35, ar_elbow=60, al_swing=35, al_elbow=60, knee_out=0.3)
    c.key(0.0, **base)
    c.key(1.0, **dict(base, s_lean=9.5, py=-0.504))
    c.key(2.0, **base)
    return c


def kneel():
    c = A.Clip("kneel", 2.0, loop=True)
    base = dict(py=-0.38, p_lean=4, s_lean=20, fr_x=0.17, fr_z=-0.34, fl_x=-0.15, fl_z=0.32, fl_y=0.0, fl_pitch=-35,
                h_pitch=-10, ar_swing=25, ar_elbow=60, al_swing=25, al_elbow=60)
    c.key(0.0, **base)
    c.key(1.0, **dict(base, s_lean=21.5))
    c.key(2.0, **base)
    return c


def pray():
    c = A.Clip("pray", 2.4, loop=True)
    base = dict(py=-0.38, p_lean=4, s_lean=26, fr_x=0.17, fr_z=-0.34, fl_x=-0.15, fl_z=0.32, fl_pitch=-35, h_pitch=-22,
                ar_swing=45, ar_abduct=-25, ar_elbow=105, al_swing=45, al_abduct=-25, al_elbow=105)
    c.key(0.0, **base)
    c.key(1.2, **dict(base, s_lean=28, h_pitch=-25))
    c.key(2.4, **base)
    return c


def heal():
    c = A.Clip("heal", 1.6, loop=True)
    base = dict(STANCE, py=-0.04, p_lean=3, s_lean=18, h_pitch=-25, al_swing=55, al_abduct=-10, al_elbow=110,
                ar_swing=15, ar_elbow=40)
    c.key(0.0, **base)
    c.key(0.8, **dict(base, s_lean=21, h_pitch=-28))
    c.key(1.6, **base)
    return c


def standoff():
    c = A.Clip("standoff", 3.0, loop=True)
    c.grip_space = "root"
    c.auto = pipeline()
    base = dict(fr_x=0.24, fr_z=-0.2, fl_x=-0.22, fl_z=0.2, p_lean=4, h_pitch=-3)
    KH(c, 0.0, crouch=0.06, lean=7, **base)
    KH(c, 1.5, crouch=0.066, lean=8.5, px=0.005, **base)
    KH(c, 3.0, crouch=0.06, lean=7, **base)
    return c


def iai_ready():
    c = A.Clip("iai_ready", 2.4, loop=True)
    c.grip_space = "root"
    c.auto = pipeline()
    base = dict(fr_x=0.26, fr_z=-0.3, fl_x=-0.24, fl_z=0.26, p_lean=6, h_pitch=-4)
    KH(c, 0.0, crouch=0.14, lean=10, **base)
    KH(c, 1.2, crouch=0.146, lean=10, **base)
    KH(c, 2.4, crouch=0.14, lean=10, **base)
    return c


def getup():
    c = A.Clip("getup", 1.2, loop=False)
    # lying on the back -> sit up -> plant the feet -> stand (0.9 s of action + settle)
    lying = dict(py=-0.55, p_lean=-58, s_lean=-14, fr_x=0.15, fr_z=-0.35, fr_y=0.12, fl_x=-0.15, fl_z=-0.25, fl_y=0.1, cr=0, cl=0,
                 ar_swing=-25, ar_abduct=30, ar_elbow=15, al_swing=-25, al_abduct=30, al_elbow=15, h_pitch=8)
    c.key(0.0, **lying)
    c.key(0.3, **dict(lying, py=-0.5, p_lean=-30, s_lean=6, ar_swing=20, al_swing=20, cr=1, cl=1, fr_y=0, fl_y=0, fr_z=-0.3, fl_z=-0.28))
    c.key(0.6, py=-0.36, p_lean=12, s_lean=30, fr_x=0.17, fr_z=-0.24, fl_x=-0.17, fl_z=0.05, ar_swing=30, al_swing=10, h_pitch=-8)
    c.key(0.95, py=-0.08, p_lean=4, s_lean=10, fr_x=0.19, fr_z=-0.15, fl_x=-0.19, fl_z=0.12, h_pitch=0)
    c.key(1.2, **dict(STANCE, py=-0.03, p_lean=3, s_lean=4))
    return c


def _reaction(name, dur, peak_t, **peak):
    c = A.Clip(name, dur, loop=False)
    base = dict(STANCE, py=-0.03, p_lean=3, s_lean=4)
    c.key(0.0, **base)
    c.key(peak_t, **dict(base, **peak))
    c.key(dur * 0.62, **dict(base, **{k: (v * 0.45 if isinstance(v, (int, float)) and k not in ("fr_x", "fl_x") else v) for k, v in peak.items()}))
    c.key(dur, **base)
    return c


def hit_f():
    return _reaction("hit_f", 0.42, 0.06, py=-0.07, p_lean=-8, s_lean=-16, h_pitch=18, fr_z=-0.1, fl_z=0.2, ar_swing=-25, al_swing=-25, ar_abduct=42, al_abduct=42, ar_elbow=40, al_elbow=40)


def hit_b():
    return _reaction("hit_b", 0.42, 0.06, py=-0.05, p_lean=10, s_lean=22, h_pitch=-14, ar_swing=-35, al_swing=-35, ar_abduct=38, al_abduct=38, ar_elbow=25, al_elbow=25)


def hit_l():
    return _reaction("hit_l", 0.42, 0.06, py=-0.05, p_roll=-10, s_roll=-16, s_yaw=-14, h_roll=-10, px=0.05, ar_abduct=45, al_abduct=30, ar_swing=15, al_swing=-15)


def hit_r():
    return _reaction("hit_r", 0.42, 0.06, py=-0.05, p_roll=10, s_roll=16, s_yaw=14, h_roll=10, px=-0.05, ar_abduct=30, al_abduct=45, ar_swing=-15, al_swing=15)


def stagger():
    c = A.Clip("stagger", 2.4, loop=False)
    base = dict(STANCE, py=-0.03, p_lean=3, s_lean=4)
    rec = dict(base, py=-0.08, p_lean=-6, s_lean=-14, h_pitch=14, fr_z=-0.02, fl_z=0.3, fr_x=0.24, fl_x=-0.24, ar_swing=-35, al_swing=-35, ar_abduct=55, al_abduct=55, ar_elbow=35, al_elbow=35)
    c.key(0.0, **base)
    c.key(0.12, **rec)
    c.key(0.5, **dict(rec, py=-0.06, s_lean=8, p_lean=6, h_pitch=-8, s_roll=6, ar_swing=-10, al_swing=-10, s_yaw=-8))
    c.key(0.9, **dict(rec, py=-0.09, s_lean=18, p_lean=8, h_pitch=-18, s_roll=-6, ar_swing=-20, al_swing=-20, s_yaw=8, h_roll=8))
    c.key(1.5, **dict(rec, py=-0.07, s_lean=12, p_lean=6, h_pitch=-12, s_roll=6, ar_swing=-15, al_swing=-15, s_yaw=-6, h_roll=-8))
    c.key(2.4, **dict(rec, py=-0.09, s_lean=18, p_lean=8, h_pitch=-18, s_roll=-5, ar_swing=-20, al_swing=-20, s_yaw=6, h_roll=6))
    return c


def block():
    c = A.Clip("block", 1.6, loop=True)
    c.grip_space = "root"
    c.auto = pipeline()
    base = dict(STANCE, p_lean=4, fr_z=-0.2, fl_z=0.16, h_pitch=-2)
    B = dict(pos=(0.05, 1.28, -0.22), blade=(-0.6, 0.75, -0.28), edge=(0.0, 0.3, -0.95))
    K(c, 0.0, B["pos"], B["blade"], edge=B["edge"], crouch=0.07, lean=6, **base)
    K(c, 0.8, B["pos"], B["blade"], edge=B["edge"], crouch=0.074, lean=7, **base)
    K(c, 1.6, B["pos"], B["blade"], edge=B["edge"], crouch=0.07, lean=6, **base)
    return c


def parry():
    c = A.Clip("parry", 0.34, loop=False)
    c.grip_space = "root"
    c.auto = pipeline()
    base = dict(STANCE, p_lean=4, fr_z=-0.2, fl_z=0.16)
    K(c, 0.0, (0.05, 1.28, -0.22), (-0.6, 0.75, -0.28), edge=(0.0, 0.3, -0.95), crouch=0.07, lean=6, **base)
    K(c, 0.1, (-0.08, 1.32, -0.3), (-0.92, 0.35, -0.25), edge=(0.0, 0.2, -0.98), crouch=0.09, lean=4, **base)
    KG(c, 0.34, crouch=0.03, lean=4, **dict(STANCE, p_lean=3))
    return c


def draw():
    c = A.Clip("draw", 0.46, loop=False)
    c.grip_space = "root"
    c.auto = pipeline()
    base = dict(STANCE, p_lean=3)
    KH(c, 0.0, left=0.0, crouch=0.04, lean=6, **base)
    K(c, 0.08, (0.0, 0.95, -0.15), (0.5, 0.4, 0.75), left=0.0, crouch=0.05, lean=6, **base)
    K(c, 0.16, (0.15, 1.15, -0.28), (0.4, 0.6, -0.4), left=0.4, crouch=0.04, lean=5, **base)
    K(c, 0.3, (0.06, 1.15, -0.28), (0.1, 0.55, -0.83), left=1.0, crouch=0.03, lean=4, **base)
    KG(c, 0.46, crouch=0.03, lean=4, **base)
    return c


def chiburi():
    c = A.Clip("chiburi", 1.1, loop=False)
    c.grip_space = "root"
    c.auto = pipeline()
    base = dict(STANCE, p_lean=3)
    KG(c, 0.0, crouch=0.03, lean=4, **base)
    K(c, 0.22, (0.26, 1.3, -0.18), (0.3, 0.7, -0.64), left=0.2, crouch=0.03, lean=4, **base)
    K(c, 0.34, (0.36, 1.0, -0.26), (0.5, -0.6, -0.62), left=0.0, crouch=0.04, lean=8, **base)
    K(c, 0.55, (0.1, 1.05, -0.4), (-0.2, 0.0, -0.98), left=0.0, crouch=0.03, lean=4, **base)
    K(c, 0.74, (-0.04, 0.98, -0.32), (-0.95, -0.05, 0.1), left=0.0, crouch=0.03, lean=4, **base)
    KH(c, 0.92, crouch=0.03, lean=5, **base)
    KH(c, 1.1, crouch=0.03, lean=4, **base)
    return c


ALL = [idle, guard_idle, crouch_idle, air, sit, kneel, pray, heal, standoff, iai_ready, getup,
       hit_f, hit_b, hit_l, hit_r, stagger, block, parry, draw, chiburi]


def build(out_dir):
    for fn in ALL:
        c = fn()
        A.bake_clip(c, out_dir)
        extra = ""
        if c.grip_space == "root":
            extra = " reach r %.2f l %.2f" % (A.REACH["r"].max(), A.REACH["l"].max())
        print("baked", c.name, extra)
