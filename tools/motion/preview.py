"""Contact sheets of a motion clip drawn as a stick figure with the game's real
proportions (fast to render, no engine needed). Right limbs red, left blue,
feet turn green while in ground contact and the sword is drawn as a bold line.

    python3 preview.py clip.npz out.png [frames]
"""
import json
import os

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Polygon

import mo_rig
from mo_rig import IDX

_rig = None


def rig():
    global _rig
    if _rig is None:
        _rig = mo_rig.Rig()
    return _rig


def _shapes():
    d = json.load(open(mo_rig.RIG_JSON))
    return d["shapes"]


def figure_points(pelvis_pos, rot):
    """World joint points for drawing. Returns dict of (T,3) arrays."""
    r = rig()
    pw, rw = r.fk(pelvis_pos, rot)
    ends = r.joint_ends(pw, rw)
    P = {}
    for n in mo_rig.ORDER:
        P[n] = pw[:, IDX[n]]
        P[n + "_end"] = ends[:, IDX[n]]
    P["_rw"] = rw
    P["_pw"] = pw
    return P


def sole_heights(pelvis_pos, rot):
    """Lowest point of each foot box (T,2) [r,l]."""
    r = rig()
    pw, rw = r.fk(pelvis_pos, rot)
    sh = _shapes()
    out = []
    for n in ("foot_r", "foot_l"):
        i = IDX[n]
        c = np.array(sh[n]["center"]) - r.pivot[i]
        s = np.array(sh[n]["size"]) * 0.5
        corners = np.array([[sx * s[0], sy * s[1], sz * s[2]] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]) + c
        ys = np.stack([(pw[:, i] + rw[i].apply(cc))[:, 1] for cc in corners], axis=1)
        out.append(ys.min(axis=1))
    return np.stack(out, axis=1)


def _proj(p, view):
    # returns (u, v) for plotting: side view looks from the right: forward (-z) to the right
    if view == "side":
        return -p[..., 2], p[..., 1]
    if view == "front":
        return p[..., 0], p[..., 1]
    return p[..., 0], -p[..., 2]   # top: forward up


def draw_frame(ax, P, t, view, contacts=None, sword=None, grip=None, lim=None, title=None):
    R_, B_ = "#c0392b", "#2471a3"
    def seg(a, b, col, lw):
        ua, va = _proj(P[a][t] if isinstance(a, str) else a, view)
        ub, vb = _proj(P[b][t] if isinstance(b, str) else b, view)
        ax.plot([ua, ub], [va, vb], color=col, lw=lw, solid_capstyle="round")
    # torso: pelvis -> belly -> chest -> head
    for a, b in (("pelvis", "belly"), ("belly", "chest")):
        seg(a, b, "#555", 7)
    seg("chest", "head", "#555", 4)
    # shoulders / hips lines
    seg("upper_arm_r", "upper_arm_l", "#888", 3)
    seg("thigh_r", "thigh_l", "#888", 3)
    # head
    hc = 0.5 * (P["head"][t] + P["head_end"][t])
    hu, hv = _proj(P["head"][t] + 0.55 * (P["head_end"][t] - P["head"][t]), view)
    ax.add_patch(Circle((hu, hv), 0.26, fc="#f5e6d3", ec="#333", lw=1.2, zorder=3))
    # eyes direction marker: front of the head
    for s_, col in (("r", R_), ("l", B_)):
        seg("upper_arm_" + s_, "forearm_" + s_, col, 4.5)
        seg("forearm_" + s_, "hand_" + s_, col, 3.5)
        seg("hand_" + s_, "hand_" + s_ + "_end", col, 2.5)
        seg("thigh_" + s_, "shin_" + s_, col, 5.5)
        seg("shin_" + s_, "foot_" + s_, col, 4.5)
        seg("foot_" + s_, "foot_" + s_ + "_end", col, 3.5)
        if contacts is not None:
            c = contacts[t, 0 if s_ == "r" else 1]
            if c > 0.5:
                u, v = _proj(P["foot_" + s_ + "_end"][t], view)
                ax.plot([u], [v], "o", color="#27ae60", ms=7, zorder=4)
    if grip is not None:
        pos, blade, edge = grip
        tip = pos + blade[t] * 0.75 * 1.0
        base = pos - blade[t] * 0.05
        ua, va = _proj(pos[t] - blade[t] * 0.05, view)
        ub, vb = _proj(pos[t] + blade[t] * 0.85, view)
        ax.plot([ua, ub], [va, vb], color="#111", lw=2.4, zorder=5)
        ax.plot([ua, ub], [va, vb], color="#dfe6e9", lw=1.0, zorder=6)
    ax.axhline(0, color="#795548", lw=1.5) if view != "top" else None
    if lim is None:
        lim = (-1.1, 1.1, -0.1, 2.2)
    ax.set_xlim(lim[0], lim[1])
    ax.set_ylim(lim[2], lim[3])
    ax.set_aspect("equal")
    ax.axis("off")
    if title:
        ax.set_title(title, fontsize=7, pad=1)


def grip_world(clip):
    """World hilt position/blade/edge (T,3 each) from the chest-relative grip channel."""
    g = clip.get("grip")
    if g is None:
        return None
    r = rig()
    pw, rw = r.fk(clip["pelvis_pos"], clip["rot"])
    ci = IDX["chest"]
    pos = pw[:, ci] + rw[ci].apply(g[:, 0:3])
    blade = rw[ci].apply(g[:, 3:6])
    edge = rw[ci].apply(g[:, 6:9])
    on = g[:, 9] > 0.02
    return pos, blade, edge, on


def sheet(clip, frames, path, views=("side", "front"), fps=30, size=1.7, grip=None):
    pelvis_pos, rot = clip["pelvis_pos"], clip["rot"]
    P = figure_points(pelvis_pos, rot)
    if grip is None and clip.get("grip") is not None:
        gw = grip_world(clip)
        grip = (gw[0], gw[1], gw[2]) if gw is not None else None
    contacts = clip.get("contacts")
    ncol = len(frames)
    nrow = len(views)
    fig, axes = plt.subplots(nrow, ncol, figsize=(size * ncol, size * 1.25 * nrow), squeeze=False)
    for ci, f in enumerate(frames):
        for ri, v in enumerate(views):
            lim = (-1.0, 1.0, -0.1, 2.15) if v != "top" else (-1.1, 1.1, -1.1, 1.1)
            ttl = "%.2fs" % (f / fps) if ri == 0 else None
            draw_frame(axes[ri][ci], P, f, v, contacts, grip=grip, lim=lim, title=ttl)
    fig.subplots_adjust(left=0, right=1, top=0.95, bottom=0, wspace=0, hspace=0)
    fig.savefig(path, dpi=80)
    plt.close(fig)
