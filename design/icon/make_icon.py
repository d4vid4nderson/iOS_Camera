# Original Mono36 icon: leatherette camera front, satin top plate, coated lens, copper shutter.
import sys
import numpy as np
from PIL import Image, ImageFilter

S = 2048
rng = np.random.default_rng(36)
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)

def _box(a, k, axis):
    if k < 1: return a
    pad = [(0, 0)] * a.ndim; pad[axis] = (k + 1, k)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * k + 1, 2 * k + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * k + 1)).astype(np.float32)

def blur(a, r):
    k = max(int(round(r * 0.93)), 1)   # three box passes ~ Gaussian of sigma r
    for _ in range(3):
        a = _box(_box(a, k, 0), k, 1)
    return a

def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)

def upsample_noise(n, size):
    a = rng.random((n, n)).astype(np.float32)
    im = Image.fromarray(a, "F").resize((size, size), Image.BICUBIC)
    return np.asarray(im, np.float32)

img = np.zeros((S, S, 3), np.float32)

# --- Leatherette: pebbled bumps lit from the top left.
bump = upsample_noise(420, S) * 0.7 + upsample_noise(160, S) * 0.3
bump = blur(bump, 2.0)
gy, gx = np.gradient(bump)
light = (-gx * 0.6 - gy * 0.8) * 60
base = 0.075 + 0.05 * (1 - yy / S)            # light falls off downwards
leather = np.clip(base + light * 0.035 + (bump - 0.5) * 0.02, 0, 1)
img[:] = leather[..., None] * np.array([1.0, 0.98, 0.96])

# --- Satin top plate (brushed horizontally) with a dark seam.
plate_h = 0.205 * S
streak = upsample_noise(64, S)[:, :1]                              # per-row variation
streak = np.repeat(np.asarray(Image.fromarray(rng.random((S, 1)).astype(np.float32), "F")
                              .resize((1, S), Image.BICUBIC)), S, axis=1)
plate = 0.62 + 0.10 * (streak - 0.5) + 0.08 * np.cos((yy / plate_h) * np.pi * 0.9)
plate = plate - 0.10 * smooth(0.6, 1.0, yy / plate_h)             # rolls away at its lower edge
in_plate = yy < plate_h
img[in_plate] = (plate[in_plate][:, None] * np.array([0.93, 0.93, 0.94]))
seam = np.exp(-((yy - plate_h) / 6) ** 2)
img *= (1 - 0.85 * seam)[..., None]
img += (0.12 * np.exp(-((yy - plate_h + 10) / 3) ** 2))[..., None]   # bright lip above the seam
# Leather shadow just under the plate.
img *= (1 - 0.45 * np.exp(-np.clip(yy - plate_h, 0, None) / 40) * (yy > plate_h))[..., None]

# --- Viewfinder window on the plate (left).
def rrect_mask(x0, y0, x1, y1, rad):
    cx = np.clip(xx, x0 + rad, x1 - rad); cy = np.clip(yy, y0 + rad, y1 - rad)
    return np.hypot(xx - cx, yy - cy) <= rad
vx0, vy0, vx1, vy1 = 0.13 * S, 0.065 * S, 0.33 * S, 0.145 * S
outer = rrect_mask(vx0 - 14, vy0 - 14, vx1 + 14, vy1 + 14, 30)
inner = rrect_mask(vx0, vy0, vx1, vy1, 20)
img[outer] = img[outer] * 0.45
gl = (0.05 + 0.10 * (1 - (yy - vy0) / (vy1 - vy0)))
img[inner] = np.stack([gl * 0.85, gl * 0.95, gl * 1.15], -1)[inner]
hl = inner & (xx - vx0 < (vy1 - yy) * 1.4 + 60) & (xx - vx0 > (vy1 - yy) * 1.4 - 10)
img[hl] += 0.18

# --- Copper shutter button on the plate (right), sunk into a collar.
bx, by = 0.80 * S, 0.105 * S
rb = np.hypot(xx - bx, yy - by)
collar = rb < 98
img[collar] *= 0.35
face = rb < 82
tone = 0.95 + 0.25 * (by - yy) / 82
copper = np.array([0.92, 0.45, 0.13])
img[face] = (tone[face][:, None] * copper)
img[(rb >= 78) & (rb < 82)] *= 0.7

# --- Lens.
cx, cy = 0.5 * S, 0.585 * S
r = np.hypot(xx - cx, yy - cy)
th = np.arctan2(yy - cy, xx - cx)
lit = np.cos(th - np.deg2rad(-125))          # +1 facing the top-left light
R0 = 0.355 * S   # outer chrome mount
R1 = 0.320 * S   # knurled ring outer
R2 = 0.265 * S   # barrel slope outer
R3 = 0.205 * S   # glass

