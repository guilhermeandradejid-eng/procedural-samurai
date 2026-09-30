"""Imports the joints of a text-to-motion run (N_out.npy for prompt N) into game clips.

    python3 text2motion/import_batch.py --results <dir> --prompts text2motion/prompts.json \
        --out ../../assets/motion_generated [--install]

Every clip is retargeted (import_smpl.py), gets its strike time from the peak speed of the
blade tip (so the game lines the hit up with the sweep window), is saved as JSON next to a
contact sheet PNG for review, and with --install also copied over assets/motion."""
import argparse
import json
import os
import shutil
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import clipio          # noqa: E402
import import_smpl     # noqa: E402
import mo_rig          # noqa: E402
import preview         # noqa: E402


def detect_strike(clip, fps):
    """Time (s) of the fastest blade-tip movement."""
    gw = preview.grip_world({"pelvis_pos": clip["pelvis_pos"], "rot": clip["rot"], "grip": clip["grip"]})
    if gw is None:
        return None
    pos, blade, _edge, on = gw
    tip = pos + blade * 0.9
    v = np.linalg.norm(np.gradient(tip, axis=0), axis=1) * fps
    from scipy.ndimage import gaussian_filter1d
    v = gaussian_filter1d(v, 1.5)
    return float(np.argmax(v) / fps)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", required=True)
    ap.add_argument("--prompts", default="text2motion/prompts.json")
    ap.add_argument("--out", default=os.path.join(clipio.MOTION_DIR, "..", "motion_generated"))
    ap.add_argument("--install", action="store_true")
    a = ap.parse_args()
    spec = json.load(open(a.prompts))
    os.makedirs(a.out, exist_ok=True)
    for i, c in enumerate(spec["clips"]):
        f = os.path.join(a.results, "%d_out.npy" % i)
        if not os.path.exists(f):
            print("missing", f)
            continue
        P = import_smpl.load_motion(f)
        res = import_smpl.import_motion(P, fps_in=20.0, fps_out=30.0, weapon=bool(c.get("weapon")), loop=bool(c.get("loop")),
                                        speed=float(c.get("speed", 1.0)), name=c["name"])
        meta = dict(res["meta"])
        meta["prompt"] = c["prompt"]
        clip = {"pelvis_pos": res["pelvis_pos"], "rot": res["rot"], "grip": res["grip"]}
        if res["grip"] is not None:
            st = detect_strike(clip, 30.0)
            if st is not None:
                meta["strike"] = round(st, 3)
        path = clipio.save(c["name"], 30.0, bool(c.get("loop")), res["pelvis_pos"], res["rot"], res["contacts"],
                           grip=res["grip"], meta=meta, out_dir=a.out)
        T = res["pelvis_pos"].shape[0]
        frames = list(np.linspace(0, T - 1, 10).astype(int))
        preview.sheet({"pelvis_pos": res["pelvis_pos"], "rot": res["rot"], "grip": res["grip"], "contacts": res["contacts"]},
                      frames, os.path.join(a.out, c["name"] + ".png"), views=("side", "top"), size=1.4)
        print("imported", c["name"], "frames", T, "strike", meta.get("strike"))
        if a.install:
            shutil.copy(path, os.path.join(clipio.MOTION_DIR, c["name"] + ".json"))
    if a.install:
        print("installed into", clipio.MOTION_DIR)


if __name__ == "__main__":
    main()
