# R5: Ubuntu 24.04 (noble) arm64 userspace prototype, measured in QEMU

Deep Research, 2026-11-13. **QEMU only (`virt`, Cortex-A53, TCG emulation, no KVM); nothing ran on an H700.** Master list task R5. Scripts and raw logs: [`r5/`](../r5/).

## Answer in one paragraph
A minimal noble arm64 rootfs built with mmdebstrap from ports.ubuntu.com boots to a login prompt and idles at about **11 MB of anonymous memory and 33–38 MB of total process memory (PSS)**, whatever the RAM size. **512 MB is comfortable for the base system: about 386 MB is still available at idle.** zram works with the distro kernel and gives a zstd swap of half the RAM. The **iwd + systemd-networkd + systemd-resolved** stack is the better default: it saves **73 MB of disk and 53 packages, removes Python entirely**, and uses about **5 MB less RAM** than NetworkManager + wpa_supplicant. The kernel's own share (MemTotal reservations, slab, a jump in "used" between 512 MB and 1 GB) comes from Ubuntu's generic QEMU kernel, so it says nothing about our H700 kernel. That has to be measured on hardware (K12).

## 1. What was built
| | NM variant | iwd variant |
|---|---|---|
| Builder | `mmdebstrap --variant=minbase`, noble + noble-updates + noble-security, main + universe, from `https://ports.ubuntu.com/ubuntu-ports` | same |
| Network stack | `network-manager`, `wpasupplicant` | `iwd`, `systemd-resolved`, systemd-networkd (DHCP on `en*`/`eth*`; iwd does its own DHCP on Wi-Fi, `NameResolvingService=systemd`) |
| Common packages | `initramfs-tools systemd-sysv udev dbus kmod iproute2 iputils-ping wireless-regdb openssh-server sudo ca-certificates systemd-zram-generator systemd-timesyncd less nano linux-firmware-realtek` | same |
| QEMU-only kernel | `linux-image-6.8.0-149-generic` + `linux-modules-extra-6.8.0-149-generic` | same |
| Trimmed | no Recommends; no docs (copyright kept), man pages or locales | same |
| zram | `[zram0] zram-size = min(ram / 2, 4096)`, `compression-algorithm = zstd` | same |
| Build time (emulated arm64 on a 2-core x86 VM) | 19 min | 9 min (initramfs set to `MODULES=list` for QEMU) |

**Kernel package choice.** The task said `linux-image-generic`. That metapackage depends on the **`linux-firmware` metapackage (~470 MB)** and `linux-modules-extra`, so I installed the same kernel by its versioned package names instead (`linux-image-6.8.0-149-generic` + `linux-modules-extra-…`). zram lives in `linux-modules-extra` (`kernel/drivers/block/zram/zram.ko.zst`), which is why the earlier `linux-image-virtual` run had no zram. This kernel is only a QEMU stand-in; our image ships our own H700 kernel (R10).

## 2. Disk size (excluding the QEMU kernel)
| | NM | iwd | Difference |
|---|---|---|---|
| Rootfs total | 537 MB | 423 MB | |
| of which kernel (`/boot`, modules, `/usr/lib/firmware/6.8.0-149-generic`) | 288 MB | 247 MB | QEMU stand-in only; NM's larger initrd is `MODULES=most` |
| **Userspace** | **249 MB** | **176 MB** | **−73 MB** |
| Packages | 199 | 146 | −53 |
| Python | 37 MB | 0 | NM → `netplan.io` → `python3-netplan` |
| `linux-firmware-realtek` | 6 MB | 6 MB | (R4) |

The 53 packages iwd drops are NM's whole dependency tree: netplan and Python, polkit, GLib, GnuTLS, libcurl, libssh, LDAP/SASL, ModemManager glue, bluez's `libbluetooth3`, and teamd. The arm64 userspace is larger than the earlier amd64 proxy (211 MB without kernel). *Corrected 2026-11-14 (audit):* this first blamed the noble-updates/security pockets and `linux-firmware-realtek`, but the proxy build used both too; the difference is **not explained** (architecture, or a different measuring method in the earlier chat).

