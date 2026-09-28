#!/usr/bin/env python3
"""Builds every 3D model of the game with Blender (bpy as a Python module).

Usage:  python3 tools/blender/build_models.py [characters weapons trees rocks buildings props]
Requires: pip install bpy==4.5.4  (Blender 4.5 LTS as a module, Python 3.11)
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402,F401  (registers mathutils & bmesh)

GROUPS = ["characters", "weapons", "trees", "rocks", "buildings", "props"]


def main():
    wanted = [a for a in sys.argv[1:] if not a.startswith("-")] or GROUPS
    t0 = time.time()
    for g in wanted:
        t = time.time()
        print("[%s]" % g)
        mod = __import__(g)
        mod.build()
        print("  (%.1fs)" % (time.time() - t))
    print("models built in %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
