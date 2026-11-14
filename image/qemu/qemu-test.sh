#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# usage: sudo qemu-test.sh IMAGE.img [MB] -> IMAGE.qemu-<MB>.log
# Boots a COPY of the image in QEMU (virt, Cortex-A53), kernel/initrd taken from its FAT partition,
# root from its partition 2 by PARTUUID. The copy is enlarged to 3 GiB to exercise first-boot growth,
# and gets r7-check injected (debugfs) so it reports and powers off. The original image is not changed.
set -euo pipefail
IMG=$(readlink -f "$1"); MB=${2:-1024}; HERE=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp --reflink=auto "$IMG" "$W/disk.img"; truncate -s 3G "$W/disk.img"
read -r P1 P2 < <(sfdisk -d "$W/disk.img" | awk -F'start= *' '/start=/{split($2,a,",");printf "%s ", a[1]} END{print ""}')
mcopy -n -i "$W/disk.img@@$((P1*512))" ::/vmlinuz "$W/vmlinuz" 2>/dev/null || \
  mcopy -n -i "$W/disk.img@@$((P1*512))" "::/$(mdir -b -i "$W/disk.img@@$((P1*512))" :: | grep -m1 '/vmlinuz-' | sed 's|.*/||')" "$W/vmlinuz"
INITRD=(); if mcopy -n -i "$W/disk.img@@$((P1*512))" ::/initrd.img "$W/initrd" 2>/dev/null; then INITRD=(-initrd "$W/initrd"); fi
P2END=$(sfdisk -d "$W/disk.img" | awk -F'size= *' '/img2/{split($2,a,",");print a[1]}')
dd if="$W/disk.img" of="$W/p2" bs=512 skip="$P2" count="$P2END" status=none
debugfs -w -R "write $HERE/r7-check /usr/local/sbin/r7-check" "$W/p2" >/dev/null 2>&1
debugfs -w -R "sif /usr/local/sbin/r7-check mode 0100755" "$W/p2" >/dev/null 2>&1
printf '[Unit]\nAfter=multi-user.target\n[Service]\nType=simple\nExecStart=/usr/local/sbin/r7-check\nStandardOutput=journal+console\n[Install]\nWantedBy=multi-user.target\n' > "$W/r7-check.service"
debugfs -w -R "write $W/r7-check.service /etc/systemd/system/r7-check.service" "$W/p2" >/dev/null 2>&1
debugfs -w -R "symlink /etc/systemd/system/multi-user.target.wants/r7-check.service /etc/systemd/system/r7-check.service" "$W/p2" >/dev/null 2>&1
dd if="$W/p2" of="$W/disk.img" bs=512 seek="$P2" conv=notrunc status=none
APPEND=$(mtype -i "$W/disk.img@@$((P1*512))" ::/extlinux/extlinux.conf | awk '/^[ \t]*append/{sub(/^[ \t]*append /,""); print; exit}' | sed 's/console=ttyS0,115200/console=ttyAMA0/; s/ quiet//')
OUTLOG="${IMG%.img}.qemu-$MB.log"
timeout 2400 qemu-system-aarch64 -M virt -cpu cortex-a53 -smp 4 -m "$MB" -nographic -no-reboot \
  -kernel "$W/vmlinuz" "${INITRD[@]}" -append "$APPEND" \
  -drive "file=$W/disk.img,format=raw,if=none,id=hd0" -device virtio-blk-device,drive=hd0 \
  -netdev user,id=n0 -device virtio-net-device,netdev=n0 > "$OUTLOG" 2>&1 || true
echo "log: $OUTLOG"
