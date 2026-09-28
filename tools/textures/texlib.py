"""Tileable procedural texture toolkit (numpy + PIL).

Everything here produces seamless textures: noise is synthesised in the
frequency domain (inherently periodic), Voronoi uses wrapped distances and
stamping wraps around the borders.
"""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
from scipy.spatial import cKDTree


def rng(seed):
    return np.random.default_rng(seed)


def fft_noise(size, beta=2.0, seed=0, low_cut=1.0):
    """Periodic fractal noise with a 1/f^beta power spectrum, normalised to [0,1]."""
    r = rng(seed)
    white = r.standard_normal((size, size))
    f = np.fft.fft2(white)
    fy = np.fft.fftfreq(size)[:, None] * size
    fx = np.fft.fftfreq(size)[None, :] * size
    k = np.sqrt(fx * fx + fy * fy)
    k[0, 0] = 1.0
    amp = 1.0 / np.power(np.maximum(k, low_cut), beta / 2.0)
    amp[0, 0] = 0.0
    out = np.real(np.fft.ifft2(f * amp))
    out -= out.min()
    out /= max(out.max(), 1e-9)
    return out


def band_noise(size, freq, seed=0, width=0.5):
    """Periodic noise concentrated around a frequency (cycles per texture)."""
    r = rng(seed)
    white = r.standard_normal((size, size))
    f = np.fft.fft2(white)
    fy = np.fft.fftfreq(size)[:, None] * size
    fx = np.fft.fftfreq(size)[None, :] * size
    k = np.sqrt(fx * fx + fy * fy)
    amp = np.exp(-((np.log2(np.maximum(k, 0.5)) - math.log2(freq)) ** 2) / (2 * width * width))
    amp[0, 0] = 0.0
    out = np.real(np.fft.ifft2(f * amp))
    out -= out.min()
    out /= max(out.max(), 1e-9)
    return out


def directional_noise(size, freq, angle_deg, stretch=6.0, seed=0):
    """Anisotropic noise (streaks) useful for wood grain, straw, sand ripples."""
    r = rng(seed)
    white = r.standard_normal((size, size))
    f = np.fft.fft2(white)
    fy = np.fft.fftfreq(size)[:, None] * size
    fx = np.fft.fftfreq(size)[None, :] * size
    a = math.radians(angle_deg)
    u = fx * math.cos(a) + fy * math.sin(a)
    v = -fx * math.sin(a) + fy * math.cos(a)
    k = np.sqrt(u * u + (v * stretch) ** 2)
    amp = 1.0 / np.maximum(k, 1.0) ** 1.2 * np.exp(-(k / (freq * 2.5)) ** 2)
    amp[0, 0] = 0.0
    out = np.real(np.fft.ifft2(f * amp))
    out -= out.min()
    out /= max(out.max(), 1e-9)
    return out


def voronoi(size, n, seed=0, jitter=1.0):
    """Wrapped Voronoi: returns (F1, F2, cell_id) with distances in pixels."""
    r = rng(seed)
    pts = r.random((n, 2)) * size
    tiles = []
    ids = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            tiles.append(pts + np.array([dx * size, dy * size]))
            ids.append(np.arange(n))
    allp = np.vstack(tiles)
    allid = np.concatenate(ids)
    tree = cKDTree(allp)
    yy, xx = np.mgrid[0:size, 0:size]
    q = np.stack([xx.ravel() + 0.5, yy.ravel() + 0.5], -1)
    d, i = tree.query(q, k=2)
    f1 = d[:, 0].reshape(size, size)
    f2 = d[:, 1].reshape(size, size)
    cid = allid[i[:, 0]].reshape(size, size)
    return f1, f2, cid


