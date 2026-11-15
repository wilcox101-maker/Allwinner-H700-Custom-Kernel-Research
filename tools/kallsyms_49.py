#!/usr/bin/env python3
"""Read the kallsyms table from a raw arm64 Linux 4.9 Image (stdlib only, read-only).

For kernels built with CONFIG_KALLSYMS_BASE_RELATIVE=y and without
CONFIG_KALLSYMS_ABSOLUTE_PERCPU (the RG34XX-SP stock 4.9.170 kernel). Layout written
by 4.9 scripts/kallsyms.c, each block aligned (8 bytes or more; this build pads
every block to 256 bytes):

  kallsyms_offsets       int32[num_syms]   address = relative_base + offset
  kallsyms_relative_base u64
  kallsyms_num_syms      u64
  kallsyms_names         per symbol: length byte, then that many token indices
  kallsyms_markers       u64[(num_syms + 255) // 256]  offsets into names
  kallsyms_token_table   256 NUL-terminated strings
  kallsyms_token_index   u16[256]  offsets into token_table

The tables are found by their shape: token_index is located first, everything else
is walked backwards from it and cross-checked (markers against names, offsets sorted).

Usage: kallsyms_49.py IMAGE [--base 0xffffff8008080000] [--out symbols.tsv]
Output: one line per symbol, "address<TAB>type<TAB>name", in table order.
With CONFIG_RELOCATABLE the Image stores relative_base as 0 (a boot-time fixup fills it);
--base is used in its place. Needs more than 256 symbols (always true for a kernel).
Test: tests/test_kallsyms_49.py (synthetic image).
"""
import argparse
import struct


MAXPAD = 256  # largest zero padding accepted between blocks


def find_token_index(img):
    """Return [(token_table_off, token_index_off)] for blocks that pass all checks.

    Blocks may be padded with zeros to a larger alignment than 8 (this build pads
    to 256), so padding is measured, not assumed.
    """
    hits = []
    n = len(img)
    for pos in range(0, n - 512, 8):
        if img[pos] != 0 or img[pos + 1] != 0:
            continue
        idx = struct.unpack_from("<256H", img, pos)
        if any(idx[i + 1] - idx[i] < 2 for i in range(255)):  # tokens are non-empty
            continue
        if idx[255] > 4096:
            continue
        e = pos
        while e > 0 and img[e - 1] == 0 and pos - e <= MAXPAD:
            e -= 1
        if pos - e > MAXPAD or e == pos:
            continue
        last_start = e
        while last_start > 0 and img[last_start - 1] != 0:
            last_start -= 1
        tbl = last_start - idx[255]
        if tbl < 0 or tbl % 8:
            continue
        if all(img[tbl + idx[i + 1] - 1] == 0 and img[tbl + idx[i]] != 0
               for i in range(255)):
            hits.append((tbl, pos))
    return hits


def tokens_from(img, tbl, idx_off):
    idx = struct.unpack_from("<256H", img, idx_off)
    toks = []
    for i in range(256):
        s = tbl + idx[i]
        e = img.index(b"\0", s)
        toks.append(img[s:e].decode("latin-1"))
    return toks


def walk_names(img, start, count):
    """Return list of (name_start, token bytes) for count symbols from start, or None."""
    out = []
    p = start
    for _ in range(count):
        if p >= len(img):
            return None
        ln = img[p]
        if ln == 0:
            return None
        out.append((p, img[p + 1:p + 1 + ln]))
        p += 1 + ln
    return out, p


