"""The Film Exposures app icon: a 35mm slide mount filling the icon, a light leak in its
window drawn as flat diagonal bands in the brand's colours (black, copper, cream), and the
mount's orange
orientation dot. Original artwork, drawn entirely in code. No text: the app's name is
under the icon, and words are unreadable at Settings and Spotlight sizes.

    python3 design/icon/make_icon.py

writes the app icon (light, dark and tinted, 1024 px, no alpha, as the App Store wants)
and the website's icons in server/public/. Needs Pillow.
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
S, K = 1024, 4                 # drawn at 4x, then scaled down for smooth edges
N = S * K
ORANGE = (232, 118, 46)


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


# The brand's three colours, as flat hard-edged shapes (no gradients: they turn to mush
# at small sizes and in iOS's tinted icons): near-black film, a copper band of light, and
# a cream edge where the light is brightest.
BLACK, COPPER, CREAM = (18, 15, 14), (232, 118, 46), (246, 236, 214)
BANDS = [BLACK, COPPER, CREAM]


def stripes(w, h, bands=BANDS):
    """Light catching the film: dark, then a copper band, then a cream edge, on the diagonal."""
    dark, light, edge = bands
    img = Image.new('RGB', (w, h), dark)
    d = ImageDraw.Draw(img)
    slant = int(h * 0.55)
    d.polygon([(int(w * 0.45), 0), (w * 2, 0), (w * 2, h), (int(w * 0.45) - slant, h)], fill=light)
    d.polygon([(int(w * 0.80), 0), (w * 2, 0), (w * 2, h), (int(w * 0.80) - slant, h)], fill=edge)
    return img


def icon(mount=((240, 231, 212), (222, 209, 182)), edge_tone=(180, 160, 125), lip_tone=(105, 86, 62),
         bands=BANDS, dot_tone=ORANGE, texture=7):
    """A 35mm slide mount filling the icon (iOS's rounded corners are the mount's), the
    window centred, and the mount's orientation dot in the corner of the top margin."""
    big = vgrad((N, N), *mount)
    edge = Image.new('L', (N, N), 0)
    ImageDraw.Draw(edge).rectangle((0, 0, N, N), outline=255, width=int(N * 0.03))
    big.paste(edge_tone, (0, 0), edge.filter(ImageFilter.GaussianBlur(N * 0.025)).point(lambda v: int(v * 0.15)))
    d = ImageDraw.Draw(big)
    ww = int(N * 0.74)
    wh = int(ww * 2 / 3)
    wx, wy = (N - ww) // 2, (N - wh) // 2
    wr, lip = int(N * 0.025), int(N * 0.009)
    d.rounded_rectangle((wx - lip, wy - lip, wx + ww + lip, wy + wh + lip), wr + lip, fill=lip_tone)
    mask = Image.new('L', (ww, wh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, ww - 1, wh - 1), wr, fill=255)
    big.paste(stripes(ww, wh, bands), (wx, wy), mask)
    r = int(N * 0.045)
    cx, cy = wx + r, wy // 2
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=dot_tone)
    img = big.resize((S, S), Image.LANCZOS)
    return grain(img, texture) if texture else img


def dark_icon():
    """For iOS dark mode: a near-black mount, as on the website, same window and dot."""
    return icon(mount=((32, 28, 26), (16, 14, 13)), edge_tone=(0, 0, 0), lip_tone=(8, 7, 6), texture=5)


def tinted_icon():
    """For iOS tinted icons: greyscale, which the system tints; dark mount, light bands."""
    return icon(mount=((24, 24, 24), (12, 12, 12)), edge_tone=(0, 0, 0), lip_tone=(4, 4, 4),
                bands=[(18, 18, 18), (150, 150, 150), (245, 245, 245)], dot_tone=(245, 245, 245), texture=0)


if __name__ == '__main__':
    img = icon()
    icons = ROOT / 'RetroCam/Assets.xcassets/AppIcon.appiconset'
    img.save(icons / 'AppIcon.png', optimize=True)
    dark_icon().save(icons / 'AppIcon-Dark.png', optimize=True)
    tinted_icon().save(icons / 'AppIcon-Tinted.png', optimize=True)
    public = ROOT / 'server/public'
    img.resize((180, 180), Image.LANCZOS).save(public / 'apple-touch-icon.png', optimize=True)
    img.resize((64, 64), Image.LANCZOS).save(public / 'favicon.png', optimize=True)
    print('wrote the app icon and the website icons')
