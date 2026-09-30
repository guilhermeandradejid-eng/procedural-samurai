"""Key-pose animation authoring on the game's real skeleton.

A clip is described by keyframes over semantic channels (pelvis offset and
rotation, spine lean/twist, head look, feet on the ground, free arm angles and
the two-hand weapon grip in the chest frame). Channels are interpolated with
monotone cubic curves, then solved into the joint rotations the game plays:

  * legs: two-bone IK from the pelvis to the foot targets (knee follows the pole)
  * arms: FK swing/abduct/elbow, or two-bone IK to a hand-on-hilt grip when the
    grip weight is on (both hands, the left one offset along the hilt)

Conventions (same as the game): +X right, +Y up, -Z forward, rotation order YXZ.
  lean   +  = bend forward            twist/yaw + = turn to the character's LEFT
  roll   +  = tilt to the right       head pitch + = look up
  swing  +  = arm/thigh forward       abduct + = outward
"""
import numpy as np
from scipy.interpolate import PchipInterpolator
from scipy.spatial.transform import Rotation as R

import mo_rig
from mo_rig import IDX, N, normalize, limb_basis, solve_ik

FPS = 30.0

DEFAULTS = {
    # pelvis offset from its rest pivot (rig units) and rotation (deg)
    "px": 0.0, "py": 0.0, "pz": 0.0, "p_lean": 0.0, "p_yaw": 0.0, "p_roll": 0.0,
    # spine (total, shared by belly 45% / chest 55%)
    "s_lean": 0.0, "s_yaw": 0.0, "s_roll": 0.0,
    # head relative to the chest
    "h_pitch": 0.0, "h_yaw": 0.0, "h_roll": 0.0,
    # feet: ground point under the ankle in root space (x right, z back), lift above ground, yaw, toe pitch
    "fr_x": 0.146, "fr_z": 0.0, "fr_y": 0.0, "fr_yaw": 0.0, "fr_pitch": 0.0,
    "fl_x": -0.146, "fl_z": 0.0, "fl_y": 0.0, "fl_yaw": 0.0, "fl_pitch": 0.0,
    "knee_out": 0.2,
    # contacts (1 = planted)
    "cr": 1.0, "cl": 1.0,
    # free arms (deg): swing, abduct, elbow flex, wrist
    "ar_swing": 0.0, "ar_abduct": 8.0, "ar_elbow": 12.0, "ar_wrist": 8.0, "ar_twist": 0.0,
    "al_swing": 0.0, "al_abduct": 8.0, "al_elbow": 12.0, "al_wrist": 8.0, "al_twist": 0.0,
    # weapon grip in the chest frame (rig units): hilt position, blade dir, edge dir
    "g_w": 0.0, "g_left": 1.0,
    "g_x": 0.0, "g_y": 0.0, "g_z": 0.0,
    "g_bx": 0.0, "g_by": 1.0, "g_bz": 0.0,
    "g_ex": 0.0, "g_ey": 0.0, "g_ez": -1.0,
}
CH = list(DEFAULTS.keys())

# weapon-in-hand geometry (mirrors ProceduralAnimator.hand_to_weapon and the left hand offset)
LEFT_HAND_OFF = -0.11   # katana: hands close together (the chibi arms are short)

_rig = None
REACH = {}


def rig():
    global _rig
    if _rig is None:
        _rig = mo_rig.Rig()
    return _rig


def euler(yaw=0.0, pitch=0.0, roll=0.0):
    """Godot Basis.from_euler(Vector3(pitch, yaw, roll)) (order YXZ), degrees, arrays ok."""
    a = np.stack(np.broadcast_arrays(np.asarray(yaw, float), np.asarray(pitch, float), np.asarray(roll, float)), axis=-1)
    return R.from_euler("YXZ", a, degrees=True)


# ------------------------------------------------------------------ keys

