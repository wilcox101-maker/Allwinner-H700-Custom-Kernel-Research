#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Build oskprobe as a static aarch64 binary (musl) with zig cc, plus a host build for a smoke run.
# Toolchain: zig 0.13.0 from PyPI (`pip install ziglang==0.13.0.post1`), or ZIG='/path/to/zig'.
# usage: tools/oskprobe/build.sh [OUTDIR]     (default: .work/oskprobe); log in OUTDIR/build.log
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-"$here/../../.work/oskprobe"}
mkdir -p "$out"
log="$out/build.log"
ZIG=${ZIG:-"python3 -m ziglang"}
ver=$(git -C "$here" describe --always --dirty 2>/dev/null || echo unknown)
flags="-std=gnu11 -O2 -Wall -Wextra -Werror"
exec 3>&1 >"$log" 2>&1
echo "oskprobe build $(date -u +%Y-%m-%dT%H:%M:%SZ), source $ver"
echo "zig $($ZIG version)"
echo "flags: $flags"
$ZIG cc -target aarch64-linux-musl -static -s $flags -DOSKPROBE_VERSION="\"$ver\"" -o "$out/oskprobe" "$here/oskprobe.c"
$ZIG cc -target native-linux-musl -static $flags -DOSKPROBE_VERSION="\"$ver\"" -o "$out/oskprobe-host" "$here/oskprobe.c"
file "$out/oskprobe" || true
sha256sum "$out/oskprobe"
"$out/oskprobe-host" version
if "$out/oskprobe-host" --ch 1 off; then echo "FAIL: --ch 1 accepted"; exit 1; fi
echo "host: --ch 1 refused (ok)"
if "$out/oskprobe-host" type 'A!'; then echo "FAIL: non-letter accepted"; exit 1; fi
echo "host: non-letter type refused (ok)"
if "$out/oskprobe-host" type abcdefghijklmnopqrstuvwxyzabcdefg; then echo "FAIL: 33 letters accepted"; exit 1; fi
echo "host: over-long word refused (ok)"
echo "build OK"
exec 1>&3
cat "$log"
