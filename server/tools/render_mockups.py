#!/usr/bin/env python3
"""Photos for the website's phone mockups, each through the film its roll is shot on,
printed with one of the app's borders (white, black, or a slide mount).

The sources are Unsplash photos (Unsplash licence), fetched through picsum.photos by id,
cropped to the app's 3:4 tiles and run through the same film pipeline as the film
previews (render_previews.py). No people in any of them.

    python3 server/tools/render_mockups.py      # writes server/public/mock/*.jpg
"""
import io
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
import render_previews as films   # noqa: E402

OUT = Path(__file__).resolve().parents[1] / 'public/mock'
W, H = 480, 640

# (file name, picsum id, film id, photographer, Unsplash page[, crop focus 0-1])
# The border each roll was printed with (RetroCam/PrintBorder.swift: white, black, slide).
BORDER = {'roll': 'white', 'profile-1': 'white', 'profile-2': 'black', 'profile-3': 'slide', 'profile-4': 'white',
          'feed-1': 'black', 'feed-2': 'white', 'feed-3': 'slide', 'feed-4': 'black'}
FILM_NAMES = {'golden100': 'GOLDEN 100', 'classic400': 'CLASSIC 400', 'dusk800': 'DUSK 800', 'pan50': 'PAN 50',
              'north400': 'NORTH 400', 'noir': 'NOIR 400', 'tide200': 'TIDE 200', 'silver100': 'SILVER 100'}
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'

PHOTOS = [
    # The roll: a coast weekend on GOLDEN 100.
    ('roll-1', 14, 'golden100', 'Paul Jarvis', 'https://unsplash.com/photos/IQ1kOQTJrOQ'),
    ('roll-2', 12, 'golden100', 'Paul Jarvis', 'https://unsplash.com/photos/I_9ILwtsl_k'),
    ('roll-3', 77, 'golden100', 'May Pamintuan', 'https://unsplash.com/photos/j9nfqTi5T5o'),
    ('roll-4', 124, 'golden100', 'Anton Sulsky', 'https://unsplash.com/photos/fj0tFloTPGQ', 0.2),
    ('roll-5', 162, 'golden100', 'Dillon McIntosh', 'https://unsplash.com/photos/SlGVAKyP20U'),
    ('roll-6', 10, 'golden100', 'Paul Jarvis', 'https://unsplash.com/photos/6J--NXulQCs'),
    ('roll-7', 116, 'golden100', 'Anton Sulsky', 'https://unsplash.com/photos/YcfCXxo7rpc'),
    # A profile's rolls.
    ('profile-1', 49, 'golden100', 'Margaret Barley', 'https://unsplash.com/photos/Qo51KwK1dKg'),
    ('profile-2', 57, 'classic400', 'Nicholas Swanson', 'https://unsplash.com/photos/SyBYM8R6VU4'),
    ('profile-3', 176, 'dusk800', 'Good Free Photos', 'https://unsplash.com/photos/WO4bxwzHRe8'),
    ('profile-4', 78, 'pan50', 'Paul Evans', 'https://unsplash.com/photos/CtkDsu4w-Rs'),
    # The feed.
    ('feed-1', 122, 'north400', 'Vadim Sherbakov', 'https://unsplash.com/photos/xS_RzdD5CFE'),
    ('feed-2', 195, 'noir', 'Matthew Skinner', 'https://unsplash.com/photos/t05kfHeygbE'),
    ('feed-3', 13, 'tide200', 'Paul Jarvis', 'https://unsplash.com/photos/3MtiSMdnoCo'),
    ('feed-4', 17, 'silver100', 'Paul Jarvis', 'https://unsplash.com/photos/Ven2CV8IJ5A'),
]


def fetch(pid):
    with urllib.request.urlopen(f'https://picsum.photos/id/{pid}/1200/900') as r:
        return Image.open(io.BytesIO(r.read())).convert('RGB')


def crop(img, size, focus=0.5):
    """Crop to the shape of `size` around `focus` (0 left, 1 right), then scale to it."""
    w, h = img.size
    tw, th = size
    if w / h > tw / th:
        cw = round(h * tw / th)
        x = round((w - cw) * focus)
        img = img.crop((x, 0, x + cw, h))
    else:
        ch = round(w * th / tw)
        y = (h - ch) // 2
        img = img.crop((0, y, w, y + ch))
    return img.resize(size, Image.LANCZOS)


def window(border):
    """Where the picture sits in a W x H print with this border."""
    if border in ('white', 'black'):
        m = round(W * 0.06)
        return (m, m, W - m, H - m)
    if border == 'slide':
        return (round(W * 0.12), round(H * 0.15), W - round(W * 0.12), H - round(H * 0.15))
    return (0, 0, W, H)


def print_with(border, picture, film, number):
    """The picture on its print: a white or black border, or a slide mount with the film's
    name and the frame number printed on the card."""
    if border not in ('white', 'black', 'slide'):
        return picture
    box = window(border)
    if border == 'slide':
        card = Image.new('RGB', (W, H))
        d = ImageDraw.Draw(card)
        for y in range(H):   # the mount's card, a little darker toward the bottom
            t = y / (H - 1)
            d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip((236, 227, 207), (221, 209, 182))))
        font = ImageFont.truetype(FONT, 22)
        ink = (58, 45, 31)
        d.text((box[0], round(H * 0.06)), FILM_NAMES.get(film, film.upper()), font=font, fill=ink)
        num = f'{number:02d}'
        d.text((box[2] - d.textlength(num, font=font), round(H * 0.06)), num, font=font, fill=(111, 96, 76))
        d.rounded_rectangle((box[0] - 2, box[1] - 2, box[2] + 1, box[3] + 1), 6, fill=(150, 135, 110))
    else:
        card = Image.new('RGB', (W, H), (244, 241, 234) if border == 'white' else (10, 10, 10))
    card.paste(picture, box[:2])
    return card


def main(cache=None):
    OUT.mkdir(parents=True, exist_ok=True)
    by_id = {f['id']: f for f in films.read_films()}
    for name, pid, film, _, _, *focus in PHOTOS:
        src = Image.open(Path(cache) / f'{pid}.jpg').convert('RGB') if cache else fetch(pid)
        border = BORDER.get(name, BORDER.get(name.split('-')[0]))
        box = window(border)
        arr = np.asarray(crop(src, (box[2] - box[0], box[3] - box[1]), *focus)).astype(np.float32) / 255
        out = np.clip(films.apply(by_id[film], arr), 0, 1)
        picture = Image.fromarray((out * 255 + 0.5).astype(np.uint8))
        number = int(name.split('-')[1]) if name.startswith('roll') else 12
        print_with(border, picture, film, number).save(OUT / f'{name}.jpg', quality=80, optimize=True, progressive=True)
        print('wrote', name, film, border)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else None)
