import json
import os
import struct
import sys

print('\nXenon 2 level data decoder')
print('V.K. Papanikolaou, Assoc. Prof. AUTh')
print('Last updated : 15/11/2026\n')

if len(sys.argv) != 3:
    print('Usage : python x2levels.py <game folder> <output folder>')
    sys.exit(1)

GAME = sys.argv[1]
OUT = sys.argv[2]
LEVELS = ['S1', 'S2',
          'S3', 'S4',
          'S5']
TABLE_WORDS = 115

# path command lengths (words after the opcode)
# 10 : set position (x, y)
# 2 : arc (heading, turn, turn change, length), angles are 256 per circle with 0 right and 64 down,
#     turn is in 1/256 angle units per pixel, length is in pixels
# 4 : wait (count)
# 8 : loop back to a byte offset inside the path (exported as a command index)
# 0 : end

ARGS = {10: 2, 2: 4,
        4: 1, 8: 1,
        0: 0}
NAMES = {10: 'pos', 2: 'arc',
         4: 'wait', 8: 'loop',
         0: 'end'}


def load(*parts):

    return open(os.path.join(GAME, *parts), 'rb').read()


def records(data):

    # 7 signed words per record, the list ends with two -1 words

    out = []

    for i in range(0, len(data) - 13, 14):
        rec = struct.unpack('<7h', data[i:i + 14])

        if rec[0] == -1 and rec[1] == -1:
            break

        out.append(rec)

    return out


def read_paths(data):

    words = struct.unpack(f'<{len(data) // 2}H', data[:len(data) // 2 * 2])
    count = 1

    while words[count] > words[count - 1]:
        count += 1

    base = TABLE_WORDS * 2
    offs = list(words[:count]) + [len(data) - base]
    paths = []
    unknown = 0

    for p in range(count):
        chunk = data[base + offs[p]:base + offs[p + 1]]
        s = struct.unpack(f'<{len(chunk) // 2}h', chunk[:len(chunk) // 2 * 2])
        commands = []
        starts = []
        i = 0

        while i < len(s):
            op = s[i]

            if op not in ARGS or i + 1 + ARGS[op] > len(s):
                commands.append(['raw'] + list(s[i:]))
                unknown += 1
                break

            starts.append(i * 2)

            if op == 8:
                commands.append(['loop', starts.index(s[i + 1]) if s[i + 1] in starts else -1])
            else:
                commands.append([NAMES[op]] + list(s[i + 1:i + 1 + ARGS[op]]))

            i += 1 + ARGS[op]

        paths.append({'commands': commands})

    return paths, unknown


def read_map(raw):

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


os.makedirs(OUT, exist_ok=True)

for lev in LEVELS:
    events = []

    # event : scroll position that triggers it, enemy type, count, path (1 based in the file),
    # spacing along the path in pixels, unknown, speed in pixels per game frame

    for y, kind, count, path, spacing, extra, speed in records(load(lev, 'EVENTS.PC')):
        events.append({'y': y, 'type': kind, 'count': count, 'path': path - 1,
                       'spacing': spacing, 'extra': extra, 'speed': speed})

    fixed = []

    # background event : trigger position, type, two unknowns, x, world y, side (0 left, 1 right)

    for y, kind, a, b, x, world_y, side in records(load(lev, 'EVENTSBG.PC')):
        fixed.append({'y': y, 'type': kind, 'a': a, 'b': b,
                      'x': x, 'world_y': world_y, 'side': side})

    paths, unknown = read_paths(load(lev, 'PATHS.BIN'))
    words = read_map(load(lev, 'MAP.CMP'))
    level = {'events': events, 'background_events': fixed, 'paths': paths,
             'map': {'width': 20, 'height': len(words) // 20,
                     'tiles': [w >> 6 for w in words],
                     'flags': [w & 63 for w in words]}}
    json.dump(level,
              open(os.path.join(OUT, lev + '.json'), 'w'),
              separators=(',', ':'))
    print(f'{lev} : {len(events)} events, {len(fixed)} background events, '
          f'{len(paths)} paths ({unknown} with undecoded commands)')
