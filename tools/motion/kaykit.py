"""Retargets ready-made animations (KayKit "Adventurers" character pack by Kay Lousberg,
CC0) onto the game's 16-part chibi rig and bakes them as clips (see clipio.py).

    python3 kaykit.py list                       # animations in the source file
    python3 kaykit.py build [name ...]           # bake the ones listed in CLIPS

Source: https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 (CC0 1.0).
Set KAYKIT_DIR to the folder with Knight.glb (addons/.../Characters/gltf).

How the retarget works
  * world rotations: every source bone's rotation away from the rest pose (in world space)
    is applied to the matching part of our rig. The source rests in a T-pose and ours has the
    arms hanging, so the arms carry a fixed shortest-arc correction (the same for every frame)
  * hips: the hip-joint centre follows the source (vertical and horizontal offsets are scaled
    by the leg length ratio, anchored at the ankle so feet stay on the floor)
  * sword: the pose of the sword mesh (or, for animations without a weapon, the right hand)
    is stored as a two-hand grip in the chest frame; the game solves both arms to it, so
    the two hands stay on the hilt whatever the arm proportions are
  * foot contacts come from the source ankles (height and speed)
"""
import os
import sys

import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.spatial.transform import Rotation as R

import authoring as A
import clipio
import gltf_reader as G
import mo_rig
from mo_rig import IDX, N, normalize

DIR = os.environ.get(
    "KAYKIT_DIR",
    "/home/user/kaykit-game-assets/kaykit-character-pack-adventures-1.0/addons/kaykit_character_pack_adventures/Characters/gltf")
FPS = 30.0
RY = R.from_euler("y", 180, degrees=True)      # glTF faces +Z, the game faces -Z

# our part -> source bone
BONE = {
    "pelvis": "hips", "belly": "spine", "chest": "chest", "head": "head",
    "upper_arm_r": "upperarm.r", "forearm_r": "lowerarm.r", "hand_r": "hand.r",
    "upper_arm_l": "upperarm.l", "forearm_l": "lowerarm.l", "hand_l": "hand.l",
    "thigh_r": "upperleg.r", "shin_r": "lowerleg.r", "foot_r": "foot.r",
    "thigh_l": "upperleg.l", "shin_l": "lowerleg.l", "foot_l": "foot.l",
}
# rest-direction bones (start, end) for the parts that need a fixed correction (arms)
ARM_DIR = {"upper_arm_r": ("upperarm.r", "lowerarm.r"), "forearm_r": ("lowerarm.r", "wrist.r"),
           "upper_arm_l": ("upperarm.l", "lowerarm.l"), "forearm_l": ("lowerarm.l", "wrist.l")}
ARM_OF_HAND = {"hand_r": "forearm_r", "hand_l": "forearm_l"}

# scale of the hilt position in the chest frame (our arms are shorter than the source's)
GRIP_SCALE = 0.86
MAX_REACH = 0.93       # fraction of the arm length a wrist may be asked to stretch