def height_to_normal(h, strength=2.0):
    """Tangent-space normal map (RGB 0..1) from a tileable height field."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength  # Godot expects OpenGL-style (Y+) normal maps
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5], -1)


def ambient_occlusion(h, radius=6, strength=1.0):
    blur = ndimage.gaussian_filter(h, radius, mode="wrap")
    ao = np.clip(1.0 - (blur - h) * strength * 4.0, 0.0, 1.0)
    return ao


def ramp(t, stops):
    """Colour ramp: stops = [(pos, (r,g,b)), ...]."""
    t = np.clip(t, 0, 1)
    pos = np.array([s[0] for s in stops])
    cols = np.array([s[1] for s in stops], dtype=np.float64)
    out = np.zeros(t.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(t, pos, cols[:, c])
    return out


def mix(a, b, t):
    t = np.asarray(t)
    if t.ndim == a.ndim - 1:
        t = t[..., None]
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def to_img(arr, mode=None):
    a = np.clip(arr, 0, 1)
    a = (a * 255 + 0.5).astype(np.uint8)
    return Image.fromarray(a, mode)


def save_rgb(arr, path, quality=None):
    img = to_img(arr, "RGB")
    if path.endswith(".jpg"):
        img.save(path, quality=quality or 90, subsampling=0)
    else:
        img.save(path, optimize=True)


def save_rgba(arr, path):
    to_img(arr, "RGBA").save(path, optimize=True)


class WrapCanvas:
    """Supersampled RGBA canvas that wraps drawings around the borders."""

    def __init__(self, size, ss=2, bg=(0, 0, 0, 0)):
        self.size = size
        self.ss = ss
        self.img = Image.new("RGBA", (size * ss, size * ss), bg)
        self.draw = ImageDraw.Draw(self.img, "RGBA")

    def _offsets(self, pts, margin):
        S = self.size * self.ss
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        offs = [(0, 0)]
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                if (ox, oy) == (0, 0):
                    continue
                if min(xs) + ox < S + margin and max(xs) + ox > -margin and min(ys) + oy < S + margin and max(ys) + oy > -margin:
                    offs.append((ox, oy))
        return offs

    def polygon(self, pts, fill, outline=None, width=1):
        s = self.ss
        P = [(x * s, y * s) for x, y in pts]
        for ox, oy in self._offsets(P, 4):
            self.draw.polygon([(x + ox, y + oy) for x, y in P], fill=fill, outline=outline, width=width)

    def line(self, pts, fill, width=1):
        s = self.ss
        P = [(x * s, y * s) for x, y in pts]
        for ox, oy in self._offsets(P, width * s + 4):
            self.draw.line([(x + ox, y + oy) for x, y in P], fill=fill, width=max(1, int(width * s)), joint="curve")

    def ellipse(self, cx, cy, rx, ry, fill, outline=None):
        s = self.ss
        box = [(cx - rx) * s, (cy - ry) * s, (cx + rx) * s, (cy + ry) * s]
        for ox, oy in self._offsets([(box[0], box[1]), (box[2], box[3])], 4):
            self.draw.ellipse([box[0] + ox, box[1] + oy, box[2] + ox, box[3] + oy], fill=fill, outline=outline)

    def result(self):
        return np.asarray(self.img.resize((self.size, self.size), Image.LANCZOS)).astype(np.float64) / 255.0


def leaf_shape(kind, length=1.0, lobes=5):
    """Returns a list of (x, y) points of a leaf outline, stem at (0,0), tip along -y."""
    pts = []
    if kind == "maple":
        # palmate leaf with `lobes` pointed lobes
        n = 90
        for i in range(n + 1):
            t = i / n
            a = -math.pi * 0.95 + t * math.pi * 1.9
            lobe = abs(math.sin(a * lobes / 2.0 + math.pi / 2 * (lobes % 2)))
            rr = length * (0.38 + 0.62 * lobe ** 3) * (0.75 + 0.25 * math.cos(a))
            rr *= 1.0 - 0.18 * (math.sin(a * lobes * 2.0) ** 2)
            pts.append((math.sin(a) * rr, -math.cos(a) * rr * 0.95 - length * 0.12))
    elif kind == "ginkgo":
        n = 50
        for i in range(n + 1):
            t = i / n
            a = -1.1 + t * 2.2
            rr = length * (0.95 - 0.12 * math.exp(-(a * 6.0) ** 2))
            pts.append((math.sin(a) * rr, -math.cos(a) * rr))
        pts.append((length * 0.05, -length * 0.05))
        pts.append((-length * 0.05, -length * 0.05))
    elif kind == "sakura":
        # five petal blossom (centred)
        n = 100
        for i in range(n + 1):
            a = i / n * math.tau
            petal = abs(math.cos(a * 2.5))
            notch = 1.0 - 0.25 * math.exp(-((petal - 1.0) * 30) ** 2)
            rr = length * (0.35 + 0.65 * petal ** 0.6) * notch
            pts.append((math.cos(a) * rr, math.sin(a) * rr))
    elif kind == "birch":
        n = 40
        for i in range(n + 1):
            t = i / n
            y = -t * length
            w = math.sin(t * math.pi) ** 0.8 * length * 0.36 * (1.0 + 0.1 * math.sin(t * 40))
            pts.append((w, y))
        for i in range(n, -1, -1):
            t = i / n
            y = -t * length
            w = math.sin(t * math.pi) ** 0.8 * length * 0.36 * (1.0 + 0.1 * math.sin(t * 40 + 1))
            pts.append((-w, y))
    else:  # lanceolate (bamboo / willow)
        n = 30
        for i in range(n + 1):
            t = i / n
            pts.append((math.sin(t * math.pi) ** 0.7 * length * 0.12, -t * length))
        for i in range(n, -1, -1):
            t = i / n
            pts.append((-math.sin(t * math.pi) ** 0.7 * length * 0.12, -t * length))
    return pts


def transform(pts, x, y, angle, scale=1.0):
    ca, sa = math.cos(angle), math.sin(angle)
    return [(x + (px * ca - py * sa) * scale, y + (px * sa + py * ca) * scale) for px, py in pts]