class Clip:
    """Keyframes -> sampled channel arrays."""

    def __init__(self, name, duration, loop=False, fps=FPS):
        self.name = name
        self.duration = duration
        self.loop = loop
        self.fps = fps
        self.keys = []          # (t, dict)
        self.events = {}
        self.meta = {}
        self.grip_space = "chest"   # "chest": g_* are relative to the chest pivot; "root": character space
        self.edge_auto = False      # chest-space clips: edge follows the tip's world travel
        self.auto = None            # callable(ch, clip) that derives body channels from the sampled sword path

    def key(self, t, **kw):
        for k in kw:
            if k not in DEFAULTS:
                raise KeyError("unknown channel " + k)
        self.keys.append((float(t), kw))
        return self

    def frames(self):
        return int(round(self.duration * self.fps)) + (0 if self.loop else 1)

    def sample(self):
        """Channel arrays (T,) from the sparse keys. Every channel is a curve through
        the keys that mention it (an implicit default key at t=0 when the first
        one comes later, the last value held)."""
        keys = sorted(self.keys, key=lambda k: k[0])
        T = self.frames()
        ts = np.arange(T) / self.fps
        out = {}
        for ch in CH:
            if ch in ("cr", "cl"):
                continue
            pts = [(t, kw[ch]) for (t, kw) in keys if ch in kw]
            if not pts:
                out[ch] = np.full(T, DEFAULTS[ch])
                continue
            if pts[0][0] > 1e-6 and not self.loop:
                pts.insert(0, (0.0, DEFAULTS[ch]))
            times = np.array([p[0] for p in pts], float)
            vals = np.array([p[1] for p in pts], float)
            if self.loop:
                times = np.concatenate([times - self.duration, times, times + self.duration])
                vals = np.concatenate([vals, vals, vals])
            order = np.argsort(times, kind="stable")
            times, vals = times[order], vals[order]
            keep = np.concatenate([[True], np.diff(times) > 1e-6])
            times, vals = times[keep], vals[keep]
            if len(times) == 1:
                out[ch] = np.full(T, vals[0])
            else:
                f = PchipInterpolator(times, vals, extrapolate=True)
                out[ch] = f(np.clip(ts, times[0], times[-1]))
        # contacts are steps: the value of the latest key
        for ch in ("cr", "cl"):
            arr = np.full(T, DEFAULTS[ch])
            for (t, kw) in keys:
                if ch in kw:
                    arr[ts >= t - 1e-6] = kw[ch]
            out[ch] = arr
        return out


# ------------------------------------------------------------------ solve

def _rot_apply(r, v):
    return r.apply(v)


