#!/usr/bin/env python3
"""Patches Godot .import files so generated assets use the right import
settings (data textures stay lossless, texture arrays are sliced, audio
loops are flagged...). Run after the first `godot --headless --import`, then
import again so Godot re-processes the changed files.
"""
import glob
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

DATA_TEX = {
    "compress/mode": "0",
    "mipmaps/generate": "false",
    "process/fix_alpha_border": "false",
    "detect_3d/compress_to": "0",
}

RULES = [
    # (glob relative to ROOT, {param: value})
    ("assets/world/splat.png", DATA_TEX),
    ("assets/world/veg.png", DATA_TEX),
    ("assets/world/normal.png", DATA_TEX),
    ("assets/world/map.png", {"compress/mode": "0", "mipmaps/generate": "true", "detect_3d/compress_to": "0"}),
    ("assets/textures/**/*_n.png", {"compress/normal_map": "1", "mipmaps/generate": "true"}),
    ("assets/textures/**/*.png", {"mipmaps/generate": "true"}),
    ("assets/textures/ui/*.png", {"compress/mode": "0", "mipmaps/generate": "false", "detect_3d/compress_to": "0"}),
    ("assets/textures/fx/*.png", {"mipmaps/generate": "true", "detect_3d/compress_to": "0", "compress/mode": "0"}),
]

AUDIO_LOOP_DIRS = ["assets/audio/music", "assets/audio/ambience"]


def patch_params(text, params):
    for k, v in params.items():
        pat = re.compile(r"^%s=.*$" % re.escape(k), re.M)
        if pat.search(text):
            text = pat.sub("%s=%s" % (k, v), text)
        else:
            text = text.rstrip("\n") + "\n%s=%s\n" % (k, v)
    return text


def main():
    changed = 0
    applied = {}
    for pattern, params in RULES:
        for src in glob.glob(os.path.join(ROOT, pattern), recursive=True):
            imp = src + ".import"
            if not os.path.exists(imp):
                continue
            merged = applied.setdefault(imp, {})
            merged.update(params)
    for imp, params in applied.items():
        txt = open(imp, encoding="utf-8").read()
        new = patch_params(txt, params)
        if new != txt:
            open(imp, "w", encoding="utf-8").write(new)
            changed += 1
    for d in AUDIO_LOOP_DIRS:
        for imp in glob.glob(os.path.join(ROOT, d, "*.ogg.import")):
            txt = open(imp, encoding="utf-8").read()
            new = patch_params(txt, {"loop": "true"})
            if new != txt:
                open(imp, "w", encoding="utf-8").write(new)
                changed += 1
    print("patched %d import files" % changed)


if __name__ == "__main__":
    main()
