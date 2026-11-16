import json
import os
import re
import struct
import sys
from PIL import Image

print('\nXenon 2 Amiga sound and graphics extractor')
print('V.K. Papanikolaou, Assoc. Prof. AUTh')
print('Last updated : 16/11/2026\n')

if len(sys.argv) != 5:
    print('Usage : python x2amiga.py <disk 1 ADF> <disk 2 ADF> <original PC folder> <remake folder>')
    sys.exit(1)

ADF = sys.argv[1]
ADF2 = sys.argv[2]
PC = sys.argv[3]
REMAKE = sys.argv[4]
OUT = os.path.join(REMAKE, 'data')
ART = os.path.join(REMAKE, 'assets', 'amiga')

# Disk 1 is the QTX dump of the original release (TOSEC "Xenon II - Megablast (1989)
# (ImageWorks)(Disk 1 of 2)[cr QTX]"). It is not a file system disk : the game program is
# stored unpacked at disk offset $70c00, linked for $400 (image offset 0 = game address
# $400), and runs as it is. Against the BS1 crack used before (file Xenon2, packed) it
# differs only in the credits pages, the first high scores, the protection key ($70f6,
# $76ae) and a delay ($93ee) : graphics, code, levels and the game's music are the same.
# The sound player of the game (David Whittaker, Paula) starts at offset $19b9e of the
# image ($19f9e in the game) with its tables, tunes, envelopes and the two sample banks
# ($1b780 music, $1b780 + $ff1c effects). The image from $19b00 to the end of the effect
# bank is written out as it is, so the remake runs the player on its own addresses (image
# offsets, the player at $49b9e as when the image sat at $30000).
#
# Before the game the disk holds the loading screen and its music : a second copy of the
# same player at disk offset $d772 (its image base $49b00) with a bank of 39 instruments
# from $4b70a, tunes at $4a50c. That is the full arrangement of the tune (the 15 s
# introduction, the scratches and voices), written out to amiga_intro_music.bin.

PROGRAM = 0x70c00
PROGRAM_SIZE = 0x3fc00
FIRST = 0x19b00
LAST = 0x3aa94
INTRO = 0xd772
INTRO_SIZE = 0xa1e66 - 0x49b00
SIGNATURE = bytes.fromhex('48e7f1fe61000058')

disk = open(ADF, 'rb').read()
image = disk[PROGRAM:PROGRAM + PROGRAM_SIZE]

if image[FIRST + 0x9e:FIRST + 0xa6] != SIGNATURE or disk[INTRO + 0x9e:INTRO + 0xa6] != SIGNATURE:
    raise SystemExit('disk 1 is not the QTX dump of the original release')

with open(os.path.join(OUT, 'amiga_sound.bin'), 'wb') as f:
    f.write(image[FIRST:LAST])

print(f'amiga_sound.bin written, {LAST - FIRST} bytes (image offsets {FIRST:#x} to {LAST:#x})')

with open(os.path.join(OUT, 'amiga_intro_music.bin'), 'wb') as f:
    f.write(disk[INTRO:INTRO + INTRO_SIZE])

print(f'amiga_intro_music.bin written, {INTRO_SIZE} bytes (disk offset {INTRO:#x})')

# Disk 2 has no file system. The game reads it a sector at a time ($921a, 11 sectors of 512
# bytes a track) and finds the level files in its table at $91ea (start sector, sectors),
# each loaded at $54e00. A level file starts with pointers : the background picture
# ($54e00), the map ($54e04), the tiles ($54e08).
#
# - Background : 320 pixels wide, two bitplanes a row (40 bytes each), colours 0 to 3,
#   drawn under the tiles (game $17d6) from line $436, which goes back by half the map
#   scroll a frame ($1f22) and wraps.
# - Map : words of tile offset / 16, 20 a row, as the PC map. 0 draws nothing, bit 15 a tile
#   drawn through its mask (game $195c) : 16 rows of mask and four plane words. The other
#   tiles are copied whole (128 bytes, four plane words a row).
#
# The tiles and the sprites have the same pixels as the PC files, so only the background and
# which tiles are empty, opaque or masked are written, for each PC tile number : 0 empty,
# 1 opaque, else the 16 mask rows. Tiles of the PC map get the kind of the Amiga map cell at
# the same place. Tiles not in the map (written by the wall objects) are looked up in the
# Amiga tile bank by their pixels. unconfirmed : a tile found both ways takes the masked one.
# The level palette (the PC's, the same 3 bit values) goes with them, for the Z flash.

LEVELS = [('S1', 11, 229), ('S2', 250, 254), ('S3', 514, 275), ('S4', 799, 345), ('S5', 1154, 312)]
BASE = 0x54e00


def pc_map(raw):
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


def pc_palette(data):
    return [tuple(round(((w >> s) & 7) * 9 * 255 / 63) for s in (8, 4, 0))
            for w in struct.unpack('>16H', data[:32])]


os.makedirs(ART, exist_ok=True)
disk2 = open(ADF2, 'rb').read()

