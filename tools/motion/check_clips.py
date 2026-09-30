"""Sanity report for every baked clip: loop seams, sudden joint jumps, penetration of the floor."""
import glob
import os

import numpy as np
from scipy.spatial.transform import Rotation as R

import clipio
import mo_rig
import posefx

names = sorted(glob.glob(os.path.join(clipio.MOTION_DIR, "*.json")))
print("%-22s %6s %5s %8s %8s %8s %8s" % ("clip", "frames", "loop", "max deg/f", "seam", "floor", "reach"))
for path in names:
    c = clipio.load(path)
    T = c["rot"].shape[0]
    rot = c["rot"]
    step = []
    for i in range(mo_rig.N):
        q = R.from_quat(rot[:, i])
        d = np.degrees((q[:-1].inv() * q[1:]).magnitude())
        step.append(d)
    step = np.array(step)
    mx = step.max()
    seam = 0.0
    if c["loop"]:
        d = np.array([np.degrees((R.from_quat(rot[-1, i]).inv() * R.from_quat(rot[0, i])).magnitude()) for i in range(mo_rig.N)])
        seam = d.max()
    low = posefx.lowest_body_point(c["pelvis_pos"], rot)
    print("%-22s %6d %5s %8.1f %8.1f %8.3f" % (os.path.basename(path)[:-5], T, c["loop"], mx, seam, low.min()))
