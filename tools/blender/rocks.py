"""Boulders, slabs, spires and cliff chunks: displaced icospheres.

Rocks use the 'rock' material slot; in Godot they get a world-space
triplanar rock shader with moss on upward faces, so UVs do not matter.
"""
import math

import bmesh
from mathutils import Vector, noise

import blib
from blib import Builder, G

VARIANTS = {
    "boulder_0": {"size": (2.2, 1.6, 1.9), "sharp": 0.55, "seed": 11, "flat": 0.25},
    "boulder_1": {"size": (1.4, 1.1, 1.5), "sharp": 0.7, "seed": 12, "flat": 0.3},
    "boulder_2": {"size": (3.2, 2.1, 2.6), "sharp": 0.45, "seed": 13, "flat": 0.2},
    "slab_0": {"size": (3.6, 0.9, 2.4), "sharp": 0.6, "seed": 14, "flat": 0.35},
    "spire_0": {"size": (1.6, 4.2, 1.5), "sharp": 0.65, "seed": 15, "flat": 0.1},
    "cliff_0": {"size": (8.0, 6.0, 5.0), "sharp": 0.8, "seed": 16, "flat": 0.15},
    "pebbles_0": {"size": (0.5, 0.35, 0.45), "sharp": 0.5, "seed": 17, "flat": 0.3},
}


def rock(name, spec):
    B = Builder()
    res = bmesh.ops.create_icosphere(B.bm, subdivisions=4, radius=0.5)
    verts = res["verts"]
    sx, sy, sz = spec["size"]
    seed = spec["seed"]
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    for v in verts:
        g = Vector(blib.GB(v.co))  # unit sphere point (Godot coords)
        d = g.normalized()
        # large lumps + faceted voronoi cells for chiselled planes
        lump = noise.fractal(d * 1.3 + off, 0.6, 2.0, 4)
        cells = noise.voronoi(d * 2.2 + off, distance_metric="DISTANCE")[0][0]
        facet = (1.0 - min(1.0, cells * 1.8)) * spec["sharp"]
        rr = 0.5 * (1.0 + 0.28 * lump + 0.22 * facet)
        p = Vector((d.x * rr * sx, d.y * rr * sy, d.z * rr * sz))
        # flatten the bottom so rocks sit on the ground
        floor_y = -sy * 0.5 * (1.0 - spec["flat"])
        if p.y < floor_y:
            p.y = floor_y + (p.y - floor_y) * 0.15
        v.co = G(p)
    idx = B.slot("rock")
    for f in B.bm.faces:
        f.material_index = idx
        f.smooth = True
    ob = B.to_object(name)
    ob = blib.decimate(ob, 0.45 if spec["size"][0] < 5 else 0.7)
    blib.smooth_all(ob, True)
    # move so the lowest point sits slightly under y = 0
    miny = min((ob.matrix_world @ v.co).z for v in ob.data.vertices)
    ob.data.transform(__import__("mathutils").Matrix.Translation((0, 0, -miny - 0.08 * spec["size"][1])))
    return ob


def build():
    for name, spec in VARIANTS.items():
        blib.reset()
        ob = rock(name, spec)
        blib.export([ob], "rocks/%s.glb" % name)
