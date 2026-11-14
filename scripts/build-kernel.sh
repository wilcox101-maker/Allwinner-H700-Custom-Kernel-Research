#!/usr/bin/env bash
# Configure, cross-build and package the RG34XX-SP kernel as Debian packages for Ubuntu 24.04.
#
# Run scripts/workbench.sh first: it prepares $WORK/linux (pinned Linux + patches/linux + dts/).
# This script then:
#   1. builds a config: arm64 defconfig + every other ARCH_* platform off + config/rg34xxsp.config
#   2. checks it: every line of the fragment holds in the final .config, and every enabled node
#      of the three RG34XX-SP DTBs has its driver enabled (tools/dt_driver_coverage.py)
#   3. with --build: make bindeb-pkg, then reports Image, modules and .deb sizes
# Nothing here touches a device, a card or a disk image. The packages are NOT booted.
#
# Usage:  scripts/build-kernel.sh [--build] [--jobs N]
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
JOBS=$(nproc)
LOCALVERSION=-rg34xxsp
PKGREL=${PKGREL:-1}   # Debian revision; bump for a rebuild of the same kernel version

while [ $# -gt 0 ]; do
	case "$1" in
	--build) BUILD=1 ;;
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
MAKE=(make -s -C "$LINUX" O="$OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
      LOCALVERSION="$LOCALVERSION" -j"$JOBS")

log "1. Config"
mkdir -p "$OUT"
"${MAKE[@]}" defconfig >/dev/null
# Every arm64 platform except ARCH_SUNXI off. Generated from the tree, so it follows new versions.
grep -E '^config ARCH_' "$LINUX/arch/arm64/Kconfig.platforms" | awk '{print $2}' |
	grep -vx ARCH_SUNXI | sed 's/.*/# CONFIG_& is not set/' >"$OUT/platforms-off.config"
echo "  $(wc -l <"$OUT/platforms-off.config") other platforms turned off"
(cd "$LINUX" && KCONFIG_CONFIG="$OUT/.config" ARCH=arm64 \
	scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" \
	"$OUT/platforms-off.config" "$REPO/config/rg34xxsp.config" >/dev/null)
"${MAKE[@]}" olddefconfig >/dev/null

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
done <"$REPO/config/rg34xxsp.config"
[ "$bad" = 0 ] || fail "config fragment did not apply cleanly"
echo "  all $(grep -c -E '^(CONFIG_|# CONFIG_)' "$REPO/config/rg34xxsp.config") fragment lines hold"

log "2b. Every enabled DT node has its driver"
"${MAKE[@]}" dtbs >/dev/null
for d in sun50i-h700-anbernic-rg34xx-sp sun50i-h700-anbernic-rg34xx-sp-redux \
	 sun50i-h700-anbernic-rg34xx-sp-reduxstock; do
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
printf '  package          %s\n' "$(basename "$deb")"
printf '  .deb file        %.1f MB\n' "$(echo "$(stat -c %s "$deb") / 1048576" | bc -l)"
printf '  installed size   %.1f MB\n' "$(echo "$(dpkg-deb -f "$deb" Installed-Size) / 1024" | bc -l)"
dpkg-deb -c "$deb" | awk '
	/\/boot\/vmlinuz-/ { printf "  vmlinuz          %.1f MB\n", $3 / 1048576 }
	/\.ko(\.[a-z]+)?$/ { n++; m += $3 }
	/rg34xx-sp.*\.dtb$/ { d++ }
	END { printf "  modules          %d files, %.1f MB\n  RG34XX-SP DTBs   %d\n", n, m / 1048576, d }'
log "Done. Packages are in $WORK. NOT booted: install only on a spare card, after K3/K4."