# Drop shadow of the lens on the body.
sh = blur((np.hypot(xx - cx, yy - (cy + 40)) < R0 + 10).astype(np.float32), 45)
img *= (1 - 0.75 * sh * (r > R0 - 2))[..., None]

# Chrome mount: bevelled, lit from the top left.
m = (r >= R1) & (r < R0)
t = (r - R1) / (R0 - R1)
chrome = 0.52 + 0.38 * lit * (0.4 + 0.6 * (1 - 2 * np.abs(t - 0.5))) + 0.10 * np.cos(t * np.pi * 2) + 0.12 * np.cos(th * 2 - 0.6)
chrome += 0.06 * (upsample_noise(512, S) - 0.5)
img[m] = (np.clip(chrome[m], 0, 1)[:, None] * np.array([0.95, 0.95, 0.97]))

# Knurled grip ring.
k = (r >= R2) & (r < R1)
teeth = 0.5 + 0.5 * np.cos(th * 180)
knurl = 0.05 + 0.07 * teeth * (0.55 + 0.45 * lit) + 0.04 * lit
img[k] = knurl[k][:, None]
img[(np.abs(r - R1) < 3) | (np.abs(r - R2) < 3)] *= 0.4

# Barrel slope down to the glass, with a thin bright lip.
b = (r >= R3) & (r < R2)
t = (r - R3) / (R2 - R3)
slope = 0.025 + 0.06 * t + 0.035 * lit * t
img[b] = slope[b][:, None]
lip = np.exp(-((r - (R3 + 9)) / 4) ** 2) * (0.25 + 0.35 * np.clip(lit, 0, 1))
img += lip[..., None] * 0.8

# Glass: deep, with coated reflections and inner elements.
g = r < R3
u = r / R3
glass = np.zeros((S, S, 3), np.float32)
glass[:] = np.array([0.012, 0.014, 0.022])
for rr, w, col, amt in [(0.78, 0.07, (0.38, 0.22, 0.62), 0.55),   # violet coating
                        (0.52, 0.06, (0.20, 0.55, 0.42), 0.35),   # green coating
                        (0.30, 0.05, (0.30, 0.20, 0.55), 0.30)]:
    ring = np.exp(-((u - rr) / w) ** 2) * (0.35 + 0.65 * np.clip(np.cos(th - np.deg2rad(-110)), 0, 1))
    glass += ring[..., None] * np.array(col) * amt
glass += (np.exp(-((u - 0.92) / 0.03) ** 2) * 0.10)[..., None]     # element edge
iris = np.exp(-(u / 0.16) ** 2) * 0.0
glass *= (1 - 0.6 * np.exp(-(u / 0.22) ** 2))[..., None]           # dark centre
img[g] = glass[g]

# Speculars.
def soft_ellipse(x, y, ax, ay, rot, soft):
    c, s = np.cos(rot), np.sin(rot)
    dx, dy = xx - x, yy - y
    e = ((dx * c + dy * s) / ax) ** 2 + ((-dx * s + dy * c) / ay) ** 2
    return 1 - smooth(1 - soft, 1 + soft, e)
spec = soft_ellipse(cx - 0.42 * R3, cy - 0.45 * R3, 0.30 * R3, 0.16 * R3, np.deg2rad(-40), 0.6) * 0.75
spec += soft_ellipse(cx - 0.20 * R3, cy - 0.20 * R3, 0.06 * R3, 0.05 * R3, 0, 0.4) * 0.9
amber = soft_ellipse(cx + 0.45 * R3, cy + 0.50 * R3, 0.16 * R3, 0.07 * R3, np.deg2rad(-40), 0.7) * 0.5
spec *= g; amber *= g
img += spec[..., None] * np.array([0.95, 0.96, 1.0])
img += amber[..., None] * np.array([0.92, 0.50, 0.18])

# Overall vignette, downsample, fine grain.
v = 1 - 0.25 * smooth(0.55, 1.0, np.hypot(xx - S / 2, yy - S / 2) / (S * 0.72))
img *= v[..., None]
out = Image.fromarray((np.clip(img, 0, 1) ** (1 / 1.0) * 255).astype(np.uint8), "RGB").resize((1024, 1024), Image.LANCZOS)
a = np.asarray(out).astype(np.float32) + rng.normal(0, 2.0, (1024, 1024, 1))
Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB").save(sys.argv[1], optimize=True)
