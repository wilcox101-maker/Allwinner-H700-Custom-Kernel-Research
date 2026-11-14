#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# usage: boot.sh NAME MB [SMP]  -> boot-NAME-MB.log (serial console). QEMU virt + Cortex-A53, TCG.
# Boots a throwaway copy of NAME.img; r5-measure prints figures then powers off.
set -eu; N=$1; M=$2; S=${3:-4}; cp --reflink=auto "$N.img" "r-$N-$M.img"
timeout "${TIMEOUT:-3000}" qemu-system-aarch64 -M virt -cpu cortex-a53 -smp "$S" -m "$M" -nographic -no-reboot \
  -kernel "$N.vmlinuz" -initrd "$N.initrd" -append "root=/dev/vda rw console=ttyAMA0 quiet" \
  -drive "file=r-$N-$M.img,format=raw,if=virtio" -nic user,model=virtio-net-pci > "boot-$N-$M.log" 2>&1 || true
rm -f "r-$N-$M.img"; echo "done-$N-$M" >> "boot-$N-$M.log"
