"""ENHANCED : an improved picture made by hand (Nano Banana Pro or 2, or anything else) put
into the game in place of its xBRZ version.

In REA/Xenon 2/enhanced, next to an object's BMP_<name>.png and xBRZ_<name>.png, save the
improved version as NB2_<name>.png (any size, the same layout and proportions as the
xBRZ_ picture). This tool finds every NB2_ picture, scales it to the size of the xBRZ_ one and, by
enhanced/layout.json (written by x2enhanced.py), writes each frame into remake/assets_hd in
place of the xBRZ one. Where the xBRZ picture has transparency (sprites), its transparency
is kept, so a background the AI drew around the frames is cut away.

Run it after x2xbrz.py and x2enhanced.py (x2xbrz.py writes assets_hd again from the
originals). Then the project needs an import.

Usage : python x2nb2.py <remake folder> <enhanced folder>
"""

import json
import numpy as np
import os
import sys

from PIL import Image

def named(key, prefix):

    # an object's picture in enhanced : BMP_ (the original), xBRZ_ or NB2_ before its name

    folder, name = key.rsplit('/', 1)
    return folder + '/' + prefix + '_' + name + '.png'


REMAKE = sys.argv[1]
ENHANCED = sys.argv[2]
HD = os.path.join(REMAKE, 'assets_hd')
layout = json.load(open(os.path.join(ENHANCED, 'layout.json')))
done = 0


def keep_alpha(new, old):

    # the frame from the improved picture, with the xBRZ frame's transparency

    new = new.convert('RGBA')

    if old.mode == 'RGBA' and old.getextrema()[3][0] < 255:
        new.putalpha(old.getchannel('A'))
    else:
        new = new.convert(old.mode)

    return new


for folder, dirs, files in os.walk(ENHANCED):
    for file in files:
        if not (file.startswith('NB2_') and file.endswith('.png')):
            continue

        key = os.path.relpath(os.path.join(folder, file[len('NB2_'):-len('.png')]), ENHANCED).replace(os.sep, '/')

        if key not in layout:
            print('not in layout.json :', key)
            continue

        entry = layout[key]
        xbrz = Image.open(os.path.join(ENHANCED, named(key, 'xBRZ')))
        nb2 = Image.open(os.path.join(folder, file)).convert('RGBA').resize(xbrz.size, Image.LANCZOS)

        if 'single' in entry:
            target = os.path.join(HD, entry['single'])
            keep_alpha(nb2, Image.open(target)).save(target)
            done += 1

            # a tile sheet : the tiles that changed also into its masked and Amiga sheets,
            # their colours with those sheets' own transparency

            if target.endswith('_tiles.png'):
                old = np.asarray(xbrz.convert('RGB')).astype(int)
                new = np.asarray(nb2.convert('RGB'))

                for extra in ('_tiles_masked.png', '_tiles_amiga.png'):
                    path = target.replace('_tiles.png', extra)
                    sheet = np.array(Image.open(path).convert('RGBA'))

                    for ty in range(0, new.shape[0] - 64, 68):
                        for tx in range(0, new.shape[1] - 64, 68):
                            oy, ox = ty + 4, tx + 4

                            if not (old[oy:oy + 64, ox:ox + 64] != new[oy:oy + 64, ox:ox + 64]).any():
                                continue

                            part = sheet[oy:oy + 64, ox:ox + 64]
                            seen = part[..., 3] > 0
                            part[seen, :3] = new[oy:oy + 64, ox:ox + 64][seen]

                    Image.fromarray(sheet).save(path)
                    done += 1
        else:
            k = entry['factor']

            for path, x, y, w, h in entry['cells']:
                target = os.path.join(HD, path)
                frame = nb2.crop((x * k, y * k, (x + w) * k, (y + h) * k))
                keep_alpha(frame, Image.open(target)).save(target)
                done += 1

        print(key, ': in the game')

print('%d pictures of assets_hd replaced' % done)
