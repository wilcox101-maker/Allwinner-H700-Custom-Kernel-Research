#!/usr/bin/env python3
"""Extract the RG34XX-SP LCD init sequences from a stock Anbernic image.

Read-only. Input: a stock SD-card image (or its first 36 MiB). The script
  1. reads the u-boot "sunxi-package" at 16,400 KiB and pulls out u-boot,
  2. finds Anbernic's panel routine via the "--allen--PE_data" string,
  3. follows both branches (PE6 low -> "boe", PE6 high) and records every
     command/data byte and delay sent over the bit-banged panel SPI,
  4. writes <out>/stock_panel_seqs.json and, with --template, rebuilds a
     panel-mipi-dpi-spi ("PANEL-FIRMWARE") file per branch that keeps the
     template's header, config and timings and replaces the init commands.

Requires: python3, capstone (pip install capstone).
Tested on: RG34XXSP stock 2025-04 image and V1.0.6 (2026-05-26).
"""
import argparse, collections, json, os, struct, sys
from capstone import Cs, CS_ARCH_ARM, CS_MODE_THUMB

BASE = 0x4A000000            # stock u-boot load address
PKG_OFF = 16400 * 1024       # boot package offset on the card

def read_uboot(img):
    with open(img, 'rb') as f:
        f.seek(PKG_OFF); pkg = f.read(2 * 1024 * 1024)
    if not pkg.startswith(b'sunxi-package'):
        sys.exit('no sunxi-package at 16,400 KiB: not a stock Anbernic image?')
    items = struct.unpack_from('<I', pkg, 0x24)[0] or 4
    for i in range(items):
        p = 0x40 + i * 0x170
        name = pkg[p:p + 64].split(b'\0')[0]
        off, ln = struct.unpack_from('<II', pkg, p + 64)
        if name == b'u-boot':
            return pkg[off:off + ln]
    sys.exit('u-boot item not found in boot package')

def literal_refs(d, va):
    return [j for j in range(0, len(d) - 3, 4) if struct.unpack_from('<I', d, j)[0] == va]

def find_detect(d):
    s = d.find(b'--allen--PE_data')
    if s < 0: sys.exit('panel detect routine not found (no --allen--PE_data)')
    ref = literal_refs(d, BASE + s)[0]
    fs = ref
    while d[fs:fs + 2] != b'\x38\xb5':          # push {r3, r4, r5, lr}
        fs -= 2
    return fs

def analyse(d):
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB)
    fs = find_detect(d)
    ins = list(md.disasm(d[fs:fs + 0x1800], BASE + fs))
    bls = [i for i in ins if i.mnemonic == 'bl']
    delay = int(bls[0].op_str[1:], 16)           # first call = mdelay(15)
    # branch on lcd_type: "cmp r5, #1" followed by "bne.w <high>" then "b <low>"
    for k, i in enumerate(ins):
        if i.mnemonic == 'cmp' and i.op_str == 'r5, #1':
            j = k + 1
            while not ins[j].mnemonic.startswith('bne'): j += 1
            high = int(ins[j].op_str[1:], 16)
            low = int(ins[j + 1].op_str[1:], 16)
            break
    else:
        sys.exit('lcd_type branch not found')
    first = next(i for i in ins if i.address >= low and i.mnemonic == 'bl')
    cmd = int(first.op_str[1:], 16)
    cnt = collections.Counter(int(i.op_str[1:], 16) for i in ins if i.mnemonic == 'bl')
    data = next(t for t, _ in cnt.most_common() if t not in (cmd, delay))
    return dict(fn=BASE + fs, low=low, high=high, cmd=cmd, data=data, delay=delay)

def walk(d, start, r5, a):
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB)
    regs = {'r5': r5, 'r0': 0xFF}
    pc, ev = start, []
    for _ in range(6000):
        i = next(md.disasm(d[pc - BASE:pc - BASE + 4], pc), None)
        if i is None: break
        m, o, nxt = i.mnemonic, i.op_str, pc + i.size
        if m in ('movs', 'mov', 'mov.w'):
            dst, src = [x.strip() for x in o.split(',', 1)]
            if src.startswith('#'): regs[dst] = int(src[1:], 0)
            elif src in regs: regs[dst] = regs[src]
            else: regs.pop(dst, None)
        elif m == 'bl':
            t = int(o[1:], 16); v = regs.pop('r0', None)
            kind = {a['cmd']: 'C', a['data']: 'D', a['delay']: 'W'}.get(t)
            if kind is None: raise RuntimeError(f'unknown call {t:#x} at {pc:#x}')
            if v is None: raise RuntimeError(f'unknown argument at {pc:#x}')
            ev.append((kind, v))
        elif m in ('b', 'b.w'):
            nxt = int(o[1:], 16)
        elif (m.startswith('b') and m not in ('bic', 'bics', 'bl', 'bx')) \
                or m.startswith('pop') or m == 'bx' or (m == 'ldr' and o == 'r3, [r4]'):
            break
        pc = nxt
    cmds, cur = [], None
    for k, v in ev:
        if k == 'C':
            if cur: cmds.append(cur)
            cur = [v]
        elif k == 'D':
            cur.append(v)
        else:
            if cur: cmds.append(cur); cur = None
            cmds.append(['sleep', v])
    if cur: cmds.append(cur)
    return cmds

def encode(cmds):
    out = bytearray()
    for c in cmds:
        if c[0] == 'sleep':
            ms = c[1]
            out += b'\x80' * (ms // 100) + b'\x00' * ((ms % 100 + 9) // 10)
        else:
            if len(c) > 0x7F: raise ValueError('command too long')
            out += bytes([len(c)]) + bytes(c)
    return bytes(out)

def rebuild(template, cmds):
    b = open(template, 'rb').read()
    assert b[:15] == b'PANEL-FIRMWARE\0', 'template is not a PANEL-FIRMWARE file'
    nt = b[16 + 47]
    head = b[:16 + 48 + nt * 32]
    # the kernel driver sends DISPLAY_ON (0x29) itself; drop it and what follows
    body = list(cmds)
    while body and (body[-1][0] == 'sleep' or body[-1][0] == 0x29):
        body.pop()
    body = [c if c != [0x11, 0] else [0x11] for c in body]
    return head + encode(body)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('image')
    ap.add_argument('-o', '--out', default='.')
    ap.add_argument('--template-low', help='PANEL-FIRMWARE file to reuse for the PE6-low panel')
    ap.add_argument('--template-high', help='PANEL-FIRMWARE file to reuse for the PE6-high panel')
    a = ap.parse_args()
    d = read_uboot(a.image)
    ver = next((l for l in d.split(b'\0') if l.startswith(b'U-Boot 20')), b'?').decode()
    an = analyse(d)
    res = {'uboot': ver, 'routine': hex(an['fn']),
           'pe6_low_boe': walk(d, an['low'], 1, an),
           'pe6_high': walk(d, an['high'], 0, an)}
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, 'stock_panel_seqs.json'), 'w') as f:
        json.dump(res, f, indent=1)
    print(f"{ver}\n  routine {res['routine']}: PE6 low {len(res['pe6_low_boe'])} cmds, "
          f"PE6 high {len(res['pe6_high'])} cmds")
    for key, tpl in (('pe6_low_boe', a.template_low), ('pe6_high', a.template_high)):
        if tpl:
            p = os.path.join(a.out, f'stock-{key}.panel')
            open(p, 'wb').write(rebuild(tpl, res[key]))
            print('  wrote', p)

if __name__ == '__main__':
    main()