def _shortest_arc(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    ax = np.cross(a, b)
    s = np.linalg.norm(ax)
    c = float(np.dot(a, b))
    if s < 1e-8:
        return R.identity() if c > 0 else R.from_rotvec(np.array([0, 0, np.pi]))
    return R.from_rotvec(ax / s * np.arctan2(s, c))


class Source:
    def __init__(self, path=None):
        self.path = path or os.path.join(DIR, "Knight.glb")
        self.g = G.GLTF(self.path)
        g = self.g
        self.idx = g.name_to_idx
        self.order = []
        seen = set()

        def visit(i):
            if i in seen:
                return
            p = g.nodes[i]["parent"]
            if p >= 0:
                visit(p)
            seen.add(i)
            self.order.append(i)
        for i in range(len(g.nodes)):
            visit(i)
        T0, R0, _ = g.rest()
        self.rest_P, self.rest_Q = self.world(T0[None], R0[None])
        # the arms' fixed correction (T-pose -> arms hanging)
        rig = mo_rig.Rig()
        self.arm_corr = {}
        for part, (a, b) in ARM_DIR.items():
            src_dir = self.rest_P[0, self.idx[b]] - self.rest_P[0, self.idx[a]]
            our_dir = rig.end[IDX[part]] - rig.pivot[IDX[part]]
            our_dir_src = RY.apply(our_dir / np.linalg.norm(our_dir))     # into the source frame
            self.arm_corr[part] = _shortest_arc(src_dir, our_dir_src)
        for hand, arm in ARM_OF_HAND.items():
            self.arm_corr[hand] = self.arm_corr[arm]

    def world(self, T, Rq):
        F, Nn = T.shape[:2]
        P = np.zeros((F, Nn, 3))
        Q = [None] * Nn
        for i in self.order:
            rl = R.from_quat(Rq[:, i])
            p = self.g.nodes[i]["parent"]
            if p < 0:
                Q[i] = rl
                P[:, i] = T[:, i]
            else:
                Q[i] = Q[p] * rl
                P[:, i] = P[:, p] + Q[p].apply(T[:, i])
        return P, Q

    def sample(self, anim, fps=FPS):
        g = self.g
        times, T, Rq, _ = g.sample(anim, fps)
        T = T.copy()
        T[:, self.idx["root"]] = 0.0          # root motion is the game's business
        P, Q = self.world(T, Rq)
        return times, P, Q


# ---------------------------------------------------------------------------- retarget

def retarget(src: Source, anim, fps=FPS, sword=None, mirror=False, unspin=False):
    """-> dict(pelvis_pos, rot, contacts, grip, meta stuff). `unspin` removes the body's turn
    about the vertical axis (spin attacks: the game turns the whole character instead, so the
    planted feet turn with it)."""
    rig = mo_rig.Rig()
    times, P, Q = src.sample(anim, fps)
    F = len(times)
    idx = src.idx

    def bone_q(name):
        return Q[idx[name]]

    # world rotation of every part in our frame
    world = {}
    for part in mo_rig.ORDER:
        b = BONE[part]
        S = src.rest_Q[idx[b]][0]
        delta = bone_q(b) * S.inv()
        corr = src.arm_corr.get(part)
        if corr is not None:
            delta = delta * corr.inv()
        world[part] = RY * delta * RY.inv()
    yaw_total = 0.0
    undo = None
    if unspin:
        f = world["pelvis"].apply(np.array([0.0, 0.0, -1.0]))
        yaw = np.unwrap(np.arctan2(-f[:, 0], -f[:, 2]))
        yaw = yaw - yaw[0]
        yaw_total = float(np.degrees(yaw[-1]))
        undo = R.from_rotvec(np.stack([np.zeros_like(yaw), -yaw, np.zeros_like(yaw)], axis=1))
        for part in world:
            world[part] = undo * world[part]
    # local rotations in our hierarchy
    rot = np.zeros((F, N, 4))
    for part in mo_rig.ORDER:
        i = IDX[part]
        p = rig.parent[i]
        loc = world[part] if p < 0 else world[mo_rig.ORDER[p]].inv() * world[part]
        rot[:, i] = loc.as_quat()
    for i in range(N):
        for t in range(1, F):
            if np.dot(rot[t, i], rot[t - 1, i]) < 0:
                rot[t, i] = -rot[t, i]
    if mirror:
        rot = mirror_rot(rot)
        world = None

    # hips: hip-joint centre, scaled by the leg length ratio, anchored at the ankles
    hc = 0.5 * (P[:, idx["upperleg.l"]] + P[:, idx["upperleg.r"]])
    hc0 = 0.5 * (src.rest_P[0, idx["upperleg.l"]] + src.rest_P[0, idx["upperleg.r"]])
    ank0 = 0.5 * (src.rest_P[0, idx["foot.l"]] + src.rest_P[0, idx["foot.r"]])
    leg_src = hc0[1] - ank0[1]
    leg_our = rig.hip_h - rig.ankle_h
    k = leg_our / leg_src
    hc_our = np.stack([-(hc[:, 0] - hc0[0]) * k, rig.ankle_h + (hc[:, 1] - ank0[1]) * k, -(hc[:, 2] - hc0[2]) * k], axis=1)
    if undo is not None:
        hc_our = undo.apply(hc_our)
    if mirror:
        hc_our[:, 0] *= -1.0
    thigh_mid = 0.5 * (rig.pivot[IDX["thigh_r"]] + rig.pivot[IDX["thigh_l"]]) - rig.pivot[0]
    pelvis_rot = R.from_quat(rot[:, 0])
    pelvis_pos = hc_our - pelvis_rot.apply(thigh_mid)
    # the hips are anchored on the floor: nothing to keep
    pw, rw = rig.fk(pelvis_pos, rot)
    return {"times": times, "P": P, "Q": Q, "rot": rot, "pelvis_pos": pelvis_pos, "pw": pw, "rw": rw, "k_leg": k,
            "src": src, "mirror": mirror, "yaw_total": yaw_total}


def mirror_rot(rot):
    """Left <-> right: swap the paired parts and mirror each rotation across the x = 0 plane."""
    out = np.zeros_like(rot)
    swap = {}
    for n in mo_rig.ORDER:
        if n.endswith("_r"):
            swap[n] = n[:-2] + "_l"
        elif n.endswith("_l"):
            swap[n] = n[:-2] + "_r"
        else:
            swap[n] = n
    for n in mo_rig.ORDER:
        q = rot[:, IDX[swap[n]]]
        # reflection across x: (x, y, z, w) -> (x, -y, -z, w)
        out[:, IDX[n]] = np.stack([q[:, 0], -q[:, 1], -q[:, 2], q[:, 3]], axis=1)
    return out


# ---------------------------------------------------------------------------- grip

def _chest_frame(r):
    pw, rw = r["pw"], r["rw"]
    return pw[:, IDX["chest"]], rw[IDX["chest"]]


def grip_from_sword(r, node="2H_Sword", left=1.0, edge_sign=1.0):
    """Sword mesh pose -> grip (chest frame) with the leading-edge rule for the edge."""
    src = r["src"]
    rig = mo_rig.Rig()
    idx = src.idx
    P, Q = r["P"], r["Q"]
    n = idx[node]
    hilt = P[:, n]
    qs = Q[n]
    blade = qs.apply(np.array([0.0, 1.0, 0.0]))
    edge = qs.apply(np.array([edge_sign, 0.0, 0.0]))
    # source chest frame and shoulder centre
    qc = Q[idx["chest"]]
    sh = 0.5 * (P[:, idx["upperarm.l"]] + P[:, idx["upperarm.r"]])
    v_local = qc.inv().apply(hilt - sh)
    v_our = RY.apply(v_local)
    b_our = RY.apply(qc.inv().apply(blade))
    e_our = RY.apply(qc.inv().apply(edge))
    if r["mirror"]:
        v_our = v_our * np.array([-1, 1, 1])
        b_our = b_our * np.array([-1, 1, 1])
        e_our = e_our * np.array([-1, 1, 1])
    sh_our = 0.5 * (rig.pivot[IDX["upper_arm_r"]] + rig.pivot[IDX["upper_arm_l"]]) - rig.pivot[IDX["chest"]]
    pos = sh_our + GRIP_SCALE * v_our
    return _finish_grip(r, pos, b_our, e_our, left)


def grip_from_hand(r, left=0.0):
    """Right hand + the game's hand_to_weapon -> grip (chest frame)."""
    rig = mo_rig.Rig()
    drop = float(rig.meta["hand_grip_drop"])
    h2w_rot = R.from_matrix(np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], float).T)
    pw, rw = r["pw"], r["rw"]
    hand = IDX["hand_r"]
    hpos = pw[:, hand]
    hrot = rw[hand]
    gpos_w = hpos + hrot.apply(np.array([0.0, -drop, -0.006]))
    grot_w = hrot * h2w_rot
    chest_pos, chest_rot = _chest_frame(r)
    pos = chest_rot.inv().apply(gpos_w - chest_pos)
    blade = chest_rot.inv().apply(grot_w.apply(np.array([0.0, 1.0, 0.0])))
    edge = chest_rot.inv().apply(grot_w.apply(np.array([0.0, 0.0, -1.0])))
    return _finish_grip(r, pos, blade, edge, left, edge_auto=False)


