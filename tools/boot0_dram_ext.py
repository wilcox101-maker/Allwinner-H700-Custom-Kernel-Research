#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Decode the Allwinner H616/H700 boot0 'DRAM.ext' strap-selected DRAM parameter table.
Read-only. usage: boot0_dram_ext.py BOOT0.bin [...]  (boot0 = 64 KiB at 8 KiB of a stock card image)
Layout (recovered from the V1.0.6 boot0 code at 0x233c0, desk only):
  0x038..0x0b7  default DRAM parameter block (32 words, starts with dram_clk)
  0x348  'DRAM.ext' magic; 0x350 mode (0 = off, 1 = GPIO straps, 2/3 = ADC variants)
  0x354  up to 6 GPIO entries, 8 bytes: port(1=PA..8=PH), pin, func, pull, drv, data, pad
  0x374 + (i-1)*0x80  parameter set for strap index i (1..15); index 0 = default block
"""
import struct, sys
NAMES = {0: "dram_clk", 1: "dram_type", 2: "dx_odt", 3: "dx_dri", 4: "ca_dri", 5: "odt_en",
         6: "para1", 7: "para2", 26: "tpr6", 27: "tpr10", 28: "tpr11", 29: "tpr12", 30: "tpr13"}
TYPES = {3: "DDR3", 4: "DDR4", 7: "LPDDR3", 8: "LPDDR4"}
def block(d, off): return struct.unpack_from("<32I", d, off)
def desc(w): return "%s @ %d MHz" % (TYPES.get(w[1], "type%d" % w[1]), w[0]) if w[0] else "empty"
for f in sys.argv[1:]:
    d = open(f, "rb").read()
    print("==", f)
    if d[0x348:0x350] != b"DRAM.ext":
        print("  no DRAM.ext"); continue
    mode = d[0x350]
    pins = []
    for i in range(4):  # 4 slots; slot 5+ overlaps the table at 0x374
        p, n, fn, pull = d[0x354 + 8*i: 0x358 + 8*i]
        if 0 < p <= 12: pins.append("P%s%d(func %d, pull %d)" % ("ABCDEFGHIJKL"[p-1], n, fn, pull))
    print("  mode %d; strap pins (bit0 first): %s" % (mode, ", ".join(pins) or "none"))
    dflt = block(d, 0x38)
    print("  index 0 (default block): %s" % desc(dflt))
    for i in range(1, 16):
        w = block(d, 0x374 + (i-1)*0x80)
        print("  index %2d: %s" % (i, desc(w)))
    print("  field dump of non-placeholder sets (hex):")
    sets = [("default", dflt)] + [("idx%d" % i, block(d, 0x374+(i-1)*0x80)) for i in range(1, 16)]
    sets = [s for s in sets if s[1][0] and s[1][0] != 0x318]
    print("    %-7s " % "word" + " ".join("%-10s" % n for n, _ in sets))
    for k in range(32):
        vals = [w[k] for _, w in sets]
        if any(vals):
            print("    %-7s " % NAMES.get(k, "w%d" % k) + " ".join("%08x  " % v for v in vals))
