"""Bakes the locomotion clips (walk, run) from the DeepMimic motion capture."""
import os
import sys

import numpy as np

import clipio
import dm_import
import mo_rig
import preview

DM_DIR = os.environ.get("DM_MOTIONS", "")


def contacts_from(pelvis_pos, rot, fps, travel_speed=0.0, vel_frac=0.32, vel_abs=0.12, height_thr=0.12, min_len=3):
    """Ground contact flags (T,2): a foot is planted when it barely moves in the
    world (in-place clip + the speed the ground scrolls at) and is low.
    travel_speed: the speed the in-place clip is meant to move at."""
    r = preview.rig()
    pw, rw = r.fk(pelvis_pos, rot)
    sh = preview.sole_heights(pelvis_pos, rot)
    T = pelvis_pos.shape[0]
    flags = np.zeros((T, 2))
    lowest = sh.min(axis=1)
    for k, n in enumerate(("foot_r", "foot_l")):
        ank = pw[:, mo_rig.IDX[n]]
        v = np.gradient(ank, axis=0) * fps
        vz = v[:, 2] - travel_speed          # forward is -z; the ground moves +travel back
        vh = np.sqrt(v[:, 0] ** 2 + vz ** 2)
        c = (vh < vel_frac * travel_speed + vel_abs) & (sh[:, k] < lowest + height_thr) & (sh[:, k] < 0.16)
        flags[:, k] = _clean(c, min_len)
    return flags


def calibrate_ground(pose, flags):
    """Shifts the pelvis so planted soles sit exactly on the ground on average."""
    sh = preview.sole_heights(pose["pelvis_pos"], pose["rot"])
    sel = flags > 0.5
    if sel.sum() == 0:
        return 0.0
    dy = -float(sh[sel].mean())
    pose["pelvis_pos"][:, 1] += dy
    return dy


def _clean(c, min_len):
    c = c.copy()
    T = len(c)
    for _ in range(2):
        # fill gaps shorter than min_len
        i = 0
        while i < T:
            if not c[i]:
                j = i
                while j < T and not c[j]:
                    j += 1
                if j - i < min_len and i > 0 and j < T:
                    c[i:j] = True
                i = j
            else:
                i += 1
        # drop blips
        i = 0
        while i < T:
            if c[i]:
                j = i
                while j < T and c[j]:
                    j += 1
                if j - i < min_len:
                    c[i:j] = False
                i = j
            else:
                i += 1
    return c


def native_speed(pelvis_pos, rot, contacts, fps):
    """Ground speed (rig units / s) at which the stance feet do not slide."""
    r = preview.rig()
    pw, _ = r.fk(pelvis_pos, rot)
    sp = []
    for k, n in enumerate(("foot_r", "foot_l")):
        v = np.gradient(pw[:, mo_rig.IDX[n]], axis=0) * fps
        sel = contacts[:, k] > 0.5
        if sel.sum() > 2:
            sp.append(v[sel, 2])      # backwards (+z) relative motion of a planted foot
    return float(np.median(np.concatenate(sp))) if sp else 0.0


def rotate_to_right_strike(pose, contacts):
    """Cycle so frame 0 is the first contact frame of the right foot."""
    c = contacts[:, 0] > 0.5
    T = len(c)
    start = None
    for i in range(T):
        if c[i] and not c[i - 1]:
            start = i
            break
    if start is None:
        return pose, contacts, 0
    idx = (np.arange(T) + start) % T
    out = dict(pose)
    out["pelvis_pos"] = pose["pelvis_pos"][idx]
    out["rot"] = pose["rot"][idx]
    return out, contacts[idx], start


def bake_cycle(name, dm_file, out_dir, fps=30.0, speed_hint=None):
    rig = mo_rig.Rig()
    c = dm_import.load(dm_file, fps)
    pose = dm_import.retarget(c, rig)
    dm_import.ground(pose)
    travel = pose["dm_speed"] * pose["leg_ratio"]
    flags = contacts_from(pose["pelvis_pos"], pose["rot"], fps, travel)
    calibrate_ground(pose, flags)
    pose, flags, shift = rotate_to_right_strike(pose, flags)
    speed = native_speed(pose["pelvis_pos"], pose["rot"], flags, fps)
    T = pose["pelvis_pos"].shape[0]
    ev = {"foot_r_down": 0.0}
    cl = flags[:, 1] > 0.5
    for i in range(T):
        if cl[i] and not cl[i - 1]:
            ev["foot_l_down"] = round(i / fps, 4)
            break
    path = clipio.save(name, fps, True, pose["pelvis_pos"], pose["rot"], flags, speed=speed, events=ev, out_dir=out_dir)
    return path, pose, flags, speed


if __name__ == "__main__":
    dm = sys.argv[1]
    out = sys.argv[2]
    for n, f in (("walk", "humanoid3d_walk.txt"), ("run", "humanoid3d_run.txt")):
        p, pose, flags, speed = bake_cycle(n, os.path.join(dm, f), out)
        print(n, p, "speed(rig u/s)=%.2f" % speed, "contacts r %d/%d l %d/%d" % (flags[:, 0].sum(), len(flags), flags[:, 1].sum(), len(flags)))
