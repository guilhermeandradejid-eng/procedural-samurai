"""Whole-clip pose operations used by the bake scripts: ground clamping against
the physical body shapes, pelvis lowering with leg IK (crouching), stride
amplification (sprint) and clip resampling."""
import json

import numpy as np
from scipy.spatial.transform import Rotation as R

import mo_rig
from mo_rig import IDX, N, normalize, limb_basis, solve_ik
import preview

_shapes = None


def shapes():
    global _shapes
    if _shapes is None:
        _shapes = json.load(open(mo_rig.RIG_JSON))["shapes"]
    return _shapes


def lowest_body_point(pelvis_pos, rot):
    """Lowest y of every physical part shape over time (T,)."""
    r = preview.rig()
    pw, rw = r.fk(pelvis_pos, rot)
    T = pelvis_pos.shape[0]
    low = np.full(T, 1e9)
    for n, sh in shapes().items():
        i = IDX[n]
        pts = []
        if sh["type"] == "sphere":
            c = np.array(sh["center"]) - r.pivot[i]
            w = pw[:, i] + rw[i].apply(c)
            low = np.minimum(low, w[:, 1] - sh["radius"])
            continue
        if sh["type"] == "box":
            c = np.array(sh["center"]) - r.pivot[i]
            h = np.array(sh["size"]) * 0.5
            pts = [c + np.array([sx * h[0], sy * h[1], sz * h[2]]) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
            for p in pts:
                low = np.minimum(low, (pw[:, i] + rw[i].apply(p))[:, 1])
        elif sh["type"] == "capsule":
            for key in ("a", "b"):
                p = np.array(sh[key]) - r.pivot[i]
                low = np.minimum(low, (pw[:, i] + rw[i].apply(p))[:, 1] - sh["radius"])
    return low


def ground_clamp(pose, clearance=0.0, smooth=3):
    """Lifts the pelvis whenever a body part would dig into the floor."""
    low = lowest_body_point(pose["pelvis_pos"], pose["rot"])
    lift = np.maximum(0.0, clearance - low)
    if smooth > 0:
        k = np.ones(2 * smooth + 1) / (2 * smooth + 1)
        pad = np.concatenate([np.full(smooth, lift[0]), lift, np.full(smooth, lift[-1])])
        sm = np.convolve(pad, k, mode="valid")
        lift = np.maximum(lift, sm)
    pose["pelvis_pos"][:, 1] += lift
    return lift


def resample(pelvis_pos, rot, n_out, loop):
    """Time-warp a clip to n_out frames."""
    T = pelvis_pos.shape[0]
    src = np.arange(T, dtype=float)
    if loop:
        dst = np.arange(n_out) * (T / n_out)
    else:
        dst = np.linspace(0, T - 1, n_out)
    i0 = np.floor(dst).astype(int) % T
    i1 = np.minimum(i0 + 1, T - 1) if not loop else (i0 + 1) % T
    u = dst - np.floor(dst)
    pp = pelvis_pos[i0] * (1 - u[:, None]) + pelvis_pos[i1] * u[:, None]
    q = np.zeros((n_out, N, 4))
    for i in range(N):
        q[:, i] = mo_rig.quat_slerp(rot[i0, i], rot[i1, i], u)
    return pp, q


def lower_pelvis(pose, dy, lean_deg=0.0, spine_share=0.6):
    """Crouch: drop the pelvis by dy (rig units) and re-solve both legs with IK
    so every ankle stays where the clip had it (knees bend more), then lean the
    spine forward."""
    r = preview.rig()
    pp = pose["pelvis_pos"].copy()
    rot = pose["rot"].copy()
    T = pp.shape[0]
    pw, rw = r.fk(pp, rot)
    ankles = {n: pw[:, IDX[n]].copy() for n in ("foot_r", "foot_l")}
    knees = {n: pw[:, IDX[n]].copy() for n in ("shin_r", "shin_l")}
    pp[:, 1] += dy
    # forward lean on pelvis + spine
    if lean_deg:
        q = R.from_quat(rot[:, 0])
        rot[:, 0] = (R.from_euler("X", -lean_deg * (1 - spine_share) * 0.5, degrees=True) * q).as_quat()
        for nm, sh in (("belly", 0.45), ("chest", 0.55)):
            qq = R.from_quat(rot[:, IDX[nm]])
            rot[:, IDX[nm]] = (R.from_euler("X", -lean_deg * spine_share * sh, degrees=True) * qq).as_quat()
    pw2, rw2 = r.fk(pp, rot)
    for side, s in ((1, "r"), (-1, "l")):
        th, sh_, ft = IDX["thigh_" + s], IDX["shin_" + s], IDX["foot_" + s]
        hip = pw2[:, th]
        l1, l2 = r.length("thigh_" + s), r.length("shin_" + s)
        pole = knees["shin_" + s] - pw[:, th]
        # the knee travels forward when the pelvis sinks
        pole = pole + np.array([0.0, 0.0, -0.15])
        mid, end, hinge = solve_ik(hip, ankles["foot_" + s], l1, l2, pole)
        h = -hinge
        thigh_w = limb_basis(mid - hip, h)
        shin_w = limb_basis(end - mid, h)
        foot_w = rw[ft]  # keep the foot's world orientation
        rot[:, th] = (rw2[0].inv() * thigh_w).as_quat()
        rot[:, sh_] = (thigh_w.inv() * shin_w).as_quat()
        rot[:, ft] = (shin_w.inv() * foot_w).as_quat()
    return {"pelvis_pos": pp, "rot": rot}


def _scale_axis_angle(q, axis, factor):
    """Scale the rotation about one local axis (x/y/z) of quaternion array q."""
    eul = R.from_quat(q).as_euler("YXZ", degrees=False)   # yaw(Y), pitch(X), roll(Z)
    col = {"y": 0, "x": 1, "z": 2}[axis]
    eul[:, col] *= factor
    return R.from_euler("YXZ", eul).as_quat()


def amplify_run(pose, hip=1.3, knee=1.15, arm=1.3, elbow=1.1, lean_deg=8.0):
    """Bigger strides and arm pump for a sprint, derived from the run cycle."""
    rot = pose["rot"].copy()
    for s in ("r", "l"):
        rot[:, IDX["thigh_" + s]] = _scale_axis_angle(rot[:, IDX["thigh_" + s]], "x", hip)
        rot[:, IDX["shin_" + s]] = _scale_axis_angle(rot[:, IDX["shin_" + s]], "x", knee)
        rot[:, IDX["upper_arm_" + s]] = _scale_axis_angle(rot[:, IDX["upper_arm_" + s]], "x", arm)
        rot[:, IDX["forearm_" + s]] = _scale_axis_angle(rot[:, IDX["forearm_" + s]], "x", elbow)
    for nm, sh in (("belly", 0.45), ("chest", 0.55)):
        qq = R.from_quat(rot[:, IDX[nm]])
        rot[:, IDX[nm]] = (R.from_euler("X", -lean_deg * sh, degrees=True) * qq).as_quat()
    return {"pelvis_pos": pose["pelvis_pos"].copy(), "rot": rot}