def read_kallsyms(img, base):
    hits = find_token_index(img)
    if len(hits) != 1:
        raise SystemExit("token_index candidates: %d (need exactly 1)" % len(hits))
    tbl, idx_off = hits[0]
    toks = tokens_from(img, tbl, idx_off)

    # kallsyms_markers ends before token_table (then zero padding): walk it backwards.
    q = tbl
    while q > 0 and img[q - 1] == 0 and tbl - q <= MAXPAD:
        q -= 1
    mend = (q + 7) & ~7                      # one past the last marker
    marks = []
    p = mend - 8
    while p >= 0:
        v = struct.unpack_from("<Q", img, p)[0]
        if marks and v >= marks[-1]:
            raise SystemExit("markers block not decreasing at 0x%x" % p)
        marks.append(v)
        if v == 0:
            break
        p -= 8
    markers_off = p
    markers = marks[::-1]
    nmark = len(markers)
    # num_syms (u64) is followed by kallsyms_names (maybe after zero padding); the
    # walk of num_syms names must end before markers_off with zero padding only.
    lo = max(0, markers_off - markers[-1] - 256 * 256 - 2 * MAXPAD)
    hi = markers_off - markers[-1]
    for ns_off in range((hi - 8) & ~7, lo, -8):
        num = struct.unpack_from("<Q", img, ns_off)[0]
        if not ((nmark - 1) * 256 < num <= nmark * 256):
            continue
        names_off = ns_off + 8
        while img[names_off] == 0 and names_off - ns_off <= MAXPAD:
            names_off += 1
        res = walk_names(img, names_off, num)
        if res is None:
            continue
        entries, names_end = res
        if names_end > markers_off or any(img[names_end:markers_off]):
            continue
        if any(markers[k] != entries[256 * k][0] - names_off for k in range(nmark)):
            continue
        # relative_base (u64) sits before num_syms, possibly with padding.
        rb_off = ns_off - 8                  # zero in a relocatable Image (see below)
        relative_base = struct.unpack_from("<Q", img, rb_off)[0]
        if relative_base == 0:
            # CONFIG_RELOCATABLE: the field is filled by a R_AARCH64_RELATIVE fixup at
            # boot, so the raw Image holds 0. The base is _text, the link address.
            relative_base = base
        # offsets: int32[num] ending before relative_base (zero padding allowed).
        end = rb_off
        while img[end - 1] == 0 and rb_off - end <= 2 * MAXPAD + 16:  # base field + two paddings
            end -= 1
        found = None
        for o in range(((end + 3) & ~3) - 4 * num, ((end + 3) & ~3) - 4 * num + 4 * 64 + 4, 4):
            offs = struct.unpack_from("<%di" % num, img, o)
            if offs[0] >= 0 and all(offs[i] <= offs[i + 1] for i in range(num - 1)) \
                    and not any(img[o + 4 * num:rb_off]):
                found = o
                break
        if found is None:
            raise SystemExit("offsets block not found (num_syms=%d)" % num)
        o = found
        syms = []
        for (p, toklist), off in zip(entries, offs):
            name = "".join(toks[t] for t in toklist)
            syms.append((relative_base + off, name[0], name[1:]))
        info = dict(token_table=tbl, token_index=idx_off, names=names_off,
                    markers=markers_off, num_syms=num, relative_base=relative_base,
                    offsets=o)
        return info, syms
    raise SystemExit("num_syms/names block not found")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("image")
    ap.add_argument("--base", default="0xffffff8008080000",
                    help="link address of the Image's first byte (_text); also used as "
                         "kallsyms_relative_base when the Image stores 0 (relocatable)")
    ap.add_argument("--out", help="write address/type/name TSV here")
    a = ap.parse_args()
    img = open(a.image, "rb").read()
    base = int(a.base, 16)
    info, syms = read_kallsyms(img, base)
    for k, v in info.items():
        if k in ("num_syms",):
            print("%-14s %d" % (k, v))
        elif k == "relative_base":
            print("%-14s 0x%x" % (k, v))
        else:
            print("%-14s file 0x%x (va 0x%x)" % (k, v, base + v))
    text = sum(1 for s in syms if s[1] in "tT")
    print("symbols        %d (%d in text)" % (len(syms), text))
    if a.out:
        with open(a.out, "w") as f:
            for addr, typ, name in syms:
                f.write("%016x\t%s\t%s\n" % (addr, typ, name))


if __name__ == "__main__":
    main()
