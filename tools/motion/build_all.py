"""Bakes every clip the game plays into assets/motion (run: python3 build_all.py).

Sources:
  * DeepMimic motion capture (real mocap from pybullet_data)  -> walk, run, sprint, roll, crouch_walk
  * authored key poses (authoring.py)                          -> idle, guard, reactions, attacks...
"""
import os
import sys

import numpy as np

import authoring as A
import clipio
import dm_import
import locomotion
import mo_rig
import posefx
import preview

OUT = clipio.MOTION_DIR
DM = os.environ.get("DM_MOTIONS", "")


def dm_file(n):
    return os.path.join(DM, "humanoid3d_%s.txt" % n)


def bake_pose_cycle(name, pose, fps, loop=True, travel=None, events=None, calibrate=True):
    """contacts + ground calibration + right-strike alignment for a locomotion pose."""
    if travel is None:
        travel = 0.0
    flags = locomotion.contacts_from(pose["pelvis_pos"], pose["rot"], fps, travel)
    if calibrate:
        locomotion.calibrate_ground(pose, flags)
    pose, flags, _ = locomotion.rotate_to_right_strike(pose, flags)
    speed = locomotion.native_speed(pose["pelvis_pos"], pose["rot"], flags, fps)
    ev = {"foot_r_down": 0.0}
    T = flags.shape[0]
    cl = flags[:, 1] > 0.5
    for i in range(T):
        if cl[i] and not cl[i - 1]:
            ev["foot_l_down"] = round(i / fps, 4)
            break
    clipio.save(name, fps, loop, pose["pelvis_pos"], pose["rot"], flags, speed=speed, events=ev, out_dir=OUT)
    return pose, flags, speed


def build_locomotion():
    fps = 30.0
    rig = mo_rig.Rig()
    res = {}
    for n, f in (("walk", "walk"), ("run", "run")):
        c = dm_import.load(dm_file(f), fps)
        pose = dm_import.retarget(c, rig)
        dm_import.ground(pose)
        travel = pose["dm_speed"] * pose["leg_ratio"]
        pose_b, flags, speed = bake_pose_cycle(n, pose, fps, travel=travel)
        res[n] = (pose_b, flags, speed)
        print("%-12s speed %.2f rig u/s  frames %d" % (n, speed, pose_b["pelvis_pos"].shape[0]))
    # sprint: bigger strides and arm pump on top of the run cycle
    run_pose = res["run"][0]
    sp = posefx.amplify_run(run_pose, hip=1.3, knee=1.15, arm=1.3, elbow=1.1, lean_deg=9.0)
    flags = locomotion.contacts_from(sp["pelvis_pos"], sp["rot"], fps, res["run"][2] * 1.25)
    locomotion.calibrate_ground(sp, flags)
    speed = locomotion.native_speed(sp["pelvis_pos"], sp["rot"], flags, fps)
    ev = {"foot_r_down": 0.0}
    clipio.save("sprint", fps, True, sp["pelvis_pos"], sp["rot"], flags, speed=speed, events=ev, out_dir=OUT)
    print("%-12s speed %.2f rig u/s" % ("sprint", speed))
    # crouch walk: the walk cycle with the pelvis sunk (legs re-solved) and the torso leaning in
    wp = res["walk"][0]
    cw = posefx.lower_pelvis(wp, -0.2, lean_deg=16.0)
    flags = res["walk"][1]
    clipio.save("crouch_walk", fps, True, cw["pelvis_pos"], cw["rot"], flags, speed=res["walk"][2], events={"foot_r_down": 0.0}, out_dir=OUT)
    return res


def build_roll():
    fps = 30.0
    rig = mo_rig.Rig()
    c = dm_import.load(dm_file("roll"), fps)
    pose = dm_import.retarget(c, rig)
    dm_import.ground(pose)
    posefx.ground_clamp(pose, clearance=0.0)
    T = pose["pelvis_pos"].shape[0]
    flags = np.zeros((T, 2))
    clipio.save("roll", fps, False, pose["pelvis_pos"], pose["rot"], flags, speed=0.0, out_dir=OUT)
    print("roll frames", T)


if __name__ == "__main__":
    which = sys.argv[1:] or ["locomotion", "roll", "poses", "katana"]
    if "locomotion" in which:
        build_locomotion()
    if "roll" in which:
        build_roll()
    if "poses" in which:
        import clips_poses
        clips_poses.build(OUT)
    if "katana" in which:
        import clips_katana
        clips_katana.build(OUT)
