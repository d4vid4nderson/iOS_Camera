#!/usr/bin/env python3
"""Pictures for the website's "Make it yours" cards: a frame on a toned film, the same
photo in each toning, a frame for the lens picker, a frame with the date back burned in,
and the seven app icons (one per shutter finish). Photos as in render_mockups.py.

    python3 server/tools/render_make_yours.py [photo cache dir]
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
import render_mockups as mock     # noqa: E402
import render_previews as films   # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'server/public/mock'
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'


def load(pid, cache):
    return Image.open(Path(cache) / f'{pid}.jpg').convert('RGB') if cache else mock.fetch(pid)


def through(film, img):
    arr = np.asarray(img).astype(np.float32) / 255
    return Image.fromarray((np.clip(films.apply(film, arr), 0, 1) * 255 + 0.5).astype(np.uint8))


def save(img, name):
    img.save(OUT / f'{name}.jpg', quality=82, optimize=True, progressive=True)
    print('wrote', name)


def main(cache=None):
    OUT.mkdir(parents=True, exist_ok=True)
    by_id = {f['id']: f for f in films.read_films()}
    classic = by_id['classic400']

    # The film: a street on CLASSIC 400, toned selenium; and a door in each toning.
    street = mock.crop(load(57, cache), (900, 600))
    save(through({**classic, 'tone': 'selenium', 'toneAmount': 1.0}, street), 'make-film')
    door = mock.crop(load(78, cache), (220, 220))
    for tone in ['neutral', 'warm', 'selenium', 'gold', 'cyanotype']:
        save(through({**classic, 'tone': tone, 'toneAmount': 1.0 if tone != 'neutral' else 0.0}, door), f'tone-{tone}')

    # Lenses: the pier on GOLDEN 100.
    save(through(by_id['golden100'], mock.crop(load(77, cache), (900, 600))), 'make-lens')

    # The camera: the boat on GOLDEN 100 with the date back's glowing orange digits.
    boat = through(by_id['golden100'], mock.crop(load(124, cache), (900, 600), 0.2)).convert('RGBA')
    glow = Image.new('RGBA', boat.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    font = ImageFont.truetype(FONT, 40)
    text = "11 03 '26"
    w = d.textlength(text, font=font)
    pos = (900 - 56 - w, 600 - 56 - 40)
    d.text(pos, text, font=font, fill=(255, 120, 40, 255))
    halo = glow.filter(ImageFilter.GaussianBlur(6))
    core = glow.filter(ImageFilter.GaussianBlur(0.8))
    out = Image.alpha_composite(Image.alpha_composite(boat, halo), core)
    save(out.convert('RGB'), 'make-date')

    # The app icons, small, for the shutter-finish row.
    assets = ROOT / 'RetroCam/Assets.xcassets'
    for name in ['', '-Silver', '-Black', '-Red', '-Cobalt', '-Olive', '-Brass']:
        icon = Image.open(assets / f'AppIcon{name}.appiconset/AppIcon.png').convert('RGB').resize((96, 96), Image.LANCZOS)
        icon.save(OUT / f'icon{name.lower() or "-copper"}.png', optimize=True)
        print('wrote icon', name or 'copper')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else None)
