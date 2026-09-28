"""Small modelling toolkit on top of bpy/bmesh used by every asset script.

Coordinates: helpers take positions in *Godot* convention (Y up, forward -Z,
right +X) and convert to Blender (Z up) with G(). The glTF exporter converts
back, so what we write here is exactly what Godot sees.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODELS = os.path.join(ROOT, "assets", "models")


def G(x, y=None, z=None):
    """Godot (x, y, z) -> Blender vector."""
    if y is None:
        x, y, z = x
    return Vector((x, -z, y))


def GB(v):
    """Blender vector -> Godot tuple."""
    return (v.x, v.z, -v.y)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


MATS = {}


def mat(name, color=(0.8, 0.8, 0.8), rough=0.7, metal=0.0, alpha=1.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha
    MATS[name] = m
    return m


class Builder:
    """Accumulates geometry in one bmesh with per-face material slots."""

    def __init__(self):
        self.bm = bmesh.new()
        self.slots = []
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.col = None

    def slot(self, material_name):
        if material_name not in self.slots:
            self.slots.append(material_name)
        return self.slots.index(material_name)

    def faces_from(self, verts_before, faces_before, material_name, smooth=True):
        idx = self.slot(material_name)
        self.bm.faces.ensure_lookup_table()
        for f in self.bm.faces[faces_before:]:
            f.material_index = idx
            f.smooth = smooth

    def mark(self):
        self.bm.verts.ensure_lookup_table()
        self.bm.faces.ensure_lookup_table()
        return len(self.bm.verts), len(self.bm.faces)

    def new_faces_since(self, faces_before):
        self.bm.faces.ensure_lookup_table()
        return self.bm.faces[faces_before:]

    def new_verts_since(self, verts_before):
        self.bm.verts.ensure_lookup_table()
        return self.bm.verts[verts_before:]

    def to_object(self, name, location=None):
        # weld coincident vertices (lathe/superellipsoid poles) only now: deleting
        # elements earlier would let bmesh reuse slots and break index ranges
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts[:], dist=1e-6)
        bmesh.ops.dissolve_degenerate(self.bm, dist=1e-7, edges=self.bm.edges[:])
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for s in self.slots:
            me.materials.append(mat(s))
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        if location is not None:
            ob.location = location
        return ob


# ---------------------------------------------------------------- primitives

def lathe(B, profile, material, center=(0, 0, 0), axis="y", sides=24, smooth=True, cap_bottom=True,
          cap_top=True, radius_fn=None, angle_range=None, uv_scale=1.0, xz_scale=(1.0, 1.0)):
    """Surface of revolution. profile: list of (h, r) along the axis (Godot coords,
    axis 'y' by default). radius_fn(angle, h, r) can modulate the radius.
    angle_range=(a0, a1) makes an open partial revolution (for plates)."""
    v0, f0 = B.mark()
    bm = B.bm
    cx, cy, cz = center
    full = angle_range is None
    a0, a1 = (0.0, math.tau) if full else angle_range
    n_ang = sides if full else sides + 1
    rings = []
    for hi, (h, r) in enumerate(profile):
        ring = []
        for s in range(n_ang):
            a = a0 + (a1 - a0) * s / (sides if full else sides)
            rr = radius_fn(a, h, r) if radius_fn else r
            if axis == "y":
                p = (cx + math.cos(a) * rr * xz_scale[0], cy + h, cz + math.sin(a) * rr * xz_scale[1])
            elif axis == "x":
                p = (cx + h, cy + math.cos(a) * rr, cz + math.sin(a) * rr)
            else:
                p = (cx + math.cos(a) * rr, cy + math.sin(a) * rr, cz + h)
            ring.append(bm.verts.new(G(p)))
        rings.append(ring)
    total_len = 0.0
    vs = [0.0]
    for i in range(1, len(profile)):
        total_len += math.hypot(profile[i][0] - profile[i - 1][0], profile[i][1] - profile[i - 1][1])
        vs.append(total_len)
    for i in range(len(rings) - 1):
        for s in range(sides):
            s1 = (s + 1) % n_ang if full else s + 1
            a, b, c, d = rings[i][s], rings[i][s1], rings[i + 1][s1], rings[i + 1][s]
            try:
                f = bm.faces.new((a, d, c, b))
            except ValueError:
                continue
            for loop, (uu, vv) in zip(f.loops, ((s, vs[i]), (s, vs[i + 1]), (s + 1, vs[i + 1]), (s + 1, vs[i]))):
                loop[B.uv].uv = (uu / sides * uv_scale * 2.0, vv * uv_scale)
    if full and cap_bottom and profile[0][1] > 1e-4:
        c = bm.verts.new(G(cx, cy + profile[0][0], cz) if axis == "y" else G(cx + profile[0][0], cy, cz))
        for s in range(sides):
            try:
                bm.faces.new((rings[0][s], rings[0][(s + 1) % sides], c))
            except ValueError:
                pass
    if full and cap_top and profile[-1][1] > 1e-4:
        c = bm.verts.new(G(cx, cy + profile[-1][0], cz) if axis == "y" else G(cx + profile[-1][0], cy, cz))
        for s in range(sides):
            try:
                bm.faces.new((rings[-1][(s + 1) % sides], rings[-1][s], c))
            except ValueError:
                pass
    B.faces_from(v0, f0, material, smooth)
    return B


def superellipsoid(B, material, center, size, p=0.6, segs=24, rings=16, smooth=True, deform=None):
    """Rounded box: p=1 ellipsoid, p->0 box. size = full extents (Godot)."""
    v0, f0 = B.mark()
    bm = B.bm
    grid = []
    for i in range(rings + 1):
        v = -math.pi / 2 + math.pi * i / rings
        row = []
        for j in range(segs):
            u = -math.pi + math.tau * j / segs
            cv, sv = math.cos(v), math.sin(v)
            cu, su = math.cos(u), math.sin(u)

            def spow(x, e):
                return math.copysign(abs(x) ** e, x)
            x = spow(cv, p) * spow(cu, p) * size[0] * 0.5
            y = spow(sv, p) * size[1] * 0.5
            z = spow(cv, p) * spow(su, p) * size[2] * 0.5
            if deform:
                x, y, z = deform(x, y, z)
            row.append(bm.verts.new(G(center[0] + x, center[1] + y, center[2] + z)))
        grid.append(row)
    for i in range(rings):
        for j in range(segs):
            a = grid[i][j]
            b = grid[i][(j + 1) % segs]
            c = grid[i + 1][(j + 1) % segs]
            d = grid[i + 1][j]
            try:
                f = bm.faces.new((a, d, c, b))
                for loop, uv in zip(f.loops, ((j / segs, i / rings), (j / segs, (i + 1) / rings), ((j + 1) / segs, (i + 1) / rings), ((j + 1) / segs, i / rings))):
                    loop[B.uv].uv = uv
            except ValueError:
                pass
    B.faces_from(v0, f0, material, smooth)
    return B


def capsule(B, material, p0, p1, r0, r1, sides=18, cap_rings=5, body_rings=6, smooth=True, bulge=0.0):
    """Tapered capsule between Godot points p0 and p1."""
    p0 = Vector(p0)
    p1 = Vector(p1)
    axis = p1 - p0
    L = axis.length
    prof = []
    for i in range(cap_rings + 1):
        t = -math.pi / 2 + (math.pi / 2) * i / cap_rings
        prof.append((r0 * math.sin(t), r0 * math.cos(t)))
    for i in range(1, body_rings):
        t = i / body_rings
        r = r0 + (r1 - r0) * t + bulge * math.sin(t * math.pi)
        prof.append((L * t, r))
    for i in range(cap_rings + 1):
        t = (math.pi / 2) * i / cap_rings
        prof.append((L + r1 * math.sin(t), r1 * math.cos(t)))
    v0, f0 = B.mark()
    lathe(B, prof, material, center=(0, 0, 0), sides=sides, smooth=smooth, cap_bottom=False, cap_top=False)
    # orient +Y (Godot) along the axis and move to p0
    verts = B.new_verts_since(v0)
    up = Vector((0, 1, 0))
    d = axis.normalized()
    rot = up.rotation_difference(d).to_matrix()
    for v in verts:
        g = Vector(GB(v.co))
        g = rot @ g + p0
        v.co = G(g)
    return B


def tube(B, material, pts, radii, sides=8, smooth=True, cap=True, uv_scale=1.0, vcol=None):
    """Generalised cylinder through Godot points with per-point radius."""
    bm = B.bm
    v0, f0 = B.mark()
    pts = [Vector(p) for p in pts]
    rings = []
    prev_n = None
    vlen = 0.0
    vcoords = []
    for i, p in enumerate(pts):
        if i == 0:
            t = (pts[1] - pts[0]).normalized()
        elif i == len(pts) - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = (pts[i + 1] - pts[i - 1]).normalized()
        if prev_n is None:
            ref = Vector((0, 1, 0)) if abs(t.y) < 0.9 else Vector((1, 0, 0))
            n = t.cross(ref).normalized()
        else:
            n = (prev_n - t * prev_n.dot(t)).normalized()
        prev_n = n
        bnm = t.cross(n).normalized()
        if i > 0:
            vlen += (pts[i] - pts[i - 1]).length
        vcoords.append(vlen)
        ring = []
        for s in range(sides):
            a = math.tau * s / sides
            q = p + (n * math.cos(a) + bnm * math.sin(a)) * radii[i]
            ring.append(bm.verts.new(G(q)))
        rings.append(ring)
    circ = math.tau * max(radii[0], 0.02)
    for i in range(len(rings) - 1):
        for s in range(sides):
            a = rings[i][s]
            b = rings[i][(s + 1) % sides]
            c = rings[i + 1][(s + 1) % sides]
            d = rings[i + 1][s]
            f = bm.faces.new((a, b, c, d))
            for loop, (uu, vv) in zip(f.loops, ((s, vcoords[i]), (s + 1, vcoords[i]), (s + 1, vcoords[i + 1]), (s, vcoords[i + 1]))):
                loop[B.uv].uv = (uu / sides * uv_scale * max(circ, 0.3), vv * uv_scale)
    if cap:
        c = bm.verts.new(G(pts[-1] + (pts[-1] - pts[-2]).normalized() * radii[-1] * 0.3))
        for s in range(sides):
            bm.faces.new((rings[-1][s], rings[-1][(s + 1) % sides], c))
    B.faces_from(v0, f0, material, smooth)
    return B


def box(B, material, center, size, smooth=False, rot=None):
    v0, f0 = B.mark()
    res = bmesh.ops.create_cube(B.bm, size=1.0)
    verts = res["verts"]
    m = Matrix.Diagonal((size[0], size[2], size[1], 1.0))
    if rot is not None:
        m = rot @ m
    bmesh.ops.transform(B.bm, matrix=m, verts=verts)
    bmesh.ops.translate(B.bm, vec=G(center), verts=verts)
    B.faces_from(v0, f0, material, smooth)
    box_uv(B, B.new_faces_since(f0))
    return B


def box_uv(B, faces, scale=1.0):
    for f in faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            co = loop.vert.co
            if ax == 0:
                loop[B.uv].uv = (co.y * scale, co.z * scale)
            elif ax == 1:
                loop[B.uv].uv = (co.x * scale, co.z * scale)
            else:
                loop[B.uv].uv = (co.x * scale, co.y * scale)


def quad(B, material, a, b, c, d, uvs=((0, 0), (1, 0), (1, 1), (0, 1)), smooth=False):
    """Quad with corners a(bottom-left) b(bottom-right) c(top-right) d(top-left), Godot coords."""
    v0, f0 = B.mark()
    vs = [B.bm.verts.new(G(p)) for p in (a, b, c, d)]
    f = B.bm.faces.new(vs)
    for loop, uv in zip(f.loops, uvs):
        loop[B.uv].uv = uv
    B.faces_from(v0, f0, material, smooth)
    return f


def transform_since(B, v0, fn):
    for v in B.new_verts_since(v0):
        v.co = G(fn(Vector(GB(v.co))))


# ---------------------------------------------------------------- objects

def apply_modifiers(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    ob.modifiers.clear()
    old = ob.data
    ob.data = me
    bpy.data.meshes.remove(old)
    return ob


def subsurf(ob, levels=1):
    m = ob.modifiers.new("sub", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    return apply_modifiers(ob)


def solidify(ob, thickness, offset=-1.0):
    m = ob.modifiers.new("sol", "SOLIDIFY")
    m.thickness = thickness
    m.offset = offset
    m.use_even_offset = True
    return apply_modifiers(ob)


def bevel(ob, width=0.01, segments=2):
    m = ob.modifiers.new("bev", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    return apply_modifiers(ob)


def decimate(ob, ratio):
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = ratio
    return apply_modifiers(ob)


def smooth_all(ob, smooth=True):
    for p in ob.data.polygons:
        p.use_smooth = smooth


def set_origin(ob, godot_point):
    """Moves the object origin to a Godot-space point, keeping vertices in place."""
    off = G(godot_point)
    ob.data.transform(Matrix.Translation(-off))
    ob.location = off


def vertex_colors(ob, fn):
    """fn(godot_pos: Vector, poly_index) -> (r, g, b, a)"""
    me = ob.data
    ca = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            co = ob.matrix_world @ me.vertices[vi].co
            ca.data[li].color = fn(Vector(GB(co)), poly.index)
    me.color_attributes.active_color = ca
    return ca


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        objs[0].name = name
        return objs[0]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


def export(objs, rel_path):
    path = os.path.join(MODELS, rel_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_vertex_color="ACTIVE", export_normals=True,
                              export_texcoords=True, export_materials="EXPORT", export_cameras=False,
                              export_lights=False, export_extras=False)
    tris = sum(len(o.data.loop_triangles) for o in objs if o.type == "MESH" and (o.data.calc_loop_triangles() or True))
    print("    exported %-42s %3d objects %7d tris" % (rel_path, len(objs), tris))


def rng(seed):
    return random.Random(seed)
