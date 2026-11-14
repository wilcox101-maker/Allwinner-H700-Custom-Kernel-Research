#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# usage: mkimg.sh ROOTFS.tar NAME  -> NAME.img (ext4, 2 GiB), NAME.vmlinuz, NAME.initrd, NAME.sizes
# Extracts as root to preserve ownership. Writes only NAME.* in the current directory.
set -euo pipefail
TAR=$1; N=$2; D=$(mktemp -d)
tar -C "$D" -xpf "$TAR"
{ echo "total_MB $(du -sxm "$D" | cut -f1)"
  echo "boot_MB $(du -sm "$D/boot" | cut -f1)"
  echo "modules_MB $(du -sm "$D"/usr/lib/modules | cut -f1)"
  echo "firmware_MB $(du -sm "$D"/usr/lib/firmware 2>/dev/null | cut -f1)"
  echo "userspace_MB $(( $(du -sxm "$D" | cut -f1) - $(du -sm "$D/boot" | cut -f1) - $(du -sm "$D"/usr/lib/modules | cut -f1) ))"
  echo "packages $(wc -l < "$D/root/r5-packages.txt")"
  echo "python_MB $(du -scm "$D"/usr/lib/python3* "$D"/usr/bin/python3* 2>/dev/null | tail -1 | cut -f1)"
  echo "apt_lists_MB $(du -sm "$D/var/lib/apt/lists" | cut -f1)"
} > "$N.sizes"
cp "$D"/boot/vmlinuz-* "$N.vmlinuz"; cp "$D"/boot/initrd.img-* "$N.initrd"
rm -f "$N.img"; truncate -s 2G "$N.img"; mkfs.ext4 -q -F -L rootfs -d "$D" "$N.img"
rm -rf "$D"; cat "$N.sizes"
