#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Write the RG34XX-SP (v1 panel) init table for panel-newvision-nv3052c.c, with proof of origin.

Usage:
  gen_nv3052c_table.py STOCK_PANEL_SEQS_JSON

Input: stock_panel_seqs.json written by tools/extract_rg34xxsp_panels.py from a stock Anbernic
image (the sequence lives in the stock u-boot, U-Boot 2018.05, a GPL-2.0+ program). Decision Q8
(Dale, 2026-11-14) puts this one sequence into GPL-2.0 kernel source.

The command list is prepared exactly as tools/gen_panel_firmware.py prepares v1 (register 0x23 =
0x00, see there), and that file's known-good SHA-256 must match before anything is printed: so
the table holds the same commands as ROCKNIX's working v1 panel file (tag 20261101), which runs
this panel on mainline. Then the trailing exit-sleep is dropped (the driver sends it) and the
commands are printed as `{ cmd, val }` pairs, with the NV3052C page selects commented.

Prints C to stdout. Python stdlib only.
"""
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_panel_firmware as gpf  # noqa: E402


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    seqs = json.load(open(sys.argv[1]))
    key, _compat, delays, clocks, keep11 = gpf.PANELS['v1']
    cmds = gpf.clean(seqs[key], 0x00, keep11)
    digest = hashlib.sha256(gpf.build(cmds, delays, clocks)).hexdigest()
    if digest != gpf.KNOWN_GOOD['v1']:
        sys.exit(f'v1 sequence does not match the known-good panel file (sha256 {digest[:16]}...)')
    if cmds[-1] == [0x11]:
        cmds.pop()
    bad = [c for c in cmds if len(c) != 2]
    if bad:
        sys.exit(f'not a plain NV3052C register table: {bad[:3]}')
    out = ['static const struct nv3052c_reg anbernic_rg34xx_sp_panel_regs[] = {']
    i = 0
    while i < len(cmds):
        c = cmds[i]
        if c[0] == 0xff and i + 2 < len(cmds) and cmds[i + 1] == [0xff, 0x52] and c[1] == 0x30:
            page = cmds[i + 2][1]
            out.append(f'\t// EXTC Command set enable, select page {page}')
            out.append(f'\t{{ 0xff, 0x30 }}, {{ 0xff, 0x52 }}, {{ 0xff, 0x{page:02x} }},')
            i += 3
            continue
        out.append(f'\t{{ 0x{c[0]:02x}, 0x{c[1]:02x} }},')
        i += 1
    out.append('};')
    print('\n'.join(out))
    print(f'/* {len(cmds)} commands; matches known-good v1 sha256 {digest[:16]}... */',
          file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
