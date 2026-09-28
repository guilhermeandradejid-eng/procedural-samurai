"""Vectorised droplet hydraulic erosion + thermal erosion (numpy).

Thousands of droplets are simulated in parallel. Each step every droplet
moves one cell downhill (with inertia), picks up or deposits sediment
depending on its carrying capacity, and the height changes are scattered
back into the heightmap with np.bincount (fast unbuffered accumulation).
"""
import numpy as np


def _brush(radius):
    offs = []
    weights = []
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            d = (dx * dx + dy * dy) ** 0.5
            if d <= radius:
                offs.append((dx, dy))
                weights.append(max(0.0, radius - d))
    w = np.array(weights, dtype=np.float64)
    w /= w.sum()
    return np.array(offs, dtype=np.int64), w


def hydraulic(h, cell_size=2.0, iterations=6, droplets=100_000, steps=56, seed=7,
              inertia=0.08, capacity_k=5.0, min_capacity=0.01, deposit_k=0.25,
              erode_k=0.3, evaporate=0.018, gravity=9.0, brush_radius=2,
              mask=None, verbose=True):
    """Erodes heightmap `h` (meters) in place and returns (h, flow) where flow
    accumulates the amount of water that passed through each cell."""
    H, W = h.shape
    rng = np.random.default_rng(seed)
    offs, bw = _brush(brush_radius)
    flow = np.zeros(H * W, dtype=np.float64)
    hf = h.reshape(-1)
    for it in range(iterations):
        px = rng.uniform(2, W - 3, droplets)
        py = rng.uniform(2, H - 3, droplets)
        if mask is not None:
            keep = mask[py.astype(np.int64), px.astype(np.int64)] > 0.5
            px = px[keep]
            py = py[keep]
        n = px.shape[0]
        dx = np.zeros(n)
        dy = np.zeros(n)
        speed = np.ones(n)
        water = np.ones(n)
        sed = np.zeros(n)
        alive = np.ones(n, dtype=bool)
        for s in range(steps):
            idx = np.nonzero(alive)[0]
            if idx.size == 0:
                break
            x = px[idx]
            y = py[idx]
            ix = x.astype(np.int64)
            iy = y.astype(np.int64)
            fx = x - ix
            fy = y - iy
            i00 = iy * W + ix
            h00 = hf[i00]
            h10 = hf[i00 + 1]
            h01 = hf[i00 + W]
            h11 = hf[i00 + W + 1]
            gx = (h10 - h00) * (1 - fy) + (h11 - h01) * fy
            gy = (h01 - h00) * (1 - fx) + (h11 - h10) * fx
            hcur = (h00 * (1 - fx) + h10 * fx) * (1 - fy) + (h01 * (1 - fx) + h11 * fx) * fy
            ndx = dx[idx] * inertia - gx * (1 - inertia)
            ndy = dy[idx] * inertia - gy * (1 - inertia)
            ln = np.sqrt(ndx * ndx + ndy * ndy)
            flat = ln < 1e-7
            ang = rng.uniform(0, 6.2831853, idx.size)
            ndx = np.where(flat, np.cos(ang), ndx / np.maximum(ln, 1e-7))
            ndy = np.where(flat, np.sin(ang), ndy / np.maximum(ln, 1e-7))
            nx = x + ndx
            ny = y + ndy
            inside = (nx > 2) & (nx < W - 3) & (ny > 2) & (ny < H - 3)
            nix = np.clip(nx, 0, W - 2).astype(np.int64)
            niy = np.clip(ny, 0, H - 2).astype(np.int64)
            nfx = np.clip(nx, 0, W - 2) - nix
            nfy = np.clip(ny, 0, H - 2) - niy
            j00 = niy * W + nix
            hnew = (hf[j00] * (1 - nfx) + hf[j00 + 1] * nfx) * (1 - nfy) + \
                   (hf[j00 + W] * (1 - nfx) + hf[j00 + W + 1] * nfx) * nfy
            dh = hnew - hcur
            dh = np.where(inside, dh, 0.0)
            s_sed = sed[idx]
            s_speed = speed[idx]
            s_water = water[idx]
            cap = np.maximum(-dh * s_speed * s_water * capacity_k, min_capacity)
            depositing = (s_sed > cap) | (dh > 0)
            dep = np.where(dh > 0, np.minimum(dh, s_sed), (s_sed - cap) * deposit_k)
            dep = np.where(depositing, dep, 0.0)
            ero = np.where(depositing, 0.0, np.minimum((cap - s_sed) * erode_k, -dh))
            ero = np.maximum(ero, 0.0)
            # many droplets can share a cell in the same step: share the budget so the
            # collective change never exceeds what a single droplet would do.
            crowd = np.bincount(i00, minlength=H * W)[i00].astype(np.float64)
            dep = dep / crowd
            ero = ero / crowd
            # deposition: bilinear onto the 4 corners of the old cell
            add = np.zeros(H * W)
            for off, wgt in ((0, (1 - fx) * (1 - fy)), (1, fx * (1 - fy)), (W, (1 - fx) * fy), (W + 1, fx * fy)):
                add += np.bincount(i00 + off, weights=dep * wgt, minlength=H * W)
            # erosion: spread with the brush around the old position
            cx = np.clip(ix, brush_radius, W - brush_radius - 1)
            cy = np.clip(iy, brush_radius, H - brush_radius - 1)
            base = cy * W + cx
            for (ox, oy), wgt in zip(offs, bw):
                add -= np.bincount(base + oy * W + ox, weights=ero * wgt, minlength=H * W)
            np.clip(add, -0.6, 0.6, out=add)
            hf += add
            flow += np.bincount(i00, weights=s_water, minlength=H * W)
            sed[idx] = s_sed - dep + ero
            speed[idx] = np.minimum(np.sqrt(np.maximum(s_speed * s_speed - dh * gravity, 0.0)) * 0.98 + 0.02, 10.0)
            water[idx] = s_water * (1 - evaporate)
            px[idx] = nx
            py[idx] = ny
            dx[idx] = ndx
            dy[idx] = ndy
            dead = ~inside | (water[idx] < 0.05)
            alive[idx[dead]] = False
        if verbose:
            print("  erosion pass %d/%d (%d droplets)" % (it + 1, iterations, n))
    return h, flow.reshape(H, W)


def thermal(h, cell_size=2.0, talus_deg=38.0, iterations=40, rate=0.3):
    """Simple thermal erosion: material slides to lower neighbours when the
    slope exceeds the talus angle. Softens unrealistic spikes."""
    talus = np.tan(np.radians(talus_deg)) * cell_size
    for _ in range(iterations):
        total = np.zeros_like(h)
        for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            nb = np.roll(np.roll(h, dy, axis=0), dx, axis=1)
            diff = h - nb
            move = np.where(diff > talus, (diff - talus) * rate * 0.25, 0.0)
            total -= move
            total += np.roll(np.roll(move, -dy, axis=0), -dx, axis=1)
        h += total
    return h
