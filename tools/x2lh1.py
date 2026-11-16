# LHA -lh1- decoder (LZSS 4096/60 + adaptive Huffman), level 0 header

import struct

N = 4096
F = 60
THRESHOLD = 2
N_CHAR = 256 - THRESHOLD + F
T = N_CHAR * 2 - 1
R = T - 1
MAX_FREQ = 0x8000
D_CODE = []
D_LEN = []

for length, count, each in ((3, 1, 32), (4, 3, 16), (5, 8, 8), (6, 12, 4), (7, 24, 2), (8, 16, 1)):

    for _ in range(count):
        code = (D_CODE[-1] + 1) if D_CODE else 0
        D_CODE += [code] * each
        D_LEN += [length] * each


def unpack(raw):

    hdr = raw[0]
    outlen = struct.unpack('<I', raw[11:15])[0]
    pos = [hdr + 2]
    bitbuf = [0, 0]

    def getbit():

        if bitbuf[1] == 0:
            bitbuf[0] = raw[pos[0]] if pos[0] < len(raw) else 0
            pos[0] += 1
            bitbuf[1] = 8

        bitbuf[1] -= 1

        return (bitbuf[0] >> bitbuf[1]) & 1

    def getbits(n):

        v = 0

        for _ in range(n):
            v = (v << 1) | getbit()

        return v

    freq = [0] * (T + 1)
    prnt = [0] * (T + N_CHAR)
    son = [0] * T

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
    prnt[R] = 0

    def reconst():

        j = 0

        for i in range(T):

            if son[i] >= T:
                freq[j] = (freq[i] + 1) // 2
                son[j] = son[i]
                j += 1

        i = 0

        for j in range(N_CHAR, T):
            k = i + 1
            f = freq[j] = freq[i] + freq[k]
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

        if freq[R] == MAX_FREQ:
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