def solve(ch, T=None, grip_space="chest", edge_auto=False, fps=FPS):
    """channel arrays -> dict(pelvis_pos, rot(T,16,4), grip(T,12), contacts(T,2), chest_w...)"""
    r = rig()
    T = len(ch["px"])
    rot_w = [None] * N     # world rotations (scipy)
    pos_w = np.zeros((T, N, 3))
    loc = [None] * N       # local rotations (scipy)

    def setlocal(i, rl):
        loc[i] = rl
        p = r.parent[i]
        rot_w[i] = rl if p < 0 else rot_w[p] * rl
        if p < 0:
            pos_w[:, i] = 0
        else:
            pos_w[:, i] = pos_w[:, p] + rot_w[p].apply(r.offset[i])

    pelvis_pos = r.rest_pelvis[None, :] + np.stack([ch["px"], ch["py"], ch["pz"]], axis=1)
    # torso chain
    setlocal(0, euler(ch["p_yaw"], -ch["p_lean"], ch["p_roll"]))
    pos_w[:, 0] = pelvis_pos
    for i, share in ((IDX["belly"], 0.45), (IDX["chest"], 0.55)):
        setlocal(i, euler(ch["s_yaw"] * share, -ch["s_lean"] * share, ch["s_roll"] * share))
    setlocal(IDX["head"], euler(ch["h_yaw"], ch["h_pitch"], ch["h_roll"]))

    # ------------------------------------------------ legs (IK)
    ank_h = r.ankle_h
    for side, s in ((1, "r"), (-1, "l")):
        th, sh, ft = IDX["thigh_" + s], IDX["shin_" + s], IDX["foot_" + s]
        hip = pos_w[:, IDX["pelvis"]] + rot_w[0].apply(r.pivot[th] - r.pivot[0])
        tgt = np.stack([ch["f%s_x" % s], ch["f%s_y" % s] + ank_h, ch["f%s_z" % s]], axis=1)
        l1, l2 = r.length("thigh_" + s), r.length("shin_" + s)
        pole = np.array([0.0, 0.0, -1.0])[None, :] + np.array([side * 1.0, 0, 0])[None, :] * ch["knee_out"][:, None]
        # pole is in root space; make it follow the pelvis yaw a bit so knees track the hips
        pole = rot_w[0].apply(pole) * 0.5 + pole * 0.5
        mid, end, hinge = solve_ik(hip, tgt, l1, l2, pole)
        h = -hinge
        d1 = mid - hip
        d2 = end - mid
        thigh_w = limb_basis(d1, h)
        shin_w = limb_basis(d2, h)
        foot_w = euler(ch["f%s_yaw" % s], ch["f%s_pitch" % s], 0.0)
        # store world -> local
        rot_w[th] = thigh_w
        pos_w[:, th] = hip
        loc[th] = rot_w[0].inv() * thigh_w
        rot_w[sh] = shin_w
        pos_w[:, sh] = mid
        loc[sh] = thigh_w.inv() * shin_w
        rot_w[ft] = foot_w
        pos_w[:, ft] = end
        loc[ft] = shin_w.inv() * foot_w

    # ------------------------------------------------ arms
    chest = IDX["chest"]
    chest_pos = pos_w[:, chest]
    chest_rot = rot_w[chest]
    grip_on = ch["g_w"] > 0.02
    grip_pos = np.stack([ch["g_x"], ch["g_y"], ch["g_z"]], axis=1)
    blade = normalize(np.stack([ch["g_bx"], ch["g_by"], ch["g_bz"]], axis=1))
    edge = np.stack([ch["g_ex"], ch["g_ey"], ch["g_ez"]], axis=1)
    edge = normalize(edge - blade * np.sum(edge * blade, axis=1, keepdims=True))
    if edge_auto and grip_space == "chest":
        # the cutting edge leads: derive it from the world-space travel of the blade tip
        from scipy.ndimage import gaussian_filter1d
        wpos = chest_pos + chest_rot.apply(grip_pos)
        wblade = chest_rot.apply(blade)
        tip = wpos + wblade * 0.9
        v = gaussian_filter1d(np.gradient(tip, axis=0) * fps, 1.2, axis=0, mode="nearest")
        vp = v - wblade * np.sum(v * wblade, axis=1, keepdims=True)
        sp = np.linalg.norm(vp, axis=1)
        wedge = np.zeros_like(vp)
        last = chest_rot[0].apply(edge[0])
        for t_ in range(len(sp)):
            if sp[t_] > 0.6:
                last = vp[t_] / sp[t_]
            e_ = last - wblade[t_] * np.dot(last, wblade[t_])
            n_ = np.linalg.norm(e_)
            wedge[t_] = e_ / n_ if n_ > 1e-4 else np.array([0.0, -1.0, 0.0])
        wedge = normalize(gaussian_filter1d(wedge, 1.8, axis=0, mode="nearest"))
        edge = normalize(chest_rot.inv().apply(wedge))
    # grip basis (AttackLibrary.grip_basis)
    gy = blade
    gz = -normalize(edge - gy * np.sum(edge * gy, axis=1, keepdims=True))
    gx = normalize(np.cross(gy, gz))
    gz = normalize(np.cross(gx, gy))
    grip_rot_local = mo_rig.rot_from_basis(gx, gy, gz)
    if grip_space == "root":
        # authored in character space: world = as given; convert to the chest frame for the file
        grip_rot_w = grip_rot_local
        grip_pos_w = grip_pos.copy()
        cinv = chest_rot.inv()
        out_pos = cinv.apply(grip_pos - chest_pos)
        out_blade = cinv.apply(blade)
        out_edge = cinv.apply(edge)
    else:
        grip_rot_w = chest_rot * grip_rot_local
        grip_pos_w = chest_pos + chest_rot.apply(grip_pos)   # grip_pos is relative to the chest pivot
        out_pos, out_blade, out_edge = grip_pos, blade, edge
    drop = float(r.meta["hand_grip_drop"])
    h2w = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], float).T   # columns: x=(1,0,0) y=(0,0,-1) z=(0,1,0)
    h2w_rot = R.from_matrix(h2w)
    h2w_pos = np.array([0.0, -drop, -0.006])
    # inverse of hand_to_weapon: hand = grip * inv
    inv_rot = h2w_rot.inv()
    inv_pos = -inv_rot.apply(h2w_pos)
    for side, s in ((1, "r"), (-1, "l")):
        ua, fa, hd = IDX["upper_arm_" + s], IDX["forearm_" + s], IDX["hand_" + s]
        shoulder = chest_pos + chest_rot.apply(r.pivot[ua] - r.pivot[chest])
        sw, ab = ch["a%s_swing" % s], ch["a%s_abduct" % s]
        # FK arm
        ua_l = euler(0.0, sw, ab * side) * R.from_rotvec(np.zeros((T, 3)))
        if np.any(ch["a%s_twist" % s] != 0):
            ua_l = ua_l * R.from_euler("Y", ch["a%s_twist" % s], degrees=True)
        fa_l = euler(0.0, ch["a%s_elbow" % s], 0.0)
        hd_l = euler(0.0, ch["a%s_wrist" % s], 0.0)
        ua_w = chest_rot * ua_l
        fa_w = ua_w * fa_l
        hd_w = fa_w * hd_l
        if grip_on.any():
            # hand target = weapon grip (the left hand sits lower on the hilt)
            gp = grip_pos_w.copy()
            if side < 0:
                gp = gp + grip_rot_w.apply(np.array([0.0, LEFT_HAND_OFF, 0.0]))
            hand_rot = grip_rot_w * inv_rot
            hand_pos = gp + grip_rot_w.apply(inv_pos)
            wgt = ch["g_w"] * (ch["g_left"] if side < 0 else 1.0)
            # FK hand for blending
            l1, l2 = r.length("upper_arm_" + s), r.length("forearm_" + s)
            fk_hand_pos = shoulder + ua_w.apply(r.pivot[fa] - r.pivot[ua]) + fa_w.apply(r.pivot[hd] - r.pivot[fa])
            tgt = fk_hand_pos * (1 - wgt[:, None]) + hand_pos * wgt[:, None]
            down = -chest_rot.apply(np.array([0.0, 1.0, 0.0]))
            back = chest_rot.apply(np.array([0.0, 0.0, 1.0]))
            out = chest_rot.apply(np.array([1.0, 0.0, 0.0])) * side
            pole = down * 0.6 + back * 0.35 + out * 0.55
            mid, end, hinge = solve_ik(shoulder, tgt, l1, l2, pole)
            REACH[s] = np.linalg.norm(tgt - shoulder, axis=1) / (l1 + l2)
            ik_ua = limb_basis(mid - shoulder, hinge)
            ik_fa = limb_basis(end - mid, hinge)
            # blend IK and FK by the grip weight
            k = np.clip(wgt, 0, 1)
            sel = k > 0.02
            fk_q = ua_w.as_quat()
            ik_q = ik_ua.as_quat()
            ua_w = R.from_quat(mo_rig.quat_slerp(fk_q, ik_q, np.where(sel, k, 0.0)))
            fk_q = fa_w.as_quat()
            ik_q = ik_fa.as_quat()
            fa_w = R.from_quat(mo_rig.quat_slerp(fk_q, ik_q, np.where(sel, k, 0.0)))
            hand_w_ik = hand_rot
            hd_w = R.from_quat(mo_rig.quat_slerp(hd_w.as_quat(), hand_w_ik.as_quat(), np.where(sel, k, 0.0)))
        rot_w[ua] = ua_w
        loc[ua] = chest_rot.inv() * ua_w
        rot_w[fa] = fa_w
        loc[fa] = ua_w.inv() * fa_w
        rot_w[hd] = hd_w
        loc[hd] = fa_w.inv() * hd_w

    rot = np.zeros((T, N, 4))
    for i in range(N):
        rot[:, i] = loc[i].as_quat()
    # keep quaternion signs continuous
    for i in range(N):
        for t in range(1, T):
            if np.dot(rot[t, i], rot[t - 1, i]) < 0:
                rot[t, i] = -rot[t, i]
    grip = np.zeros((T, 12))
    grip[:, 0:3] = out_pos
    grip[:, 3:6] = out_blade
    grip[:, 6:9] = out_edge
    # reach diagnostics: how stretched each arm is (1 = fully extended)
    reach = {}
    grip[:, 9] = ch["g_w"]
    grip[:, 10] = ch["g_left"]
    contacts = np.stack([ch["cr"], ch["cl"]], axis=1)
    return {"pelvis_pos": pelvis_pos, "rot": rot, "grip": grip, "contacts": contacts, "reach": REACH}


