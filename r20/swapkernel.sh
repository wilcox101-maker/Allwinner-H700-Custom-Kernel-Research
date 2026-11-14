#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# swapkernel.sh IN.tar KERNEL.deb OUT.tar : replace our kernel in an R18 rootfs tar (desk only)
set -euo pipefail
IN=$1; DEB=$2; OUT=$3; D=$(mktemp -d)
tar -C "$D" -xpf "$IN"
rm -rf "$D"/usr/lib/modules/*-rg34xxsp "$D"/boot/vmlinuz-*-rg34xxsp "$D"/boot/System.map-*-rg34xxsp "$D"/boot/config-*-rg34xxsp "$D"/boot/initrd.img-*-rg34xxsp
dpkg-deb --fsys-tarfile "$DEB" | tar -C "$D" -x --keep-directory-symlink
V=$(ls "$D"/usr/lib/modules | grep rg34xxsp)
depmod -b "$D" "$V"
: > "$D/boot/initrd.img-$V"   # mkimg.sh copies one; the boot uses none
tar -C "$D" -cpf "$OUT" .
rm -rf "$D"