for name, start, count in LEVELS:
    level = disk2[start * 512:(start + count) * 512]
    bg, mp, tl = (struct.unpack('>I', level[o:o + 4])[0] - BASE for o in (0, 4, 8))
    rows = (mp - bg) // 80
    pal = pc_palette(open(os.path.join(PC, name, 'SPRITES.VGA'), 'rb').read())
    picture = Image.new('RGB', (320, rows))
    px = picture.load()

    for y in range(rows):
        a = bg + y * 80

        for x in range(320):
            c = ((level[a + x // 8] >> (7 - x % 8)) & 1) | (((level[a + 40 + x // 8] >> (7 - x % 8)) & 1) << 1)
            px[x, y] = pal[c]

    picture.save(os.path.join(ART, name + '_background.png'))

    pc_words = pc_map(open(os.path.join(PC, name, 'MAP.CMP'), 'rb').read())
    mods = open(os.path.join(PC, name, 'MODS.VGA'), 'rb').read()
    bank = level[tl:bg]
    kinds = {}

    for i, w in enumerate(pc_words):
        a = struct.unpack('>H', level[mp + 2 * i:mp + 2 * i + 2])[0]
        t = w >> 6

        if a == 0:
            kinds[t] = 0
        elif a & 0x8000:
            o = tl + (a & 0x7fff) * 16
            kinds[t] = [struct.unpack('>H', level[o + r * 10:o + r * 10 + 2])[0] for r in range(16)]
        else:
            kinds[t] = 1

    for t in range(len(mods) // 128):
        if t in kinds:
            continue

        tile = mods[t * 128:(t + 1) * 128]
        pattern = b''.join(b'(..)' + re.escape(tile[r * 8:(r + 1) * 8]) for r in range(16))
        m = re.search(pattern, bank, re.S)

        if m:
            kinds[t] = [struct.unpack('>H', m.group(r + 1))[0] for r in range(16)]
        elif tile in bank:
            kinds[t] = 1

    json.dump({'background_rows': rows, 'palette': pal, 'tiles': {str(k): v for k, v in sorted(kinds.items())}},
              open(os.path.join(OUT, 'amiga_' + name + '.json'), 'w'), separators=(',', ':'))
    masked = sum(1 for v in kinds.values() if isinstance(v, list))
    print(f'{name} : background 320x{rows}, {len(kinds)} tiles ({masked} masked)')

# The title (game $8236) draws in 16 colours from $86b2, 3 bit values as the PC's, each
# doubled before it goes to the colour registers (add.l, so 7 becomes 14). They are written
# with the PC's conversion, as all the remake's pictures : the remake darkens the whole
# screen by 14 / 15 with the Amiga graphics. Its pictures are bitplane rows, four
# words a 16 pixel column (planes 0 to 3) :
# - the logo at $c966, 208 x 54 ($7de2),
# - the large font at $9a36, 41 glyphs of 16 x 22, in the order of $86d2 ($7f12),
# - the small font at $b666, 38 glyphs of 16 x 16, in the order of $86fc ($8b6a).
# They are written with colour 0 transparent. The colours of the title stars by depth are
# the bytes at $8614 ($854c).


def game(address, length):
    return image[address - 0x400:address - 0x400 + length]


def planes(data, width, height, pal):
    picture = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    px = picture.load()
    columns = width // 16

    for y in range(height):
        for c in range(columns):
            o = (y * columns + c) * 8
            words = struct.unpack('>4H', data[o:o + 8])

            for b in range(16):
                v = sum(((words[p] >> (15 - b)) & 1) << p for p in range(4))

                if v:
                    px[c * 16 + b, y] = pal[v] + (255,)

    return picture


def strip(data, count, rows, pal):
    picture = Image.new('RGBA', (16 * count, rows), (0, 0, 0, 0))

    for i in range(count):
        picture.paste(planes(data[i * rows * 8:(i + 1) * rows * 8], 16, rows, pal), (16 * i, 0))

    return picture


title_palette = pc_palette(game(0x86b2, 32))
planes(game(0xc966, 104 * 54), 208, 54, title_palette).save(os.path.join(ART, 'title_logo.png'))
strip(game(0x9a36, 41 * 0xb0), 41, 22, title_palette).save(os.path.join(ART, 'title_large.png'))
strip(game(0xb666, 38 * 0x80), 38, 16, title_palette).save(os.path.join(ART, 'title_small.png'))
json.dump({'palette': title_palette, 'star_colours': list(game(0x8614, 8)),
           'large': game(0x86d2, 41).decode('latin1'), 'small': game(0x86fc, 38).decode('latin1')},
          open(os.path.join(OUT, 'amiga_title.json'), 'w'), separators=(',', ':'))
print('title : logo 208x54, large font 41 glyphs, small font 38 glyphs')

# The shop file of disk 2 (sector 1476, 248 sectors, loaded at $54e00) brings a player of its
# own for effects only (no tune), which the shop puts on the vertical blank vectors $2090 and
# $2094 (shop $54e0c) and takes off at its end ($55036). Its variables and voices start at
# $6476e (the player's a3), the synthesised effects at $64e0e, the volume curves through
# $6476e + $8cc, the waveforms and the four sampled effects in the bank at $650da. From $6476e
# to the end of the bank goes to amiga_shop_sound.bin.

SHOP_START, SHOP_SECTORS = 1476, 248
SHOP_PLAYER = 0x6476e
shop_file = disk2[SHOP_START * 512:(SHOP_START + SHOP_SECTORS) * 512]
bank = 0x650da - BASE
end = bank + 0xf42

for _ in range(4):
    length = struct.unpack('>I', shop_file[end:end + 4])[0]
    end += 6 + length

with open(os.path.join(OUT, 'amiga_shop_sound.bin'), 'wb') as f:
    f.write(shop_file[SHOP_PLAYER - BASE:end])

print(f'amiga_shop_sound.bin written, {end - (SHOP_PLAYER - BASE)} bytes from ${SHOP_PLAYER:x}')
