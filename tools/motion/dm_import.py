"""Loads DeepMimic / PyBullet humanoid motion clips (real motion capture that
ships with the `pybullet_data` package) and retargets them to the game rig.

The DeepMimic humanoid has the same joint topology as the game rig (root,
chest, neck, hips, knees, ankles, shoulders, elbows) and every joint frame is
aligned with the world at rest, so joint rotations copy across directly once
the axes are converted (DeepMimic: +X forward, +Y up, +Z right  ->  game:
-Z forward, +Y up, +X right).
"""
import json
import os

import numpy as np
from scipy.spatial.transform import Rotation as R

import mo_rig
from mo_rig import IDX, N

# DeepMimic frame layout (after the frame duration):
# root pos(3) root rot(4) chest(4) neck(4) r_hip(4) r_knee(1) r_ankle(4)
# r_shoulder(4) r_elbow(1) l_hip(4) l_knee(1) l_ankle(4) l_shoulder(4) l_elbow(1)  [quats w,x,y,z]
M = np.array([[0, 0, 1.0], [0, 1.0, 0], [-1.0, 0, 0]])   # dm -> game axes
STAND_HEIGHT = 0.88   # DeepMimic pelvis height when standing straight (m)
DM_LEG = 0.8315       # hip to ankle (m)


def _q_dm(w, x, y, z):
    """DeepMimic quaternion (w,x,y,z) -> rotation in game axes."""
    v = M @ np.array([x, y, z])
    return R.from_quat([v[0], v[1], v[2], w])


def load(path, fps=30.0):
    d = json.load(open(path))
    fr = np.array(d["Frames"], dtype=float)
    dur = fr[:, 0]
    t = np.concatenate([[0.0], np.cumsum(dur)[:-1]])
    total = float(np.sum(dur))
    loop = d.get("Loop", "none") == "wrap"
    n_out = max(2, int(round(total * fps)))
    if loop:
        ts = np.arange(n_out) * total / n_out
    else:
        ts = np.linspace(0, t[-1], n_out)
    out = {"loop": loop, "duration": total if loop else float(t[-1]), "fps": fps}
    # resample: linear for positions/scalars, slerp for quaternions
    def interp_cols(cols):
        return np.stack([np.interp(ts, t, fr[:, c], period=total if loop else None) for c in cols], axis=-1)

    def interp_quat(c0):
        q = fr[:, c0:c0 + 4]
        res = np.zeros((n_out, 4))
        idx = np.searchsorted(t, ts, side="right") - 1
        idx = np.clip(idx, 0, len(t) - 1)
        nxt = (idx + 1) % len(t) if loop else np.minimum(idx + 1, len(t) - 1)
        t1 = t[idx]
        t2 = np.where(nxt > idx, t[nxt], total if loop else t[nxt])
        u = np.where(t2 > t1, (ts - t1) / np.maximum(t2 - t1, 1e-9), 0.0)
        a = q[idx]
        b = q[nxt]
        # (w,x,y,z) -> (x,y,z,w) for our slerp
        a = a[:, [1, 2, 3, 0]]
        b = b[:, [1, 2, 3, 0]]
        r = mo_rig.quat_slerp(a, b, u)
        return r  # x,y,z,w in DM axes

    root_pos = interp_cols([1, 2, 3])
    q_root = interp_quat(4)
    layout = [("chest", 8, "q"), ("neck", 12, "q"), ("r_hip", 16, "q"), ("r_knee", 20, "s"),
              ("r_ankle", 21, "q"), ("r_shoulder", 25, "q"), ("r_elbow", 29, "s"),
              ("l_hip", 30, "q"), ("l_knee", 34, "s"), ("l_ankle", 35, "q"),
              ("l_shoulder", 39, "q"), ("l_elbow", 43, "s")]
    joints = {}
    for name, c, kind in layout:
        if kind == "q":
            joints[name] = interp_quat(c)
        else:
            joints[name] = np.interp(ts, t, fr[:, c], period=total if loop else None)
    out.update(root_pos=root_pos, q_root=q_root, joints=joints, n=n_out)
    return out


def _to_game_quat(q_xyzw_dm):
    """(T,4) x,y,z,w in DM axes -> game axes (vector part rotated by M)."""
    v = q_xyzw_dm[:, :3] @ M.T
    return np.concatenate([v, q_xyzw_dm[:, 3:4]], axis=1)