def bake_clip(c: Clip, out_dir=None, speed=0.0):
    import clipio
    ch = c.sample()
    if c.auto is not None:
        c.auto(ch, c)
    res = solve(ch, grip_space=c.grip_space, edge_auto=c.edge_auto, fps=c.fps)
    has_grip = np.any(ch["g_w"] > 0.02)
    path = clipio.save(c.name, c.fps, c.loop, res["pelvis_pos"], res["rot"], res["contacts"],
                       grip=res["grip"] if has_grip else None, speed=speed, events=c.events, meta=c.meta, out_dir=out_dir)
    res["path"] = path
    return res


# ------------------------------------------------------------------ torso reach solver

def _hand_pivots(pos, blade, edge, left_off):
    """Wrist targets (right, left) for a two-hand grip in character space."""
    gy = blade
    gz = -normalize(edge - gy * np.sum(edge * gy, axis=1, keepdims=True))
    gx = normalize(np.cross(gy, gz))
    gz = normalize(np.cross(gx, gy))
    grot = mo_rig.rot_from_basis(gx, gy, gz)
    drop = float(rig().meta["hand_grip_drop"])
    h2w = R.from_matrix(np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], float).T)
    inv_rot = h2w.inv()
    inv_pos = -inv_rot.apply(np.array([0.0, -drop, -0.006]))
    wr = pos + grot.apply(inv_pos)
    wl = pos + grot.apply(np.array([0.0, left_off, 0.0])) + grot.apply(inv_pos)
    return wr, wl


