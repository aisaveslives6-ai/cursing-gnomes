#!/usr/bin/env python3
"""Chroma-key the green-screen residue out of the extracted wall art.

The HTML build keyed these with PIL at build time; the embedded PNGs retain
a green fringe. This is a one-time pass: backs up originals to *_raw.png,
writes keyed versions in place.
"""
import struct, zlib, glob, os, shutil

ART = os.path.expanduser("~/workspace/godot-cursing-gnomes/assets/art/walls")


def read_png(p):
    d = open(p, "rb").read()
    pos = 8
    idat = b""
    w = h = ctype = None
    while pos < len(d):
        ln = struct.unpack(">I", d[pos:pos + 4])[0]
        typ = d[pos + 4:pos + 8]
        dat = d[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, _depth, ctype = struct.unpack(">IIBB", dat[:10])
        elif typ == b"IDAT":
            idat += dat
        pos += 12 + ln
    raw = zlib.decompress(idat)
    ch = {6: 4, 2: 3}[ctype]
    stride = w * ch
    px = bytearray(w * h * ch)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:
            for i in range(ch, len(line)):
                line[i] = (line[i] + line[i - ch]) & 255
        elif f == 2:
            for i in range(len(line)):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(len(line)):
                a = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(len(line)):
                a = line[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        px[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, ch, px


def write_png(p, w, h, px):
    stride = w * 4
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += px[y * stride:(y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    out = bytearray(b"\x89PNG\r\n\x1a\n")
    for typ, dat in [(b"IHDR", ihdr), (b"IDAT", zlib.compress(bytes(raw), 6))]:
        out += struct.pack(">I", len(dat)) + typ + dat
        out += struct.pack(">I", zlib.crc32(typ + dat) & 0xFFFFFFFF)
    out += struct.pack(">I", 0) + b"IEND" + struct.pack(">I", zlib.crc32(b"IEND") & 0xFFFFFFFF)
    open(p, "wb").write(bytes(out))


def main():
    for p in sorted(glob.glob(os.path.join(ART, "*.png"))):
        if p.endswith("_raw.png"):
            continue
        w, h, ch, px = read_png(p)
        assert ch == 4, p
        keyed = 0
        for i in range(0, len(px), 4):
            r, g, b, a = px[i], px[i + 1], px[i + 2], px[i + 3]
            # green-screen residue: green strongly dominates, not too dark
            if a > 0 and g > 70 and g > r + 45 and g > b + 45:
                px[i + 3] = 0
                keyed += 1
        raw_backup = p.replace(".png", "_raw.png")
        if not os.path.exists(raw_backup):
            shutil.copy(p, raw_backup)
        write_png(p, w, h, px)
        print("%s: keyed %d px" % (os.path.basename(p), keyed))


if __name__ == "__main__":
    main()
