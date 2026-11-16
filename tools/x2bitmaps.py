import os
import struct
import sys
from PIL import Image

print('\nXenon 2 bitmap extractor')
print('V.K. Papanikolaou, Assoc. Prof. AUTh')
print('Last updated : 15/11/2026\n')

if len(sys.argv) != 3:
    print('Usage : python x2bitmaps.py <game folder> <output folder>')
    sys.exit(1)

GAME = sys.argv[1]
OUT = sys.argv[2]
LEVELS = ['S1', 'S2',
          'S3', 'S4',
          'S5']
ARCHIVES = ['X2SPR.DAT', 'X2WEAPS.DAT',
            'SHOP.DAT']

# LHA lh1 constants (LZSS 4096/60 with adaptive Huffman)

N = 4096
F = 60
THRESHOLD = 2
N_CHAR = 256 - THRESHOLD + F
T = N_CHAR * 2 - 1
R = T - 1
D_CODE = []
D_LEN = []

for length, count, each in ((3, 1, 32), (4, 3, 16), (5, 8, 8), (6, 12, 4), (7, 24, 2), (8, 16, 1)):

    for _ in range(count):
        code = (D_CODE[-1] + 1) if D_CODE else 0
        D_CODE += [code] * each
        D_LEN += [length] * each


def unpack_lh1(raw):

    # the DAT files are single LHA level 0 members with the method id blanked

    outlen = struct.unpack('<I', raw[11:15])[0]
    state = [raw[0] + 2, 0, 0]
    freq = [0] * (T + 1)
    prnt = [0] * (T + N_CHAR)
    son = [0] * T

    def getbit():

        if state[2] == 0:
            state[1] = raw[state[0]] if state[0] < len(raw) else 0
            state[0] += 1
            state[2] = 8

        state[2] -= 1

        return (state[1] >> state[2]) & 1

    def getbits(n):

        v = 0

        for _ in range(n):
            v = (v << 1) | getbit()

        return v

    def reconst():

        j = 0

        for i in range(T):

            if son[i] >= T:
                freq[j] = (freq[i] + 1) // 2
                son[j] = son[i]
                j += 1

        i = 0

        for j in range(N_CHAR, T):
            f = freq[i] + freq[i + 1]
            freq[j] = f
            k = j - 1

            while f < freq[k]:
                k -= 1

            k += 1
            freq[k + 1:j + 1] = freq[k:j]
            freq[k] = f
            son[k + 1:j + 1] = son[k:j]
            son[k] = i
            i += 2

        for i in range(T):
            k = son[i]
            prnt[k] = i

            if k < T:
                prnt[k + 1] = i

    def update(c):

        if freq[R] == 0x8000:
            reconst()

        c = prnt[c + T]

        while True:
            freq[c] += 1
            k = freq[c]
            l = c + 1

            if k > freq[l]:

                while k > freq[l + 1]:
                    l += 1

                freq[c] = freq[l]
                freq[l] = k
                i = son[c]
                prnt[i] = l

                if i < T:
                    prnt[i + 1] = l

                j = son[l]
                son[l] = i
                prnt[j] = c

                if j < T:
                    prnt[j + 1] = c

                son[c] = j
                c = l

            c = prnt[c]

            if c == 0:
                break

    for i in range(N_CHAR):
        freq[i] = 1
        son[i] = i + T
        prnt[i + T] = i

    i = 0

    for j in range(N_CHAR, R + 1):
        freq[j] = freq[i] + freq[i + 1]
        son[j] = i
        prnt[i] = prnt[i + 1] = j
        i += 2

    freq[T] = 0xffff
    win = bytearray(b' ' * N)
    r = N - F
    out = bytearray()

    while len(out) < outlen:
        c = son[R]

        while c < T:
            c = son[c + getbit()]

        c -= T
        update(c)

        if c < 256:
            out.append(c)
            win[r] = c
            r = (r + 1) & (N - 1)
        else:
            i = getbits(8)
            p = (D_CODE[i] << 6) | (((i << (D_LEN[i] - 2)) | getbits(D_LEN[i] - 2)) & 0x3f)
            src = (r - p - 1) & (N - 1)

            for k in range(c - 255 + THRESHOLD):
                b = win[(src + k) & (N - 1)]
                out.append(b)
                win[r] = b
                r = (r + 1) & (N - 1)

    return bytes(out[:outlen])


def read_palette(data):

    # 16 big endian words, 3 bits per channel (0RGB), upper bits are junk

    pal = []

    for i in range(16):
        w = (data[i * 2] << 8) | data[i * 2 + 1]
        rgb = [((w >> s) & 7) for s in (8, 4, 0)]
        pal.append(tuple(round(v * 9 * 255 / 63) for v in rgb))

    return pal


