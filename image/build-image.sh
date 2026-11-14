#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# R7 prototype: build a ReduxOS card image for the Anbernic RG34XX-SP: Ubuntu 24.04 (noble) arm64
# packages plus our kernel and boot setup. Named ReduxOS, not Ubuntu (Q7; R9 §2).
#
#   mmdebstrap (rootfs from image/packages.txt)  ->  chroot stage (kernel .deb, overlays, extlinux
#   via u-boot-menu)  ->  genimage (MBR: u-boot @ 8 KiB, FAT32 /boot @ 16 MiB, ext4 root)
#
# usage: sudo [KERNEL_DEB=linux-image-…rg34xxsp….deb | KERNEL=ubuntu] [UBOOT_BIN=u-boot-sunxi-with-spl.bin]
#             [SOURCE_DATE_EPOCH=…] [OUT=out] image/build-image.sh
#   KERNEL_DEB  our kernel package (KR R10/R17). Default if neither is given: error.
#   KERNEL=ubuntu  Ubuntu's linux-image-6.8.0-149-generic + modules-extra + initramfs, for QEMU tests only.
#   UBOOT_BIN   SPL+u-boot for the board's DRAM type (R1/R3). Without it the image has NO bootloader
#               and can only be tested in QEMU.
#   PANEL_FW    directory holding panels/<compatible>.panel made by tools/gen_panel_firmware.py from
#               YOUR OWN stock image (R19 option b). Copied to /usr/lib/firmware/panels; the image is
#               named -private and must not be published (R9: stock-derived data).
# Writes only under $OUT. It never touches a block device: writing the image to a card is a separate,
# deliberate step (see docs/r7-image-tooling.md). Publishing it needs the source bundle from
# image/release-sources.sh (R9). Needs: mmdebstrap genimage dosfstools mtools e2fsprogs
# qemu-user-static + binfmt (non-arm64 hosts), rsync.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
OUT=${OUT:-$PWD/out}; MIRROR=${MIRROR:-https://ports.ubuntu.com/ubuntu-ports}
SUITE=noble; DISK_SIG=${DISK_SIG:-0x48373030}          # "H700": fixed so PARTUUIDs are reproducible
BOOT_MB=${BOOT_MB:-256}
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$REPO" log -1 --format=%ct 2>/dev/null || date +%s)}
[ "$(id -u)" = 0 ] || { echo "run as root (mmdebstrap root mode, chroot, genimage)" >&2; exit 1; }
if [ -n "${KERNEL_DEB:-}" ]; then KMODE=deb; KERNEL_DEB=$(readlink -f "$KERNEL_DEB")
elif [ "${KERNEL:-}" = ubuntu ]; then KMODE=ubuntu
else echo "set KERNEL_DEB=<our kernel .deb> or KERNEL=ubuntu (QEMU only)" >&2; exit 2; fi
STAMP=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%d)
NAME=reduxos-rg34xxsp-noble-$STAMP-$KMODE${UBOOT_BIN:+-uboot}${PANEL_FW:+-private}
if [ -n "${PANEL_FW:-}" ]; then
	PANEL_FW=$(readlink -f "$PANEL_FW")
	ls "$PANEL_FW"/panels/*.panel >/dev/null 2>&1 || { echo "PANEL_FW=$PANEL_FW has no panels/*.panel" >&2; exit 2; }
fi
ROOT="root=PARTUUID=$(printf '%08x' $((DISK_SIG)))-02"
log() { printf '== %s\n' "$*"; }

# a failed earlier run can leave the /boot tmpfs (and mmdebstrap mounts) behind
awk -v r="$OUT/rootfs/" 'index($2, r) == 1 {print $2}' /proc/mounts | sort -r | while read -r m; do umount -l "$m"; done
rm -rf "$OUT/rootfs" "$OUT/tmp" "$OUT/genimage"; mkdir -p "$OUT/rootfs" "$OUT/tmp" "$OUT/genimage"
PKGS=$(grep -v '^\s*#' "$HERE/packages.txt" | grep . | paste -sd,)
[ "$KMODE" = ubuntu ] && PKGS="$PKGS,initramfs-tools,linux-image-6.8.0-149-generic,linux-modules-extra-6.8.0-149-generic"

log "1. rootfs ($SUITE, $(echo "$PKGS" | tr , '\n' | wc -l) packages requested, kernel: $KMODE)"
# /boot is mounted from a separate tmpfs while packages install, so u-boot-menu sees a separate
# /boot (as on the card) and writes FAT-relative paths; its content becomes the FAT partition.
mmdebstrap --variant=minbase --arch=arm64 --components=main,universe \
  --include="$PKGS" \
  --aptopt='APT::Install-Recommends "false"' \
  --dpkgopt='path-exclude=/usr/share/doc/*' --dpkgopt='path-include=/usr/share/doc/*/copyright' \
  --dpkgopt='path-exclude=/usr/share/man/*' --dpkgopt='path-exclude=/usr/share/locale/*' \
  --dpkgopt='path-include=/usr/share/locale/locale.alias' \
  --dpkgopt='force-confdef' --dpkgopt='force-confold' \
  --setup-hook='mkdir -p "$1/boot" && mount -t tmpfs -o size=512m h700boot "$1/boot"' \
  --setup-hook='mkdir -p "$1/etc/kernel" && printf "do_symlinks = no\n" > "$1/etc/kernel-img.conf"' \
  --setup-hook='mkdir -p "$1/etc/initramfs-tools/conf.d" && echo MODULES=list > "$1/etc/initramfs-tools/conf.d/h700.conf" && printf "virtio_blk\nvirtio_pci\next4\n" > "$1/etc/initramfs-tools/modules"' \
  --setup-hook="mkdir -p \"\$1/etc/default\" && sed 's|@ROOT@|$ROOT|' '$HERE/overlay/etc/default/u-boot' > \"\$1/etc/default/u-boot\"" \
  --customize-hook="cp -a '$REPO/config/rootfs/.' '$HERE/overlay/.' \"\$1/\" && sed -i 's|@ROOT@|$ROOT|' \"\$1/etc/default/u-boot\"" \
  --customize-hook='[ -z "'"${KERNEL_DEB:-}"'" ] || { cp "'"${KERNEL_DEB:-/dev/null}"'" "$1/tmp/kernel.deb" && chroot "$1" dpkg -i /tmp/kernel.deb && rm -f "$1/tmp/kernel.deb"; }' \
  --customize-hook='chroot "$1" u-boot-update' \
  --customize-hook='echo rg34xxsp > "$1/etc/hostname"; printf "127.0.1.1\trg34xxsp\n" >> "$1/etc/hosts"' \
  --customize-hook='printf "LABEL=rootfs\t/\text4\tdefaults,noatime\t0\t1\nLABEL=BOOT\t/boot\tvfat\tdefaults,noatime,umask=0077\t0\t2\n" > "$1/etc/fstab"' \
  --customize-hook='printf "[Match]\nName=en* eth*\n[Network]\nDHCP=yes\n" > "$1/etc/systemd/network/20-wired.network"; mkdir -p "$1/etc/iwd"; printf "[General]\nEnableNetworkConfiguration=true\n[Network]\nNameResolvingService=systemd\n" > "$1/etc/iwd/main.conf"' \
  --customize-hook='chroot "$1" systemctl enable systemd-networkd iwd earlyoom h700-firstboot.service h700-boot-ok.service' \
  --customize-hook='chroot "$1" systemctl disable motd-news.timer e2scrub_all.timer e2scrub_reap.service 2>/dev/null || true' \
  --customize-hook='G=$(for g in sudo video render input audio; do chroot "$1" getent group $g >/dev/null && printf "%s," $g; done); chroot "$1" useradd -m -s /bin/bash -G "${G%,}" dale && echo dale:redux | chroot "$1" chpasswd && chroot "$1" passwd -e dale' \
  --customize-hook='rm -f "$1"/etc/ssh/ssh_host_* "$1/var/lib/dbus/machine-id"' \
  --customize-hook='chroot "$1" dpkg-query -W -f="\${Package}\t\${Version}\t\${Installed-Size}\n" > "$1/root/manifest.tsv"' \
  --customize-hook='mkdir -p "'"$OUT/tmp/boot"'" && cp -a "$1/boot/." "'"$OUT/tmp/boot"'/" && umount "$1/boot"' \
  "$SUITE" "$OUT/rootfs" \
  "deb $MIRROR $SUITE main universe" "deb $MIRROR $SUITE-updates main universe" "deb $MIRROR $SUITE-security main universe"

log "2. stage /boot content into the rootfs tree for genimage"
# mmdebstrap empties /etc/machine-id at the end; systemd only runs ConditionFirstBoot= units when it
# reads "uninitialized" (or the file is missing), so set it after mmdebstrap.
echo uninitialized > "$OUT/rootfs/etc/machine-id"
rm -rf "$OUT/rootfs/boot"; mkdir -p "$OUT/rootfs/boot"; cp -a "$OUT/tmp/boot/." "$OUT/rootfs/boot/"
cp "$OUT/rootfs/root/manifest.tsv" "$OUT/$NAME.manifest.tsv"
# Our identity file. /etc/os-release stays as Ubuntu's base-files ships it (unmodified package, R9 §2).
printf 'NAME="ReduxOS"\nID=reduxos\nBUILD_ID=%s\nIMAGE_ID=%s\nBASE="Ubuntu 24.04 LTS (noble) packages"\nHOME_URL="https://github.com/wilcox101-maker/Allwinner-H700-Custom-Kernel-Research"\n' \
	"$STAMP" "$NAME" > "$OUT/rootfs/etc/reduxos-release"
if [ -n "${PANEL_FW:-}" ]; then          # private image only (see PANEL_FW above)
	install -d "$OUT/rootfs/usr/lib/firmware/panels"
	install -m 0644 "$PANEL_FW"/panels/*.panel "$OUT/rootfs/usr/lib/firmware/panels/"
fi
# R9: source package list for image/release-sources.sh, then the licence checks (fail = no image)
dpkg-query --admindir="$OUT/rootfs/var/lib/dpkg" -W -f='${source:Package}\t${source:Version}\n' | LC_ALL=C sort -u > "$OUT/$NAME.sources.tsv"
PRIVATE=${PANEL_FW:+1} "$HERE/check-licences.sh" "$OUT/rootfs"
ROOT_KB=$(du -sxk --exclude=./boot "$OUT/rootfs" | cut -f1)
ROOT_MB=$(( ROOT_KB / 1024 * 120 / 100 + 64 ))           # content + 20 % + 64 MiB; grown on first boot
log "   root content $((ROOT_KB / 1024)) MiB -> partition $ROOT_MB MiB; /boot $(du -sm "$OUT/rootfs/boot" | cut -f1) MiB of $BOOT_MB"

log "3. genimage"
UBOOT_PART=""
if [ -n "${UBOOT_BIN:-}" ]; then
	cp "$UBOOT_BIN" "$OUT/genimage/u-boot-sunxi-with-spl.bin"
	UBOOT_PART=$'\tpartition u-boot {\n\t\tin-partition-table = false\n\t\timage = "u-boot-sunxi-with-spl.bin"\n\t\toffset = 8K\n\t\tsize = 1016K\n\t}'
fi
sed -e "s|@BOOT_MB@|$BOOT_MB|" -e "s|@ROOT_MB@|$ROOT_MB|" -e "s|@IMAGE@|$NAME.img|" -e "s|@DISK_SIG@|$DISK_SIG|" \
    "$HERE/genimage.cfg.in" | awk -v u="$UBOOT_PART" '{ if ($0 == "@UBOOT_PART@") { if (u != "") print u } else print }' \
    > "$OUT/genimage.cfg"
genimage --config "$OUT/genimage.cfg" --rootpath "$OUT/rootfs" --tmppath "$OUT/genimage/tmp" \
         --inputpath "$OUT/genimage" --outputpath "$OUT/genimage" >"$OUT/genimage.log" 2>&1 \
  || { tail -20 "$OUT/genimage.log"; exit 1; }
mv "$OUT/genimage/$NAME.img" "$OUT/"
(cd "$OUT" && sha256sum "$NAME.img" > "$NAME.img.sha256")
log "done: $OUT/$NAME.img ($(du -h --apparent-size "$OUT/$NAME.img" | cut -f1)); $ROOT"
if [ -n "${PANEL_FW:-}" ]; then log "PRIVATE image (stock-derived panel firmware): for your own devices only, do not publish"
else log "before publishing: image/release-sources.sh $OUT/$NAME.sources.tsv (R9: the image's source bundle)"; fi
