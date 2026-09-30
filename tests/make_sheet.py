#!/usr/bin/env python3
"""Builds contact sheets from pose_gallery PNGs.
Usage: make_sheet.py <dir> <out_prefix> [pose,pose...] [--cols N] [--tile W]
Each row is one pose; the columns are its moments (front-right | side)."""
import glob
import os
import re
import sys

from PIL import Image, ImageDraw

d, prefix = sys.argv[1], sys.argv[2]
want = [a for a in sys.argv[3:] if not a.startswith("--")]
want = want[0].split(",") if want else None
tile = 300
for i, a in enumerate(sys.argv):
    if a == "--tile":
        tile = int(sys.argv[i + 1])
poses = {}
for f in sorted(glob.glob(os.path.join(d, "*.png"))):
    m = re.match(r"(.+)_(\d+)_(\d+)\.png", os.path.basename(f))
    if not m:
        continue
    poses.setdefault(m.group(1), {}).setdefault(int(m.group(2)), {})[int(m.group(3))] = f
names = [n for n in poses if not want or n in want]
per_sheet = 5
for s_i in range(0, len(names), per_sheet):
    chunk = names[s_i:s_i + per_sheet]
    maxcols = max(len(poses[n]) for n in chunk)
    sheet = Image.new("RGB", (maxcols * tile, tile * 2 * len(chunk)), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    for r, n in enumerate(chunk):
        for c, moment in enumerate(sorted(poses[n])):
            for v, f in sorted(poses[n][moment].items()):
                im = Image.open(f).convert("RGB").resize((tile, tile))
                sheet.paste(im, (c * tile, (r * 2 + v) * tile))
        dr.text((6, r * 2 * tile + 4), n, fill=(255, 255, 0))
    out = "%s_%02d.png" % (prefix, s_i // per_sheet)
    sheet.save(out)
    print(out, chunk)
