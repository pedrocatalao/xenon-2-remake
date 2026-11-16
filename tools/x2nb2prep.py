"""Prepare an enhanced object for NB2 : its xBRZ_ picture on black, padded to the nearest NB2 aspect
ratio with a black margin. Writes <out>/<tag>_in.png and <tag>_box.json.
Usage : python x2nb2prep.py <enhanced> <object key> <tag> <out>"""
import json, os, sys
from PIL import Image

def named(key, prefix):

    # an object's picture in enhanced : BMP_ (the original), xBRZ_ or NB2_ before its name

    folder, name = key.rsplit('/', 1)
    return folder + '/' + prefix + '_' + name + '.png'


E, KEY, TAG, OUT = sys.argv[1:5]
RATIOS = {'1:1': 1, '4:3': 4 / 3, '3:4': 3 / 4, '16:9': 16 / 9, '9:16': 9 / 16, '3:2': 1.5, '2:3': 2 / 3,
          '5:4': 1.25, '4:5': 0.8, '21:9': 21 / 9, '4:1': 4, '1:4': 0.25}
x = Image.open(os.path.join(E, named(KEY, 'xBRZ'))).convert('RGBA')
on_black = Image.new('RGB', x.size, (0, 0, 0))
on_black.paste(x, (0, 0), x)
margin = max(16, int(0.06 * max(x.size)))
w, h = x.width + 2 * margin, x.height + 2 * margin
name, r = min(RATIOS.items(), key=lambda t: abs(w / h - t[1]) / t[1])
W, H = (w, round(w / r)) if w / h > r else (round(h * r), h)
canvas = Image.new('RGB', (W, H), (0, 0, 0))
ox, oy = (W - x.width) // 2, (H - x.height) // 2
canvas.paste(on_black, (ox, oy))
os.makedirs(OUT, exist_ok=True)
canvas.save(os.path.join(OUT, TAG + '_in.png'))
json.dump({'key': KEY, 'ratio': name, 'canvas': [W, H], 'box': [ox, oy, x.width, x.height]}, open(os.path.join(OUT, TAG + '_box.json'), 'w'))
print(TAG, name, (W, H))
