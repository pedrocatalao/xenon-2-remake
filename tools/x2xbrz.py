"""ENHANCED graphics : every picture of the remake enlarged with xBRZ (pixel-art scaler, only
the picture's own colours, nothing invented).

Reads remake/assets (sprites, tiles, Amiga backgrounds and title pictures, fonts, HUD, shop
panels ; not maps, which hold tile numbers) and writes the same tree, each picture FACTOR
times larger. xBRZ looks at the neighbours of every pixel, so each picture is padded first
and cropped after :

- tiles : every 16x16 tile on its own (the sheet has a 1 pixel border between tiles that
  must not bleed in), edges repeated, placed at its scaled origin (1 + n * 17) * FACTOR.
  Also S?_tiles_masked.png (colour 0 transparent) and S?_tiles_amiga.png (the Amiga masks),
  for the masked tiles and the flashes,
- Amiga level backgrounds : they wrap from bottom to top, so padded with the other edge,
- pictures with transparency (sprites) : transparent border,
- other pictures : edges repeated.

tools/xbrz is the xbrz.py package (GPL 3, the xBRZ library by Zenju) built for this Python
with Visual Studio 2022, with one function added (xbrz_scale_cfg in src/xbrz.h, called by
scale_pillow_cfg) to pass the scaler's settings. The settings here are the "smooth" set
chosen on 2026-11-16 (library defaults : 1, 30, 4, 3.6, 2.2) : rounder rock and pillar
edges, 7 % of the pixels of the level tiles differ from the defaults.

Usage : python x2xbrz.py <remake folder> <output folder, remake/assets_hd> [factor, default 4]
Then x2enhanced.py lays the pictures out by object in REA/Xenon 2/enhanced.
"""

import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'xbrz'))
import xbrz

REMAKE = sys.argv[1]
OUT = sys.argv[2]
FACTOR = int(sys.argv[3]) if len(sys.argv) > 3 else 4
PAD = 3
SKIP = ('maps',)

SETTINGS = {
    'luminance_weight': 0.5,
    'equal_color_tolerance': 50,
    'center_direction_bias': 4.0,
    'dominant_direction_threshold': 2.5,
    'steep_direction_threshold': 1.5,
}


def scale(im):
    return xbrz.scale_pillow_cfg(im.convert('RGBA'), FACTOR, **SETTINGS)


def padded(im, mode):

    # pad by PAD pixels : 'edge' repeats the edge, 'clear' is transparent, 'wrap' takes the
    # opposite rows top and bottom (edges left and right)

    w, h = im.size
    out = Image.new('RGBA', (w + 2 * PAD, h + 2 * PAD), (0, 0, 0, 0))
    out.paste(im, (PAD, PAD))

    if mode == 'clear':
        return out

    if mode == 'wrap':
        out.paste(im.crop((0, h - PAD, w, h)), (PAD, 0))
        out.paste(im.crop((0, 0, w, PAD)), (PAD, h + PAD))
    else:
        for i in range(PAD):
            out.paste(im.crop((0, 0, w, 1)), (PAD, i))
            out.paste(im.crop((0, h - 1, w, h)), (PAD, h + PAD + i))

    for i in range(PAD):
        out.paste(out.crop((PAD, 0, PAD + 1, h + 2 * PAD)), (i, 0))
        out.paste(out.crop((PAD + w - 1, 0, PAD + w, h + 2 * PAD)), (PAD + w + i, 0))

    return out


def enlarge(im, mode):
    big = scale(padded(im, mode))
    p = PAD * FACTOR
    return big.crop((p, p, p + im.width * FACTOR, p + im.height * FACTOR))


