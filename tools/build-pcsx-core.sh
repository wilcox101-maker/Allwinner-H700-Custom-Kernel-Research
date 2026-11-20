#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the PS1 fast core (pcsx_rearmed, GPL-2.0) from source for the RG34XX-SP (aarch64/Cortex-A53).
# Dale's request 2026-11-20. The resulting .so is NOT committed (no binaries in the repo, AGENTS.md);
# it is injected into the ReduxOS image at build time via PCSX_CORE=... image/build-image.sh.
#
# Why from source: Ubuntu noble has no pcsx_rearmed package, and the packaged PS1 option
# (beetle-psx / mednafen_psx) is too heavy for the A53. pcsx_rearmed uses the arm64 "ari64"
# dynarec + NEON GPU and is the playable PS1 core on this SoC.
#
# usage: tools/build-pcsx-core.sh [OUTDIR]   (default OUTDIR: ./out-pcsx)
set -euo pipefail
PIN=7b0e8f8fadfbce3d170d195b9d9eecaabfa08c8e   # libretro/pcsx_rearmed, pinned
OUT=$(readlink -f "${1:-$PWD/out-pcsx}"); mkdir -p "$OUT"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
TRIPLE=aarch64-linux-gnu
# pcsx_rearmed is C only; CXX is passed for completeness but never invoked, so g++ is not required.
for t in $TRIPLE-gcc $TRIPLE-ar git make; do command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 2; }; done
CXX=$TRIPLE-g++; command -v "$CXX" >/dev/null || CXX=$TRIPLE-gcc  # fallback; no C++ is compiled

git clone https://github.com/libretro/pcsx_rearmed.git "$WORK/src"
git -C "$WORK/src" checkout -q "$PIN"
git -C "$WORK/src" submodule update --init --recursive --depth 1
make -C "$WORK/src" -f Makefile.libretro \
  CC=$TRIPLE-gcc CXX=$CXX AS=$TRIPLE-as AR=$TRIPLE-ar \
  platform=unix -j"$(nproc)"

SO="$WORK/src/pcsx_rearmed_libretro.so"
[ -f "$SO" ] || { echo "build produced no .so" >&2; exit 1; }
# Sanity: must be an aarch64 shared object exporting the libretro API.
# (Use grep -c, not grep -q: under `set -o pipefail`, grep -q exits early and SIGPIPEs the producer,
#  which would make the pipeline fail even on success.)
[ "$(file -b "$SO" | grep -c 'ARM aarch64')" -ge 1 ] || { echo "not aarch64" >&2; exit 1; }
[ "$($TRIPLE-nm -D "$SO" | grep -c '\<retro_api_version\>')" -ge 1 ] || { echo "no libretro API" >&2; exit 1; }
"$TRIPLE-strip" --strip-unneeded "$SO" -o "$OUT/pcsx_rearmed_libretro.so"
sha256sum "$OUT/pcsx_rearmed_libretro.so" | tee "$OUT/pcsx_rearmed_libretro.so.sha256"
echo "pcsx_rearmed core: $OUT/pcsx_rearmed_libretro.so (pinned $PIN)"
