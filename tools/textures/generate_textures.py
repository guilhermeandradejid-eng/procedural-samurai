#!/usr/bin/env python3
"""Generates every texture of the game procedurally.

Usage: python3 tools/textures/generate_textures.py [terrain|vegetation|materials|fx|ui ...]
"""
import os
import sys
import time
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(__file__))
import gen_fx  # noqa: E402
import gen_materials  # noqa: E402
import gen_terrain  # noqa: E402
import gen_ui  # noqa: E402
import gen_vegetation  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX = os.path.join(ROOT, "assets", "textures")

GROUPS = {
    "terrain": (gen_terrain, "terrain"),
    "vegetation": (gen_vegetation, "vegetation"),
    "materials": (gen_materials, "materials"),
    "fx": (gen_fx, "fx"),
    "ui": (gen_ui, "ui"),
}


def main():
    wanted = sys.argv[1:] or list(GROUPS.keys())
    t0 = time.time()
    with Pool(4) as pool:
        for g in wanted:
            mod, sub = GROUPS[g]
            t = time.time()
            print("[%s]" % g)
            mod.generate(os.path.join(TEX, sub), pool)
            print("  (%.1fs)" % (time.time() - t))
    print("all textures in %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
