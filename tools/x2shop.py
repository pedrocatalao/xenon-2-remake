import json
import os
import struct
import sys
import x2lh1

print('\nXenon 2 shop table decoder')
print('V.K. Papanikolaou, Assoc. Prof. AUTh')
print('Last updated : 15/11/2026\n')

if len(sys.argv) != 3:
    print('Usage : python x2shop.py <game folder> <output folder>')
    sys.exit(1)

GAME = sys.argv[1]
OUT = sys.argv[2]

# offsets inside the load module of XENON2.EXE (file offset minus the 0x800 header).
# The data segment is 0x1853, so ds:X is at module offset 0x18530 + X.

DS = 0x18530

# the common sprite buffer holds the three archives one after the other, and a sprite
# pointer points 8 bytes past the frame header

COMMON = [('X2SPR', 0), ('X2WEAPS', 0x6be6),
          ('SHOP', 0xabbc)]
FRAME_BIAS = 8

# ds:0x3cb6 : the 20 item boxes, 12 bytes each (counter, x, y, item, animation, launcher)
# ds:0x38ce : price of item n at 0x38ce + 2n
# ds:0x3898 : animation of item n at 0x3898 + 2n
# ds:0x3866 : description of item n at 0x3866 + 2n
# ds:0x384d : flags of item n at 0x384d + n (slot checks of 0x4fe3)
# ds:0x381a : purchase routine of item n at 0x381a + 2n
# ds:0x3ca0 : box frames for the counter values -9 to 0
# ds:0x3cb2 : box background, by loop count parity
# ds:0x3de4 : 7 background animations (x, y, animation) of the shopkeeper area
# ds:0x3ed6 : advice messages, ds:0x427d : shop palette (16 triplets of 6 bit values)

SLOTS = 0x3cb6
PRICES = 0x38ce
ANIMS = 0x3898
TEXTS = 0x3866
FLAGS = 0x384d
HANDLERS = 0x381a
BOX_FRAMES = 0x3ca0
BOX_BACK = 0x3cb2
BACKGROUND = 0x3de4
ADVICE = 0x3ed6
PALETTE = 0x427d

# messages printed by the shop code (address of the immediate in the code)

MESSAGES = {
    'sell': 0x3da6,
    'buy': 0x3dc4,
    'welcome': 0x3e82,
    'everything': 0x3ea6,
    'last_chance': 0x3eb9,
    'out_of_stock': 0x392b,
    'no_room': 0x3902,
    'give_cash': 0x3952,
    'what_else': 0x3967,
    'here_cash': 0x3980,
    'will_pay': 0x3ab4,
    'will_cost': 0x3ac2,
    'power': 0x3ad4,
    'end_1': 0x3796,
    'end_2': 0x37b1,
    'end_3': 0x37d8,
}

# sprites the shop code draws by immediate address

SPRITES = [0xec90, 0xefc0, 0xabe4, 0xace4, 0xad94, 0xae94, 0xaf94, 0xb044, 0xb144,
           0xb1ae, 0xb218, 0xb282, 0xdde0, 0xe1e8, 0xdfe4, 0xe3ec, 0xe7f4, 0xe5f0,
           0xea9e, 0xe9f8, 0xebea, 0xeb44, 0xf470, 0xf700, 0xf990, 0xfc20]


def load(*parts):

    return open(os.path.join(GAME, *parts), 'rb').read()


def frame_table(data, base, name):

    table = {}
    p = 32
    index = 0

    while p + 16 <= len(data):
        h = struct.unpack('<8h', data[p:p + 16])
        table[base + p + FRAME_BIAS] = f'{name}/{index:03d}'
        p += 16 + (h[7] + 1) * ((h[6] + 7) // 8) * 5
        p += p & 1
        index += 1

    return table


def word(addr):

    return struct.unpack('<H', module[DS + addr:DS + addr + 2])[0]


def signed(addr):

    return struct.unpack('<h', module[DS + addr:DS + addr + 2])[0]


def text(addr):

    end = module.index(b'\0', DS + addr)

    return module[DS + addr:end].decode('latin1')


def frame(ptr):

    return common.get(ptr, f'?{ptr:04x}')


def animation(addr):

    # frame pointers ended by a zero word and the address to go on from (code 0x571b)

    out = []
    p = addr

    while word(p) != 0 and len(out) < 64:
        out.append(frame(word(p)))
        p += 2

    back = word(p + 2)

    return {'frames': out, 'loop': (back - addr) // 2}


module = load('XENON2.EXE')[0x800:]
common = {}

for name, base in COMMON:
    common.update(frame_table(x2lh1.unpack(load(name + '.DAT')), base, name))

result = {
    'palette': [[round(v * 255 / 63) for v in module[DS + PALETTE + 3 * i:DS + PALETTE + 3 * i + 3]]
                for i in range(16)],
    'slots': [[signed(SLOTS + 12 * i + 2), signed(SLOTS + 12 * i + 4)] for i in range(20)],
    'items': {},
    'box_frames': [frame(word(BOX_FRAMES + 2 * i)) for i in range(10)],
    'box_back': [frame(word(BOX_BACK + 2 * i)) for i in range(2)],
    'background': [],
    'advice': [text(word(ADVICE + 2 * i)) for i in range(30)],
    'messages': {k: text(v) for k, v in MESSAGES.items()},
    'sprites': {f'{a:04x}': frame(a) for a in SPRITES},
}

for n in range(1, 28):
    item = {'anim': animation(word(ANIMS + 2 * n)) if word(ANIMS + 2 * n) else None}

    if n <= 25:
        item.update({
            'price': signed(PRICES + 2 * n),
            'text': text(word(TEXTS + 2 * n)),
            'flags': module[DS + FLAGS + n],
            'handler': f'{word(HANDLERS + 2 * n):#x}',
        })

    result['items'][str(n)] = item

for i in range(7):
    a = BACKGROUND + 6 * i
    result['background'].append({'x': signed(a), 'y': signed(a + 2), 'anim': animation(word(a + 4))})

# the palettes the sprite pictures were saved with, so the shop can draw the common
# sprites with its own palette (16 words big endian, 3 bits a channel, as x2bitmaps.py)

result['sprite_palettes'] = {}

for name, base in COMMON:
    head = x2lh1.unpack(load(name + '.DAT'))[:32]
    result['sprite_palettes'][name] = [[round(((w >> s) & 7) * 9 * 255 / 63) for s in (8, 4, 0)]
                                       for w in struct.unpack('>16H', head)]

missing = [k for k, v in result['sprites'].items() if v.startswith('?')]

with open(os.path.join(OUT, 'shop.json'), 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=1)

print(f'shop.json written, {len(missing)} sprites not found')
