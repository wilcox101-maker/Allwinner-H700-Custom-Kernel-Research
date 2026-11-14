#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Display consistency check on a built rootfs tree (R19 / Q8 a; R7 image build).
#
# usage: image/check-display.sh <rootfs-dir>
# The RG34XX-SP's original panel (PE6 low) runs on the upstream NV3052C driver. The u-boot PE6
# patch loads sun50i-h700-anbernic-rg34xx-sp-redux-panel.dtb on those units, so if that tree is on
# the card, the kernel must also carry the driver and it must match the tree's panel compatible:
#   - the DTB is in /boot/dtb-<kver>/allwinner/ (u-boot-menu's synced copy) for every kernel
#   - panel-newvision-nv3052c is a module (modules.alias has the compatible) or built in
#     (modules.builtin), for the same kernel
# A kernel without the display layer has no panel tree, so it only gets a note (no display; PE6
# high units have no display until K9 in any case).
# Exit 0 = consistent; 1 = a panel tree without a matching driver.
set -euo pipefail
R=$(cd "${1:?usage: $0 <rootfs-dir>}" && pwd)
DTB=sun50i-h700-anbernic-rg34xx-sp-redux-panel.dtb
COMPAT=anbernic,rg34xx-sp-panel
MOD=panel-newvision-nv3052c
fail=0
shopt -s nullglob
kvers=("$R"/usr/lib/modules/*/)
[ ${#kvers[@]} -gt 0 ] || { echo "display: no kernel modules tree in $R"; exit 1; }
for d in "${kvers[@]}"; do
	kv=$(basename "$d")
	dtb=$R/boot/dtb-$kv/allwinner/$DTB
	if [ ! -e "$dtb" ]; then
		echo "display: $kv has no $DTB: no display on this kernel (built without the display layer?)"
		continue
	fi
	# compatible strings are NUL-separated in the blob; the panel node must carry ours
	grep -qaF "$COMPAT" "$dtb" || { echo "FAIL $kv: $DTB has no \"$COMPAT\" node"; fail=1; continue; }
	if grep -q "^alias of:N\*T\*C${COMPAT}\(C\*\)\? ${MOD//-/_}\$" "$d/modules.alias" 2>/dev/null; then
		how="module ${MOD}.ko (modules.alias)"
	elif grep -q "/${MOD}\.ko$" "$d/modules.builtin" 2>/dev/null; then
		how="built in (modules.builtin)"
	else
		echo "FAIL $kv: $DTB is on the card but no $MOD driver matches \"$COMPAT\""; fail=1; continue
	fi
	echo "display: $kv: $DTB + $how"
done
[ $fail = 0 ] && echo "display check: PASS" || echo "display check: FAIL"
exit $fail