def _finish_grip(r, pos, blade, edge, left, edge_auto=True):
    """Keeps both wrists within reach (moves the hilt, releases the left hand when it cannot
    follow), carries the edge along the blade and packs the 12-float grip array."""
    rig = mo_rig.Rig()
    fps = FPS
    T = len(pos)
    blade = normalize(blade)
    chest_pos, chest_rot = _chest_frame(r)
    if edge_auto:
        wpos = chest_rot.apply(pos)
        wblade = chest_rot.apply(blade)
        e0 = chest_rot[0].apply(edge[0])
        we = A.edge_from_path(wpos, wblade, fps, e0)
        edge = chest_rot.inv().apply(we)
    edge = normalize(edge - blade * np.sum(edge * blade, axis=1, keepdims=True))
    arm = rig.length("upper_arm_r") + rig.length("forearm_r")
    sh_r = rig.pivot[IDX["upper_arm_r"]] - rig.pivot[IDX["chest"]]
    sh_l = rig.pivot[IDX["upper_arm_l"]] - rig.pivot[IDX["chest"]]
    max_r = arm * MAX_REACH
    left_w = np.full(T, float(left))
    for it in range(24):
        wr, wl = A._hand_pivots(pos, blade, edge, A.LEFT_HAND_OFF)
        dr = np.linalg.norm(wr - sh_r, axis=1)
        dl = np.linalg.norm(wl - sh_l, axis=1)
        over_r = np.maximum(dr - max_r, 0.0)
        over_l = np.maximum(dl - max_r * 1.02, 0.0) * (left_w > 0.5)
        if over_r.max() < 1e-3 and over_l.max() < 1e-3:
            break
        corr = -((wr - sh_r) / np.maximum(dr, 1e-6)[:, None]) * over_r[:, None] * 0.7
        corr += -((wl - sh_l) / np.maximum(dl, 1e-6)[:, None]) * over_l[:, None] * 0.35
        pos = pos + corr
    wr, wl = A._hand_pivots(pos, blade, edge, A.LEFT_HAND_OFF)
    dl = np.linalg.norm(wl - sh_l, axis=1)
    # release the left hand smoothly when it would have to stretch past its reach
    rel = np.clip((dl - arm * 0.92) / (arm * 0.12), 0.0, 1.0)
    left_w = left_w * (1.0 - rel)
    left_w = gaussian_filter1d(left_w, 1.5, mode="nearest")
    grip = np.zeros((T, 12))
    grip[:, 0:3] = pos
    grip[:, 3:6] = blade
    grip[:, 6:9] = edge
    grip[:, 9] = 1.0
    grip[:, 10] = left_w
    r["reach"] = (dr, dl)
    return grip


