#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Rebuild the kernel-research workbench and run every desk check.
#
# What it does (nothing here touches a device, a card or a disk image):
#   1. fetches torvalds/linux at the pinned snapshot into $WORK/linux
#   2. applies patches/linux/*.patch on a local branch
#   3. copies dts/* in, generates the "reduxstock" variant, adds local Makefile lines
#   4. builds and schema-checks the three RG34XX-SP DTBs (CHECK_DTBS=y): any warning fails
#   5. runs checkpatch on every patch, the xlate host test (after checking that its copy of the
#      function still matches patch 0001), and the OPP generator round trip
#   6. with --bindings, also runs dt_binding_check for the touched schemas (slow)
#
# Usage:  scripts/workbench.sh [--bindings] [--stock-dts PATH]
#   WORK=<dir>  work directory (default: ./.work, ignored by git)
#   --stock-dts PATH  Redux reference/stock-202505/board.dts; enables the generator check
#
# Needs: git, make, gcc, aarch64-linux-gnu-gcc, dtc, python3 with dtschema, yamllint, ply.
# Ubuntu: apt install gcc-aarch64-linux-gnu device-tree-compiler bc flex bison libssl-dev
#         pip install dtschema yamllint ply gitpython

set -euo pipefail

LINUX_URL=https://github.com/torvalds/linux.git
LINUX_SHA=97d73c8251226cf27cc6656b4c542869bb8c69fa   # 2026-11-13, after v7.4-rc2
LINUX_SINCE=2026-11-08                                # v7.4-rc2 date, for the shallow fallback

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${WORK:-$REPO/.work}
BINDINGS=0
STOCK_DTS=

while [ $# -gt 0 ]; do
	case "$1" in
	--bindings) BINDINGS=1 ;;
	--stock-dts) STOCK_DTS=$2; shift ;;
	-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

log() { printf '\n== %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for tool in git make gcc aarch64-linux-gnu-gcc dtc python3; do
	command -v "$tool" >/dev/null || fail "missing tool: $tool"
done

mkdir -p "$WORK"
LINUX=$WORK/linux
DTS=arch/arm64/boot/dts/allwinner
OUT=$WORK/kbuild
MAKE=(make -s -C "$LINUX" O="$OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)")

log "1. Linux at ${LINUX_SHA:0:12}"
if [ ! -d "$LINUX/.git" ]; then
	git init -q "$LINUX"
	git -C "$LINUX" remote add origin "$LINUX_URL"
fi
if ! git -C "$LINUX" cat-file -e "$LINUX_SHA^{commit}" 2>/dev/null; then
	git -C "$LINUX" fetch -q --depth 1 origin "$LINUX_SHA" 2>/dev/null ||
		git -C "$LINUX" fetch -q --shallow-since="$LINUX_SINCE" origin master
fi
git -C "$LINUX" cat-file -e "$LINUX_SHA^{commit}" || fail "could not fetch $LINUX_SHA"

log "2. Apply patches"
git -C "$LINUX" am --abort >/dev/null 2>&1 || true
git -C "$LINUX" checkout -q -f -B workbench "$LINUX_SHA"
git -C "$LINUX" clean -q -fd -- "$DTS"
git -C "$LINUX" -c user.name=workbench -c user.email=workbench@invalid \
	am -q "$REPO"/patches/linux/*.patch
git -C "$LINUX" log --oneline "$LINUX_SHA"..HEAD

log "3. Device trees (local only, not committed)"
cp "$REPO"/dts/*.dts "$REPO"/dts/*.dtsi "$LINUX/$DTS/"
{
	cat "$REPO/dts/sun50i-h700-anbernic-rg34xx-sp-redux.dts"
	printf '\n#include "sun50i-h700-redux-cpu-opp-stock.dtsi"\n'
	printf '#include "sun50i-h700-redux-stock-thermal.dtsi"\n'
} >"$LINUX/$DTS/sun50i-h700-anbernic-rg34xx-sp-reduxstock.dts"
for v in redux reduxstock; do
	line="dtb-\$(CONFIG_ARCH_SUNXI) += sun50i-h700-anbernic-rg34xx-sp-$v.dtb"
	grep -qxF "$line" "$LINUX/$DTS/Makefile" || echo "$line" >>"$LINUX/$DTS/Makefile"
done

log "4. dtbs_check (any output counts as a failure)"
"${MAKE[@]}" defconfig >/dev/null
DTBS=(sun50i-h700-anbernic-rg34xx-sp sun50i-h700-anbernic-rg34xx-sp-redux
      sun50i-h700-anbernic-rg34xx-sp-reduxstock)
targets=()
for d in "${DTBS[@]}"; do targets+=("allwinner/$d.dtb"); done
msgs=$("${MAKE[@]}" CHECK_DTBS=y "${targets[@]}" 2>&1) || fail "DTB build failed: $msgs"
if [ -n "$msgs" ]; then
	printf '%s\n' "$msgs"
	fail "dtbs_check reported problems"
fi
for d in "${DTBS[@]}"; do
	printf '  %-45s %6d bytes, 0 warnings\n' "$d.dtb" "$(stat -c %s "$OUT/$DTS/$d.dtb")"
done

log "5a. checkpatch (--no-signoff; Signed-off-by is added by a human, never by a tool)"
for p in "$REPO"/patches/linux/*.patch; do
	res=$("$LINUX/scripts/checkpatch.pl" -q --no-signoff --terse "$p" 2>&1 || true)
	# A new board .dts always draws the MAINTAINERS reminder; the directory is already covered.
	res=$(printf '%s\n' "$res" | grep -v 'does MAINTAINERS need updating' |
		grep -v -E '^total: 0 errors, [01] warnings' | grep -v -E '^\s*$' || true)
	if [ -n "$res" ]; then
		printf '%s\n' "$res"
		fail "checkpatch: $(basename "$p")"
	fi
	echo "  ok  $(basename "$p")"
done

log "5b. xlate host test"
python3 -I "$REPO/tools/check_xlate_copy.py" "$REPO"/patches/linux/0001-*.patch \
	"$REPO/tests/xlate_test.c" || fail "tests/xlate_test.c no longer matches patch 0001"
cc -Wall -Werror -o "$WORK/xlate_test" "$REPO/tests/xlate_test.c"
"$WORK/xlate_test" | tail -1

if [ -n "$STOCK_DTS" ]; then
	log "5c. OPP generator round trip"
	python3 -I "$REPO/tools/gen_cpu_opp_stock.py" "$STOCK_DTS" |
		cmp - "$REPO/dts/sun50i-h700-redux-cpu-opp-stock.dtsi" ||
		fail "generated dtsi differs from dts"
	echo "  generated dtsi matches byte for byte"
fi

if [ "$BINDINGS" = 1 ]; then
	log "6. dt_binding_check"
	for s in sound/allwinner,sun4i-a10-codec.yaml \
		 opp/allwinner,sun50i-h6-operating-points.yaml arm/sunxi.yaml; do
		# Serial make: the schema tools warn about the parallel jobserver otherwise.
		msgs=$(make -s -C "$LINUX" O="$OUT" ARCH=arm64 \
			dt_binding_check DT_SCHEMA_FILES="$s" 2>&1) || fail "dt_binding_check $s: $msgs"
		if [ -n "$msgs" ]; then
			printf '%s\n' "$msgs"
			fail "dt_binding_check reported problems in $s"
		fi
		echo "  ok  $s"
	done
fi

log "All desk checks passed. Nothing here has run on hardware."
