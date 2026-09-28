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

# images imported as Texture2DArray: path -> (horizontal slices, compress mode)
TEXTURE_ARRAYS = {
    "assets/textures/terrain/terrain_albedo.jpg": (8, 2),
    "assets/textures/terrain/terrain_nrh.png": (8, 0),
}


def write_array_import(src_rel, slices, mode):
    imp = os.path.join(ROOT, src_rel) + ".import"
    if os.path.exists(imp):
        txt = open(imp, encoding="utf-8").read()
        if 'importer="2d_array_texture"' in txt and "slices/horizontal=%d" % slices in txt:
            return False
    uid = ""
    if os.path.exists(imp):
        m = re.search(r'^uid="([^"]+)"', open(imp, encoding="utf-8").read(), re.M)
        if m:
            uid = 'uid="%s"\n' % m.group(1)
    txt = ('[remap]\n\nimporter="2d_array_texture"\ntype="CompressedTexture2DArray"\n%s\n'
           '[params]\n\ncompress/mode=%d\ncompress/high_quality=false\ncompress/lossy_quality=0.7\n'
           'compress/hdr_compression=1\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\n'
           'slices/horizontal=%d\nslices/vertical=1\n') % (uid, mode, slices)
    open(imp, "w", encoding="utf-8").write(txt)
    return True


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
    for rel, (slices, mode) in TEXTURE_ARRAYS.items():
        if os.path.exists(os.path.join(ROOT, rel)) and write_array_import(rel, slices, mode):
            changed += 1
    for pattern, params in RULES:
        for src in glob.glob(os.path.join(ROOT, pattern), recursive=True):
            rel = os.path.relpath(src, ROOT).replace(os.sep, "/")
            if rel in TEXTURE_ARRAYS:
                continue
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