def _hinge_quat(theta):
    """Rotation about +X of the game frame by theta (DM revolute about +Z)."""
    return R.from_rotvec(np.stack([theta, np.zeros_like(theta), np.zeros_like(theta)], axis=-1)).as_quat()


def retarget(clip, rig, arm_abduct_deg=7.0, ref_height=STAND_HEIGHT, remove_travel=True):
    """Returns dict(pelvis_pos (T,3), rot (T,16,4), travel_speed, heading)."""
    T = clip["n"]
    j = clip["joints"]
    rot = np.zeros((T, N, 4))
    rot[..., 3] = 1.0
    # root orientation in game axes, heading removed
    qr = _to_game_quat(clip["q_root"])
    Rr = R.from_quat(qr)
    fwd = Rr.apply(np.array([0, 0, -1.0]))
    psi = np.unwrap(np.arctan2(-fwd[:, 0], -fwd[:, 2]))
    psi_mean = float(np.mean(psi))
    Ry_inv = R.from_rotvec([0, -psi_mean, 0])
    pelvis_rot = Ry_inv * Rr
    rot[:, IDX["pelvis"]] = pelvis_rot.as_quat()
    # spine: split the chest rotation evenly between belly and chest
    qc = R.from_quat(_to_game_quat(j["chest"]))
    half = R.from_rotvec(qc.as_rotvec() * 0.5).as_quat()
    rot[:, IDX["belly"]] = half
    rot[:, IDX["chest"]] = half
    rot[:, IDX["head"]] = _to_game_quat(j["neck"])
    for side, s in (("r", "r"), ("l", "l")):
        rot[:, IDX["thigh_" + s]] = _to_game_quat(j[side + "_hip"])
        rot[:, IDX["shin_" + s]] = _hinge_quat(j[side + "_knee"])
        rot[:, IDX["foot_" + s]] = _to_game_quat(j[side + "_ankle"])
        ua = R.from_quat(_to_game_quat(j[side + "_shoulder"]))
        # the chibi torso is wider than a human one: swing the arms out a little
        sign = 1.0 if s == "r" else -1.0
        ab = R.from_rotvec(np.tile([0, 0, np.deg2rad(arm_abduct_deg) * sign], (T, 1)))
        rot[:, IDX["upper_arm_" + s]] = (ab * ua).as_quat()
        rot[:, IDX["forearm_" + s]] = _hinge_quat(j[side + "_elbow"])
    # pelvis translation: heading-relative, travel removed, height scaled to the short legs
    p = clip["root_pos"] @ M.T
    loc = Ry_inv.apply(p - p[0])
    speed = 0.0
    if remove_travel and clip["loop"]:
        tt = np.arange(T) / clip["fps"]
        A = np.stack([tt, np.ones_like(tt)], axis=1)
        kz = np.linalg.lstsq(A, loc[:, 2], rcond=None)[0]
        kx = np.linalg.lstsq(A, loc[:, 0], rcond=None)[0]
        speed = float(-kz[0])
        loc[:, 2] -= A @ kz
        loc[:, 0] -= A @ kx
        loc[:, 2] -= loc[:, 2].mean()
        loc[:, 0] -= loc[:, 0].mean()
    else:
        loc[:, 0] -= loc[0, 0]
        loc[:, 2] -= loc[0, 2]
    leg_ratio = (rig.length("thigh_r") + rig.length("shin_r")) / DM_LEG
    y = p[:, 1]
    pelvis = np.zeros((T, 3))
    pelvis[:, 0] = loc[:, 0] * leg_ratio
    pelvis[:, 2] = loc[:, 2] * leg_ratio
    pelvis[:, 1] = rig.rest_pelvis[1] + leg_ratio * (y - ref_height)
    return {"pelvis_pos": pelvis, "rot": rot, "dm_speed": speed, "leg_ratio": leg_ratio, "psi_mean": psi_mean}


def ground(clip_pose, min_clearance=0.0):
    """Shifts the pelvis so the lowest sole of the whole clip touches the ground."""
    import preview
    sh = preview.sole_heights(clip_pose["pelvis_pos"], clip_pose["rot"])
    dy = min_clearance - float(sh.min())
    clip_pose["pelvis_pos"][:, 1] += dy
    return dy
