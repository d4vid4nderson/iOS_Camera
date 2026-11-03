"""The Film Exposures app icon: a 35mm slide mount filling the icon, with a light leak in
its window drawn as flat diagonal bands (black, the shutter's colour, cream) and the
mount's orientation dot in the shutter's colour. One icon per shutter finish: copper is
the main icon, the others are alternate icons the app switches to when you change the
shutter. Original artwork, drawn entirely in code. No text: the app's name is under the
icon, and words are unreadable at Settings and Spotlight sizes.

    python3 design/icon/make_icon.py

writes every icon set (light, dark and tinted, 1024 px, no alpha, as the App Store wants)
into RetroCam/Assets.xcassets, and the website's icons into server/public/. Needs Pillow.
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
# at small sizes and in iOS's tinted icons): near-black film, a band of light in the
# shutter's colour, and a cream edge where the light is brightest. Unequal bands
# (30 / 40 / 30) at a steep angle, so the colour reads as one streak of light.
BLACK, CREAM = (18, 15, 14), (246, 236, 214)
MOUNT = ((234, 223, 198), (228, 215, 188))           # nearly flat card
LIP = (90, 72, 52)

# The shutter finishes (RetroCam/ShutterFinish.swift), each as a mid tone so the three
# bands still separate in tinted mode. Copper is the main icon; the rest are alternates.
FINISHES = {
    'Copper': (232, 118, 46), 'Silver': (160, 160, 157), 'Black': (98, 98, 96), 'Red': (204, 48, 36),
    'Cobalt': (60, 106, 188), 'Olive': (116, 132, 70), 'Brass': (205, 164, 76),
}


def stripes(w, h, light, dark=BLACK, edge=CREAM):
    img = Image.new('RGB', (w, h), dark)
    d = ImageDraw.Draw(img)
    slant = h * 0.404                                  # about 68 degrees from horizontal
    for x_mid, colour in ((w * 0.30, light), (w * 0.70, edge)):
        d.polygon([(x_mid + slant / 2, 0), (w * 2, 0), (w * 2, h), (x_mid - slant / 2, h)], fill=colour)
    return img


def icon(light=FINISHES['Copper'], mount=MOUNT, edge_tone=(180, 160, 125), lip_tone=LIP,
         dark=BLACK, edge=CREAM, dot_tone=None, texture=6):
    """A 35mm slide mount filling the icon (iOS's rounded corners are the mount's), the
    window centred, and the mount's orientation dot in the corner of the top margin."""
    big = vgrad((N, N), *mount)
    shade = Image.new('L', (N, N), 0)
    ImageDraw.Draw(shade).rectangle((0, 0, N, N), outline=255, width=int(N * 0.03))
    big.paste(edge_tone, (0, 0), shade.filter(ImageFilter.GaussianBlur(N * 0.025)).point(lambda v: int(v * 0.12)))
    d = ImageDraw.Draw(big)
    ww = int(N * 0.74)
    wh = int(ww * 2 / 3)
    wx, wy = (N - ww) // 2, (N - wh) // 2
    wr, lip = int(N * 0.025), int(N * 0.012)
    d.rounded_rectangle((wx - lip, wy - lip, wx + ww + lip, wy + wh + lip), wr + lip, fill=lip_tone)
    mask = Image.new('L', (ww, wh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, ww - 1, wh - 1), wr, fill=255)
    big.paste(stripes(ww, wh, light, dark, edge), (wx, wy), mask)
    r = int(N * 0.045)                                 # 9% across, its left edge on the window's lip
    cx, cy = wx - lip + r, (wy - lip) // 2
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=dot_tone or light)
    img = big.resize((S, S), Image.LANCZOS)
    return grain(img, texture) if texture else img


def dark_icon(light=FINISHES['Copper']):
    """For iOS dark mode: a near-black mount, as on the website, same window and dot."""
    return icon(light, mount=((30, 27, 25), (22, 20, 18)), edge_tone=(0, 0, 0), lip_tone=(6, 5, 4), texture=5)


def tinted_icon():
    """For iOS tinted icons: greyscale, which the system tints; dark mount, three clear tones."""
    return icon((150, 150, 150), mount=((24, 24, 24), (16, 16, 16)), edge_tone=(0, 0, 0), lip_tone=(4, 4, 4),
                dark=(18, 18, 18), edge=(245, 245, 245), dot_tone=(245, 245, 245), texture=0)


def icon_set(folder, light):
    """One app icon set: light, dark and tinted, 1024 px each."""
    folder.mkdir(parents=True, exist_ok=True)
    icon(light).save(folder / 'AppIcon.png', optimize=True)
    dark_icon(light).save(folder / 'AppIcon-Dark.png', optimize=True)
    tinted_icon().save(folder / 'AppIcon-Tinted.png', optimize=True)
    (folder / 'Contents.json').write_text(CONTENTS)


def rounded(img, size):
    """The icon at `size` px with iOS's corner radius, transparent outside (for the web)."""
    out = img.resize((size, size), Image.LANCZOS).convert('RGBA')
    mask = Image.new('L', (size * K, size * K), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * K - 1, size * K - 1), int(size * K * 0.2237), fill=255)
    out.putalpha(mask.resize((size, size), Image.LANCZOS))
    return out


def og_image(main):
    """The link preview (1200 x 630): the icon and the name on the website's near-black."""
    from PIL import ImageFont
    W, H = 1200, 630
    img = Image.new('RGB', (W, H), (15, 13, 12))
    ic = rounded(main, 300)
    img.paste(ic, (120, (H - 300) // 2), ic)
    d = ImageDraw.Draw(img)
    try:
        bold = ImageFont.truetype('DejaVuSans-Bold.ttf', 64)
        mono = ImageFont.truetype('DejaVuSansMono-Bold.ttf', 26)
    except OSError:
        bold = mono = ImageFont.load_default()
    d.text((480, 232), 'Film Exposures', font=bold, fill=(242, 237, 228))
    d.text((482, 326), 'A FILM CAMERA FOR YOUR IPHONE', font=mono, fill=ORANGE)
    return img


CONTENTS = """{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "AppIcon-Dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
      "filename" : "AppIcon-Tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""


if __name__ == '__main__':
    assets = ROOT / 'RetroCam/Assets.xcassets'
    for name, colour in FINISHES.items():
        # Copper is the main icon (AppIcon); each other finish is an alternate icon.
        icon_set(assets / ('AppIcon.appiconset' if name == 'Copper' else f'AppIcon-{name}.appiconset'), colour)
    main = icon()
    public = ROOT / 'server/public'
    main.resize((180, 180), Image.LANCZOS).save(public / 'apple-touch-icon.png', optimize=True)
    main.resize((64, 64), Image.LANCZOS).save(public / 'favicon.png', optimize=True)
    # The website's logo (header and home page) and its link preview use the same icon.
    rounded(main, 256).save(public / 'app-icon.png', optimize=True)
    og_image(main).save(public / 'og-image.png', optimize=True)
    print('wrote', len(FINISHES), 'icon sets and the website icons')
