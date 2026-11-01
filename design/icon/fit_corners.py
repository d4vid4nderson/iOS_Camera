# Bend the artwork's corners so its rim follows iOS's (rounder) icon corner.
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
S = 1024
A = Image.open(sys.argv[1] if len(sys.argv) > 1 else 'crop256.png').convert('RGB').resize((S, S), Image.LANCZOS)
A = A.filter(ImageFilter.UnsharpMask(radius=3, percent=50, threshold=2))
A = np.asarray(A).astype(np.float32)

Ra = 40 / 256 * S      # artwork's own corner radius
Rt = 0.235 * S         # target: a touch rounder than iOS's ~0.2237 so the rim is never clipped

def bilinear(img, qx, qy):
    h, w = img.shape[:2]
    qx = np.clip(qx, 0, w - 1.001); qy = np.clip(qy, 0, h - 1.001)
    x0 = qx.astype(int); y0 = qy.astype(int); fx = (qx - x0)[..., None]; fy = (qy - y0)[..., None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
            + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)

def warp_top_left(img):
    out = img.copy()
    n = int(np.ceil(Rt)) + 1
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) + 0.5
    dx, dy = xx - Rt, yy - Rt
    rho = np.hypot(dx, dy)
    inzone = (xx < Rt) & (yy < Rt)
    theta = np.arctan2(dy, dx)                       # 180..270 deg (y down)
    theta = np.where(theta > 0, theta - 2 * np.pi, theta)
    t = np.clip((theta + np.pi) / (np.pi / 2), 0, 1)  # 0 at left edge, 1 at top edge
    t = 1 - np.abs(1 - t)                             # guard
    t = np.clip((-(theta) - np.pi / 2) / (np.pi / 2), 0, 1)   # 0: pointing -y (top), 1: pointing -x (left)
    d = Rt - rho                                      # depth inside the target outline
    # Artwork outline through this corner, from the top edge (Rt,0) to the left edge (0,Rt):
    L1 = Rt - Ra; L2 = np.pi * Ra / 2; L = 2 * L1 + L2
    s = t * L
    Bx = np.where(s < L1, Rt - s, 0.0); By = np.zeros_like(s); Nx = np.zeros_like(s); Ny = np.ones_like(s)
    arc = (s >= L1) & (s < L1 + L2)
    phi = -np.pi / 2 - (s - L1) / Ra                  # -90deg (up) -> -180deg (left)
    Bx = np.where(arc, Ra + Ra * np.cos(phi), Bx); By = np.where(arc, Ra + Ra * np.sin(phi), By)
    Nx = np.where(arc, -np.cos(phi), Nx); Ny = np.where(arc, -np.sin(phi), Ny)
    seg3 = s >= L1 + L2
    Bx = np.where(seg3, 0.0, Bx); By = np.where(seg3, Ra + (s - L1 - L2), By)
    Nx = np.where(seg3, 1.0, Nx); Ny = np.where(seg3, 0.0, Ny)
    # Where the target outline point for this angle sits, and how far the artwork's outline is from it.
    Mx = Rt + Rt * np.cos(theta); My = Rt + Rt * np.sin(theta)
    Dx = Bx - Mx; Dy = By - My            # zero at both edges of the corner zone
    band = 110.0                          # the bend fades out over this depth
    f = np.clip(1 - d / band, 0, 1); f = f * f * (3 - 2 * f)
    f = np.where(d < 0, 1.0, f)
    qx = xx + Dx * f; qy = yy + Dy * f
    warped = bilinear(img, qx - 0.5, qy - 0.5)
    m = inzone[..., None]
    out[:n, :n] = np.where(m, warped, img[:n, :n])
    # Outside the target outline: dark (iOS clips it anyway).
    out[:n, :n] = np.where((inzone & (d < -1.5))[..., None], np.array([10, 10, 10], np.float32), out[:n, :n])
    return out

img = A
for flip in [(False, False), (True, False), (False, True), (True, True)]:
    v = img
    if flip[0]: v = v[:, ::-1]
    if flip[1]: v = v[::-1, :]
    v = warp_top_left(np.ascontiguousarray(v))
    if flip[1]: v = v[::-1, :]
    if flip[0]: v = v[:, ::-1]
    img = np.ascontiguousarray(v)
out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGB')
out.save('corners.png')

# Preview under two mask approximations: circular r=0.2237 and a superellipse (continuous corners).
def circ_mask(sz):
    m = Image.new('L', (S * 2, S * 2), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, 2 * S - 1, 2 * S - 1], radius=round(0.2237 * 2 * S), fill=255)
    return m.resize((sz, sz), Image.LANCZOS)
def squircle_mask(sz, n=5.0):
    y, x = np.mgrid[0:sz, 0:sz].astype(np.float32); u = np.abs((x + .5) / sz * 2 - 1); v = np.abs((y + .5) / sz * 2 - 1)
    return Image.fromarray(((u ** n + v ** n) <= 1).astype(np.uint8) * 255, 'L')
pv = Image.new('RGB', (1000, 470), (34, 34, 36)); d = ImageDraw.Draw(pv)
pv.paste(out.resize((420, 420), Image.LANCZOS), (20, 30), circ_mask(420)); d.text((20, 10), 'iOS-style mask (rounded rect)', fill=(220, 220, 220))
pv.paste(out.resize((420, 420), Image.LANCZOS), (460, 30), squircle_mask(420)); d.text((460, 10), 'superellipse mask', fill=(220, 220, 220))
pv.paste(out.resize((120, 120), Image.LANCZOS), (870, 60), circ_mask(120))
pv.paste(out.resize((60, 60), Image.LANCZOS), (900, 220), circ_mask(60))
pv.save('corners-preview.png')
# Zoom on the top-left corner, unmasked, to check the rim.
out.crop((0, 0, 320, 320)).resize((320, 320)).save('corner-zoom.png')
