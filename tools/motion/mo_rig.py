"""Skeleton model shared by every motion tool.

Loads the same rig.json the game reads (written by tools/blender/characters.py)
and does forward kinematics with the exact conventions of the Godot side:

  * character space: +X right, +Y up, -Z forward, rig units (the game scales
    everything by the character scale)
  * every part rotates about its own pivot; its world transform is
        world = parent_world * translate(pivot - parent_pivot) * rotate(local)
    the pelvis has no parent: its pivot is placed by ``pelvis_pos``
  * limbs hang along -Y in the rest pose, elbows/knees hinge about +X
    (flexion is +X rotation for the elbow, -X rotation for the knee)
"""
import json
import os

import numpy as np
from scipy.spatial.transform import Rotation as R

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RIG_JSON = os.path.join(ROOT, "assets", "models", "characters", "rig.json")

ORDER = [
    "pelvis", "belly", "chest", "head",
    "upper_arm_r", "forearm_r", "hand_r", "upper_arm_l", "forearm_l", "hand_l",
    "thigh_r", "shin_r", "foot_r", "thigh_l", "shin_l", "foot_l",
]
IDX = {n: i for i, n in enumerate(ORDER)}
N = len(ORDER)


class Rig:
    def __init__(self, path=RIG_JSON):
        d = json.load(open(path))
        self.meta = d["meta"]
        parts = d["parts"]
        self.parent = np.array([IDX[parts[n]["parent"]] if parts[n]["parent"] else -1 for n in ORDER])
        self.pivot = np.array([parts[n]["pivot"] for n in ORDER], dtype=float)
        self.end = np.array([parts[n]["end"] for n in ORDER], dtype=float)
        self.offset = np.zeros((N, 3))
        for i in range(N):
            if self.parent[i] >= 0:
                self.offset[i] = self.pivot[i] - self.pivot[self.parent[i]]
        self.rest_pelvis = self.pivot[0].copy()
        self.ankle_h = float(self.meta["ankle_height"])
        self.hip_h = float(self.meta["hip_height"])

    def length(self, name):
        i = IDX[name]
        return float(np.linalg.norm(self.end[i] - self.pivot[i]))

    # ------------------------------------------------------------------ FK
    def fk(self, pelvis_pos, rot):
        """pelvis_pos (T,3), rot (T,16,4) quaternions x,y,z,w -> world
        positions (T,16,3) and rotations as scipy Rotation list of length 16."""
        T = pelvis_pos.shape[0]
        rw = [None] * N
        pw = np.zeros((T, N, 3))
        for i in range(N):
            rl = R.from_quat(rot[:, i, :])
            p = self.parent[i]
            if p < 0:
                rw[i] = rl
                pw[:, i] = pelvis_pos
            else:
                rw[i] = rw[p] * rl
                pw[:, i] = pw[:, p] + rw[p].apply(self.offset[i])
        return pw, rw

    def joint_ends(self, pw, rw):
        """World position of the end point of every part (T,16,3)."""
        out = np.zeros_like(pw)
        for i in range(N):
            local_end = self.end[i] - self.pivot[i]
            out[:, i] = pw[:, i] + rw[i].apply(local_end)
        return out

    def rest_pose(self, T=1):
        pp = np.tile(self.rest_pelvis, (T, 1))
        q = np.zeros((T, N, 4))
        q[..., 3] = 1.0
        return pp, q


# ---------------------------------------------------------------- helpers

def quat_normalize(q):
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


def quat_slerp(a, b, t):
    """a,b (...,4) x,y,z,w; t (...,) or scalar."""
    a = quat_normalize(a)
    b = quat_normalize(b)
    d = np.sum(a * b, axis=-1, keepdims=True)
    b = np.where(d < 0, -b, b)
    d = np.abs(d)
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    close = d > 0.9995
    th = np.arccos(np.clip(d, -1, 1))
    s = np.sin(th)
    s = np.where(s < 1e-6, 1.0, s)
    wa = np.sin((1 - t) * th) / s
    wb = np.sin(t * th) / s
    out = np.where(close, a * (1 - t) + b * t, a * wa + b * wb)
    return quat_normalize(out)


def rot_from_basis(x, y, z):
    """Rotation from column vectors (each (T,3))."""
    m = np.stack([x, y, z], axis=-1)
    return R.from_matrix(m)


def normalize(v, eps=1e-9):
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, eps)


def limb_basis(bone_dir, hinge):
    """Godot's ProceduralAnimator._basis_from_bone: rest direction -Y, rest
    hinge +X. bone_dir/hinge (T,3) world vectors."""
    y = -normalize(bone_dir)
    x = hinge - y * np.sum(hinge * y, axis=-1, keepdims=True)
    xl = np.linalg.norm(x, axis=-1, keepdims=True)
    fallback = np.where(np.abs(y[..., :1]) < 0.9, np.array([1.0, 0, 0]), np.array([0, 0, -1.0]))
    fb = fallback - y * np.sum(fallback * y, axis=-1, keepdims=True)
    x = np.where(xl < 0.7, fb, x)
    x = normalize(x)
    z = normalize(np.cross(x, y))
    return rot_from_basis(x, y, z)


def solve_ik(root, target, l1, l2, pole):
    """Two-bone IK identical to ProceduralAnimator.solve_ik.
    All (T,3). Returns mid, end, hinge (bend plane normal)."""
    to_t = target - root
    dist = np.linalg.norm(to_t, axis=-1)
    lo = max(abs(l1 - l2) + 0.001, 0.02)
    dist_c = np.clip(dist, lo, l1 + l2 - 0.0005)
    dirv = np.where(dist[..., None] > 1e-4, to_t / np.maximum(dist[..., None], 1e-9), np.array([0, -1.0, 0]))
    cos_a = np.clip((l1 * l1 + dist_c ** 2 - l2 * l2) / (2.0 * l1 * dist_c), -1, 1)
    a = np.arccos(cos_a)
    bend = pole - dirv * np.sum(pole * dirv, axis=-1, keepdims=True)
    bl = np.linalg.norm(bend, axis=-1, keepdims=True)
    alt = np.array([0, 0, -1.0]) - dirv * np.sum(np.array([0, 0, -1.0]) * dirv, axis=-1, keepdims=True)
    bend = np.where(bl < 1e-3, alt, bend)
    bend = normalize(bend)
    mid = root + (dirv * np.cos(a)[..., None] + bend * np.sin(a)[..., None]) * l1
    end = root + dirv * dist_c[..., None]
    hinge = normalize(np.cross(bend, dirv))
    return mid, end, hinge
