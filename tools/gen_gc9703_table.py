#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Write the RG34XX-SP newer-panel (v2, PE6 high) init table for panel-galaxycore-gc9703.c.

Usage:
  gen_gc9703_table.py STOCK_PANEL_SEQS_JSON

Input: stock_panel_seqs.json written by tools/extract_rg34xxsp_panels.py from a stock Anbernic
V1.0.6 image (the sequence lives in the stock u-boot, U-Boot 2018.05, a GPL-2.0+ program; the
2025 firmware used PE6 high for an older, different panel and is refused here). Decision Q8
(Dale, 2026-11-14) puts the board's two panel sequences into GPL-2.0 kernel source.

The command list is prepared exactly as tools/gen_panel_firmware.py prepares v2 (trailing
exit-sleep and display-on dropped: the driver sends both), and that file's known-good SHA-256
must match before anything is printed: so the table holds the same commands as ROCKNIX's working
v2 panel file (tag 20261101), which runs this panel on mainline.

Table format (one command per line): number of parameter bytes, command, parameters.

Prints C to stdout. Python stdlib only.
"""
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_panel_firmware as gpf  # noqa: E402

UNLOCK = [0xd7, 0x61, 0x74, 0x97]   # GC9703 command-set enable
PAGE = 0xd0                         # page select; parameter 0x10, 0x11 or 0x12
WRAP = 12                           # parameter bytes per continuation line


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    seqs = json.load(open(sys.argv[1]))
    key, _compat, delays, clocks, keep11 = gpf.PANELS['v2']
    if key not in seqs:
        sys.exit(f'{sys.argv[1]}: no {key} sequence')
    cmds = gpf.clean(seqs[key], None, keep11)
    digest = hashlib.sha256(gpf.build(cmds, delays, clocks)).hexdigest()
    if digest != gpf.KNOWN_GOOD['v2']:
        sys.exit(f'v2 sequence does not match the known-good panel file (sha256 {digest[:16]}...)')
    if cmds[0] != UNLOCK:
        sys.exit(f'not a GC9703 sequence: starts {cmds[0]}')
    if any(c[0] == 'sleep' for c in cmds):
        sys.exit('unexpected delay inside the sequence: the table format has no delay entry')
    out = ['static const u8 anbernic_rg34xx_sp_v2_init[] = {']
    for c in cmds:
        cmd, par = c[0], c[1:]
        if c == UNLOCK:
            out.append('\t/* command set enable */')
        elif cmd == PAGE and len(par) == 1:
            out.append(f'\t/* page 0x{par[0]:02x} */')
        head = f'\t{len(par)}, 0x{cmd:02x},'
        if len(par) <= WRAP:
            out.append((head + ' ' + ' '.join(f'0x{b:02x},' for b in par)).rstrip())
            continue
        out.append(head)
        for i in range(0, len(par), WRAP):
            out.append('\t\t' + ' '.join(f'0x{b:02x},' for b in par[i:i + WRAP]))
    out.append('};')
    print('\n'.join(out))
    print(f'/* {len(cmds)} commands; matches known-good v2 sha256 {digest[:16]}... */',
          file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
