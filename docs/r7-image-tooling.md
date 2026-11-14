# R7: Image build tooling for the RG34XX-SP noble image

Deep Research, 2026-11-14. **Prototype built and booted in QEMU only (with our kernel); no image has been written to a card or booted on an H700, and no u-boot was included.** Master list task R7. Script: [`image/build-image.sh`](../image/build-image.sh).

## Answer in one paragraph
**Use mmdebstrap + genimage, glued by one shell script, with Ubuntu's `u-boot-menu` handling the boot menu.** mmdebstrap builds the noble rootfs reproducibly without a VM (R5 already uses it); genimage turns a directory tree into an MBR card image with the SPL at 8 KiB, a FAT32 `/boot` and an ext4 root; and `u-boot-menu` (Ubuntu `main`) rewrites `/boot/extlinux/extlinux.conf` and copies the kernel's DTBs to the FAT partition on **every** kernel install or removal, so the card image and later apt updates (R8) use the same mechanism. debos would also work but needs a VM (KVM, or UML/slow QEMU) or root with `--disable-fakemachine`, and adds a YAML layer we don't need. The prototype produces a complete image with either our kernel `.deb` or Ubuntu's kernel (for QEMU tests); the bootloader is an input (R1).

## 1. Tool choice
| | **mmdebstrap + genimage + shell (chosen)** | debos | Ubuntu `ubuntu-image` / livecd-rootfs | Hand-rolled (`dd`, `sfdisk`, loop mounts) |
|---|---|---|---|---|
| In noble | mmdebstrap 1.4.3 (main), genimage 17 (universe) | debos 1.1.3 (universe) | yes, but built around Ubuntu's own image definitions and gadget snaps | coreutils |
| Needs a VM / loop devices | no / no (genimage builds filesystems from directories, no mounting) | fakemachine VM: KVM, UML or a slow QEMU backend; or `--disable-fakemachine` as root | varies | loop devices + root |
| CI on a plain runner (no KVM) | yes (binfmt + root, as R5/R18 did) | only with `--disable-fakemachine` (root) or the slow backend | heavy | yes, fragile |
| Reproducibility | `SOURCE_DATE_EPOCH`, fixed MBR signature → fixed PARTUUIDs; package manifest per build | similar | similar | manual |
| Fit for an MBR card with raw SPL at 8 KiB | genimage `hdimage` with `partition-table-type = "mbr"` + raw partition at 8K, `in-partition-table = false` | yes (raw action) | not its model | yes |
| Complexity | ~100 lines of shell + 2 small templates | YAML recipe + Go tool | large | grows with every feature |

The fakemachine backends are kvm, uml and qemu, and `auto` never picks the slow qemu one; Ubuntu's own testers noted debos needs `--disable-fakemachine` (and root) on Ubuntu VMs without nested KVM. That removes debos's main advantage (rootless builds) on our CI.

