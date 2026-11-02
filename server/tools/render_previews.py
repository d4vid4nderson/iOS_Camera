#!/usr/bin/env python3
"""Render the website's film previews: the same photo through every built-in film.

A NumPy port of RetroCam/FilmLook.swift (and ColorGrade.swift) for the website's
before/after sliders. It follows the app's pipeline step by step (exposure, edge
softness, the black & white channel mix, the tone curve, white balance, the colour
grade and STRENGTH, fog, glow, halation, toning, grain at the default GRAIN setting,
vignette) with the app's constants, so the previews read like the app. Core Image's
tone-curve spline, vignette shape and grain texture are approximated, so it is close,
not pixel-identical.

Film settings are read from RetroCam/FilmStock.swift, so a changed film re-renders
with its new values.

    python3 server/tools/render_previews.py            # writes server/public/films/*.jpg
"""
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
# Black & white films are shown on an Italian street (whites, plaster, ivy, shutters);
# colour films on a coast at golden hour (sea, sky, warm rock, pines).
SOURCES = {False: ROOT / 'server/tools/preview-bw.jpg', True: ROOT / 'server/tools/preview-color.jpg'}
OUT = ROOT / 'server/public/films'
THUMB = 420   # slide-mount thumbnails, px wide
WIDTH = 1200
RNG = np.random.default_rng(36)

L = np.array([0.2126, 0.7152, 0.0722])


# --- Film settings from FilmStock.swift ----------------------------------------------

DEFAULTS = dict(tone='neutral', toneAmount=0.0, bloom=0.0, edgeSoftness=0.0, exposure=0.0, key=0.0, fog=0.0,
                color=False, strength=1.0, saturation=1.0, warmth=0.0, tint=0.0, shadowHue=0.58, shadowAmount=0.0,
                highlightHue=0.1, highlightAmount=0.0, aqua=0.0, unify=0.0, unifyHue=0.11,
                redShadows=0.0, redHighlights=0.0, greenShadows=0.0, greenHighlights=0.0,
                blueShadows=0.0, blueHighlights=0.0, halation=0.0)


def read_films():
    src = (ROOT / 'RetroCam/FilmStock.swift').read_text()
    order = re.search(r'static let all: \[FilmStock\] = \[(.*?)\]', src, re.S).group(1)
    names = re.findall(r'\.(\w+)', order)
    films = []
    for name in names:
        body = re.search(r'static let %s = FilmStock\((.*?)\)\n' % name, src, re.S).group(1)
        film = dict(DEFAULTS)
        for key, value in re.findall(r'(\w+):\s*("[^"]*"|\.\w+|-?[\d.]+|true|false)', body):
            if value.startswith('"'):
                film[key] = value[1:-1]
            elif value.startswith('.'):
                film[key] = value[1:]
            elif value in ('true', 'false'):
                film[key] = value == 'true'
            else:
                film[key] = float(value)
        films.append(film)
    return films


# --- Colour helpers ---------------------------------------------------------------

def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def _box(a, r, axis):
    # Running mean of width 2r+1 along an axis, edges extended (like clampedToExtent).
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode='edge'), axis=axis, dtype=np.float64)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def blur(img, sigma):
    """Gaussian blur, approximated by three box blurs (Core Image's blurs are Gaussian)."""
    if sigma <= 0.3:
        return img
    r = max(1, int(round((math.sqrt(12 * sigma * sigma / 3 + 1) - 1) / 2)))
    out = img.astype(np.float32)
    for _ in range(3):
        out = _box(_box(out, r, 0), r, 1)
    return out


def screen(base, layer):
    return 1 - (1 - base) * (1 - layer)


def soft_light(base, s):
    d = np.where(base <= 0.25, ((16 * base - 12) * base + 4) * base, np.sqrt(np.clip(base, 0, None)))
    return np.where(s <= 0.5, base - (1 - 2 * s) * base * (1 - base), base + (2 * s - 1) * (d - base))


def hsv(x):
    r, g, b = x[..., 0], x[..., 1], x[..., 2]
    hi, lo = x.max(-1), x.min(-1)
    d = hi - lo
    h = np.zeros_like(hi)
    m = d > 0
    rr = (hi == r) & m
    gg = (hi == g) & m & ~rr
    bb = m & ~rr & ~gg
    h[rr] = ((g - b)[rr] / d[rr]) % 6
    h[gg] = (b - r)[gg] / d[gg] + 2
    h[bb] = (r - g)[bb] / d[bb] + 4
    return (h / 6) % 1, np.where(hi > 0, d / np.maximum(hi, 1e-9), 0), hi


