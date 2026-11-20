#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Configure, cross-build and package the RG34XX-SP kernel as Debian packages for Ubuntu 24.04.
#
# Run scripts/workbench.sh first: it prepares $WORK/linux (pinned Linux + patches/linux + dts/).
# This script then:
#   1. builds a config: arm64 defconfig + every other ARCH_* platform off + config/rg34xxsp.config,
#      then turns off every module that is not on the allowlist (config/module-keep.txt, task R17)
#   2. checks it: every line of the fragment holds in the final .config, the boot path (SD slot 1
#      and serial console) is built in so no initramfs is needed (tools/boot_path.py), and every
#      enabled node of the RG34XX-SP DTBs has its driver enabled (tools/dt_driver_coverage.py)
#   3. with --build: make bindeb-pkg, then reports Image, modules and .deb sizes
# Nothing here touches a device, a card or a disk image. The packages are NOT booted.
#
# Usage:  scripts/build-kernel.sh [--build] [--no-trim] [--display] [--fragment F]... [--jobs N]
#   --display  the tree has the display layer (workbench.sh --display): merge
#              config/rg34xxsp-display.config and check the panel trees too
#   --fragment F  merge one more config fragment after the others (repeatable; for trials
#              such as config/rg34xxsp-builtin-trim.config); every line must hold
#   WORK=<dir>  same work directory as workbench.sh (default ./.work)
#   PKGREL=<n>  Debian revision of the packages (default 1)
# Needs (Ubuntu): the workbench tools plus dpkg-dev fakeroot rsync kmod cpio debhelper
#                 libdw-dev libelf-dev libssl-dev

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${WORK:-$REPO/.work}
LINUX=$WORK/linux
OUT=$WORK/kbuild-deb
DTS=arch/arm64/boot/dts/allwinner
BUILD=0
TRIM=1
DISPLAY=0
EXTRA=()
JOBS=$(nproc)
LOCALVERSION=-rg34xxsp
PKGREL=${PKGREL:-1}   # Debian revision; bump for a rebuild of the same kernel version

while [ $# -gt 0 ]; do
	case "$1" in
	--build) BUILD=1 ;;
	--no-trim) TRIM=0 ;;
	--display) DISPLAY=1 ;;
	--fragment) [ -f "${2:-}" ] || { echo "--fragment: no file ${2:-}" >&2; exit 2; }
		EXTRA+=("$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"); shift ;;
	--jobs) JOBS=$2; shift ;;
	-h|--help) sed -n '2,15p' "$0"; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

