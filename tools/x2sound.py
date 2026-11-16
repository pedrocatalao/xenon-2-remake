import os
import sys

print('\nXenon 2 sound driver extractor')
print('V.K. Papanikolaou, Assoc. Prof. AUTh')
print('Last updated : 15/11/2026\n')

if len(sys.argv) != 3:
    print('Usage : python x2sound.py <game folder> <output folder>')
    sys.exit(1)

GAME = sys.argv[1]
OUT = sys.argv[2]

# The PC speaker driver of XENON2.EXE is a segment of its own, 0x14b9, reached through the
# interrupt 0x80 vector set at 0x51c of the load module. Its variables, tunes, sound
# effects and period table live inside the segment, addressed from its start, so the
# segment is written out as it is (from load module offset 0x14b90 to the data segment at
# 0x18530) and the remake runs the driver on a copy of it.

SEGMENT = 0x14b90
END = 0x18530

module = open(os.path.join(GAME, 'XENON2.EXE'), 'rb').read()[0x800:]
image = module[SEGMENT:END]

with open(os.path.join(OUT, 'sound.bin'), 'wb') as f:
    f.write(image)

print(f'sound.bin written, {len(image)} bytes')
