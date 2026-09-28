"""Fast vectorised noise helpers (numpy + scipy) used by the world generator.

All noise is built from random lattices interpolated with cubic B-splines
(scipy.ndimage.map_coordinates) which is smooth, fast and deterministic.
"""
import numpy as np
from scipy import ndimage


class LatticeNoise:
    """Smooth value noise in roughly [-1, 1], periodic with `period` lattice cells."""

    def __init__(self, seed, period=512):
        rng = np.random.default_rng(seed)
        grid = rng.random((period, period))
        self.period = period
        self.coeffs = ndimage.spline_filter(grid, order=3, mode="grid-wrap")
        # empirical normalisation so the output roughly spans [-1, 1]
        test = ndimage.map_coordinates(self.coeffs, rng.random((2, 20000)) * period, order=3,
                                       mode="grid-wrap", prefilter=False)
        self.mean = float(test.mean())
        self.scale = 1.0 / (float(test.std()) * 2.2)

    def __call__(self, u, v):
        u = np.asarray(u, dtype=np.float64)
        v = np.asarray(v, dtype=np.float64)
        shp = u.shape
        coords = np.stack([np.mod(v.ravel(), self.period), np.mod(u.ravel(), self.period)])
        out = ndimage.map_coordinates(self.coeffs, coords, order=3, mode="grid-wrap", prefilter=False)
        return ((out - self.mean) * self.scale).reshape(shp)


class FBM:
    def __init__(self, seed, octaves=6, lacunarity=2.03, gain=0.5, period=512):
        self.octaves = octaves
        self.lac = lacunarity
        self.gain = gain
        self.noise = LatticeNoise(seed, period)
        rng = np.random.default_rng(seed + 991)
        self.offsets = rng.random((octaves, 2)) * period

    def __call__(self, u, v):
        total = np.zeros(np.shape(u))
        amp = 1.0
        norm = 0.0
        f = 1.0
        for o in range(self.octaves):
            total += amp * self.noise(u * f + self.offsets[o, 0], v * f + self.offsets[o, 1])
            norm += amp
            amp *= self.gain
            f *= self.lac
        return total / norm

    def ridged(self, u, v, sharpness=2.0):
        """Ridged multifractal in [0, 1] (1 = ridge crest)."""
        total = np.zeros(np.shape(u))
        amp = 1.0
        norm = 0.0
        f = 1.0
        weight = np.ones(np.shape(u))
        for o in range(self.octaves):
            n = self.noise(u * f + self.offsets[o, 0], v * f + self.offsets[o, 1])
            r = 1.0 - np.abs(np.clip(n, -1, 1))
            r = r ** sharpness
            r *= weight
            weight = np.clip(r * 1.6, 0, 1)
            total += amp * r
            norm += amp
            amp *= self.gain
            f *= self.lac
        return total / norm


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def bilinear(field, px, py):
    """Bilinear sample of a 2D array at float pixel coords (x = column, y = row)."""
    h, w = field.shape
    px = np.clip(px, 0, w - 1.001)
    py = np.clip(py, 0, h - 1.001)
    ix = px.astype(np.int64)
    iy = py.astype(np.int64)
    fx = px - ix
    fy = py - iy
    a = field[iy, ix]
    b = field[iy, ix + 1]
    c = field[iy + 1, ix]
    d = field[iy + 1, ix + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
