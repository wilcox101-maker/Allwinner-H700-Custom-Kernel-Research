# R10: kernel config, cross-build and Debian packages for Ubuntu 24.04

Kernel Research chat, 2026-11-13. **Desk work only: the packages below were built, not booted.**
Installing them on a device waits for a serial console (K3) and a first FEL boot (K4), on a spare
card only.

## Goal and scope
- A reproducible kernel for the RG34XX-SP as `.deb` packages that install on Ubuntu 24.04 (noble).
- In scope: config, cross-build, packaging, sizes, and checks that the config covers the board.
- Not in scope yet: display (no mainline H616/H700 display or PWM support; see
  `kernel-findings-2026-11-13.md` Q2), the boot chain (R1/R2), the image (R7), updates (R8).

## Decision: base the packages on mainline, not on ROCKNIX's 7.2 tree
The task note said "ROCKNIX 7.2 + H700 set". This build uses **torvalds/linux `97d73c8`
(after v7.4-rc2) + our six patches** instead:
- **Our series targets it.** Patches 0001–0006 and all three board trees are checked against it;
  porting them back to 7.2 is extra work with nothing to show for it yet.
- **Repo rules.** ROCKNIX's 32 H700 kernel patches can only be referenced here by name and commit,
  never copied. Layering them belongs in a later, separate step with its own licence check (R9).
- **What 7.2 + ROCKNIX would add today** is mainly the display stack (LCD, panel, PWM backlight),
  the joypad driver and suspend glue. Display is the one large gap, and it is tracked upstream (R11).
- **To revisit** when the display can't wait: carry the upstream display/PWM series (by
  name and version, pinned) on top of our base, rather than moving the base to 7.2.
- Pin to **v7.4 final** once it is tagged; v7.4-rc2 is a moving target only in that sense.

## How the config is made (`config/rg34xxsp.config`, `scripts/build-kernel.sh`)
1. `make defconfig` (arm64).
2. A generated fragment turns off every other `ARCH_*` platform (53 at `97d73c8`), read from
   `arch/arm64/Kconfig.platforms`, so it follows new kernel versions without editing.
3. `config/rg34xxsp.config` on top, then `olddefconfig`. Every line says why it is there:
   - **trim:** no PCI, ACPI or virtualization (the SoC has no PCIe; no ACPI firmware);
   - **board drivers** that `defconfig` lacks, found by `tools/dt_driver_coverage.py`: sticks
     (`INPUT_JOYSTICK`, `JOYSTICK_ADC`, `IIO_MUX`, `SUN20I_GPADC`), audio codec, AXP717
     ADC/battery/USB power, IOMMU, PRCM power domains, video engine (Cedrus);
   - **Wi-Fi/BT** as modules (`RTW88_8821CS`, `BT_HCIUART_RTL`, `BT_RTL`) with
     `FW_LOADER_COMPRESS_ZSTD`, because noble ships the firmware `.zst` (R4); no `EXTRA_FIRMWARE`;
   - **zram** with lz4 and zstd back-ends, lz4 default (R5 found noble's `virtual` kernel lacks it);
   - **systemd v255** required options and the optional ones we want (oomd's PSI, cgroup BPF,
     seccomp filter, namespaces), from systemd's own README at tag `v255` (`db11bab`);
   - **reproducible name:** `LOCALVERSION_AUTO` off, `LOCALVERSION=-rg34xxsp`, so the release is
     `<version>-rg34xxsp` with no hash of the local patch commits.

**Two checks run before any build, and either one stops it:**
- every line of the fragment holds in the final `.config` (an option whose dependencies are
  missing silently disappears otherwise; this caught `JOYSTICK_ADC` without `INPUT_JOYSTICK`);
- every enabled node in all three RG34XX-SP DTBs has its driver enabled
  (`tools/dt_driver_coverage.py`). Against plain `defconfig` it lists 11 gaps; with the fragment,
  0 in each tree. Ignored nodes and why: `tools/dt_driver_coverage.ignore` (root, CPUs, cache,
  `simple-battery`, and the H616 `hstimer`, whose driver is only selectable on 32-bit ARM; arm64
  uses the architected timer).

## Packaging
- `make bindeb-pkg` with `DEB_BUILD_PROFILES=pkg.linux-upstream.nokernelheaders`: no
  `linux-headers` package, since nothing here builds out-of-tree modules.
- Host packages (Ubuntu 24.04 build host): `dpkg-dev fakeroot rsync kmod cpio debhelper
  libdw-dev libelf-dev libssl-dev`, besides the workbench tools.

## Results
Built 2026-11-13 on an Ubuntu 24.04 x86-64 host with 2 CPUs and `aarch64-linux-gnu-gcc` 13.2
(`WORK=/tmp/wb scripts/build-kernel.sh --build`, after `scripts/workbench.sh`).

| Item | Result |
|---|---|
| Config checks | all 60 fragment lines hold; 62 / 64 / 65 enabled nodes (upstream-style / redux / reduxstock), **0 without a driver** |
| Build time | 25 min from clean (2 jobs); re-packaging an unchanged tree: about 1 min |
| Kernel release | `7.4.0-rc2-rg34xxsp` |
| Packages | `linux-image-7.4.0-rc2-rg34xxsp_7.4.0~rc2-1_arm64.deb` (18.4 MB), `…-dbg_…` (62.4 MB, debug symbols, never installed on the device), `linux-libc-dev_…` (not needed) |
| Installed size | **56.4 MB**: `vmlinuz` 9.3 MB (gzip; the raw `Image` is 23 MB), **924 modules, 38.5 MB**, `System.map`, config |
| Device trees | all 67 Allwinner arm64 DTBs, including the 3 RG34XX-SP trees, under `/usr/lib/linux-image-7.4.0-rc2-rg34xxsp/allwinner/`, the directory extlinux `FDTDIR` can point at (R1) |

**What the numbers say:**
- **Modules are the bulk** and mostly not ours: 924 modules come from the generic `defconfig`
  (USB gadgets, network, sound and media drivers for other boards). Trimming them is next step 2;
  most of the 38.5 MB should go, but no figure is claimed until it is measured.
- **The kernel is 9.3 MB compressed.** u-boot's `booti` can load the gzip image directly (it
  decompresses it), so the boot partition needs room for about 10 MB per kernel, plus the
  initramfs, times two for a fallback entry (R1/R8 sizing). Not yet tried on a device.
- **The version is stable:** the release name and package version contain no hash of the local
  patch commits, so rebuilding the same tree gives the same names.


## What this does not tell us (needs hardware)
- Whether it boots: needs K3 (UART) and K4 (FEL), then a spare card.
- Whether each driver *works* on this board, not just binds: K2/K5/K6/K14–K16 and the M6 matrix.
- Real memory cost on the 512 MB tier: K12, against the R5 QEMU numbers.

## Next steps
1. Measure module load at boot in QEMU (`virt`, Cortex-A53) with the R5 rootfs: kernel + initramfs
   size and RAM after boot, for the R13 tier spec. Board drivers won't bind there; generic ones will.
2. Trim modules that no RG34XX-SP node or noble feature needs (the `defconfig` still builds many
   generic USB/network/sound drivers), with before/after sizes.
3. Pin to v7.4 final when tagged; re-run `workbench.sh` and this script.
