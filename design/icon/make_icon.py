"""The Film Exposures app icon: a 35mm slide mount filling the icon, a light leak in its
window, and the brand mark (orange dot + FILM EXPOSURES) across the top, as on the
website's header. Original artwork, drawn entirely in code.

    python3 design/icon/make_icon.py

writes RetroCam/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024 px, no alpha, as
the App Store wants) and the website's icons in server/public/. Needs Pillow and the
DejaVu Sans Mono Bold font (free; its licence allows use in artwork like this).
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
S, K = 1024, 4                 # drawn at 4x, then scaled down for smooth edges
N = S * K
ORANGE = (232, 118, 46)
INK = (58, 45, 31)
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'


def vgrad(size, top, bottom):
    w, h = size
    g = Image.new('RGB', size)
    d = ImageDraw.Draw(g)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g


def grain(img, amount=7):
    noise = Image.effect_noise(img.size, 40).convert('L').point(lambda v: 128 + (v - 128) * amount // 40)
    return ImageChops.overlay(img.convert('RGB'), Image.merge('RGB', (noise,) * 3))


def light_leak(w, h):
    img = Image.new('RGB', (w, h), (20, 14, 14))
    glow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(glow).ellipse((int(w * 0.45), int(-h * 0.4), int(w * 1.5), int(h * 1.1)), fill=255)
    img.paste((235, 92, 40), (0, 0), glow.filter(ImageFilter.GaussianBlur(w * 0.12)))
    core = Image.new('L', (w, h), 0)
    ImageDraw.Draw(core).ellipse((int(w * 0.72), int(-h * 0.1), int(w * 1.25), int(h * 0.6)), fill=230)
    img.paste((255, 200, 120), (0, 0), core.filter(ImageFilter.GaussianBlur(w * 0.07)))
    return img


def icon():
    big = vgrad((N, N), (240, 231, 212), (217, 203, 174))           # the card, edge to edge
    edge = Image.new('L', (N, N), 0)
    ImageDraw.Draw(edge).rectangle((0, 0, N, N), outline=255, width=int(N * 0.035))
    big.paste((180, 160, 125), (0, 0), edge.filter(ImageFilter.GaussianBlur(N * 0.03)).point(lambda v: int(v * 0.35)))
    d = ImageDraw.Draw(big)

    # The window, 3:2, dead centre, with a dark lip and softly rounded corners.
    ww = int(N * 0.70)
    wh = int(ww * 2 / 3)
    wx, wy = (N - ww) // 2, (N - wh) // 2
    wr, lip = int(N * 0.025), int(N * 0.008)
    d.rounded_rectangle((wx - lip, wy - lip, wx + ww + lip, wy + wh + lip), wr + lip, fill=(105, 86, 62))
    mask = Image.new('L', (ww, wh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, ww - 1, wh - 1), wr, fill=255)
    big.paste(light_leak(ww, wh), (wx, wy), mask)

    # The brand mark across the top, as in the website's header: the orange dot with its
    # faint halo, then FILM EXPOSURES in bold monospace, widely spaced (0.14 em), the dot
    # about as tall as the letters.
    row = int(wy * 0.52)
    size = int(N * 0.056)
    font = ImageFont.truetype(FONT, size)
    dot = int(size * 0.46)
    dx = wx + int(dot * 1.6)
    halo = Image.new('L', (N, N), 0)
    ImageDraw.Draw(halo).ellipse((dx - dot * 1.5, row - dot * 1.5, dx + dot * 1.5, row + dot * 1.5), fill=int(255 * 0.22))
    big.paste(ORANGE, (0, 0), halo)
    d.ellipse((dx - dot, row - dot, dx + dot, row + dot), fill=ORANGE)
    kern = size * 0.14
    x, top = dx + dot * 1.5 + size * 0.62, row - size * 0.58
    for ch in 'FILM EXPOSURES':
        d.text((x, top), ch, font=font, fill=INK)
        x += d.textlength(ch, font=font) + kern
    return grain(big.resize((S, S), Image.LANCZOS))


if __name__ == '__main__':
    img = icon()
    img.save(ROOT / 'RetroCam/Assets.xcassets/AppIcon.appiconset/AppIcon.png', optimize=True)
    public = ROOT / 'server/public'
    img.resize((180, 180), Image.LANCZOS).save(public / 'apple-touch-icon.png', optimize=True)
    img.resize((64, 64), Image.LANCZOS).save(public / 'favicon.png', optimize=True)
    print('wrote the app icon and the website icons')
