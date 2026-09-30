"""Turns the output of a text-to-motion model into a game clip.

Any text-to-motion tool that writes SMPL joint positions in the HumanML3D layout
(22 joints, +Y up, character facing +Z, 20 fps) can feed the game: MDM, MoMask,
T2M-GPT, MotionGPT, AnimationGPT (combat / katana moves), HY-Motion, Kimodo (its
posed joints)... The importer

  1. converts the axes (SMPL -> game: x,y,z -> -x,y,-z) and resamples to 30 fps,
  2. finds the pelvis / chest / head frames and the bone directions, and solves the
     local rotation of every rig part (limb bend planes give the elbow / knee hinge),
  3. removes the character's world travel (the game moves the capsule itself; the
     travel is kept in the clip meta so attack lunges can use it),
  4. detects foot contacts, grounds the feet on the ground and lifts body parts that
     would dig into the floor,
  5. optionally derives the two-hand weapon grip from the wrists (blade = left wrist
     -> right wrist), so sword moves keep both hands on the hilt.

    python3 import_smpl.py motion.npy my_clip [--loop] [--weapon] [--fps 20] [--speed 1.0]
"""
import argparse
import os
import sys

import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.spatial.transform import Rotation as R

import clipio
import locomotion
import mo_rig
import posefx
import preview
from mo_rig import IDX, N, limb_basis, normalize

# the rig's foot bone (ankle -> toe end) points slightly downwards at rest
_rr = mo_rig.Rig()
_fd = _rr.end[IDX["foot_r"]] - _rr.pivot[IDX["foot_r"]]
FOOT_REST_PITCH = float(np.degrees(np.arctan2(-_fd[1], -_fd[2])))

J = dict(pelvis=0, l_hip=1, r_hip=2, spine1=3, l_knee=4, r_knee=5, spine2=6, l_ankle=7, r_ankle=8, spine3=9,
         l_foot=10, r_foot=11, neck=12, l_collar=13, r_collar=14, head=15, l_shoulder=16, r_shoulder=17,
         l_elbow=18, r_elbow=19, l_wrist=20, r_wrist=21)


# ---------------------------------------------------------------- loading

def recover_from_ric(data, joints_num=22):
    """HumanML3D 263-d features (de-normalised) -> joint positions (T, J, 3)."""
    data = np.asarray(data, float)
    T = data.shape[0]
    rot_vel = data[:, 0]
    ang = np.zeros(T)
    ang[1:] = rot_vel[:-1]
    ang = np.cumsum(ang)
    rq = R.from_quat(np.stack([np.zeros(T), np.sin(ang), np.zeros(T), np.cos(ang)], axis=1))   # x,y,z,w about Y
    r_pos = np.zeros((T, 3))
    r_pos[1:, [0, 2]] = data[:-1, 1:3]
    r_pos = rq.inv().apply(r_pos)
    r_pos = np.cumsum(r_pos, axis=0)
    r_pos[:, 1] = data[:, 3]
    pos = data[:, 4:(joints_num - 1) * 3 + 4].reshape(T, joints_num - 1, 3)
    pos = np.stack([rq.inv().apply(pos[:, j]) for j in range(joints_num - 1)], axis=1)
    pos[..., 0] += r_pos[:, 0:1]
    pos[..., 2] += r_pos[:, 2:3]
    return np.concatenate([r_pos[:, None, :], pos], axis=1)


def load_motion(path):
    a = np.load(path, allow_pickle=True)
    if a.dtype == object:
        a = a.item()
        a = a.get("joints", a.get("posed_joints"))
    a = np.asarray(a, float)
    if a.ndim == 4:
        a = a[0]
    if a.ndim == 3 and a.shape[1] >= 22:
        return a[:, :22]
    if a.ndim == 2 and a.shape[1] == 263:
        return recover_from_ric(a)
    raise ValueError("unsupported motion array of shape %s" % (a.shape,))


# ---------------------------------------------------------------- helpers