## 2. What the prototype does (`image/build-image.sh`)
1. **Rootfs** with mmdebstrap (`minbase`, no Recommends, docs/man/locales excluded) from `image/packages.txt`: the R5 iwd base **plus** `apt`, `libpam-systemd`, `tzdata`, `netbase` (R5/R6 findings), `earlyoom` + zram (R13), `linux-firmware-realtek` (R4), the GL-only Mesa stack (R6), `u-boot-menu` + `rsync`, `fdisk` (first-boot growth with `sfdisk`), `exfatprogs`, `zstd`.
2. **Kernel**: our `.deb` (`KERNEL_DEB=…`, from KR's R10/R17) or, for QEMU tests only, Ubuntu's 6.8 kernel + a small initramfs (`KERNEL=ubuntu`). During the build `/boot` is a separate tmpfs, so `u-boot-menu` behaves exactly as on the card (FAT-relative paths, DTBs synced to `/dtb-<version>/`).
3. **Configuration**: `config/rootfs/` (R13) and `image/overlay/` (`/etc/default/u-boot`, first-boot unit); networkd + iwd + earlyoom enabled; R13's timers disabled; hostname, fstab by label, user `dale` with an expired password (must be changed at first login).
4. **First boot** (`h700-firstboot.service`, `ConditionFirstBoot=yes`): new SSH host keys (none ship in the image), grow the root partition to the card (`sfdisk -N <n>` with `,+`, then `partx -u`) and the filesystem (`resize2fs`, online). `/etc/machine-id` ships as `uninitialized`.
5. **Image** with genimage: MBR (signature `0x48373030`), optional SPL+u-boot raw at **8 KiB** (`UBOOT_BIN`, ≤ 1016 KiB), **FAT32 `BOOT` 256 MiB at 16 MiB** (bootable flag), **ext4 `rootfs`** sized to its content + 20 % + 64 MiB. Outputs: `<name>.img`, `.sha256`, `.manifest.tsv` (every package, version, size).

Boot chain this assumes (to be confirmed by R1/K4): u-boot's distro boot finds the bootable FAT partition, reads `/extlinux/extlinux.conf`, loads `/vmlinuz-<ver>` and, through `fdtdir /dtb-<ver>/`, the DTB named by `fdtfile` (set by our PE6 patch to `allwinner/<board>.dtb`). Kernel command line: `root=PARTUUID=48373030-02 ro rootwait console=ttyS0,115200 quiet`; `ro` lets systemd-fsck check the root before remounting it read-write, so no initramfs is needed (R18).

## 3. Results
Two builds on a 2-core x86-64 VM (arm64 under qemu-user), then each image booted in QEMU (`virt`, Cortex-A53, TCG) by `image/qemu/qemu-test.sh`, which boots a **copy** enlarged to 3 GiB, takes the kernel from the image's FAT partition and the command line from its `extlinux.conf`, and injects a one-shot report (`image/qemu/r7-check`). Logs: `image/qemu/results/`.

| | **Our kernel** (`linux-image-7.4.0-rc2-rg34xxsp`, rebuilt here with KR's `scripts/workbench.sh` + `build-kernel.sh --build`: all desk checks passed, 160 modules, 26.9 MB installed, same as KR reported) | Ubuntu 6.8 kernel (QEMU-only mode) |
|---|---|---|
| Build time | ~15 min | ~25 min (initramfs under emulation) |
| Packages / installed size | **189 / 440 MB** (Mesa GL stack 226 MB of it, R6); **no Python** | — |
| Image | **866 MB** (425 MB actually allocated; sparse); `/boot` 16 MB used of 256; root 594 MiB before growth | 1.2 GB; `/boot` 84 MB (Ubuntu's kernel + initrd + non-symlinked copies, see below) |
| `extlinux.conf` (written by u-boot-menu) | `linux /vmlinuz-7.4.0-rc2-rg34xxsp`, **`fdtdir /dtb-7.4.0-rc2-rg34xxsp/`**, `append root=PARTUUID=48373030-02 ro rootwait console=ttyS0,115200 quiet`; plus a rescue entry | same, with `initrd`, no `fdtdir` |
| DTBs on the FAT partition | 67 Allwinner DTBs under `/dtb-<ver>/allwinner/`, incl. `…rg34xx-sp.dtb`, `…-redux.dtb`, `…-reduxstock.dtb` | n/a |
| QEMU boot (512 MB) | `is-system-running`: **running**, no failed units, **no initramfs** | (1 GB) running |
| First boot | **SSH host keys generated; root grown online 594 MiB → 2.7 GiB** (sfdisk + partx + resize2fs); machine-id generated | — (first build ran before the machine-id fix) |
| apt, network | apt 2.8.4; eth0 DHCP via networkd; `resolvectl query ports.ubuntu.com` resolved | same |
| Services | networkd, iwd, earlyoom, resolved, zram0, ssh.socket: all active | same |
| Memory at idle | 409 MB available of 479 MB | — |

Problems found and fixed while building (all in the script now):
1. **Conffile prompt:** pre-seeding `/etc/default/u-boot` made dpkg stop and ask; fixed with `force-confdef`/`force-confold`.
2. **`ConditionFirstBoot` never fired:** mmdebstrap empties `/etc/machine-id` at the end, and systemd only treats `uninitialized` (or a missing file) as first boot; the script now writes `uninitialized` after mmdebstrap.
3. **Python came back:** `cloud-guest-utils` (for `growpart`) depends on `python3`; replaced by `sfdisk -N 2` + `partx -u` + `resize2fs` in `h700-firstboot`.
4. **FAT has no symlinks:** Ubuntu's kernel packages make `/boot/vmlinuz`/`initrd.img` (+ `.old`) symlinks, which become full copies on FAT (≈54 MB wasted, and a risk on updates); the image sets `do_symlinks = no` in `/etc/kernel-img.conf`. Our `bindeb-pkg` kernel doesn't create them anyway.
5. **Leftover mounts:** an interrupted run left the build-time `/boot` tmpfs mounted; the script unmounts anything under its output first.
6. **binfmt vanished** in the build container between runs; it had to be re-registered (see §4).

### For R8 (update/rollback), already shown by this prototype
- Kernel updates are plain `apt` installs of our `linux-image-…` package: its postinst runs `/etc/kernel/postinst.d/zz-u-boot-menu`, which syncs that version's DTBs to `/boot/dtb-<ver>/` and rewrites `extlinux.conf` with **one entry per installed kernel** (newest first, plus rescue entries). Keeping the previous kernel installed is the rollback path; u-boot's menu (timeout 1 s, `U_BOOT_TIMEOUT=10`) picks it over serial. R8 decides how many to keep and how to select one without a serial console.

## 4. Decisions and dependencies
- **Card layout is provisional until R1** (KR). The ROM/exFAT partition the assessment wanted for Windows visibility is not in the prototype: genimage 17 has no exFAT image type; options are an `mkfs.exfat` step after growth on first boot, or keeping ROMs on the second card slot. Decide in R1.
- **u-boot**: `UBOOT_BIN` must match the board's DRAM type (R3: LPDDR4 original, LPDDR3 revised) and carry our PE6 patch with DTB names matching our kernel (audit D2). Name images by DRAM type.
- **Writing a card is never part of the build.** When it's time (spare card only, never the stock card): verify the `.sha256`, then write with a tool that shows the target (balenaEtcher/Rufus, or `dd` to a device you have double-checked). This replaces everything on that card, including its boot0.
- **binfmt on CI**: non-arm64 hosts need `qemu-user-static` and an active `qemu-aarch64` binfmt entry; in containers it can vanish (seen here) and must be re-registered before mmdebstrap.

## 5. Sources
- noble package versions (ports/archive indexes, 2026-11-14): mmdebstrap 1.4.3-6, genimage 17-2, debos 1.1.3-1ubuntu0.3, u-boot-menu 4.2.3ubuntu1 (main), cloud-guest-utils 0.33-1 (depends on python3; not used).
- genimage v17 README (`hdimage`, `partition-table-type`, `in-partition-table`, `offset`, `bootable`, `vfat`, `ext4`): https://github.com/pengutronix/genimage/blob/v17/README.rst
- u-boot-menu 4.2.3ubuntu1 scripts (`/usr/sbin/u-boot-update`, `/usr/share/u-boot-menu/read-config`, `/etc/kernel/postinst.d/zz-u-boot-menu`): separate-`/boot` detection, `U_BOOT_SYNC_DTBS` rsync from `/usr/lib/linux-image-<version>`.
- fakemachine backends and auto selection: https://pkg.go.dev/github.com/go-debos/fakemachine ; Ubuntu discussion of debos needing `--disable-fakemachine` without nested KVM (Debian bug list, 2022-10).
