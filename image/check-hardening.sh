#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# ReduxOS build check (docs/reduxos-distro-build.md §2-§3): the staged rootfs must meet the
# manifest's security and app-set rules. Read-only. Usage: check-hardening.sh ROOTFS
set -u
R=${1:?usage: check-hardening.sh ROOTFS}
FAIL=0
ok()  { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; FAIL=1; }
t()   { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
en()  { [ -e "$R/etc/systemd/system/$1/$2" ]; }

echo "== hardening check: $R"
t "no SSH host keys in the image (made on first boot)" bash -c "! ls '$R'/etc/ssh/ssh_host_* >/dev/null 2>&1"
t "machine-id not set in the image (made on first boot)" bash -c "[ ! -s '$R/etc/machine-id' ] || grep -qx uninitialized '$R/etc/machine-id'"
t "root has no password (locked)" bash -c "grep -q '^root:[*!]' '$R/etc/shadow'"
t "user password expired (must change at first login)" bash -c "awk -F: '\$1==\"dale\" && \$3==0 {f=1} END {exit !f}' '$R/etc/shadow'"
t "sshd: root login off" grep -qx 'PermitRootLogin no' "$R/etc/ssh/sshd_config.d/60-reduxos.conf"
t "firewall enabled (nftables.service)" en sysinit.target.wants nftables.service
t "firewall drops inbound by default" grep -q 'type filter hook input priority filter; policy drop;' "$R/etc/nftables.conf"
t "motd-news timer off (no fetch of motd.ubuntu.com)" test ! -e "$R/etc/systemd/system/timers.target.wants/motd-news.timer"
t "journal kept across reboots" grep -qx 'Storage=persistent' "$R/etc/systemd/journald.conf.d/60-h700.conf"
t "no wiliwili or other stock vendor apps" bash -c "! find '$R' -xdev \( -iname 'wiliwili*' -o -iname '*.dge' -o -iname 'dmenu.bin' \) -print -quit | grep -q ."
t "no stock dev leftovers (snapd, qemu-user, openmpi, moonlight)" bash -c "! grep -qE '^(snapd|qemu-user[a-z-]*|openmpi-bin|moonlight[a-z-]*)\s' '$R/root/manifest.tsv'"
t "no hostapd/dnsmasq running at boot" bash -c "! ls '$R'/etc/systemd/system/*.wants/{hostapd,dnsmasq}.service >/dev/null 2>&1"

echo "== frontend check (R32)"
t "player account exists" bash -c "grep -q '^player:' '$R/etc/passwd'"
t "player password locked (no login off the console)" bash -c "grep -q '^player:[*!]' '$R/etc/shadow'"
t "player is NOT in sudo" bash -c "! awk -F: '/^sudo:/{print \$4}' '$R/etc/group' | grep -qw player"
t "tty1 autologin -> player" grep -q 'autologin player' "$R/etc/systemd/system/getty@tty1.service.d/60-reduxos-autologin.conf"
t "RetroArch global config present" test -f "$R/etc/retroarch.cfg"
t "RetroArch gamepad autoconfig present" test -f "$R/etc/retroarch/autoconfig/ReduxOS_RG34XXSP.cfg"
t "codec mixer baseline service present" test -f "$R/etc/systemd/system/reduxos-audio-init.service"
t "retroarch installed" grep -qE '^retroarch\s' "$R/root/manifest.tsv"
t "at least one libretro core installed" bash -c "grep -qE '^libretro-' '$R/root/manifest.tsv'"
[ "$FAIL" = 0 ] && echo "hardening check: PASS" || { echo "hardening check: FAIL"; exit 1; }