def resample(P, fps_in, fps_out):
    T = P.shape[0]
    n = max(2, int(round((T - 1) / fps_in * fps_out)) + 1)
    src = np.arange(T) / fps_in
    dst = np.linspace(0, src[-1], n)
    out = np.zeros((n,) + P.shape[1:])
    flat = P.reshape(T, -1)
    for k in range(flat.shape[1]):
        out.reshape(n, -1)[:, k] = np.interp(dst, src, flat[:, k])
    return out


def frame_from(x_axis, y_hint):
    """Right-handed frame (columns x=right, y=up, z=back) from a right vector and an up hint."""
    x = normalize(x_axis)
    y = y_hint - x * np.sum(y_hint * x, axis=-1, keepdims=True)
    y = normalize(y)
    z = normalize(np.cross(x, y))
    return mo_rig.rot_from_basis(x, y, z)


def solve_rotations(P, rig, arm_abduct_deg=7.0):
    """P: joint positions in game axes, character-space (T,22,3). Returns local
    quaternions (T,16,4) and the pelvis world frame Rotation."""
    T = P.shape[0]
    g = lambda n: P[:, J[n]]
    up_world = np.tile([0.0, 1.0, 0.0], (T, 1))
    hips_x = g("r_hip") - g("l_hip")
    spine_up = normalize(g("spine3") - g("pelvis"))
    pel = frame_from(hips_x, spine_up)
    sh_x = g("r_shoulder") - g("l_shoulder")
    chest_up = normalize(g("neck") - g("spine1"))
    chest = frame_from(sh_x, chest_up)
    belly = R.from_quat(mo_rig.quat_slerp(pel.as_quat(), chest.as_quat(), 0.45))
    # head: pitch/roll from the neck->head bone, yaw follows the chest
    head_up = normalize(g("head") - g("neck"))
    head = frame_from(sh_x, head_up)
    world = {"pelvis": pel, "belly": belly, "chest": chest, "head": head}
    loc = {}
    loc["pelvis"] = pel
    loc["belly"] = pel.inv() * belly
    loc["chest"] = belly.inv() * chest
    loc["head"] = chest.inv() * head
    for side, s in (("r", "r"), ("l", "l")):
        sgn = 1.0 if side == "r" else -1.0
        # ---- arm
        sh, el, wr = g(side + "_shoulder"), g(side + "_elbow"), g(side + "_wrist")
        d1, d2 = normalize(el - sh), normalize(wr - el)
        hinge = np.cross(d1, d2)
        hn = np.linalg.norm(hinge, axis=1, keepdims=True)
        ref = chest.apply(np.array([1.0, 0, 0]))
        hinge = np.where(hn > 0.02, hinge / np.maximum(hn, 1e-9), ref)
        # blend towards the reference axis when the arm is almost straight (stable twist)
        wgt = np.clip(hn / 0.12, 0, 1)
        hinge = normalize(hinge * wgt + ref * (1 - wgt))
        ua_w = limb_basis(d1, hinge)
        fa_w = limb_basis(d2, hinge)
        hd_w = fa_w * R.from_euler("X", 8.0, degrees=True)
        ab = R.from_euler("Z", sgn * arm_abduct_deg, degrees=True)
        loc["upper_arm_" + s] = chest.inv() * ua_w * ab
        ua_w2 = ua_w * ab
        loc["forearm_" + s] = ab.inv() * ua_w.inv() * fa_w
        loc["hand_" + s] = fa_w.inv() * hd_w
        world["upper_arm_" + s] = ua_w2
        # ---- leg
        hp, kn, an = g(side + "_hip"), g(side + "_knee"), g(side + "_ankle")
        e1, e2 = normalize(kn - hp), normalize(an - kn)
        lh = -np.cross(e1, e2)
        ln = np.linalg.norm(lh, axis=1, keepdims=True)
        ref = pel.apply(np.array([1.0, 0, 0]))
        lh = np.where(ln > 0.02, lh / np.maximum(ln, 1e-9), ref)
        wl = np.clip(ln / 0.12, 0, 1)
        lh = normalize(lh * wl + ref * (1 - wl))
        th_w = limb_basis(e1, lh)
        sh_w = limb_basis(e2, lh)
        # foot: forward = ankle -> toe, up from the world
        toe = g(side + "_foot")
        f_fwd = normalize(toe - an)
        f_z = -f_fwd
        f_x = normalize(np.cross(up_world, f_z))
        f_y = normalize(np.cross(f_z, f_x))
        ft_w = mo_rig.rot_from_basis(f_x, f_y, f_z) * R.from_euler("X", FOOT_REST_PITCH, degrees=True)
        loc["thigh_" + s] = pel.inv() * th_w
        loc["shin_" + s] = th_w.inv() * sh_w
        loc["foot_" + s] = sh_w.inv() * ft_w
    q = np.zeros((T, N, 4))
    for name, r in loc.items():
        q[:, IDX[name]] = r.as_quat()
    for i in range(N):
        for t in range(1, T):
            if np.dot(q[t, i], q[t - 1, i]) < 0:
                q[t, i] = -q[t, i]
    return q, pel, chest


