#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# R18: boot NAME.img with OUR kernel in QEMU virt + Cortex-A53 (TCG) and log the console.
# usage: boot.sh NAME MB [SMP] [initrd]  -> boot-NAME-MB.log
# Same as r5/boot.sh except: our kernel has no PCI (config/rg34xxsp.config), so the disk and NIC
# are virtio over MMIO (virtio-blk-device, virtio-net-device). By default it boots WITHOUT an
# initramfs (ext4 and virtio-blk are built in); pass "initrd" as 4th argument to use NAME.initrd.
# Boots a throwaway copy of NAME.img; r5-measure prints figures, then powers off.
set -eu; N=$1; M=$2; S=${3:-4}; I=${4:-}; cp --reflink=auto "$N.img" "r-$N-$M.img"
INITRD=(); [ "$I" = initrd ] && INITRD=(-initrd "$N.initrd")
timeout 3000 qemu-system-aarch64 -M virt -cpu cortex-a53 -smp "$S" -m "$M" -nographic -no-reboot \
  -kernel "$N.vmlinuz" "${INITRD[@]}" -append "root=/dev/vda rw rootwait console=ttyAMA0 quiet" \
  -drive "file=r-$N-$M.img,format=raw,if=none,id=hd0" -device virtio-blk-device,drive=hd0 \
  -netdev user,id=n0 -device virtio-net-device,netdev=n0 > "boot-$N-$M${I:+-$I}.log" 2>&1 || true
rm -f "r-$N-$M.img"; echo "done-$N-$M" >> "boot-$N-$M${I:+-$I}.log"