def rgb(h, s, v):
    c = v * s
    hh = (h % 1) * 6
    x = c * (1 - np.abs(hh % 2 - 1))
    z = np.zeros_like(h)
    conds = [hh < 1, hh < 2, hh < 3, hh < 4, hh < 5]
    r = np.select(conds, [c, x, z, z, x], c)
    g = np.select(conds, [x, c, c, x, z], z)
    b = np.select(conds, [z, z, x, c, c], x)
    m = v - c
    return np.stack([r + m, g + m, b + m], -1)


def tint(hue):
    c = rgb(np.array([hue]), np.array([1.0]), np.array([1.0]))[0]
    return c - c @ L


# --- The pipeline (FilmLook.apply) ---------------------------------------------------

def curve_points(c, k, lo, hi):
    y = lambda v: lo + min(max(v, 0), 1) * (hi - lo)
    key = min(max(k, -1), 1)
    mid = 0.5 + 0.2 * key
    q1 = min(max(0.25 - 0.13 * c + 0.16 * key, 0.02), mid - 0.02)
    q3 = max(min(0.75 + 0.13 * c + 0.12 * key, 0.98), mid + 0.02)
    return [0, 0.25, 0.5, 0.75, 1], [y(0), y(q1), y(mid), y(q3), y(1)]


def tone_curve(x, film):
    xs, ys = curve_points(film['contrast'], film['key'], film['blackLift'], film['whitePoint'])
    xs, ys = np.array(xs), np.array(ys)
    # Monotone cubic through the five points (Core Image uses a spline too).
    dx = np.diff(xs)
    slope = np.diff(ys) / dx
    m = np.zeros(5)
    m[0], m[-1] = slope[0], slope[-1]
    for i in range(1, 4):
        m[i] = 0 if slope[i - 1] * slope[i] <= 0 else 2 / (1 / slope[i - 1] + 1 / slope[i])
    i = np.clip(np.searchsorted(xs, x, side='right') - 1, 0, 3)
    t = (x - xs[i]) / dx[i]
    h00, h10, h01, h11 = 2 * t**3 - 3 * t**2 + 1, t**3 - 2 * t**2 + t, -2 * t**3 + 3 * t**2, t**3 - t**2
    return np.clip(h00 * ys[i] + h10 * dx[i] * m[i] + h01 * ys[i + 1] + h11 * dx[i] * m[i + 1], 0, 1)


def grade(x, f):
    def bend(v, lo, hi):
        return np.clip(v + 0.08 * (lo * 6.75 * v * (1 - v) ** 2 + hi * 6.75 * v * v * (1 - v)), 0, 1)
    x = np.stack([bend(x[..., 0], f['redShadows'], f['redHighlights']),
                  bend(x[..., 1], f['greenShadows'], f['greenHighlights']),
                  bend(x[..., 2], f['blueShadows'], f['blueHighlights'])], -1)
    if f['aqua']:
        h, s, v = hsv(x)
        dist = np.abs(((h - 0.6) + 0.5) % 1 - 0.5)
        w = np.maximum(0, 1 - dist / 0.14)
        x = np.where((s > 0.02)[..., None], rgb((h - f['aqua'] * 0.045 * w * w) % 1, s, v), x)
    if f['unify']:
        y0 = x @ L
        h, s, v = hsv(x)
        d = ((h - f['unifyHue']) + 0.5) % 1 - 0.5
        near = np.clip(1 - np.abs(d) / 0.25, 0, 1)
        far = np.clip((np.abs(d) - 0.08) / 0.3, 0, 1)
        out = rgb((h - d * f['unify'] * 0.6 * near) % 1, s * (1 - f['unify'] * 0.85 * far), v)
        out = np.clip(out + (y0 - out @ L)[..., None], 0, 1)
        x = np.where((s > 0.01)[..., None], out, x)
    y = x @ L
    x = np.clip(y[..., None] + f['saturation'] * (x - y[..., None]), 0, 1)
    y = x @ L
    ws = f['shadowAmount'] * np.maximum(0, 1 - y / 0.5) ** 2
    wh = f['highlightAmount'] * np.maximum(0, (y - 0.5) / 0.5) ** 2
    return np.clip(x + 0.3 * (ws[..., None] * tint(f['shadowHue']) + wh[..., None] * tint(f['highlightHue'])), 0, 1)