# ---------------------------------------------------------------- pipeline

def import_motion(P_smpl, fps_in=20.0, fps_out=30.0, weapon=False, loop=False, smooth=1.0, speed=1.0, name="imported", arm_abduct=7.0):
    rig = mo_rig.Rig()
    P = np.asarray(P_smpl, float).copy()
    # SMPL (x left, y up, z forward) -> game (x right, y up, -z forward)
    P[..., 0] *= -1.0
    P[..., 2] *= -1.0
    if smooth > 0:
        P = gaussian_filter1d(P, smooth, axis=0, mode="nearest")
    P = resample(P, fps_in * speed, fps_out)
    T = P.shape[0]
    # data proportions -> rig scale
    leg = np.median(np.linalg.norm(P[:, J["r_hip"]] - P[:, J["r_knee"]], axis=1) + np.linalg.norm(P[:, J["r_knee"]] - P[:, J["r_ankle"]], axis=1))
    leg += np.median(np.linalg.norm(P[:, J["l_hip"]] - P[:, J["l_knee"]], axis=1) + np.linalg.norm(P[:, J["l_knee"]] - P[:, J["l_ankle"]], axis=1))
    leg *= 0.5
    scale = (rig.length("thigh_r") + rig.length("shin_r")) / leg
    # heading of the first frame defines "forward"; remove it
    fwd0 = np.cross([0, 1, 0], P[0, J["r_hip"]] - P[0, J["l_hip"]])   # the character's front (-z when facing forward)
    heading0 = np.arctan2(-fwd0[0], -fwd0[2])
    Ry0 = R.from_rotvec([0, -heading0, 0])
    Pw = Ry0.apply(P.reshape(-1, 3)).reshape(P.shape)
    root0 = Pw[0, J["pelvis"]].copy()
    root0[1] = 0.0
    # world travel of the pelvis (horizontal) and its low-passed path
    travel = Pw[:, J["pelvis"]] - root0
    travel[:, 1] = 0.0
    contacts_world = _foot_contacts(Pw, fps_out)
    # in-place positions: subtract the low-passed horizontal path so bob/sway stay
    path = gaussian_filter1d(travel, max(2.0, fps_out * 0.25), axis=0, mode="nearest") if not loop else travel * 0.0
    if loop:
        # cyclic: remove a linear trend
        tt = np.arange(T) / fps_out
        A_ = np.stack([tt, np.ones_like(tt)], axis=1)
        for ax in (0, 2):
            k = np.linalg.lstsq(A_, travel[:, ax], rcond=None)[0]
            path[:, ax] = A_ @ k
    Pl = Pw.copy()
    Pl[..., 0] -= (root0[0] + path[:, None, 0])
    Pl[..., 2] -= (root0[2] + path[:, None, 2])
    q, pel, chest = solve_rotations(Pl, rig, arm_abduct)
    # pelvis position in the rig: height scaled to the short legs, horizontal wobble scaled
    stand = np.percentile(Pl[:, J["pelvis"], 1], 90)
    pel_pos = np.zeros((T, 3))
    pel_pos[:, 0] = (Pl[:, J["pelvis"], 0]) * scale
    pel_pos[:, 2] = (Pl[:, J["pelvis"], 2]) * scale
    pel_pos[:, 1] = rig.rest_pelvis[1] + scale * (Pl[:, J["pelvis"], 1] - stand)
    pose = {"pelvis_pos": pel_pos, "rot": q}
    # contacts on the world motion, then ground calibration on the rig
    flags = contacts_world.astype(float)
    if flags.sum() > 0:
        locomotion.calibrate_ground(pose, flags)
    lift = posefx.ground_clamp(pose, clearance=0.0)
    meta = {
        "source": "text-to-motion", "scale": round(float(scale), 4),
        "root_travel": [round(float(x), 4) for x in (travel[-1] * scale)],
        "root_path": [[round(float(v), 4) for v in p] for p in (travel[::3] * scale)],
    }
    grip = None
    if weapon:
        grip = derive_grip(Pl, pose, rig, scale)
    return {"pelvis_pos": pose["pelvis_pos"], "rot": pose["rot"], "contacts": flags, "grip": grip, "meta": meta, "fps": fps_out}


