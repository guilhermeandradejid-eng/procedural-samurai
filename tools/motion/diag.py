"""python3 diag.py clips_katana light_2  -> per frame reach table (only frames where an arm is stretched)"""
import importlib
import sys

import numpy as np

import authoring as A

np.set_printoptions(precision=2, suppress=True, linewidth=220)
mod = importlib.import_module(sys.argv[1])
c = getattr(mod, sys.argv[2])()
ch = c.sample()
if c.auto:
    c.auto(ch, c)
res = A.solve(ch, grip_space=c.grip_space, edge_auto=c.edge_auto, fps=c.fps)
ts = np.arange(len(ch["px"])) / c.fps
rr, rl = A.REACH["r"], A.REACH["l"]
print("%s  max reach r %.2f l %.2f" % (c.name, rr.max(), rl.max()))
bad = [i for i in range(len(ts)) if rr[i] > 0.97 or (rl[i] > 0.97 and ch["g_left"][i] > 0.3) or rr[i] < 0.3]
for i in bad:
    print("  t=%.2f  r %.2f  l %.2f  (left w %.2f)  chest yaw %.0f lean %.0f" % (ts[i], rr[i], rl[i], ch["g_left"][i], ch["p_yaw"][i] + ch["s_yaw"][i], ch["s_lean"][i]))