def read_sprites(data, pal):

    # frame : 8 signed words (the last two are width and height - 1), then
    # mask plane and 4 colour planes, each height x ceil(width / 8) bytes, word aligned

    frames = []
    p = 32

    while p + 16 <= len(data):
        h = struct.unpack('<8h', data[p:p + 16])
        w = h[6]
        rows = h[7] + 1
        rb = (w + 7) // 8
        p += 16
        img = Image.new('RGBA', (w, rows), (0, 0, 0, 0))
        px = img.load()

        for y in range(rows):

            for x in range(w):
                bit = 0x80 >> (x & 7)
                o = p + y * rb + (x >> 3)

                if data[o] & bit:
                    c = 0

                    for pl in range(4):

                        if data[o + (pl + 1) * rows * rb] & bit:
                            c |= 1 << pl

                    px[x, y] = pal[c] + (255,)

        p += rows * rb * 5
        p += p & 1
        frames.append((h, img))

    return frames


def save_sprites(name, data):

    pal = read_palette(data)
    frames = read_sprites(data, pal)
    folder = os.path.join(OUT, 'sprites', name)
    os.makedirs(folder, exist_ok=True)
    cw = max(f[1].width for f in frames) + 2
    ch = max(f[1].height for f in frames) + 2
    cols = 16
    sheet = Image.new('RGBA', (cols * cw, ((len(frames) + cols - 1) // cols) * ch), (0, 0, 0, 0))
    lines = ['frame,f0,f1,f2,f3,f4,f5,width,height']

    for i, (h, img) in enumerate(frames):
        img.save(os.path.join(folder, f'{i:03d}.png'))
        sheet.paste(img, ((i % cols) * cw + 1, (i // cols) * ch + 1))
        lines.append(','.join(str(v) for v in (i,) + h[:6] + (img.width, img.height)))

    sheet.save(os.path.join(OUT, 'sprites', name + '_sheet.png'))
    open(os.path.join(folder, 'frames.csv'), 'w').write('\n'.join(lines) + '\n')
    print(f'{name} : {len(frames)} sprites')


def read_tiles(data, pal):

    # 16x16 tiles, 128 bytes each, per row one big endian word for each of the 4 planes

    tiles = []

    for t in range(len(data) // 128):
        img = Image.new('RGB', (16, 16))
        px = img.load()

        for y in range(16):
            o = t * 128 + y * 8
            words = [(data[o + pl * 2] << 8) | data[o + pl * 2 + 1] for pl in range(4)]

            for x in range(16):
                c = sum(((words[pl] >> (15 - x)) & 1) << pl for pl in range(4))
                px[x, y] = pal[c]

        tiles.append(img)

    return tiles


def read_map(raw):

    # run length coded : count, that many words, count, that many empty words
    # word : tile number in the upper 10 bits, bit 0 is a flag

    words = []
    i = 0

    while i < len(raw):
        n = raw[i]
        i += 1

        for _ in range(n):
            words.append(raw[i] | (raw[i + 1] << 8))
            i += 2

        if i >= len(raw):
            break

        words += [0] * raw[i]
        i += 1

    return words


def load(*parts):

    return open(os.path.join(GAME, *parts), 'rb').read()


os.makedirs(os.path.join(OUT, 'tiles'), exist_ok=True)
os.makedirs(os.path.join(OUT, 'maps'), exist_ok=True)

for lev in LEVELS:
    spr = load(lev, 'SPRITES.VGA')
    save_sprites(lev, spr)
    pal = read_palette(spr)
    tiles = read_tiles(load(lev, 'MODS.VGA'), pal)
    cols = 20
    sheet = Image.new('RGB', (cols * 17 + 1, ((len(tiles) + cols - 1) // cols) * 17 + 1), (255, 0, 255))

    for i, img in enumerate(tiles):
        sheet.paste(img, ((i % cols) * 17 + 1, (i // cols) * 17 + 1))

    sheet.save(os.path.join(OUT, 'tiles', lev + '_tiles.png'))
    words = read_map(load(lev, 'MAP.CMP'))
    level = Image.new('RGB', (320, (len(words) // 20) * 16), pal[0])

    for i, w in enumerate(words):

        if w >> 6:
            level.paste(tiles[w >> 6], ((i % 20) * 16, (i // 20) * 16))

    level.save(os.path.join(OUT, 'maps', lev + '_map.png'))
    print(f'{lev} : {len(tiles)} tiles, map {level.width}x{level.height}')

for arc in ARCHIVES:
    save_sprites(arc.split('.')[0], unpack_lh1(load(arc)))


def planar(data, off, wb, h, pal):

    # 4 planes one after the other, each h rows of wb bytes

    img = Image.new('RGB', (wb * 8, h))
    px = img.load()

    for y in range(h):

        for x in range(wb * 8):
            c = 0

            for pl in range(4):

                if data[off + pl * wb * h + y * wb + (x >> 3)] & (0x80 >> (x & 7)):
                    c |= 1 << pl

            px[x, y] = pal[c]

    return img


def interleaved(data, off, words, h, pal):

    # per row and per 16 pixels, one big endian word for each of the 4 planes

    img = Image.new('RGB', (words * 16, h))
    px = img.load()

    for y in range(h):

        for x in range(words * 16):
            o = off + y * words * 8 + (x >> 4) * 8 + ((x >> 3) & 1)
            c = 0

            for pl in range(4):

                if data[o + pl * 2] & (0x80 >> (x & 7)):
                    c |= 1 << pl

            px[x, y] = pal[c]

    return img


def save_glyphs(name, data, off, wb, h, count, pal, width=None):

    # width : crop each glyph to its left pixels (the tiny font holds every
    # 4 pixel glyph twice in one byte, once per nibble)

    gw = width or wb * 8
    sheet = Image.new('RGB', (count * (gw + 1) + 1, h + 2), (255, 0, 255))
    os.makedirs(os.path.join(OUT, 'gr', name), exist_ok=True)

    for i in range(count):
        img = planar(data, off + i * wb * h * 4, wb, h, pal).crop((0, 0, gw, h))
        img.save(os.path.join(OUT, 'gr', name, f'{i:02d}.png'))
        sheet.paste(img, (i * (gw + 1) + 1, 1))

    sheet.save(os.path.join(OUT, 'gr', name + '.png'))


# GR.DAT is a headerless pack. The offsets and sizes below come from the table of
# conversion calls at 0x113bc of XENON2.EXE (GR.DAT is loaded at segment 0x2824),
# where each block is given as offset, count of 16 pixel units and units per row
#
#   0x0000  HUD bar               0x38ad  320 units planar
#   0x0500  HUD digits 0 to 9     0x398d  10 glyphs, 0x0640 a second set of 10
#   0x0780  large font            40 glyphs of 22 rows   (routine 0x116e8)
#   0x2300  medium font           42 glyphs of 14 rows   (routine 0x116e8)
#   0x3560  pipe, 2 units per row, 382 units   ->  32 x 191
#   0x4150  pipe, 1 unit per row, 191 units    ->  16 x 191
#   0x4748  pipe, 8 units per row, 72 units    -> 128 x 9
#   0x4988  pipe, 8 units per row, 72 units    -> 128 x 9
#   0x4bc8  pipe, 90 units -> 160 x 9. The table gives 8 units per row here, but
#           that value only drives the CGA dither row counter and the picture
#           lines up at 10 units per row
#   0x4e98  shop bottom panel, 12 per row, 432 ->  192 x 36
#   0x5c18, 0x64d8, 0x6d98  shop side panel in three blocks of 7 per row -> 112 x 149
#   0x7cb0  tiny font, 60 glyphs of 32 bytes (routine 0x116c0), characters 0x20 to 0x5b
#   0x8430, 0x8f90, 0x91c0  shopkeeper strip, 7 per row -> 112 x 198
#   0xaf80  title logo, 13 per row, 702 units  ->  208 x 54 (drawn by 0x111cc)

gr = unpack_lh1(load('GR.DAT'))
level_pal = read_palette(load('S1', 'SPRITES.VGA'))
shop_pal = read_palette(unpack_lh1(load('SHOP.DAT')))

# colours 1 to 3 of the title screens, read from the running game

title_pal = list(level_pal)
title_pal[1:4] = [(255, 182, 109), (255, 146, 73),
                  (219, 109, 73)]
os.makedirs(os.path.join(OUT, 'gr'), exist_ok=True)
planar(gr, 0, 40, 8, level_pal).save(os.path.join(OUT, 'gr', 'hud_bar.png'))
save_glyphs('hud_digits', gr, 1280, 1, 8, 20, level_pal)
save_glyphs('font_large', gr, 1920, 2, 22, 40, title_pal)
save_glyphs('font_medium', gr, 8960, 2, 14, 42, title_pal)
save_glyphs('font_tiny', gr, 31920, 1, 8, 60, shop_pal, width=4)
os.makedirs(os.path.join(OUT, 'gr', 'pipes'), exist_ok=True)

# the shop draws its digits (credits at 0x1716 of segment 0xf29, lives at 0x1669) with the
# shop palette

save_glyphs('hud_digits_shop', gr, 1280, 1, 8, 20, shop_pal)

# sizes as the shop background blits them (table at cs:0x1f4c of segment 0xf29, routine
# 0x1a2b : offset, screen address, units of 16 pixels per row, rows). The fifth piece is
# 5 units by 18 rows.

for i, (off, words, rows) in enumerate(((13664, 2, 191), (16720, 1, 191), (18248, 8, 9),
                                        (18824, 8, 9), (19400, 5, 18))):
    interleaved(gr, off, words, rows, shop_pal).save(os.path.join(OUT, 'gr', 'pipes', f'{i}.png'))

interleaved(gr, 20120, 12, 36, shop_pal).save(os.path.join(OUT, 'gr', 'shop_bottom_panel.png'))
interleaved(gr, 23576, 7, 149, shop_pal).save(os.path.join(OUT, 'gr', 'shop_side_panel.png'))


# shopkeeper head and its animation pieces, left as one uncut strip

interleaved(gr, 33840, 7, 198, shop_pal).save(os.path.join(OUT, 'gr', 'shopkeeper_strip.png'))
interleaved(gr, 44928, 13, 54, title_pal).save(os.path.join(OUT, 'gr', 'title_logo.png'))
print('GR : HUD bar, 20 HUD digits, 3 fonts, 5 pipe pieces, 2 shop panels, shopkeeper strip, title logo')