def _foot_contacts(Pw, fps, height_thr=0.11, toe_thr=0.07, vel_thr=0.6):
    """Flags (T,2) [right, left] for planted feet from the world motion."""
    out = np.zeros((Pw.shape[0], 2))
    ground = min(Pw[:, J["r_foot"], 1].min(), Pw[:, J["l_foot"], 1].min())
    for k, (an, ft) in enumerate((("r_ankle", "r_foot"), ("l_ankle", "l_foot"))):
        a = Pw[:, J[an]]
        v = np.linalg.norm(np.gradient(a, axis=0)[:, [0, 2]], axis=1) * fps
        c = (a[:, 1] - ground < height_thr + 0.06) & (Pw[:, J[ft], 1] - ground < toe_thr + 0.04) & (v < vel_thr)
        out[:, k] = locomotion._clean(c, 3)
    return out


def derive_grip(Pl, pose, rig, scale):
    """Two-hand sword grip from the wrists: the hilt sits on the right hand, the blade
    points from the left wrist towards the right one. Returns (T,12) in the chest frame."""
    T = Pl.shape[0]
    pw, rw = rig.fk(pose["pelvis_pos"], pose["rot"])
    ci = IDX["chest"]
    rwr, lwr = Pl[:, J["r_wrist"]], Pl[:, J["l_wrist"]]
    blade = rwr - lwr
    bl = np.linalg.norm(blade, axis=1, keepdims=True)
    # forearm direction as a fallback when the hands are together
    fa = normalize(Pl[:, J["r_wrist"]] - Pl[:, J["r_elbow"]])
    blade = np.where(bl > 0.05, blade / np.maximum(bl, 1e-9), fa)
    blade = normalize(gaussian_filter1d(blade, 1.5, axis=0, mode="nearest"))
    # wrist position on the rig: relative to the chest joint, scaled with the arms
    chest_joint = Pl[:, J["spine3"]]
    rel = (rwr - chest_joint) * scale
    pos_w = pw[:, ci] + rw[ci].apply(np.array([0.0, 0.16, 0.0])) + rel
    grip = np.zeros((T, 12))
    cinv = rw[ci].inv()
    grip[:, 0:3] = cinv.apply(pos_w - pw[:, ci])
    grip[:, 3:6] = cinv.apply(blade)
    edge = np.tile([0.0, -0.86, -0.5], (T, 1))
    grip[:, 6:9] = edge
    grip[:, 9] = 1.0
    grip[:, 10] = 1.0
    return grip


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("motion")
    ap.add_argument("name")
    ap.add_argument("--fps", type=float, default=20.0)
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--weapon", action="store_true")
    ap.add_argument("--speed", type=float, default=1.0, help="playback speed factor")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    P = load_motion(a.motion)
    res = import_motion(P, a.fps, 30.0, a.weapon, a.loop, speed=a.speed, name=a.name)
    path = clipio.save(a.name, 30.0, a.loop, res["pelvis_pos"], res["rot"], res["contacts"], grip=res["grip"], meta=res["meta"], out_dir=a.out)
    print("wrote", path, "frames", res["pelvis_pos"].shape[0])


if __name__ == "__main__":
    main()
