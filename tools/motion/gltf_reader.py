"""Minimal glTF/GLB reader for skeletal animation (no dependencies beyond numpy).

    g = GLTF("Knight.glb")
    g.nodes            # list of dicts: name, parent, t, r, s (rest, local)
    g.animations       # {name: {"duration": s, "channels": [(node, path, times, values, interp)]}}
    g.sample(name, fps) -> (times, T[frames, nodes, 3], R[frames, nodes, 4 (xyzw)], S[frames, nodes, 3])
"""
import json
import struct

import numpy as np

COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
TYPE_N = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def _slerp(a, b, t):
    d = float(np.dot(a, b))
    if d < 0.0:
        b = -b
        d = -d
    if d > 0.9995:
        r = a + (b - a) * t
        return r / np.linalg.norm(r)
    th = np.arccos(np.clip(d, -1, 1))
    return (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)


class GLTF:
    def __init__(self, path):
        with open(path, "rb") as f:
            data = f.read()
        magic, version, length = struct.unpack("<4sII", data[:12])
        assert magic == b"glTF", "not a GLB"
        off = 12
        self.json = None
        self.bin = b""
        while off < length:
            clen, ctype = struct.unpack("<II", data[off:off + 8])
            chunk = data[off + 8:off + 8 + clen]
            if ctype == 0x4E4F534A:
                self.json = json.loads(chunk.decode("utf8"))
            elif ctype == 0x004E4942:
                self.bin = chunk
            off += 8 + clen
        j = self.json
        self.nodes = []
        for i, n in enumerate(j["nodes"]):
            self.nodes.append({"name": n.get("name", "node%d" % i), "parent": -1, "children": n.get("children", []),
                               "t": np.array(n.get("translation", [0, 0, 0]), float),
                               "r": np.array(n.get("rotation", [0, 0, 0, 1]), float),
                               "s": np.array(n.get("scale", [1, 1, 1]), float),
                               "mesh": n.get("mesh"), "skin": n.get("skin")})
        for i, n in enumerate(self.nodes):
            for c in n["children"]:
                self.nodes[c]["parent"] = i
        self.name_to_idx = {n["name"]: i for i, n in enumerate(self.nodes)}
        self.animations = {}
        for a in j.get("animations", []):
            chans = []
            dur = 0.0
            for ch in a["channels"]:
                s = a["samplers"][ch["sampler"]]
                times = self._accessor(s["input"])
                values = self._accessor(s["output"])
                path = ch["target"]["path"]
                if path == "weights":
                    continue
                chans.append((ch["target"]["node"], path, times, values, s.get("interpolation", "LINEAR")))
                dur = max(dur, float(times[-1]))
            self.animations[a.get("name", "anim%d" % len(self.animations))] = {"duration": dur, "channels": chans}

    def _accessor(self, idx):
        acc = self.json["accessors"][idx]
        bv = self.json["bufferViews"][acc["bufferView"]]
        dt = COMPONENT[acc["componentType"]]
        n = TYPE_N[acc["type"]]
        count = acc["count"]
        start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = bv.get("byteStride", 0)
        itemsize = np.dtype(dt).itemsize * n
        if stride and stride != itemsize:
            raw = np.frombuffer(self.bin, dtype=np.uint8, count=stride * count, offset=start).reshape(count, stride)[:, :itemsize]
            arr = np.frombuffer(raw.tobytes(), dtype=dt).reshape(count, n)
        else:
            arr = np.frombuffer(self.bin, dtype=dt, count=count * n, offset=start).reshape(count, n)
        arr = arr.astype(np.float64)
        if acc.get("normalized"):
            arr = arr / float(np.iinfo(dt).max)
        return arr[:, 0] if n == 1 else arr

    def rest(self):
        T = np.array([n["t"] for n in self.nodes])
        R = np.array([n["r"] for n in self.nodes])
        S = np.array([n["s"] for n in self.nodes])
        return T, R, S

    def sample(self, name, fps=30.0):
        a = self.animations[name]
        dur = a["duration"]
        nframes = max(2, int(round(dur * fps)) + 1)
        times = np.arange(nframes) / fps
        T0, R0, S0 = self.rest()
        N = len(self.nodes)
        T = np.repeat(T0[None], nframes, 0)
        R = np.repeat(R0[None], nframes, 0)
        S = np.repeat(S0[None], nframes, 0)
        for node, path, tk, vals, interp in a["channels"]:
            for f, t in enumerate(times):
                t = min(t, tk[-1])
                i = int(np.searchsorted(tk, t, side="right")) - 1
                i = max(0, min(i, len(tk) - 1))
                j = min(i + 1, len(tk) - 1)
                u = 0.0 if j == i or interp == "STEP" else (t - tk[i]) / (tk[j] - tk[i])
                if interp == "CUBICSPLINE":
                    v0 = vals[3 * i + 1]
                    v1 = vals[3 * j + 1]
                else:
                    v0 = vals[i]
                    v1 = vals[j]
                if path == "rotation":
                    R[f, node] = _slerp(v0 / np.linalg.norm(v0), v1 / np.linalg.norm(v1), u)
                elif path == "translation":
                    T[f, node] = v0 + (v1 - v0) * u
                elif path == "scale":
                    S[f, node] = v0 + (v1 - v0) * u
        return times, T, R, S