def tiles(im):

    # 20 tiles a row, 17 pixel pitch, 1 pixel border (main.gd _tile_origin)

    # the border around each tile is filled with the tile's own repeated edge (half the
    # border from each side), so filtered drawing never picks up the sheet's border colour

    out = im.convert('RGBA').resize((im.width * FACTOR, im.height * FACTOR), Image.NEAREST)
    half = FACTOR // 2
    p = PAD * FACTOR

    for ty in range((im.height - 1) // 17):
        for tx in range((im.width - 1) // 17):
            x, y = 1 + tx * 17, 1 + ty * 17
            big = scale(padded(im.crop((x, y, x + 16, y + 16)).convert('RGBA'), 'edge'))
            side = 16 * FACTOR + 2 * half
            out.paste(big.crop((p - half, p - half, p - half + side, p - half + side)), (x * FACTOR - half, y * FACTOR - half))

    return out


def masked_tiles(im, masks=None):

    # the masked tiles, on a transparent sheet of the same layout : colour 0 transparent
    # (main.gd _tile_masked, also the base of the flashes), or with masks (tile -> 16 rows of
    # 16 bits, the Amiga masks of data/amiga_S?.json, main.gd _amiga_masked) only those tiles.
    # The edges are repeated so that tiles next to each other still meet.

    out = Image.new('RGBA', (im.width * FACTOR, im.height * FACTOR), (0, 0, 0, 0))
    count = ((im.height - 1) // 17) * 20

    for tile in range(count):
        if masks is not None and tile not in masks:
            continue

        x, y = 1 + (tile % 20) * 17, 1 + (tile // 20) * 17
        cell = im.crop((x, y, x + 16, y + 16)).convert('RGBA')
        px = cell.load()

        for v in range(16):
            for u in range(16):
                r, g, b, a = px[u, v]
                hide = (masks[tile][v] >> (15 - u)) & 1 == 0 if masks is not None else (r, g, b) == (0, 0, 0)

                if hide:
                    px[u, v] = (0, 0, 0, 0)

        out.paste(enlarge(cell, 'edge'), (x * FACTOR, y * FACTOR))

    return out


count = 0
src_root = os.path.join(REMAKE, 'assets')

for folder, dirs, files in os.walk(src_root):
    rel = os.path.relpath(folder, src_root)

    if rel.split(os.sep)[0] in SKIP:
        continue

    for name in sorted(files):
        if not name.endswith('.png'):
            continue

        # the overview sheets of the extractors (sprites/<set>_sheet.png, gr/<name>.png next to
        # a gr/<name> folder of single pictures) are not drawn by the game

        if name.endswith('_sheet.png') or os.path.isdir(os.path.join(folder, name[:-4])):
            continue

        im = Image.open(os.path.join(folder, name))
        alpha = im.mode in ('RGBA', 'LA', 'P') and 'A' in im.convert('RGBA').getbands() and im.convert('RGBA').getextrema()[3][0] < 255

        if rel.startswith('tiles'):
            out = tiles(im.convert('RGB'))
            dst = os.path.join(OUT, rel)
            os.makedirs(dst, exist_ok=True)
            level = name.split('_')[0]
            masked_tiles(im.convert('RGB')).save(os.path.join(dst, level + '_tiles_masked.png'))
            data = os.path.join(REMAKE, 'data', 'amiga_%s.json' % level)

            if os.path.exists(data):
                kinds = json.load(open(data))['tiles']
                masks = {int(k): [int(r) for r in v] for k, v in kinds.items() if isinstance(v, list)}
                masked_tiles(im.convert('RGB'), masks).save(os.path.join(dst, level + '_tiles_amiga.png'))
                count += 1

            count += 1
        elif rel.startswith('amiga') and name.endswith('_background.png'):
            out = enlarge(im.convert('RGBA'), 'wrap')
        else:
            out = enlarge(im.convert('RGBA'), 'clear' if alpha else 'edge')

        if not alpha:
            out = out.convert('RGB')

        dst = os.path.join(OUT, rel)
        os.makedirs(dst, exist_ok=True)
        out.save(os.path.join(dst, name))
        count += 1

print('%d pictures x%d' % (count, FACTOR))