STOPS = {  # Toning.stops: ink, mid, paper
    'neutral': ((0, 0, 0), (0.5, 0.5, 0.5), (1, 1, 1)),
    'warm': ((0.03, 0.015, 0), (0.57, 0.47, 0.35), (1, 0.95, 0.85)),
    'cool': ((0, 0.005, 0.025), (0.46, 0.5, 0.56), (0.97, 1, 1)),
    'selenium': ((0.04, 0, 0.035), (0.51, 0.46, 0.49), (1, 1, 0.99)),
    'split': ((0, 0.01, 0.045), (0.53, 0.48, 0.46), (1, 0.9, 0.8)),
    'gold': ((0, 0.01, 0.04), (0.46, 0.49, 0.54), (1, 0.99, 0.97)),
    'platinum': ((0.05, 0.04, 0.03), (0.55, 0.5, 0.44), (0.97, 0.94, 0.88)),
    'cyanotype': ((0.02, 0.1, 0.28), (0.28, 0.45, 0.62), (0.96, 0.97, 0.95)),
    'tintype': ((0.04, 0.03, 0.02), (0.48, 0.44, 0.38), (0.88, 0.85, 0.76)),
}


def tone(x, toning, amount):
    ink, mid, paper = STOPS[toning]
    a = min(max(amount, 0), 1)
    out = []
    for c in range(3):
        k, m, p = a * ink[c], 0.5 + a * (mid[c] - 0.5), 1 + a * (paper[c] - 1)
        c1, c2 = -3 * k + 4 * m - p, 2 * k - 4 * m + 2 * p
        v = x[..., c]
        out.append(k + c1 * v + c2 * v * v)
    return np.clip(np.stack(out, -1), 0, 1)


def bloom(x, amount, long_side, tint_rgb=None, threshold=0.7, spread=0.015):
    bright = np.clip((x - threshold) / (1 - threshold), 0, 1)
    glow = blur(bright, long_side * spread)
    if tint_rgb is None:
        layer = glow * amount
    else:
        layer = (glow @ L)[..., None] * amount * np.array(tint_rgb)
    return np.clip(screen(x, np.clip(layer, 0, 1)), 0, 1)


def fog(x, amount, long_side):
    cells = long_side / 7
    noise = RNG.random((12, 12, 1))
    patch = blur(noise, 0.9)
    h, w = x.shape[:2]
    big = np.asarray(Image.fromarray(np.float32(patch[..., 0])).resize((int(12 * cells), int(12 * cells)), Image.BICUBIC))
    big = big[int(cells):int(cells) + h, int(cells):int(cells) + w][..., None]
    big = blur(big, cells * 0.25)
    lift = 0.22 * min(max(amount, 0), 1)
    layer = np.clip(lift * 4 * big - lift * 1.5, 0, 1)
    return screen(x, layer)


def grain(x, amount, size, long_side):
    if amount <= 0:
        return x
    px = max(1.0, size * long_side / 1600)
    h, w = x.shape[:2]
    grainy = x
    for scale, strength in ((px, 2.6 * amount), (px * 2.2, 1.4 * amount)):
        sh, sw = max(2, int(h / scale)), max(2, int(w / scale))
        n = RNG.normal(0.5, 0.167, (sh, sw)).astype(np.float32)
        n = np.asarray(Image.fromarray(n).resize((w, h), Image.BILINEAR))
        layer = np.clip(0.5 + (n - 0.5) * strength, 0, 1)[..., None]
        grainy = soft_light(grainy, layer)
    lum = x @ L
    weight = np.clip(0.3 + 2.8 * lum - 2.8 * lum * lum, 0, 1)[..., None]
    return np.clip(x + weight * (grainy - x), 0, 1)


def vignette(x, amount):
    h, w = x.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.hypot(xx - w / 2, yy - h / 2) / (max(w, h) * 0.62)
    dark = min(amount, 1.2) * 0.8 * np.clip((d - 0.4) / 0.6, 0, 1) ** 2
    return x * (1 - np.clip(dark, 0, 1))[..., None]


