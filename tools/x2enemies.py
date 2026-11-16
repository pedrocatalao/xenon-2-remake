import json
import os
import struct
import sys
import x2lh1

print('\nXenon 2 enemy table decoder')
print('V.K. Papanikolaou, Assoc. Prof. AUTh')
print('Last updated : 15/11/2026\n')

if len(sys.argv) != 3:
    print('Usage : python x2enemies.py <game folder> <output folder>')
    sys.exit(1)

GAME = sys.argv[1]
OUT = sys.argv[2]
LEVELS = ['S1', 'S2',
          'S3', 'S4',
          'S5']

# offsets inside the load module of XENON2.EXE (file offset minus the 0x800 header)
# 0xfc6 : per level pointer to the enemy type dispatcher
# 0x3389 : the routine that spawns a wave from an enemy definition

LEVEL_TABLE = 0xfc6
SPAWN = 0x3389

# the common sprite buffer holds the three archives one after the other

COMMON = [('X2SPR', 0), ('X2WEAPS', 0x6be6),
          ('SHOP', 0xabbc)]

# an animation entry points 8 bytes past the sprite frame header, and its lowest bit
# selects the buffer : odd for the level sprites, even for the common ones

FRAME_BIAS = 8


def load(*parts):

    return open(os.path.join(GAME, *parts), 'rb').read()


def frame_table(data, base, name):

    # sprite file : 32 byte palette, then frames of 8 word header plus 5 planes

    table = {}
    p = 32
    index = 0

    while p + 16 <= len(data):
        h = struct.unpack('<8h', data[p:p + 16])
        table[base + p + FRAME_BIAS] = (name, index, h[4], h[5])
        p += 16 + (h[7] + 1) * ((h[6] + 7) // 8) * 5
        p += p & 1
        index += 1

    return table


def words(off, count):

    return struct.unpack(f'<{count}H', module[off:off + 2 * count])


def read_animation(off, frames):

    # pairs of (frame pointer, game frames to show it), ended by a zero word

    out = []
    missing = 0

    while True:
        ptr, ticks = words(off, 2)

        if ptr == 0 or len(out) > 64:
            break

        table = frames[ptr & 1]
        ptr &= 0xfffe

        if ptr in table:
            name, index, hot_x, hot_y = table[ptr]
            out.append({'set': name, 'frame': index, 'ticks': ticks,
                        'hot_x': hot_x, 'hot_y': hot_y})
        else:
            missing += 1

        off += 4

    return out, missing


module = load('XENON2.EXE')[0x800:]
common = {}

for name, base in COMMON:
    common.update(frame_table(x2lh1.unpack(load(name + '.DAT')), base, name))

result = {}

for number, lev in enumerate(LEVELS, 1):
    local = frame_table(load(lev, 'SPRITES.VGA'), 0, lev)
    events = load(lev, 'EVENTS.PC')
    types = set()

    for i in range(0, len(events) - 13, 14):
        rec = struct.unpack('<7h', events[i:i + 14])

        if rec[0] == -1 and rec[1] == -1:
            break

        types.add(rec[1])

    handler = words(LEVEL_TABLE + 2 * number, 1)[0]

    # the dispatcher is : shl bx,1 / jmp cs:[bx + table]

    if module[handler:handler + 5] != bytes([0xd1, 0xe3, 0x2e, 0xff, 0xa7]):
        print(f'{lev} : dispatcher not recognised')
        continue

    table = words(handler + 5, 1)[0]
    level = {}
    notes = []

    for kind in sorted(types):
        code = words(table + 2 * kind, 1)[0]

        # a plain type handler is : mov bx, definition / call or jmp spawn

        target = None

        if module[code] == 0xbb and module[code + 3] in (0xe8, 0xe9):
            rel = struct.unpack('<h', module[code + 4:code + 6])[0]
            target = (code + 6 + rel) & 0xffff

        if target != SPAWN:
            notes.append(f'type {kind} has a special handler at {code:#x}')
            continue

        definition = words(code + 1, 1)[0]
        frames = (common, local)
        parts = []

        # an enemy is a list of 16 byte parts ended by a zero word, all following the same path
        # part : id, word, update routine, draw routine, routine, animation, word, two bytes
        # only the fields whose use was read in the spawn routine are named

        while words(definition, 1)[0] != 0 and len(parts) < 8:
            d = words(definition, 8)
            animation, missing = read_animation(d[5], frames)

            if missing:
                notes.append(f'type {kind} has {missing} unresolved frames')

            parts.append({'id': d[0], 'start_delay': d[1], 'update': f'{d[2]:#06x}',
                          'raw': [f'{v:#06x}' for v in d], 'frames': animation})
            definition += 16

        level[str(kind)] = {'parts': parts}

    result[lev] = level
    print(f'{lev} : {len(level)} of {len(types)} enemy types decoded' + (' (' + ', '.join(notes) + ')' if notes else ''))

# the sine table used by the path stepping : 320 signed bytes, 256 per circle plus a quarter

result['sine'] = list(struct.unpack('<320b', module[0x6116:0x6116 + 320]))
os.makedirs(OUT, exist_ok=True)
json.dump(result,
          open(os.path.join(OUT, 'enemies.json'), 'w'),
          indent=1)
