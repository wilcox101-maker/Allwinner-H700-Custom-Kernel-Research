#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# usage: mkimg-r13.sh ROOTFS.tar NAME -> NAME.img with config/rootfs overlaid and the R13 check enabled
# (instead of r5-measure). Writes only NAME.* in the current directory.
set -euo pipefail
TAR=$1; N=$2; HERE=$(cd "$(dirname "$0")" && pwd); D=$(mktemp -d)
tar -C "$D" -xpf "$TAR"
cp -a "$HERE/../config/rootfs/." "$D/"
# Optional userspace OOM killer: OOM=earlyoom|oomd (debs from DEBDIR), default none.
case "${OOM:-none}" in
  earlyoom) F=$(basename "$DEBDIR"/earlyoom_*.deb); cp "$DEBDIR/$F" "$D/tmp/"; chroot "$D" dpkg -i "/tmp/$F"; rm -f "$D/tmp/$F" ;;
  oomd) F=$(basename "$DEBDIR"/systemd-oomd_*.deb); cp "$DEBDIR/$F" "$D/tmp/"; chroot "$D" dpkg -i "/tmp/$F"; rm -f "$D/tmp/$F"
        mkdir -p "$D/etc/systemd/system/-.slice.d"
        printf '[Slice]\nManagedOOMSwap=kill\n' > "$D/etc/systemd/system/-.slice.d/60-h700-oomd.conf"
        chroot "$D" systemctl enable systemd-oomd.service ;;
  none) ;;
  *) echo "OOM must be none, earlyoom or oomd" >&2; exit 2 ;;
esac
install -m755 "$HERE/r13-check" "$D/usr/local/sbin/r13-check"
install -m644 "$HERE/r13-check.service" "$D/etc/systemd/system/r13-check.service"
rm -f "$D/etc/systemd/system/multi-user.target.wants/measure.service"
ln -sf /etc/systemd/system/r13-check.service "$D/etc/systemd/system/multi-user.target.wants/r13-check.service"
cp "$D"/boot/vmlinuz-* "$N.vmlinuz"; cp "$D"/boot/initrd.img-* "$N.initrd"
rm -f "$N.img"; truncate -s 2G "$N.img"; mkfs.ext4 -q -F -L rootfs -d "$D" "$N.img"; rm -rf "$D"
