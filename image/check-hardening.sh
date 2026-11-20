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
t "sshd: root login not blocked (Dale 2026-11-20)" grep -qx 'PermitRootLogin yes' "$R/etc/ssh/sshd_config.d/60-reduxos.conf"
t "no root SSH key shipped (no /root/.ssh/authorized_keys)" bash -c "! test -e '$R/root/.ssh/authorized_keys'"
t "no authorized_keys shipped for any user" bash -c "! find '$R/root' '$R/home' '$R/etc/ssh' -name 'authorized_keys*' 2>/dev/null | grep -q ."
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
t "retroarch installed (noble or reduxos-retroarch, R33)" grep -qE '^(reduxos-)?retroarch\s' "$R/root/manifest.tsv"
t "RetroArch links no Qt/X11/Wayland/Pulse/JACK (if reduxos-retroarch, R33)" bash -c "! grep -qE '^reduxos-retroarch\s' '$R/root/manifest.tsv' || ! readelf -d '$R/usr/bin/retroarch' | grep NEEDED | grep -qE 'Qt5|libX11|libwayland|libpulse|libjack'"
t "at least one libretro core installed" bash -c "grep -qE '^libretro-' '$R/root/manifest.tsv'"
t "console font tools present (kbd)" grep -qE '^kbd\s' "$R/root/manifest.tsv"
t "legible console font configured (vconsole.conf)" grep -q '^FONT=Lat15-Terminus' "$R/etc/vconsole.conf"
t "console font file present for setfont" bash -c "ls '$R'/usr/share/consolefonts/Lat15-Terminus20x10.psf* >/dev/null 2>&1"
t "interactive shell env installed" test -f "$R/etc/profile.d/10-reduxos.sh"

echo "== fly-out OSK check (R32)"
t "cage kiosk compositor installed" grep -qE '^cage\s' "$R/root/manifest.tsv"
t "wvkbd fly-out keyboard installed" grep -qE '^wvkbd\s' "$R/root/manifest.tsv"
t "wayland terminal (foot) installed" grep -qE '^foot\s' "$R/root/manifest.tsv"
t "OSK launcher present" test -x "$R/usr/local/bin/redux-kbapp"
t "OSK shell + file-manager launchers present" bash -c "test -x '$R/usr/local/bin/redux-shell' && test -x '$R/usr/local/bin/redux-files'"
t "gamepad->pointer bridge injected (aarch64)" bash -c "test -x '$R/usr/local/bin/redux-osk-pointer' && file '$R/usr/local/bin/redux-osk-pointer' | grep -q 'ARM aarch64'"
echo "== games/BIOS framework check (R36)"
t "system map present" test -f "$R/usr/share/reduxos/systems.tsv"
t "BIOS reference present" test -f "$R/usr/share/reduxos/bios-reference.tsv"
t "roms setup + bios check tools present" bash -c "test -x '$R/usr/local/bin/redux-setup-roms' && test -x '$R/usr/local/bin/redux-bios-check'"
t "no BIOS/ROM content shipped (structure only)" bash -c "! find '$R/roms' -type f ! -name '.keep' 2>/dev/null | grep -q ."
t "retroarch system dir points at /roms/bios" grep -q '^system_directory = \"/roms/bios\"' "$R/etc/retroarch.cfg"
echo "== cores, launcher, PortMaster check (R36)"
t "launcher core + info present" bash -c "test -f '$R/usr/lib/aarch64-linux-gnu/libretro/redux_exec_libretro.so' && test -f '$R/usr/share/libretro/info/redux_exec_libretro.info'"
t "every libretro core is aarch64" bash -c "for f in '$R'/usr/lib/aarch64-linux-gnu/libretro/*.so; do file -b \"\$f\" | grep -q 'ARM aarch64' || exit 1; done"
t "launch helper allow-lists /roms/PORTS, /roms/APPS, PortMaster only" bash -c "grep -q '/roms/PORTS/\*|/roms/APPS/\*|/opt/tools/PortMaster/\*) ;;' '$R/usr/local/bin/redux-launch'"
t "playlist scanner + service enabled" bash -c "test -x '$R/usr/local/bin/redux-scan-roms' && test -L '$R/etc/systemd/system/multi-user.target.wants/reduxos-playlists.service'"
t "uinput limited to the input group (0660)" grep -q 'GROUP="input", MODE="0660"' "$R/etc/udev/rules.d/70-reduxos-uinput.rules"
# KR V1.0.6 breakdown §8A: stock Anbernic binaries carry a "deeplayer" check and reboot on a kernel without
# the vendor driver. ReduxOS builds everything from source; this guards against a stock binary slipping in.
t "no stock deeplayer-checked binary in the image" bash -c "! grep -rlqa -e deeplayer -e debug2_reg2 '$R/usr' '$R/opt' '$R/etc' 2>/dev/null"
t "PortMaster (if injected) owned by player, not root-run" bash -c "[ ! -d '$R/opt/tools/PortMaster' ] || { [ \"\$(stat -c %U '$R/opt/tools/PortMaster')\" != root ] && test -f '$R/opt/tools/PortMaster/reduxos/launch_hooks.txt'; }"
[ "$FAIL" = 0 ] && echo "hardening check: PASS" || { echo "hardening check: FAIL"; exit 1; }
