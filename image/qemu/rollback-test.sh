#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# R8 rollback test in QEMU with a real u-boot (qemu_arm64 + BOOTCOUNT_ENV + env on FAT; config in
# docs/r8-update-rollback.md). usage: sudo rollback-test.sh IMAGE.img UBOOT.bin [MB]
#  run 1: boots a COPY of the image normally (u-boot saves its environment on first boot)
#  then simulates a kernel update whose new default entry panics (init=/bin/false), exactly as
#  h700-kernel-fallback would leave it: extlinux.conf default = new (bad), extlinux-fallback.conf
#  default = previous (good), upgrade_available=1, bootcount=0
#  run 2: boots without -no-reboot; expected: bad entry panics and resets until bootcount > bootlimit (3),
#  then altbootcmd boots the fallback entry, h700-boot-ok clears the counter, r8-check reports.
#  run 3: a plain reboot must boot the good kernel directly (h700-boot-ok made the fallback menu default).
set -euo pipefail
IMG=$(readlink -f "$1"); UB=$(readlink -f "$2"); MB=${3:-512}; HERE=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cp --reflink=auto "$IMG" "$W/disk.img"; truncate -s 3G "$W/disk.img"
read -r P1 P2 < <(sfdisk -d "$W/disk.img" | awk -F'start= *' '/start=/{split($2,a,",");printf "%s ", a[1]} END{print ""}')
FAT="$W/disk.img@@$((P1*512))"
P2SIZE=$(sfdisk -d "$W/disk.img" | awk -F'size= *' '/img2/{split($2,a,",");print a[1]}')
dd if="$W/disk.img" of="$W/p2" bs=512 skip="$P2" count="$P2SIZE" status=none
debugfs -w -R "write $HERE/r8-check /usr/local/sbin/r8-check" "$W/p2" >/dev/null 2>&1
debugfs -w -R "sif /usr/local/sbin/r8-check mode 0100755" "$W/p2" >/dev/null 2>&1
printf '[Unit]\nAfter=multi-user.target h700-boot-ok.service\n[Service]\nType=simple\nExecStart=/usr/local/sbin/r8-check\nStandardOutput=journal+console\n[Install]\nWantedBy=multi-user.target\n' > "$W/r8-check.service"
debugfs -w -R "write $W/r8-check.service /etc/systemd/system/r8-check.service" "$W/p2" >/dev/null 2>&1
debugfs -w -R "symlink /etc/systemd/system/multi-user.target.wants/r8-check.service /etc/systemd/system/r8-check.service" "$W/p2" >/dev/null 2>&1
dd if="$W/p2" of="$W/disk.img" bs=512 seek="$P2" conv=notrunc status=none
q() { timeout "$1" qemu-system-aarch64 -M virt -cpu cortex-a53 -smp 2 -m "$MB" -nographic -bios "$UB" $2 \
      -drive "file=$W/disk.img,format=raw,if=none,id=hd0" -device virtio-blk-device,drive=hd0 \
      -netdev user,id=n0 -device virtio-net-device,netdev=n0 || true; }
OUT="${IMG%.img}.rollback"
# Test-only: QEMU virt's UART is ttyAMA0 (the device's is ttyS0); point every entry's console there.
mcopy -n -i "$FAT" ::/extlinux/extlinux.conf "$W/orig.conf"; sed 's/console=ttyS0,115200/console=ttyAMA0/' "$W/orig.conf" > "$W/qemu.conf"
mcopy -o -n -i "$FAT" "$W/qemu.conf" ::/extlinux/extlinux.conf
echo "== run 1 (normal boot)"; q 900 -no-reboot > "$OUT-run1.log" 2>&1
mcopy -n -i "$FAT" ::/uboot.env "$W/uboot.env" || { echo "u-boot saved no environment"; exit 1; }
mcopy -n -i "$FAT" ::/extlinux/extlinux.conf "$W/good.conf"
# Simulated update: a new l0 that panics; the previous entries move down (l1 = the good kernel).
awk 'BEGIN{b=0} /^label l0$/ {b=1; n=0; next} b && /^label / {b=2} b==1 {body[++n]=$0; next}
     b==2 && !done {print "label l0"; print "\tmenu label NEW (simulated bad kernel)";
       for (i=1;i<=n;i++) if (body[i] !~ /menu label/) {l=body[i]; if (l ~ /append/) sub(/ quiet/, " init=/bin/false quiet", l); print l}
       print ""; print "label l1"; for (i=1;i<=n;i++) print body[i]; done=1}
     {print}' "$W/good.conf" > "$W/new.conf"
sed 's/^default l0$/default l1/' "$W/new.conf" > "$W/fallback.conf"
printf '%s 0x0000 0x10000\n' "$W/uboot.env" > "$W/fw_env.config"
fw_setenv -c "$W/fw_env.config" upgrade_available 1; fw_setenv -c "$W/fw_env.config" bootcount 0
mcopy -o -n -i "$FAT" "$W/new.conf" ::/extlinux/extlinux.conf
mcopy -o -n -i "$FAT" "$W/fallback.conf" ::/extlinux/extlinux-fallback.conf
mcopy -o -n -i "$FAT" "$W/uboot.env" ::/uboot.env
cp "$W/new.conf" "$OUT-new.conf"
echo "== run 2 (update with a bad kernel; resets allowed)"; q 2400 "" > "$OUT-run2.log" 2>&1
echo "== run 3 (plain reboot after the fallback)"; q 900 -no-reboot > "$OUT-run3.log" 2>&1
echo "logs: $OUT-run1.log $OUT-run2.log $OUT-run3.log"
