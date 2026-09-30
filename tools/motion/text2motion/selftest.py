"""Round-trip test of the text-to-motion importer without any neural model.

Takes the authored / retargeted clips of the game, turns their joints into the SMPL
22-joint layout a text-to-motion tool would write (resampled to 20 fps), runs them
through import_smpl / import_batch and reports how far the imported bones are from the
originals. Run:  python3 text2motion/selftest.py"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import clipio       # noqa: E402
import mo_rig       # noqa: E402
from mo_rig import IDX  # noqa: E402

rig = mo_rig.Rig()


def to_smpl(pel, rot):
    pw, rw = rig.fk(pel, rot)
    ends = rig.joint_ends(pw, rw)
    T = pel.shape[0]
    P = np.zeros((T, 22, 3))
    pv = lambda n: pw[:, IDX[n]]
    P[:, 0] = (pv("thigh_r") + pv("thigh_l")) / 2
    P[:, 1], P[:, 2] = pv("thigh_l"), pv("thigh_r")
    P[:, 3], P[:, 6] = pv("belly"), pv("chest")
    P[:, 9] = 0.5 * (pv("chest") + (pv("upper_arm_r") + pv("upper_arm_l")) / 2) + np.array([0, 0.02, 0])
    P[:, 12] = pv("head")
    P[:, 15] = 0.5 * (pv("head") + ends[:, IDX["head"]])
    P[:, 4], P[:, 5] = pv("shin_l"), pv("shin_r")
    P[:, 7], P[:, 8] = pv("foot_l"), pv("foot_r")
    P[:, 10], P[:, 11] = ends[:, IDX["foot_l"]], ends[:, IDX["foot_r"]]
    P[:, 13] = pv("upper_arm_l") * 0.5 + P[:, 9] * 0.5
    P[:, 14] = pv("upper_arm_r") * 0.5 + P[:, 9] * 0.5
    P[:, 16], P[:, 17] = pv("upper_arm_l"), pv("upper_arm_r")
    P[:, 18], P[:, 19] = pv("forearm_l"), pv("forearm_r")
    P[:, 20], P[:, 21] = pv("hand_l"), pv("hand_r")
    P[..., 0] *= -1
    P[..., 2] *= -1
    return P


def main():
    names = ["katana_light_1", "katana_light_2", "hit_f"]
    tmp = tempfile.mkdtemp()
    spec = {"clips": []}
    for i, n in enumerate(names):
        c = clipio.load(os.path.join(clipio.MOTION_DIR, n + ".json"))
        P = to_smpl(c["pelvis_pos"], c["rot"])
        T = P.shape[0]
        # 30 fps -> 20 fps like the models write
        idx = np.linspace(0, T - 1, max(2, int(T * 20 / 30))).astype(int)
        np.save(os.path.join(tmp, "%d_out.npy" % i), P[idx][None])
        spec["clips"].append({"name": "selftest_" + n, "prompt": n, "weapon": n.startswith("katana"), "loop": False})
    json.dump(spec, open(os.path.join(tmp, "prompts.json"), "w"))
    out = os.path.join(tmp, "out")
    subprocess.check_call([sys.executable, os.path.join(HERE, "import_batch.py"), "--results", tmp,
                           "--prompts", os.path.join(tmp, "prompts.json"), "--out", out])
    worst = 0.0
    for n in names:
        a = clipio.load(os.path.join(clipio.MOTION_DIR, n + ".json"))
        b = clipio.load(os.path.join(out, "selftest_" + n + ".json"))
        pa, ra = rig.fk(a["pelvis_pos"], a["rot"])
        pb, rb = rig.fk(b["pelvis_pos"], b["rot"])
        # compare at matching normalised times
        ta = np.linspace(0, 1, pa.shape[0])
        tb = np.linspace(0, 1, pb.shape[0])
        errs = []
        for part in ("thigh_r", "shin_r", "thigh_l", "shin_l", "chest", "forearm_r", "forearm_l"):
            i = IDX[part]
            ea = rig.joint_ends(pa, ra)[:, i] - pa[:, i]
            eb = rig.joint_ends(pb, rb)[:, i] - pb[:, i]
            ea = np.stack([np.interp(tb, ta, ea[:, k]) for k in range(3)], axis=1)
            cosang = np.sum(mo_rig.normalize(ea) * mo_rig.normalize(eb), axis=1)
            errs.append(np.degrees(np.arccos(np.clip(cosang, -1, 1))).mean())
        print("%-16s mean bone-direction error %.1f deg" % (n, np.mean(errs)))
        worst = max(worst, float(np.mean(errs)))
    print("OK" if worst < 12.0 else "FAILED", "(worst %.1f deg)" % worst)
    sys.exit(0 if worst < 12.0 else 1)


if __name__ == "__main__":
    main()