def reach_solver(ch, clip, max_reach=0.92, yaw_range=(-55, 55), lean_range=(-8, 22), w_yaw=0.6, w_lean=0.35,
                 pelvis_share=0.35, sigma=1.6, left_off=None, lead=0.03, hip_extra=0.0, release_reach=(0.9, 1.05)):
    """Finds, per frame, how far the chest has to twist/bend so both hands reach a
    character-space grip comfortably (arms stay bent), then adds that to the
    channels: the spine takes most of the yaw, the hips a share (and lead it in time).
    Grip channels must be in character space (clip.grip_space == 'root')."""
    from scipy.ndimage import gaussian_filter1d
    r = rig()
    left_off = LEFT_HAND_OFF if left_off is None else left_off
    T = len(ch["px"])
    ts = np.arange(T) / clip.fps
    on = np.clip(ch["g_w"], 0, 1)
    pos = np.stack([ch["g_x"], ch["g_y"], ch["g_z"]], axis=1)
    blade = normalize(np.stack([ch["g_bx"], ch["g_by"], ch["g_bz"]], axis=1))
    edge = np.stack([ch["g_ex"], ch["g_ey"], ch["g_ez"]], axis=1)
    edge = normalize(edge - blade * np.sum(edge * blade, axis=1, keepdims=True))
    wr, wl = _hand_pivots(pos, blade, edge, left_off)
    yaws = np.arange(yaw_range[0], yaw_range[1] + 1, 5.0)
    leans = np.arange(lean_range[0], lean_range[1] + 1, 4.0)
    L = r.length("upper_arm_r") + r.length("forearm_r")
    best_yaw = np.zeros(T)
    best_lean = np.zeros(T)
    pel_off = r.pivot[IDX["belly"]] - r.pivot[0]
    che_off = r.pivot[IDX["chest"]] - r.pivot[IDX["belly"]]
    sh_r_off = r.pivot[IDX["upper_arm_r"]] - r.pivot[IDX["chest"]]
    sh_l_off = r.pivot[IDX["upper_arm_l"]] - r.pivot[IDX["chest"]]
    for t in range(T):
        if on[t] < 0.05:
            continue
        pelvis_pos = r.rest_pelvis + np.array([ch["px"][t], ch["py"][t], ch["pz"][t]])
        cost = np.full((len(yaws), len(leans)), 1e9)
        for iy, dy in enumerate(yaws):
            for il, dl in enumerate(leans):
                yaw_total = ch["s_yaw"][t] + dy
                lean_total = ch["s_lean"][t] + dl
                pr = euler(ch["p_yaw"][t] + pelvis_share * dy * 0.0, -ch["p_lean"][t], ch["p_roll"][t])
                br = euler(yaw_total * 0.45, -lean_total * 0.45, ch["s_roll"][t] * 0.45)
                cr = euler(yaw_total * 0.55, -lean_total * 0.55, ch["s_roll"][t] * 0.55)
                bpos = pelvis_pos + pr.apply(pel_off)
                cw = pr * br
                cpos = bpos + cw.apply(che_off)
                cw2 = cw * cr
                sr = cpos + cw2.apply(sh_r_off)
                sl = cpos + cw2.apply(sh_l_off)
                rr = np.linalg.norm(wr[t] - sr) / L
                rl = np.linalg.norm(wl[t] - sl) / L if ch["g_left"][t] > 0.05 else 0.0
                over = max(0.0, max(rr, rl) - max_reach)
                cost[iy, il] = 150.0 * over ** 2 + 0.6 * (max(rr, rl)) ** 2 + w_yaw * (dy / 30.0) ** 2 + w_lean * (dl / 12.0) ** 2
        iy, il = np.unravel_index(np.argmin(cost), cost.shape)
        best_yaw[t] = yaws[iy]
        best_lean[t] = leans[il]
    # smooth in time; frames without a grip get no correction
    by = gaussian_filter1d(best_yaw * on, sigma, mode="nearest")
    bl = gaussian_filter1d(best_lean * on, sigma, mode="nearest")
    ch["s_yaw"] = ch["s_yaw"] + by * (1 - pelvis_share)
    ch["p_yaw"] = ch["p_yaw"] + np.interp(ts + lead, ts, by) * pelvis_share
    ch["s_lean"] = ch["s_lean"] + bl
    # the left hand lets go of the hilt when the sword swings wider than it can follow
    rl_final = np.zeros(T)
    for t in range(T):
        pelvis_pos = r.rest_pelvis + np.array([ch["px"][t], ch["py"][t], ch["pz"][t]])
        pr = euler(ch["p_yaw"][t], -ch["p_lean"][t], ch["p_roll"][t])
        br = euler(ch["s_yaw"][t] * 0.45, -ch["s_lean"][t] * 0.45, ch["s_roll"][t] * 0.45)
        cr = euler(ch["s_yaw"][t] * 0.55, -ch["s_lean"][t] * 0.55, ch["s_roll"][t] * 0.55)
        cpos = pelvis_pos + pr.apply(pel_off)
        cw = pr * br
        cpos = cpos + cw.apply(che_off)
        cw2 = cw * cr
        sl = cpos + cw2.apply(sh_l_off)
        rl_final[t] = np.linalg.norm(wl[t] - sl) / L
    lo, hi = release_reach
    left_w = np.clip((hi - rl_final) / max(hi - lo, 1e-3), 0.0, 1.0)
    left_w = gaussian_filter1d(left_w, 1.2, mode="nearest")
    ch["g_left"] = ch["g_left"] * left_w
    return by, bl