## 3. RAM at idle (60 s after boot, serial console only, no UI)
| Run | MemTotal | MemAvailable | used (= total − available) | AnonPages | Slab | PSS sum (all processes) | zram size | Running services* |
|---|---|---|---|---|---|---|---|---|
| NM, 512 MB | 454 MB | 389 MB | 65 MB | 11 MB | 33 MB | **38 MB** | 226 MB | 9 |
| NM, 1 GB | 956 MB | 817 MB | 139 MB | 11 MB | 33 MB | – | 477 MB | 9 |
| NM, 2 GB | 1959 MB | 1820 MB | 139 MB | 11 MB | 33 MB | – | 979 MB | 9 |
| iwd, 512 MB | 454 MB | 386 MB | 68 MB | 11 MB | 32 MB | **33 MB** | 226 MB | 10 |
| iwd, 1 GB | 956 MB | 822 MB | 134 MB | 11 MB | 32 MB | 33 MB | 477 MB | 10 |
| iwd, 2 GB | 1959 MB | 1818 MB | 141 MB | 11 MB | 32 MB | 33 MB | 979 MB | 10 |

\* excluding the measurement service itself. NM: dbus, NetworkManager, wpa_supplicant, journald, logind, timesyncd, udevd, getty@tty1, serial-getty. iwd: dbus, iwd, networkd, resolved, journald, logind, timesyncd, udevd, getty@tty1, serial-getty. (PSS was added to the measurement after the NM 1 GB/2 GB runs; userspace figures are flat across RAM sizes, as the AnonPages column shows.)

Largest processes by PSS:

| NM, 512 MB | | iwd, 512 MB | |
|---|---|---|---|
| NetworkManager | 13.7 MB | systemd-resolved | 6.8 MB |
| systemd (PID 1) | 6.7 MB | systemd (PID 1) | 6.1 MB |
| systemd-journald | 3.4 MB | systemd-journald | 4.2 MB |
| wpa_supplicant | 3.1 MB | systemd-networkd | 3.2 MB |
| systemd-udevd | 3.0 MB | systemd-udevd | 3.0 MB |
| systemd-logind | 2.3 MB | systemd-logind | 2.0 MB |
| | | iwd | 1.6 MB |

Reading the numbers:
- **Userspace cost is flat: about 11 MB anonymous, 33–38 MB PSS.** NM + wpa_supplicant cost 16.8 MB PSS; iwd + networkd + resolved cost 11.6 MB. resolved is the largest piece of the iwd stack; dropping it (static DNS from networkd) would save about 7 MB more, at the cost of DNS handling we'd then own. Not recommended for v0.x.
- **The jump in "used" from ~65 MB at 512 MB to ~139 MB at 1 GB+ is kernel accounting**, the same for both stacks and with identical userspace. The likely cause is reservations that the generic Ubuntu kernel scales with RAM [not traced]. Our kernel's figures will differ; K12 measures them on hardware.
- **Slab ≈ 33 MB** is the generic kernel's (many drivers built in or loaded for QEMU). A trimmed H700 kernel should be well below this [expected, unverified].

## 4. zram
- Worked on all six runs with the distro kernel: `/dev/zram0`, zstd, size = RAM/2 (226 / 477 / 979 MB), swap priority 100. Nothing was swapped at idle, as expected.
- **Our kernel needs `CONFIG_ZRAM` (=m is fine) with `CONFIG_ZRAM_BACKEND_ZSTD`** (and `_LZ4` for the fallback). *Corrected 2026-11-14 (audit):* this first said `CONFIG_CRYPTO_ZSTD`; since Linux 6.12 zram compresses through its own back-ends, so the crypto option isn't what zram needs. The R10 config (`config/rg34xxsp.config`) already has both back-ends.
- noble ships `systemd-zram-generator` 1.1.2; its documented default size is `min(ram / 2, 4096)`, which is what this prototype set explicitly.

