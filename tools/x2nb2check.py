"""After NB2 : crop the result back to the object, size of the xBRZ_ picture, check every frame against
the xBRZ one (silhouette IoU and colour), report it (every frame stays NB2 : the user reviews and asks for a redo, a frame
from xBRZ next to NB2 ones looks worse ; an optional min IoU brings the xBRZ frame back), save
<enhanced>/<folder>/NB2_<name>.png and a side by side check picture.
Usage : python x2nb2check.py <enhanced> <tag> <dir> [min IoU, default 0 : all NB2]"""
import json, os, sys
import numpy as np
from PIL import Image

def named(key, prefix):

    # an object's picture in enhanced : BMP_ (the original), xBRZ_ or NB2_ before its name

    folder, name = key.rsplit('/', 1)
    return folder + '/' + prefix + '_' + name + '.png'


E, TAG, D = sys.argv[1:4]
LIMIT = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
info = json.load(open(os.path.join(D, TAG + '_box.json')))
key = info['key']
lay = json.load(open(os.path.join(E, 'layout.json')))[key]
x = Image.open(os.path.join(E, named(key, 'xBRZ'))).convert('RGBA')
res = Image.open(os.path.join(D, TAG + '_out.png')).convert('RGB')
k = res.width / info['canvas'][0]
ox, oy, bw, bh = info['box']
nb = res.crop((round(ox * k), round(oy * k), round((ox + bw) * k), round((oy + bh) * k))).resize(x.size, Image.LANCZOS).convert('RGBA')
f = lay['factor']
out = nb.copy()
report = []
for path, cx, cy, cw, ch in lay['cells']:
    box = (cx * f, cy * f, (cx + cw) * f, (cy + ch) * f)
    a = np.asarray(x.crop(box)).astype(int)
    b = np.asarray(nb.crop(box).convert('RGB')).astype(int)
    ma = a[..., 3] > 0
    mb = b.max(2) > 30
    iou = (ma & mb).sum() / max(1, (ma | mb).sum())
    both = ma & mb
    col = np.abs(a[..., :3][both] - b[both]).mean() if both.any() else 0
    ok = iou >= LIMIT
    if not ok:
        out.paste(x.crop(box), box[:2])
    report.append((os.path.basename(path), round(iou, 2), round(col), 'NB2' if ok else 'xBRZ'))
# black outside the frames (x2nb2 keeps the xBRZ transparency anyway)
out.convert('RGB').save(os.path.join(E, named(key, 'NB2')))
# check picture : xBRZ above, result below, on dark grey
bg = (40, 40, 40)
c = Image.new('RGB', (x.width, x.height * 2 + 8), bg)
for i, im in enumerate((x, out)):
    layer = Image.new('RGB', x.size, bg)
    mask = x.getchannel('A')
    layer.paste(im.convert('RGB'), (0, 0), mask)
    c.paste(layer, (0, i * (x.height + 8)))
c.save(os.path.join(D, TAG + '_check.png'))
kept = sum(1 for r in report if r[3] == 'NB2')
print(key, ': %d of %d frames from NB2' % (kept, len(report)))
for r in report:
    print('   ', *r)
