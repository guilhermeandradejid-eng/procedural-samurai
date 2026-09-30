"""Helpers shared by the clip scripts: sword key frames in character space, the
whole-body pipeline (edge follows the cut, reach solver, head counter-rotation) and
the footwork of a lunge."""
import numpy as np

import authoring as A

# resting guard (chudan): hands at chest height, tip towards the eyes
GUARD = dict(pos=(0.02, 1.12, -0.24), blade=(0.0, 0.5, -0.86))
EDGE0 = (0.0, -0.86, -0.5)
# stance: right foot forward
STANCE = dict(fr_x=0.2, fr_z=-0.15, fl_x=-0.2, fl_z=0.13)
# hand on the sheathed hilt (the scabbard sits on the front left of the belt)
HILT = dict(pos=(-0.12, 0.93, -0.26), blade=(-0.25, -0.3, 0.92))


def K(c, t, pos, blade, crouch=0.0, lean=0.0, left=1.0, w=1.0, edge=EDGE0, **kw):
    x, y, z = pos
    c.key(t, g_x=x, g_y=y, g_z=z, g_bx=blade[0], g_by=blade[1], g_bz=blade[2],
          g_ex=edge[0], g_ey=edge[1], g_ez=edge[2], g_w=w, g_left=left, s_lean=lean, py=-crouch, **kw)


def KG(c, t, **kw):
    K(c, t, GUARD["pos"], GUARD["blade"], **kw)


def KH(c, t, **kw):
    kw.setdefault("left", 0.0)
    K(c, t, HILT["pos"], HILT["blade"], edge=(0.0, 1.0, 0.0), **kw)


def pipeline(head_k=0.8, **solver):
    def fn(ch, clip):
        A.auto_edge(ch, clip)
        clip.solver_out = A.reach_solver(ch, clip, **solver)
        # eyes stay on the front: the head counter-rotates against the torso, a little late
        ts = np.arange(len(ch["px"])) / clip.fps
        tw = ch["p_yaw"] + ch["s_yaw"]
        ch["h_yaw"] = ch["h_yaw"] - head_k * np.interp(ts - 0.03, ts, tw)
    return fn


def feet(c, t_lift, t_land, dist, t_rel, t_end, front_z=-0.15, rear_z=0.13, stretch=0.1):
    """Right-foot-forward lunge: the front foot steps out and is pinned when it lands,
    the rear foot slides along behind the pelvis and settles again."""
    tm = 0.5 * (t_lift + t_land)
    c.key(0.0, fr_x=0.2, fr_z=front_z, fr_y=0.0, fl_x=-0.2, fl_z=rear_z, fl_y=0.0, cr=1, cl=1)
    c.key(t_lift, fr_x=0.2, fr_z=front_z, fr_y=0.0, cr=0)
    c.key(tm, fr_x=0.21, fr_z=front_z - 0.5 * dist - 0.05, fr_y=0.12)
    c.key(t_land, fr_x=0.22, fr_z=front_z - stretch - 0.12, fr_y=0.0, cr=1, fl_z=rear_z + 0.3 * dist, cl=0, fl_y=0.015)
    c.key(t_rel, fl_x=-0.22, fl_z=rear_z + 0.34 * dist, fl_y=0.015, fr_z=front_z - stretch - 0.1)
    c.key(t_end, fr_x=0.2, fr_z=front_z, fl_x=-0.2, fl_z=rear_z, fl_y=0.0, cl=1)


# ---------------------------------------------------------------- chest-space authoring
def bl(az, el=0.0):
    """blade direction in the chest frame: azimuth (deg, + = to the right of the chest's
    forward) and elevation (deg, + = up)"""
    a, e = np.radians(az), np.radians(el)
    return (float(np.sin(a) * np.cos(e)), float(np.sin(e)), float(-np.cos(a) * np.cos(e)))


def C(c, t, hand, blade, yaw=(0.0, 0.0), crouch=0.0, lean=0.0, left=1.0, w=1.0, **kw):
    """key with the grip in the chest frame (hand = grip position relative to the chest
    pivot, x right / y up / z back) and explicit torso twist: yaw = (pelvis, spine) in
    degrees, positive = turn left. The whole chest turns by pelvis + spine."""
    c.key(t, g_x=hand[0], g_y=hand[1], g_z=hand[2], g_bx=blade[0], g_by=blade[1], g_bz=blade[2],
          g_ex=0.0, g_ey=-0.86, g_ez=-0.5, g_w=w, g_left=left, p_yaw=yaw[0], s_yaw=yaw[1],
          s_lean=lean, py=-crouch, **kw)


def CG(c, t, **kw):
    C(c, t, (0.0, 0.10, -0.22), bl(0, 30), **kw)


def chest_pipeline(head_k=0.8):
    def fn(ch, clip):
        ts = np.arange(len(ch["px"])) / clip.fps
        tw = ch["p_yaw"] + ch["s_yaw"]
        ch["h_yaw"] = ch["h_yaw"] - head_k * np.interp(ts - 0.03, ts, tw)
    return fn