## 5. Boot time (QEMU TCG, for comparison between variants only)
Emulated Cortex-A53 on a shared 2-core host, so absolute times mean nothing for the device. Uncontended runs: kernel 19–24 s, userspace **58–60 s (iwd) vs 65–69 s (NM)**. In `systemd-analyze blame`, `NetworkManager.service` takes 24–25 s; `iwd.service` 17 s, `systemd-networkd` 6 s and `systemd-resolved` 7 s run in parallel. Real boot time is K12.

### Not tested in R5 (added 2026-11-14, audit)
- **No network traffic was checked.** QEMU had only a wired virtio NIC and the hook didn't print addresses, so "the network stack works" is not shown for either variant, and iwd/Wi-Fi was not exercised at all. R7's QEMU check should print `networkctl status` and resolve a name; Wi-Fi is device-only (K-list).

## 6. Recommendations (feed R7 and R13)
1. **Default network stack: iwd + systemd-networkd + systemd-resolved.** No Python on the device, 73 MB less disk, ~5 MB less RAM, fewer packages to patch. iwd (2.14) and `systemd-zram-generator` (1.1.2) are both in noble `universe` (checked in the ports index), so their security fixes come from the community rather than Canonical; record this under R8/R9. NM remains an option for users who want it (one apt command).
2. **Base package list for R7: add `libpam-systemd`, `tzdata` and `netbase` explicitly.** The NM variant got them only as NM dependencies (checked in `r5/results/*-packages.txt`); without `libpam-systemd` logins don't get logind sessions (user services, seat access for the game UI later), and `netbase` provides `/etc/services` and `/etc/protocols`. (`netbase` added 2026-11-14, audit.)
3. **Never install the `linux-image-generic` or `linux-firmware` metapackages** in the image; our kernel package plus `linux-firmware-realtek` covers the hardware (R4).
4. **SSH:** the image bakes host keys at build time. R7 must regenerate them on first boot (delete keys in the image; `ssh-keygen -A` in a first-boot unit), or every card shares the same keys.
5. **Add `apt` to the package list** (found in R6, 2026-11-14): `--variant=minbase` installs only Priority `required` packages and Ubuntu's `apt` is `important`, so neither R5 rootfs has apt. +17 MB, 14 packages.
6. **Measure again on hardware (K12)** with our kernel: MemTotal, MemAvailable, Slab, PSS, boot time per stage.

## 7. Reproduce
```bash
# Ubuntu 24.04 x86-64 host with sudo
sudo apt-get install -y mmdebstrap qemu-system-arm qemu-user-static binfmt-support e2fsprogs
# if binfmt isn't active (containers): register qemu-aarch64 from /usr/lib/binfmt.d/qemu-aarch64.conf
sudo NET=iwd r5/build.sh iwd.tar            # or NET=nm; ~10-20 min under emulation
sudo r5/mkimg.sh iwd.tar iwd                # -> iwd.img (2 GiB ext4), iwd.vmlinuz, iwd.initrd, iwd.sizes
for m in 512 1024 2048; do sudo r5/boot.sh iwd $m; done   # -> boot-iwd-<MB>.log; ~4 min each under TCG
python3 r5/summary.py boot-*.log
```
All outputs are files in the current directory; nothing touches block devices. The images are throwaway copies.

## 8. Sources
- Ubuntu ports archive `noble`, `noble-updates`, `noble-security` (arm64), 2026-11-13; `dists/noble-updates/main/binary-arm64/Packages.gz` (linux-image-generic 6.8.0-149.149 depends on `linux-firmware`); `dists/noble-updates/Contents-arm64.gz` (zram.ko in `linux-modules-extra`).
- zram-generator.conf(5), noble 1.1.2: https://manpages.ubuntu.com/manpages/noble/man5/zram-generator.conf.5.html
- Raw logs and package lists: `r5/results/`.
