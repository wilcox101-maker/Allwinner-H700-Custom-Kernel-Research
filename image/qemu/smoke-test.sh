#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# R23 boot smoke test: boot a COPY of a ReduxOS image in QEMU (via qemu-test.sh, which injects r7-check)
# and fail unless the boot reached a healthy multi-user system. Used by CI (.github/workflows/image-smoke.yml)
# and runnable by hand. The original image is not changed; nothing touches a card or block device.
#
# usage: sudo image/qemu/smoke-test.sh IMAGE.img [MB]       boot and check (MB default 512, the smallest tier)
#        image/qemu/smoke-test.sh --check-log LOG [KMODE]    only check an existing qemu-test.sh log
#   KMODE  deb (our kernel, default; the kernel release must end in -rg34xxsp) or ubuntu
# Writes <image>.smoke-<MB>.txt (and appends to $GITHUB_STEP_SUMMARY when set). Exit 0 = all checks passed.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" = --check-log ]; then
	LOG=$2; KMODE=${3:-deb}; REPORT=/dev/null
else
	IMG=$(readlink -f "$1"); MB=${2:-512}
	case "$IMG" in *-ubuntu*.img) KMODE=ubuntu ;; *) KMODE=deb ;; esac
	"$HERE/qemu-test.sh" "$IMG" "$MB"
	LOG="${IMG%.img}.qemu-$MB.log"; REPORT="${IMG%.img}.smoke-$MB.txt"
fi
[ -f "$LOG" ] || { echo "no log: $LOG" >&2; exit 1; }

# r7-check's lines arrive on the console as "[ time] r7-check[pid]: text"; keep the text only.
OUT=$(sed -n 's/^.*r7-check\[[0-9]*\]: //p' "$LOG" | tr -d '\r')
section() { printf '%s\n' "$OUT" | awk -v s="== $1" 'index($0, s) == 1 {on = 1; print; next} /^== |^R7END/ {on = 0} on'; }

set +e   # every check runs; the exit status is decided at the end
PASS=0; FAIL=0; RESULTS=
check() {   # check <name> <ok:0/1> <detail>
	if [ "$2" = 0 ]; then PASS=$((PASS + 1)); RESULTS+="| PASS | $1 | $3 |"$'\n'
	else FAIL=$((FAIL + 1)); RESULTS+="| **FAIL** | $1 | $3 |"$'\n'; fi
}
has() { printf '%s\n' "$OUT" | grep -qE "$1"; }

has '^R7BEGIN$' && has '^R7END$'; check "boot reached multi-user, check ran" $? "R7BEGIN/R7END in the console log"
sys=$(printf '%s\n' "$OUT" | sed -n 's/^== system: //p' | head -1)
[ "$sys" = running ]; check "systemd state is running" $? "${sys:-none}"
fb=$(section firstboot | grep -o 'root grown: [0-9]* -> [0-9]* bytes' || true)
[ -n "$fb" ]; check "first boot grew the root filesystem" $? "${fb:-no 'root grown' line}"
root=$(section disk | awk '$NF == "/" && /ext4/ {print $(NF-3)}' | head -1)
root_gib=$(section disk | awk '$1 ~ /^\/dev\/root/ {print $2}' | head -1)
[[ "$root_gib" =~ ^[2-9]\.?[0-9]*G$ ]]; check "root filesystem is ≥ 2 GiB after growth" $? "${root_gib:-?} (partition ${root:-?})"
keys=$(printf '%s\n' "$OUT" | sed -n 's/^== ssh host keys: //p')
[ "${keys:-0}" -ge 3 ]; check "SSH host keys generated" $? "${keys:-0} keys"
mid=$(printf '%s\n' "$OUT" | sed -n 's/^== machine-id: //p')
[[ "$mid" =~ ^[0-9a-f]{32}$ ]]; check "machine-id initialised" $? "${mid:-none}"
has '^== apt: apt [0-9]'; check "apt installed" $? "$(printf '%s\n' "$OUT" | sed -n 's/^== apt: //p')"
svc=$(section services | sed -n 2p)
[ "$svc" = "active active active active active active" ]
check "networkd, iwd, earlyoom, resolved, zram, ssh.socket active" $? "${svc:-none}"
section network | grep -qE '^ *[0-9]+ (eth0|en[a-z0-9]+) +ether +routable +configured'
check "wired network configured (routable)" $? "$(section network | grep -E 'eth0|en[a-z0-9]' | head -1 | tr -s ' ')"
kver=$(printf '%s\n' "$OUT" | sed -n 's/^== kernel: //p')
if [ "$KMODE" = deb ]; then [[ "$kver" == *-rg34xxsp ]]; else [ -n "$kver" ]; fi
check "kernel is ours ($KMODE)" $? "${kver:-none}"
section extlinux | grep -qE '^\s*fdtdir /dtb-'; check "extlinux uses fdtdir (u-boot-menu)" $? \
	"$(section extlinux | grep -m1 fdtdir | tr -d '\t')"
bad=$(grep -E 'Kernel panic|Oops|BUG:|Call trace:|segfault' "$LOG" | head -3 || true)
[ -z "$bad" ]; check "no panic/oops/BUG/segfault in the log" $? "${bad:-none}"
# DNS through QEMU user networking depends on the host network: reported, not failed.
dns=$(section network | grep -c 'ports.ubuntu.com: [0-9]' || true)
RESULTS+="| info | DNS lookup of ports.ubuntu.com | $([ "$dns" -gt 0 ] && echo resolved || echo 'not resolved (host network)') |"$'\n'
avail=$(section mem | awk '/^Mem:/ {print $NF " MB available of " $2}')
RESULTS+="| info | memory | ${avail:-?} |"$'\n'

{
	echo "### ReduxOS QEMU boot smoke test: $PASS passed, $FAIL failed"
	echo
	echo "Log: \`$(basename "$LOG")\`. QEMU virt + Cortex-A53, TCG; not the RG34XX-SP hardware."
	echo
	echo "| Result | Check | Detail |"; echo "|---|---|---|"
	printf '%s' "$RESULTS"
} | tee "$REPORT" | { if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then tee -a "$GITHUB_STEP_SUMMARY"; else cat; fi; }
[ "$FAIL" -eq 0 ]
