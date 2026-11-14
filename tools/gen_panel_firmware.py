#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Build the RG34XX-SP panel firmware files from the user's OWN stock image.

Usage:
  gen_panel_firmware.py STOCK_PANEL_SEQS_JSON OUT_DIR [--panel v1|v2|both] [--keep-0x23]

Input: stock_panel_seqs.json written by tools/extract_rg34xxsp_panels.py from a stock Anbernic
image you own. Output: OUT_DIR/panels/<compatible>.panel for the generic MIPI DPI+SPI panel
driver (display layer, patchwork series 937983): header, config, timings, init sequence.

The init commands come only from your image; they are never stored in this repository (their
redistribution terms are open, task R9). Everything else is set here, from hardware facts:
  - timing: 720x480, h fp/sync/bp 47/4/42, v 33/4/16, 26 MHz (v1 also 52 MHz), HSYNC and
    VSYNC active low;
    bus: data-enable active high, pixel data driven on the falling clock edge; 71 x 48 mm;
    reset/init/sleep/backlight delays 1/10/120/120 ms (v1), 10/50/120/120 ms (v2).
    These are the values ROCKNIX ships for this board (tag 20261101, cefc143), which work on
    mainline. Stock's own timing (u-boot/kernel lcd0: ht 820, vt 536, syncs active high) goes
    with stock's NV3052C register 0x23 = 0xA2; ROCKNIX's goes with 0x23 = 0x00.
  - so, for v1 (PE6 low), register 0x23 is set to 0x00 unless --keep-0x23 is given.
  - trailing exit-sleep (0x11) / display-on (0x29) commands and the sleeps after them are
    dropped (the driver sends both itself), except that v1 keeps one exit-sleep, as ROCKNIX does.
Check: from the stock 2025 image (v1) and V1.0.6 image (v2) this reproduces ROCKNIX's two
working files byte for byte.
Python stdlib only. Writes only under OUT_DIR.
"""
import argparse
import hashlib
import json
import os
import struct
import sys

# name: (JSON key, compatible, reset/init/sleep/backlight delays in ms, pixel clocks in kHz,
#        keep a trailing exit-sleep: ROCKNIX's v1 file keeps stock's, its v2 file drops it;
#        the driver sends exit-sleep itself, so a kept one is a harmless duplicate)
PANELS = {
    'v1': ('pe6_low_boe', 'anbernic,rg34xx-sp-panel', (1, 10, 120, 120), (26000, 52000), True),
    'v2': ('pe6_high', 'anbernic,rg34xx-sp-v2-panel', (10, 50, 120, 120), (26000,), False),
}
# hactive, hfp, hslen, hbp, vactive, vfp, vslen, vbp (pixel clock added per mode)
TIMING = (720, 47, 4, 42, 480, 33, 4, 16)
MODE_FLAGS = 0x2 | 0x8   # DRM_MODE_FLAG_NHSYNC | DRM_MODE_FLAG_NVSYNC
# DRM_BUS_FLAG_DE_HIGH | DRM_BUS_FLAG_PIXDATA_DRIVE_NEGEDGE
BUS_FLAGS = 0x2 | 0x8
SIZE_MM = (71, 48)
# SHA-256 of the known-good output files: identical to ROCKNIX's working files (tag 20261101).
# v1 comes out the same from the 2025 and V1.0.6 stock images; v2 only from V1.0.6 (the 2025
# firmware used PE6-high for an older third panel, which is NOT the v2 panel).
KNOWN_GOOD = {
    'v1': '929432ef1971f7332c8bd3cad6837c1bb6d0a8d5f7176e206e1eea554a8b2c09',
    'v2': '3ecd82f153a07ce86097a6cf3326484b235a9d6c5556e5ad56299a490096d3c2',
}


def encode(cmds):
    out = bytearray()
    for c in cmds:
        if c[0] == 'sleep':
            ms = c[1]
            out += b'\x80' * (ms // 100) + b'\x00' * ((ms % 100 + 9) // 10)
        else:
            if not 1 <= len(c) <= 0x7F:
                raise ValueError(f'command length {len(c)} out of range')
            out += bytes([len(c)]) + bytes(c)
    return bytes(out)


def clean(cmds, set_0x23, keep_exit_sleep):
    cmds = [list(c) for c in cmds]
    # Drop trailing display-on / exit-sleep and the sleeps after them: the driver sends both.
    had_exit_sleep = False
    while cmds and (cmds[-1][0] == 'sleep' or cmds[-1] in ([0x11], [0x29])):
        had_exit_sleep |= cmds[-1] == [0x11]
        cmds.pop()
    if keep_exit_sleep and had_exit_sleep:
        cmds.append([0x11])
    if set_0x23 is not None:
        hits = [i for i, c in enumerate(cmds) if c[0] == 0x23 and len(c) == 2]
        if len(hits) != 1:
            sys.exit(f'expected exactly one 0x23 command, found {len(hits)}')
        cmds[hits[0]][1] = set_0x23
    return cmds


def build(cmds, delays, clocks):
    header = b'PANEL-FIRMWARE\0' + bytes([1])
    config = struct.pack('>HHH2s8s', SIZE_MM[0], SIZE_MM[1], 0, b'\0' * 2, b'\0' * 8)
    config += struct.pack('>HHHH', *delays) + b'\0' * 8
    config += struct.pack('>HHII', 0, 0, 0, BUS_FLAGS) + b'\0' * 2 + bytes([0, len(clocks)])
    timings = b''.join(struct.pack('>HHHHHHHHII', *TIMING, k, MODE_FLAGS) + b'\0' * 8
                       for k in clocks)
    assert len(config) == 48 and len(timings) == 32 * len(clocks)
    return header + config + timings + encode(cmds)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('seqs')
    ap.add_argument('out')
    ap.add_argument('--panel', choices=['v1', 'v2', 'both'], default='both')
    ap.add_argument('--keep-0x23', action='store_true', help="keep stock's 0x23 value (v1)")
    ap.add_argument('--allow-unknown', action='store_true',
                    help='write a file that matches no known-good file (untested panel data)')
    a = ap.parse_args()
    seqs = json.load(open(a.seqs))
    os.makedirs(os.path.join(a.out, 'panels'), exist_ok=True)
    for name in (['v1', 'v2'] if a.panel == 'both' else [a.panel]):
        key, compat, delays, clocks, keep11 = PANELS[name]
        if key not in seqs:
            sys.exit(f'{a.seqs}: no {key} sequence')
        fix = None if (a.keep_0x23 or name != 'v1') else 0x00
        data = build(clean(seqs[key], fix, keep11), delays, clocks)
        digest = hashlib.sha256(data).hexdigest()
        known = digest == KNOWN_GOOD[name] and not a.keep_0x23
        if not known and not a.allow_unknown:
            print(f'{name}: NOT written: the result matches no known-good {name} panel file '
                  f'(sha256 {digest[:16]}...). Wrong stock version for this panel?',
                  file=sys.stderr)
            continue
        path = os.path.join(a.out, 'panels', compat + '.panel')
        open(path, 'wb').write(data)
        print(f"{path}: {len(data)} bytes, {'known-good' if known else 'UNKNOWN (allowed)'}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
