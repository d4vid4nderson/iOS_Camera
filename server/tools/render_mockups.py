#!/usr/bin/env python3
"""Photos for the website's phone mockups, each through the film its roll is shot on.

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
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import render_previews as films   # noqa: E402

OUT = Path(__file__).resolve().parents[1] / 'public/mock'
W, H = 480, 640

# (file name, picsum id, film id, photographer, Unsplash page[, crop focus 0-1])
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


def tile(img, focus=0.5):
    """Crop to 3:4 portrait at the tile size, around `focus` (0 left, 1 right)."""
    w, h = img.size
    cw = round(h * W / H)
    x = round((w - cw) * focus)
    img = img.crop((x, 0, x + cw, h))
    return img.resize((W, H), Image.LANCZOS)


def main(cache=None):
    OUT.mkdir(parents=True, exist_ok=True)
    by_id = {f['id']: f for f in films.read_films()}
    for name, pid, film, _, _, *focus in PHOTOS:
        src = Image.open(Path(cache) / f'{pid}.jpg').convert('RGB') if cache else fetch(pid)
        arr = np.asarray(tile(src, *focus)).astype(np.float32) / 255
        out = np.clip(films.apply(by_id[film], arr), 0, 1)
        Image.fromarray((out * 255 + 0.5).astype(np.uint8)).save(OUT / f'{name}.jpg', quality=80, optimize=True, progressive=True)
        print('wrote', name, film)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else None)
