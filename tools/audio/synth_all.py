#!/usr/bin/env python3
"""Synthesises every sound of the game (no samples, no external assets):

  assets/audio/sfx/<name>_<n>.ogg      one-shots with variations
  assets/audio/music/<name>.ogg        exploration score + combat taiko layer
  assets/audio/ambience/<name>.ogg     looping beds (wind, birds, crickets, ocean, rain, fire)
  assets/audio/manifest.json           name -> files, read by the Audio autoload

Usage: python3 tools/audio/synth_all.py [--only name,name]
Requires numpy, scipy and soundfile (libsndfile with Vorbis).
"""
import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
import soundfile as sf

sys.path.insert(0, os.path.dirname(__file__))
from dsp import SR  # noqa: E402
import sfx  # noqa: E402
import music  # noqa: E402
import ambience  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio")

MUSIC = {"exploration": music.exploration, "combat": music.combat}
AMBIENCE = {"wind": ambience.wind, "birds": ambience.birds, "crickets": ambience.crickets,
            "ocean": ambience.ocean, "rain": ambience.rain, "fire": ambience.fire}


def _write(path, data, quality=0.6):
    data = np.clip(np.asarray(data, dtype=np.float32), -1.0, 1.0)
    channels = 1 if data.ndim == 1 else data.shape[1]
    # libsndfile's Vorbis encoder can crash on very large single writes:
    # stream the buffer in blocks instead
    with sf.SoundFile(path, "w", SR, channels, format="OGG", subtype="VORBIS") as f:
        block = 8192
        for i in range(0, len(data), block):
            f.write(data[i:i + block])


def _job(job):
    kind, name, idx = job
    t0 = time.time()
    if kind == "sfx":
        gen, _ = sfx.SFX[name]
        data = gen(1000 + idx * 17 + sum(map(ord, name)))
        rel = "sfx/%s_%d.ogg" % (name, idx)
    elif kind == "music":
        data = MUSIC[name]()
        rel = "music/%s.ogg" % name
    else:
        data = AMBIENCE[name]()
        rel = "ambience/%s.ogg" % name
    _write(os.path.join(OUT, rel), data)
    return kind, name, rel, time.time() - t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    args = ap.parse_args()
    only = set(filter(None, args.only.split(",")))
    for d in ("sfx", "music", "ambience"):
        os.makedirs(os.path.join(OUT, d), exist_ok=True)
    jobs = []
    for name, (_, count) in sfx.SFX.items():
        for i in range(count):
            jobs.append(("sfx", name, i))
    for name in MUSIC:
        jobs.append(("music", name, 0))
    for name in AMBIENCE:
        jobs.append(("ambience", name, 0))
    if only:
        jobs = [j for j in jobs if j[1] in only]
    # long jobs first so the pool stays busy
    jobs.sort(key=lambda j: 0 if j[0] == "music" else (1 if j[0] == "ambience" else 2))
    t0 = time.time()
    manifest_path = os.path.join(OUT, "manifest.json")
    manifest = {"sfx": {}, "music": {}, "ambience": {}}
    if only and os.path.exists(manifest_path):
        manifest = json.load(open(manifest_path))
    results = []
    with ProcessPoolExecutor(max_workers=args.jobs) as ex:
        for kind, name, rel, dt in ex.map(_job, jobs):
            results.append((kind, name, rel))
            print("  %-9s %-22s %5.1fs" % (kind, rel, dt))
    for kind, name, rel in sorted(results):
        if kind == "sfx":
            lst = manifest["sfx"].setdefault(name, [])
            if rel not in lst:
                lst.append(rel)
        else:
            manifest[kind][name] = rel
    for k in manifest["sfx"]:
        manifest["sfx"][k] = sorted(manifest["sfx"][k])
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print("audio synthesised: %d files in %.1fs" % (len(results), time.time() - t0))


if __name__ == "__main__":
    main()