# ---------------------------------------------------------------------------- contacts / strike

def contacts(r, height_tol=0.035, speed_tol=0.9):
    src = r["src"]
    idx = src.idx
    P = r["P"]
    out = np.zeros((len(P), 2), int)
    for col, name in ((0, "foot.r"), (1, "foot.l")):
        a = P[:, idx[name]]
        y = a[:, 1]
        base = np.percentile(y, 5)
        sp = np.linalg.norm(np.gradient(a[:, [0, 2]], axis=0) * FPS, axis=1)
        sp = gaussian_filter1d(sp, 1.0)
        out[:, col] = ((y - base) < height_tol) & (sp < speed_tol)
    if r["mirror"]:
        out = out[:, ::-1].copy()
    return out


def strike_time(r, grip, blade_len=0.75):
    """Time (s) of the fastest blade-tip motion in the middle of the clip."""
    chest_pos, chest_rot = _chest_frame(r)
    wpos = chest_pos + chest_rot.apply(grip[:, 0:3])
    wblade = chest_rot.apply(grip[:, 3:6])
    tip = wpos + wblade * blade_len
    v = np.linalg.norm(np.gradient(tip, axis=0) * FPS, axis=1)
    v = gaussian_filter1d(v, 1.2)
    T = len(v)
    lo, hi = int(T * 0.12), int(T * 0.85)
    i = lo + int(np.argmax(v[lo:hi]))
    return i / FPS, float(v[i])


