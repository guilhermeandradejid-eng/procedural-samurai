"""Clip file format shared by the offline tools and the game.

assets/motion/<name>.json
  name, fps, frames, loop, duration
  pelvis  : flat list, 3 floats per frame (rig units, absolute pelvis pivot in root space)
  rot     : flat list, 16 parts x 4 floats (x,y,z,w) per frame, parts in Rig.ORDER
  contact : flat list, 2 ints per frame [foot_r, foot_l]
  grip    : optional, 12 floats per frame: pos(3) blade(3) edge(3) weight left_weight 0 0
            (pos/blade/edge are relative to the chest part frame)
  speed   : ground speed the clip natively travels at (rig units / s), 0 for in-place clips
  events  : {name: time in seconds}
"""
import json
import os

import numpy as np

import mo_rig

MOTION_DIR = os.path.join(mo_rig.ROOT, "assets", "motion")


def save(name, fps, loop, pelvis_pos, rot, contacts, grip=None, speed=0.0, events=None, meta=None, out_dir=None):
    out_dir = out_dir or MOTION_DIR
    os.makedirs(out_dir, exist_ok=True)
    T = pelvis_pos.shape[0]
    d = {
        "name": name, "fps": fps, "frames": T, "loop": bool(loop), "duration": T / fps if loop else (T - 1) / fps,
        "pelvis": [round(float(x), 4) for x in pelvis_pos.reshape(-1)],
        "rot": [round(float(x), 4) for x in rot.reshape(-1)],
        "contact": [int(x) for x in np.asarray(contacts).reshape(-1)],
        "speed": round(float(speed), 4),
        "events": events or {},
    }
    if grip is not None:
        d["grip"] = [round(float(x), 4) for x in np.asarray(grip).reshape(-1)]
    if meta:
        d["meta"] = meta
    path = os.path.join(out_dir, name + ".json")
    with open(path, "w") as f:
        json.dump(d, f, separators=(",", ":"))
    return path


def load(path):
    d = json.load(open(path))
    T = d["frames"]
    out = {
        "name": d["name"], "fps": d["fps"], "loop": d["loop"], "speed": d.get("speed", 0.0),
        "pelvis_pos": np.array(d["pelvis"]).reshape(T, 3),
        "rot": np.array(d["rot"]).reshape(T, mo_rig.N, 4),
        "contacts": np.array(d["contact"]).reshape(T, 2),
        "events": d.get("events", {}),
    }
    if "grip" in d:
        out["grip"] = np.array(d["grip"]).reshape(T, 12)
    return out
