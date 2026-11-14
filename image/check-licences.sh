#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# R9 release checks on a built rootfs tree (docs/r9-licensing-redistribution.md §3, items 3 and 4).
#
# usage: image/check-licences.sh <rootfs-dir>
#   1. every installed package keeps its copyright file (/usr/share/doc/<pkg>/copyright)
#   2. every file under /usr/lib/firmware belongs to an installed package (no hand-dropped blobs)
#   3. no panel init blobs (*.panel) anywhere: ROCKNIX's carry no licence, ours come from stock
#   4. no files from stock images: nothing under /lib/firmware or /boot named like Anbernic's
#      boot0/kernel dumps (boot0*.bin, boot_package*, *.fex)
# Reads only; uses the host's dpkg-query with --admindir, so no chroot or qemu is needed.
# Exit 0 = all checks passed; 1 = at least one failed (each failure is printed).
set -euo pipefail
R=${1:?usage: $0 <rootfs-dir>}
R=$(cd "$R" && pwd)
ADMIN=$R/var/lib/dpkg
[ -f "$ADMIN/status" ] || { echo "no dpkg database in $R" >&2; exit 2; }
fail=0
bad() { printf 'FAIL %s\n' "$*"; fail=1; }

# 1. copyright files. A package's doc dir may be a relative symlink to another package's.
n=0
while read -r pkg; do
	n=$((n + 1))
	d=$R/usr/share/doc/${pkg%%:*}
	if [ -L "$d" ]; then t=$(readlink "$d"); case $t in /*) d=$R$t ;; *) d=$(dirname "$d")/$t ;; esac; fi
	[ -e "$d/copyright" ] || bad "no copyright file for package $pkg"
done < <(dpkg-query --admindir="$ADMIN" -W -f='${db:Status-Abbrev} ${binary:Package}\n' | awk '$1 ~ /^ii/ {print $2}')
echo "1. copyright files: checked $n installed packages"

# 2. firmware ownership. /lib is a symlink to usr/lib on noble; check the real tree.
owned=$(mktemp); trap 'rm -f "$owned"' EXIT
cat "$ADMIN"/info/*.list | sed -e 's|^/lib/|/usr/lib/|' | sort -u > "$owned"
fw=0
if [ -d "$R/usr/lib/firmware" ]; then
	while IFS= read -r f; do
		fw=$((fw + 1)); p=${f#"$R"}
		grep -qxF "$p" "$owned" || bad "firmware file not owned by any package: $p"
	done < <(find "$R/usr/lib/firmware" \( -type f -o -type l \))
fi
echo "2. firmware ownership: checked $fw files under /usr/lib/firmware"

# 3 + 4. forbidden content
while IFS= read -r f; do bad "panel blob: ${f#"$R"}"; done < <(find "$R" -xdev -name '*.panel' 2>/dev/null)
while IFS= read -r f; do bad "stock-image file: ${f#"$R"}"; done < <(find "$R/boot" "$R/usr/lib/firmware" \
	\( -iname 'boot0*.bin' -o -iname 'boot_package*' -o -iname '*.fex' \) 2>/dev/null)
echo "3-4. panel blob and stock-image file scan: done"

if [ $fail = 0 ]; then echo "licence checks: PASS"; else echo "licence checks: FAIL"; fi
exit $fail