def soften_edges(lin, amount, long_side):
    h, w = lin.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.hypot(xx - w / 2, yy - h / 2)
    mask = np.clip((d - long_side * 0.30) / (long_side * 0.45), 0, 1)[..., None]
    soft = blur(lin, amount * long_side * 0.008 / 2)
    return lin + mask * (soft - lin)


def apply(film, srgb_img):
    long_side = max(srgb_img.shape[:2])
    lin = srgb_to_linear(srgb_img)
    if film['exposure']:
        lin = lin * 2 ** film['exposure']
    if film['edgeSoftness'] > 0:
        lin = soften_edges(lin, film['edgeSoftness'], long_side)
    if film['color']:
        img = linear_to_srgb(np.clip(lin, 0, 1))
    else:
        mono = np.clip(lin @ np.array([film['red'], film['green'], film['blue']]), 0, 1)
        img = linear_to_srgb(np.repeat(mono[..., None], 3, -1))
    natural = img.copy()
    if film['color'] and (film['warmth'] or film['tint']):
        w, t = film['warmth'], film['tint']
        img = np.clip(img * np.array([1 + 0.07 * w + 0.03 * t, 1 + 0.01 * w - 0.05 * t, 1 - 0.08 * w + 0.03 * t]), 0, 1)
    img = tone_curve(img, film)
    if film['color']:
        img = grade(img, film)
        s = min(max(film['strength'], 0), 1)
        img = natural + s * (img - natural)
    if film['fog'] > 0:
        img = fog(img, film['fog'], long_side)
    if film['bloom'] > 0:
        img = bloom(img, film['bloom'], long_side)
    if film['color'] and film['halation'] > 0:
        img = bloom(img, film['halation'], long_side, (1, 0.36, 0.16), 0.78, 0.008)
    if not film['color'] and film['toneAmount'] > 0 and film['tone'] != 'neutral':
        img = tone(img, film['tone'], film['toneAmount'])
    # The GRAIN dial's default (100%) gives this share of a film's base grain.
    img = grain(img, film['grain'] * 0.25 * (1 / 0.75) ** 1.413, film['grainSize'], long_side)
    if film['vignette'] > 0:
        img = vignette(img, film['vignette'])
    return np.clip(img, 0, 1)


def main():
    (OUT / 'thumbs').mkdir(parents=True, exist_ok=True)
    bases = {}
    for color, path in SOURCES.items():
        src = Image.open(path).convert('RGB')
        src = src.resize((WIDTH, round(src.height * WIDTH / src.width)), Image.LANCZOS)
        src = src.crop((0, 0, WIDTH, WIDTH * 2 // 3))   # 3:2, like the viewer
        src.save(OUT / f"before-{'color' if color else 'bw'}.jpg", quality=82, optimize=True, progressive=True)
        bases[color] = np.asarray(src).astype(np.float32) / 255
    films = read_films()
    index = []
    ramp = np.repeat(np.linspace(0, 1, 7, dtype=np.float32)[None, :, None], 3, -1)
    for film in films:
        out = apply(film, bases[bool(film['color'])])
        img = Image.fromarray((out * 255 + 0.5).astype(np.uint8))
        img.save(OUT / f"{film['id']}.jpg", quality=82, optimize=True, progressive=True)
        # A small copy for the film's slide mount on the home page.
        img.resize((THUMB, THUMB * 2 // 3), Image.LANCZOS).save(OUT / 'thumbs' / f"{film['id']}.jpg", quality=80, optimize=True, progressive=True)
        # The film's tone strip, like the app's cards: grey steps through the film, without
        # grain, glow or vignette.
        flat = dict(film, grain=0, vignette=0, fog=0, bloom=0, halation=0, edgeSoftness=0)
        strip = apply(flat, ramp)[0]
        tones = ['#%02x%02x%02x' % tuple(int(v * 255 + 0.5) for v in px) for px in strip]
        index.append({'id': film['id'], 'name': film['name'], 'blurb': film.get('blurb', ''),
                      'iso': int(film['iso']), 'color': bool(film['color']), 'tones': tones})
        print('rendered', film['id'], file=sys.stderr)
    (ROOT / 'server/src/film-previews.js').write_text(
        '// Generated by server/tools/render_previews.py from RetroCam/FilmStock.swift. Do not edit.\n'
        '// Each built-in film, with its tone strip; /films/<id>.jpg is the preview photo through it.\n'
        'export const FILM_PREVIEWS = ' + json.dumps(index, indent=1) + ';\n')


if __name__ == '__main__':
    main()