def reach_time(r, grip):
    """Time (s) of the furthest forward reach of the hilt (thrusts)."""
    chest_pos, chest_rot = _chest_frame(r)
    wpos = chest_pos + chest_rot.apply(grip[:, 0:3])
    wblade = chest_rot.apply(grip[:, 3:6])
    tip = wpos + wblade * 0.75
    f = -tip[:, 2]                       # forward is -Z
    T = len(f)
    lo, hi = int(T * 0.1), int(T * 0.9)
    i = lo + int(np.argmax(f[lo:hi]))
    return i / FPS


def bake(name, src, anim, fps=FPS, sword="2H_Sword", grip="sword", left=1.0, loop=False, mirror=False, trim=None,
         out_dir=None, edge_sign=1.0, strike="speed", meta=None, ground=False, unspin=False):
    r = retarget(src, anim, fps, mirror=mirror, unspin=unspin)
    g = None
    if grip == "sword":
        g = grip_from_sword(r, sword, left=left, edge_sign=edge_sign)
    elif grip == "hand":
        g = grip_from_hand(r, left=0.0)
    c = contacts(r)
    pel = r["pelvis_pos"].copy()
    rot = r["rot"]
    m = dict(meta or {})
    m["source"] = "KayKit Adventurers (CC0) / " + anim
    if unspin:
        m["spin_degrees"] = round(r["yaw_total"], 1)
    t0 = 0.0
    if g is not None and grip == "sword" and strike:
        ts = strike_time(r, g)[0] if strike == "speed" else reach_time(r, g)
        m["strike"] = round(ts, 3)
    if trim is not None:
        a, b = int(round(trim[0] * fps)), int(round(trim[1] * fps)) + 1
        pel, rot, c = pel[a:b], rot[a:b], c[a:b]
        if g is not None:
            g = g[a:b]
        t0 = a / fps
        if "strike" in m:
            m["strike"] = round(m["strike"] - t0, 3)
    if ground:
        import posefx
        pel = posefx.ground_clamp({"pelvis_pos": pel, "rot": rot}, clearance=0.0)["pelvis_pos"]
    path = clipio.save(name, fps, loop, pel, rot, c, grip=g, speed=0.0, meta=m, out_dir=out_dir)
    return path, r


# name -> bake options. Katana moves use the two-handed sword animations (the sword becomes our katana,
# both hands stay on the hilt); the one-handed ones get the left hand added.
CLIPS = {
    "katana_light_1": dict(anim="2H_Melee_Attack_Slice", trim=(0.2, 1.0)),
    "katana_light_2": dict(anim="1H_Melee_Attack_Slice_Horizontal", sword="1H_Sword", trim=(0.0, 0.75)),
    "katana_light_3": dict(anim="2H_Melee_Attack_Spinning", unspin=True),
    "katana_heavy_charge": dict(anim="2H_Melee_Attack_Chop", trim=(0.1, 0.7), strike=None),
    "katana_heavy": dict(anim="2H_Melee_Attack_Chop", trim=(0.7, 1.4)),
    "katana_counter": dict(anim="1H_Melee_Attack_Chop", sword="1H_Sword", trim=(0.05, 0.75)),
    "katana_iai": dict(anim="1H_Melee_Attack_Slice_Diagonal", sword="1H_Sword", trim=(0.0, 0.7)),
    "katana_assassinate": dict(anim="1H_Melee_Attack_Stab", sword="1H_Sword", strike="reach"),
    "kanabo_smash": dict(anim="2H_Melee_Attack_Chop"),
    "kanabo_sweep": dict(anim="2H_Melee_Attack_Spin", trim=(0.4, 1.7), unspin=True),
    "yari_thrust": dict(anim="2H_Melee_Attack_Stab", strike="reach"),
    "yari_sweep": dict(anim="2H_Melee_Attack_Slice", trim=(0.2, 1.0)),
}


def build(names=None, out_dir=None):
    src = Source()
    for n, o in CLIPS.items():
        if names and n not in names:
            continue
        o = dict(o)
        path, r = bake(n, src, o.pop("anim"), out_dir=out_dir, **o)
        print("baked %-22s <- %s" % (n, os.path.basename(path)))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list":
        s = Source()
        for n, a in sorted(s.g.animations.items()):
            print("%-34s %.2fs" % (n, a["duration"]))
    elif cmd == "build":
        build(sys.argv[2:] or None)