log() { printf '\n== %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -d "$LINUX/.git" ] || fail "no $LINUX: run scripts/workbench.sh first"
[ "$(git -C "$LINUX" rev-parse --abbrev-ref HEAD)" = workbench ] ||
	fail "$LINUX is not on the workbench branch: run scripts/workbench.sh first"
# Reproducible build (Documentation/kbuild/reproducible-builds.rst): fixed timestamp, user, host
# and build number, and no absolute build paths in debug info. The timestamp is the commit date of
# the last change to the kernel inputs, so a docs-only commit does not change the kernel's bytes.
SOURCE_DATE_EPOCH=$(git -C "$REPO" log -1 --format=%ct -- patches/linux patches/upstream patches/linux-display dts config \
	scripts/build-kernel.sh tools/gen_trim_config.py tools/dt_driver_coverage.py \
	tools/dt_driver_coverage.ignore)
[ -n "$SOURCE_DATE_EPOCH" ] || fail "cannot date the kernel inputs from git (is $REPO a clone?)"
export SOURCE_DATE_EPOCH
KBUILD_BUILD_TIMESTAMP=$(LC_ALL=C date -u -d "@$SOURCE_DATE_EPOCH")   # shown in /proc/version
export KBUILD_BUILD_TIMESTAMP
export KBUILD_BUILD_USER=rg34xxsp KBUILD_BUILD_HOST=allwinner-h700-research
export KBUILD_BUILD_VERSION=${PKGREL}
PREFIX_MAP="-fdebug-prefix-map=$LINUX=/usr/src/linux -fdebug-prefix-map=$OUT=/usr/src/linux-build"
FRAGMENTS=("$REPO/config/rg34xxsp.config")
if [ "$DISPLAY" = 1 ]; then
	grep -q 'anbernic,rg34xx-sp-panel' "$LINUX/drivers/gpu/drm/panel/panel-newvision-nv3052c.c" ||
		fail "--display, but $LINUX has no display layer: run scripts/workbench.sh --display first"
	FRAGMENTS+=("$REPO/config/rg34xxsp-display.config")
fi
FRAGMENTS+=("${EXTRA[@]}")
MAKE=(make -s -C "$LINUX" O="$OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
      LOCALVERSION="$LOCALVERSION" KCFLAGS="$PREFIX_MAP" KAFLAGS="$PREFIX_MAP" -j"$JOBS")

log "1. Config"
mkdir -p "$OUT"
"${MAKE[@]}" defconfig >/dev/null
# Every arm64 platform except ARCH_SUNXI off. Generated from the tree, so it follows new versions.
grep -E '^config ARCH_' "$LINUX/arch/arm64/Kconfig.platforms" | awk '{print $2}' |
	grep -vx ARCH_SUNXI | sed 's/.*/# CONFIG_& is not set/' >"$OUT/platforms-off.config"
echo "  $(wc -l <"$OUT/platforms-off.config") other platforms turned off"
(cd "$LINUX" && KCONFIG_CONFIG="$OUT/.config" ARCH=arm64 \
	scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" \
	"$OUT/platforms-off.config" "${FRAGMENTS[@]}" >/dev/null)
"${MAKE[@]}" olddefconfig >/dev/null
cp "$OUT/.config" "$OUT/base.config"
"${MAKE[@]}" dtbs >/dev/null
BOARD_DTBS=(sun50i-h700-anbernic-rg34xx-sp sun50i-h700-anbernic-rg34xx-sp-redux
	    sun50i-h700-anbernic-rg34xx-sp-reduxstock)
[ "$DISPLAY" = 1 ] && BOARD_DTBS+=(sun50i-h700-anbernic-rg34xx-sp-redux-panel
					 sun50i-h700-anbernic-rg34xx-sp-redux-v2-panel)

if [ "$TRIM" = 1 ]; then
	log "1b. Module trim (allowlist: config/module-keep.txt)"
	: >"$OUT/board-symbols.txt"
	for d in "${BOARD_DTBS[@]}"; do
		python3 -I "$REPO/tools/dt_driver_coverage.py" "$LINUX" "$OUT/$DTS/$d.dtb" --symbols \
			--ignore "$REPO/tools/dt_driver_coverage.ignore" >>"$OUT/board-symbols.txt"
	done
	KEEPFROM=()
	for f in "${FRAGMENTS[@]}"; do KEEPFROM+=(--keep-from "$f"); done
	python3 -I "$REPO/tools/gen_trim_config.py" "$OUT/base.config" "$REPO/config/module-keep.txt" \
		"${KEEPFROM[@]}" --keep-from "$OUT/board-symbols.txt" \
		>"$OUT/trim.config" 2>"$OUT/trim.summary"
	(cd "$LINUX" && KCONFIG_CONFIG="$OUT/.config" ARCH=arm64 \
		scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/base.config" "$OUT/trim.config" \
		>/dev/null)
	"${MAKE[@]}" olddefconfig >/dev/null
	echo "  $(cat "$OUT/trim.summary")"
	# Compare base, trim list and result: what select brought back, and any kept module lost.
	python3 -I - "$OUT/base.config" "$OUT/trim.config" "$OUT/.config" "$LINUX" <<'PY' || fail "kept modules were lost by the trim (a dependency was turned off; see above)"
import re, sys
def vals(p):
    d = {}
    for l in open(p):
        m = re.match(r'CONFIG_(\w+)=(.*)', l)
        if m: d[m.group(1)] = m.group(2)
    return d
base, final = vals(sys.argv[1]), vals(sys.argv[3])
off = set(re.findall(r'# CONFIG_(\w+) is not set', open(sys.argv[2]).read()))
back = sorted(s for s in off if final.get(s) in ('y', 'm'))
gone = [s for s, v in base.items() if v == 'm' and s not in off and final.get(s) not in ('y', 'm')]
# Helpers with no prompt exist only while something selects them: losing those is expected.
# A lost option WITH a prompt means one of its dependencies was turned off: that is a failure.
import os
prompted = set()
for root, _, files in os.walk(sys.argv[4]):
    if '/.git' in root:
        continue
    for f in files:
        if not f.startswith('Kconfig'):
            continue
        cur = None
        for l in open(os.path.join(root, f), errors='ignore'):
            m = re.match(r'\s*(?:menu)?config\s+(\w+)', l)
            if m:
                cur = m.group(1)
            elif cur and re.match(r'\s*(bool|tristate|prompt)\s+"', l):
                prompted.add(cur)
lost = sorted(s for s in gone if s in prompted)
helpers = sorted(s for s in gone if s not in prompted)
print('  selected back by kept options:', ' '.join(back) or 'none')
print('  helpers no longer selected by anything:', ' '.join(helpers) or 'none')
if lost:
    print('  LOST:', ' '.join(lost))
    sys.exit(1)
PY
	printf '  modules: %s before, %s after\n' "$(grep -c '=m$' "$OUT/base.config")" \
		"$(grep -c '=m$' "$OUT/.config")"
fi

log "2a. Every fragment line holds"
bad=0
while IFS= read -r line; do
	case "$line" in
	CONFIG_*=*) want=$line; sym=${line%%=*} ;;
	'# CONFIG_'*' is not set') sym=${line#\# }; sym=${sym%% *}; want="# $sym is not set" ;;
	*) continue ;;
	esac
	have=$(grep -E "^($sym=|# $sym is not set)" "$OUT/.config" || true)
	# An option that is off may also be absent (its dependencies are off): that counts as off.
	if [ "$have" != "$want" ] && ! { [ -z "$have" ] && [ "${want#\# }" != "$want" ]; }; then
		printf '  wanted %-40s got %s\n' "$want" "${have:-(absent)}"
		bad=1
	fi
done < <(cat "${FRAGMENTS[@]}")
[ "$bad" = 0 ] || fail "config fragment did not apply cleanly"
echo "  all $(cat "${FRAGMENTS[@]}" | grep -c -E '^(CONFIG_|# CONFIG_)') fragment lines hold"

log "2a2. Boot path built in: SD card slot 1 (mmc0) and the serial console, no initramfs needed"
python3 -I "$REPO/tools/boot_path.py" "$LINUX" "$OUT/$DTS/sun50i-h700-anbernic-rg34xx-sp-redux.dtb" \
	--config "$OUT/.config" /soc/mmc@4020000 serial0 >"$OUT/boot-path.tsv" ||
	{ grep -vP '\t(y|always|.*optional.*)\t' "$OUT/boot-path.tsv"; fail "boot path has modules"; }
for s in MMC_BLOCK EXT4_FS MSDOS_PARTITION DEVTMPFS DEVTMPFS_MOUNT; do
	grep -qx "CONFIG_$s=y" "$OUT/.config" || fail "boot path: CONFIG_$s is not built in"
done
echo "  $(wc -l <"$OUT/boot-path.tsv") boot-path drivers, all built in (+ MMC_BLOCK EXT4_FS MSDOS_PARTITION DEVTMPFS)"

log "2b. Every enabled DT node has its driver"
for d in "${BOARD_DTBS[@]}"; do
	res=$(python3 -I "$REPO/tools/dt_driver_coverage.py" "$LINUX" "$OUT/$DTS/$d.dtb" \
		--config "$OUT/.config" --ignore "$REPO/tools/dt_driver_coverage.ignore") ||
		{ printf '%s\n' "$res" | grep -E 'MISSING|NO DRIVER'; fail "$d: driver coverage"; }
	echo "  $d: $(printf '%s\n' "$res" | tail -1)"
done

if [ "$BUILD" = 0 ]; then
	log "Config checks passed (no build requested; add --build)."
	exit 0
fi

log "3. bindeb-pkg ($JOBS jobs)"
start=$(date +%s)
# Package version from the kernel version alone ("7.4.0-rc2" -> "7.4.0~rc2-1"), so it never
# carries a hash of the local patch commits. No linux-headers package: nothing here builds
# out-of-tree modules (DKMS).
kver=$("${MAKE[@]}" kernelversion)
DEB_BUILD_PROFILES=pkg.linux-upstream.nokernelheaders \
	"${MAKE[@]}" KDEB_PKGVERSION="${kver//-/\~}-$PKGREL" bindeb-pkg >"$WORK/bindeb-pkg.log" 2>&1 ||
	{ tail -40 "$WORK/bindeb-pkg.log"; fail "bindeb-pkg failed (log: $WORK/bindeb-pkg.log)"; }
echo "  built in $(( ($(date +%s) - start) / 60 )) min"

log "4. Sizes (what the image package installs)"
krel=$(cat "$OUT/include/config/kernel.release")
deb=$(ls "$WORK"/linux-image-"$krel"_*.deb)
printf '  kernel release   %s\n' "$krel"
printf '  compiler         %s\n' "$(aarch64-linux-gnu-gcc --version | head -1)"
printf '  source date      %s (SOURCE_DATE_EPOCH %s)\n' "$(date -u -d "@$SOURCE_DATE_EPOCH" +%F)" "$SOURCE_DATE_EPOCH"
printf '  package          %s\n' "$(basename "$deb")"
printf '  .deb file        %.1f MB\n' "$(echo "$(stat -c %s "$deb") / 1048576" | bc -l)"
printf '  installed size   %.1f MB\n' "$(echo "$(dpkg-deb -f "$deb" Installed-Size) / 1024" | bc -l)"
dpkg-deb -c "$deb" | awk '
	/\/boot\/vmlinuz-/ { printf "  vmlinuz          %.1f MB\n", $3 / 1048576 }
	/\.ko(\.[a-z]+)?$/ { n++; m += $3 }
	/rg34xx-sp.*\.dtb$/ { d++ }
	END { printf "  modules          %d files, %.1f MB\n  RG34XX-SP DTBs   %d\n", n, m / 1048576, d }'
log "Done. Packages are in $WORK. NOT booted: install only on a spare card, after K3/K4."
