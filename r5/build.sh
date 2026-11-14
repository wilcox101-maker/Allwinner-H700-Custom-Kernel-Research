#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# R5: minimal Ubuntu 24.04 (noble) rootfs for H700 sizing, built with mmdebstrap.
# usage: [ARCH=arm64] [MIRROR=...] [NET=nm|iwd] [KVER=6.8.0-149-generic] ./build.sh OUT.tar
#  NET=nm  : NetworkManager + wpasupplicant (Ubuntu default stack; pulls netplan + Python)
#  NET=iwd : iwd + systemd-networkd + systemd-resolved (no Python)
#  KVER    : distro kernel for QEMU only (linux-image-$KVER + linux-modules-extra-$KVER).
#            The linux-image-generic metapackage is NOT used: it depends on the
#            linux-firmware metapackage (~470 MB). Set KVER= (empty) for a kernel-less rootfs.
# Untested on hardware; QEMU sizing only. Writes only to OUT.tar.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ARCH=${ARCH:-arm64}; MIRROR=${MIRROR:-https://ports.ubuntu.com/ubuntu-ports}
NET=${NET:-nm}; KVER=${KVER-6.8.0-149-generic}
OUT=${1:?usage: build.sh OUT.tar}
BASE="initramfs-tools,systemd-sysv,udev,dbus,kmod,iproute2,iputils-ping,wireless-regdb,openssh-server,sudo,ca-certificates,systemd-zram-generator,systemd-timesyncd,less,nano,linux-firmware-realtek"
case $NET in
  nm)  NETPKGS="network-manager,wpasupplicant"; NETHOOK='true' ;;
  iwd) NETPKGS="iwd,systemd-resolved"
       NETHOOK='mkdir -p "$1/etc/systemd/network" && printf "[Match]\nName=en* eth*\n[Network]\nDHCP=yes\n" > "$1/etc/systemd/network/20-wired.network" && printf "[General]\nEnableNetworkConfiguration=true\n[Network]\nNameResolvingService=systemd\n" > "$1/etc/iwd/main.conf" && chroot "$1" systemctl enable systemd-networkd iwd' ;;
  *) echo "NET must be nm or iwd" >&2; exit 2 ;;
esac
PKGS="$BASE,$NETPKGS"; [ -n "$KVER" ] && PKGS="$PKGS,linux-image-$KVER,linux-modules-extra-$KVER"
mmdebstrap --variant=minbase --arch="$ARCH" --components=main,universe \
  --include="$PKGS" \
  --dpkgopt='path-exclude=/usr/share/doc/*' --dpkgopt='path-include=/usr/share/doc/*/copyright' \
  --dpkgopt='path-exclude=/usr/share/man/*' --dpkgopt='path-exclude=/usr/share/locale/*' \
  --dpkgopt='path-include=/usr/share/locale/locale.alias' \
  --aptopt='APT::Install-Recommends "false"' \
  --customize-hook='echo rg34xxsp > "$1/etc/hostname"' \
  --customize-hook='chroot "$1" useradd -m -s /bin/bash -G sudo dale && echo dale:redux | chroot "$1" chpasswd' \
  --customize-hook='printf "[zram0]\nzram-size = min(ram / 2, 4096)\ncompression-algorithm = zstd\n" > "$1/etc/systemd/zram-generator.conf"' \
  --customize-hook="$NETHOOK" \
  --customize-hook="install -m755 '$HERE/r5-measure' \"\$1/usr/local/sbin/r5-measure\"; install -m644 '$HERE/measure.service' \"\$1/etc/systemd/system/\"; chroot \"\$1\" systemctl enable measure.service; echo '/dev/vda / ext4 defaults 0 1' > \"\$1/etc/fstab\"" \
  --customize-hook='chroot "$1" dpkg-query -W -f="\${Package} \${Installed-Size}\n" > "$1/root/r5-packages.txt"' \
  noble "$OUT" "deb $MIRROR noble main universe" "deb $MIRROR noble-updates main universe" "deb $MIRROR noble-security main universe"
