#!/usr/bin/env python3
"""Host test for tools/kallsyms_49.py on a synthetic image (no stock binary needed).

Builds the 4.9 base-relative kallsyms layout with the padding the RG34XX-SP stock kernel
uses (each table aligned to 256 bytes, relative_base stored as 0 as in a relocatable
Image) and checks that every symbol comes back with the right address, type and name.
Run: python3 -I tests/test_kallsyms_49.py
"""
import os
import random
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import kallsyms_49  # noqa: E402

BASE = 0xffffff8008080000
ALIGN = 256


def pad(buf, align=ALIGN):
    buf += b"\0" * (-len(buf) % align)
    return buf


def build(num, seed=1):
    rnd = random.Random(seed)
    # 256 tokens: printable single characters first, then multi-character tokens.
    singles = [chr(c) for c in range(0x21, 0x7f)]
    multi = ["_" + a + b for a in "aeiou" for b in "lnrst"]
    multi += ["init", "probe", "sunxi_", "axp", "dev_", "_show", "_store"]
    toks = (singles + multi + ["x%02d" % i for i in range(256)])[:256]
    names, offsets, entries = [], [], []
    addr = 0
    for i in range(num):
        typ = rnd.choice("tTdDbr")
        body = "".join(rnd.choice(multi[:20] + list("abcdefghij")) for _ in range(rnd.randint(1, 6)))
        name = "%s_%d" % (body, i)
        full = typ + name
        enc = [toks.index(c) for c in full]          # one token per character
        if len(enc) > 255:
            raise SystemExit("name too long")
        entries.append(bytes([len(enc)] + enc))
        names.append((addr, typ, name))
        offsets.append(addr)
        addr += rnd.choice((0, 4, 8, 16, 64))
    img = bytearray(b"\xaa" * 0x1000)                # some code before the tables
    img = pad(img)
    img += struct.pack("<%di" % num, *offsets)
    img = pad(img)
    img += struct.pack("<Q", 0)                       # relative_base: 0 (relocatable)
    img = pad(img)
    img += struct.pack("<Q", num)
    img = pad(img)
    markers, pos = [], 0
    for i, e in enumerate(entries):
        if i % 256 == 0:
            markers.append(pos)
        pos += len(e)
    img += b"".join(entries)
    img = pad(img)
    img += struct.pack("<%dQ" % len(markers), *markers)
    img = pad(img)
    tbl = bytearray()
    index = []
    for t in toks:
        index.append(len(tbl))
        tbl += t.encode() + b"\0"
    img += tbl
    img = pad(img)
    img += struct.pack("<256H", *index)
    img = pad(img)
    img += b"\x55" * 0x800
    return bytes(img), names


def main():
    failures = 0
    for num, seed in ((300, 1), (1000, 2), (2049, 3)):
        img, want = build(num, seed)
        _, got = kallsyms_49.read_kallsyms(img, BASE)
        exp = [(BASE + a, t, n) for a, t, n in want]
        if got != exp:
            failures += 1
            bad = next(i for i, (g, e) in enumerate(zip(got, exp)) if g != e) if len(got) == len(exp) else -1
            print("FAIL num=%d: first mismatch at %d" % (num, bad))
        else:
            print("ok num=%d" % num)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