def auto_edge(ch, clip, blade_len=0.9, sigma=1.2, smooth_vel=True):
    """Edge direction of the blade follows the way the tip travels (the cutting edge
    leads), computed from the sampled character-space grip path."""
    from scipy.ndimage import gaussian_filter1d
    T = len(ch["px"])
    pos = np.stack([ch["g_x"], ch["g_y"], ch["g_z"]], axis=1)
    blade = normalize(np.stack([ch["g_bx"], ch["g_by"], ch["g_bz"]], axis=1))
    tip = pos + blade * blade_len
    v = np.gradient(tip, axis=0) * clip.fps
    if smooth_vel:
        v = gaussian_filter1d(v, sigma, axis=0, mode="nearest")
    vp = v - blade * np.sum(v * blade, axis=1, keepdims=True)
    sp = np.linalg.norm(vp, axis=1)
    edge = np.zeros((T, 3))
    last = np.array([0.0, -0.8, -0.6])
    for t in range(T):
        if sp[t] > 0.6:
            last = vp[t] / sp[t]
        # keep the edge perpendicular to the blade
        e = last - blade[t] * np.dot(last, blade[t])
        n = np.linalg.norm(e)
        edge[t] = e / n if n > 1e-4 else np.array([0.0, -1.0, 0.0])
    # slow movements: blend towards a smoothed version to avoid twitching
    edge = gaussian_filter1d(edge, sigma * 1.5, axis=0, mode="nearest")
    edge = normalize(edge)
    ch["g_ex"], ch["g_ey"], ch["g_ez"] = edge[:, 0], edge[:, 1], edge[:, 2]
