# R24: card image with the real u-boot (desk), and the R8 `mmc 0:1` check

Deep Research, 2026-11-14. Follows R1 (KR's u-boot build) and R7 (image tooling). **Desk and QEMU only.** No card
was written and nothing ran on an RG34XX-SP. What the boot ROM, the SPL's DRAM init and u-boot do on the real board
stays K3 → K4 (FEL) → first spare-card boot.

## 1. Result in short
- `image/build-image.sh` with `UBOOT_BIN=` now builds a complete card image: KR's SPL + BL31 + u-boot at 8 KiB,
  FAT `/boot` at 16 MiB, ext4 root. Built for **both** DRAM types from the same rootfs inputs.
- The image is **named by DRAM type** (`…-uboot-lpddr4.img`, `…-uboot-lpddr3.img`, R1 §4) and records the u-boot
  in `/etc/reduxos-release` (`UBOOT=u-boot-rg34xxsp-lpddr4-2026.10`). The build refuses a binary whose name doesn't
  say `lpddr4`/`lpddr3`, or whose `.config` says the other type.
- New `image/check-boot-layout.py` (32 checks, read-only) runs at the end of every u-boot image build; a failure
  fails the build. Both images: **32/32**. Eight negative controls fail on the intended check.
- The u-boot region survives first boot: after QEMU's first boot grew root from 595 MiB to 2.7 GiB (MBR rewritten),
  the bytes at 8 KiB still equal the binary and the gaps are still empty.
- **R8 `mmc 0:1` is right** for a card in slot 1 (TF1); see §4. Caveat: u-boot sees only slot 1.

> **2026-11-15 update (R9):** the checker has an 8th section, the bootloader licence notices in the root fs
> (33 checks). See `docs/r9-licensing-redistribution.md` §3a.

## 2. What was built (2026-11-14)
| Input | Value |
|---|---|
| repo | `main` at `e1c9583` (+ this change) |
| u-boot | `scripts/build-uboot.sh --dram all --sources`: SHA-256 `1d0381e1…` (lpddr4), `c0c3de97…` (lpddr3), **identical to KR's R1 values** on a different machine (reproducible) |
| kernel | `scripts/workbench.sh --display` + `build-kernel.sh --display --build`: `linux-image-7.4.0-rc2-rg34xxsp_7.4.0~rc2-1_arm64.deb` |
| images | `reduxos-rg34xxsp-noble-20261114-deb-uboot-lpddr4.img` (`19122382…`), `…-uboot-lpddr3.img` (`a23eedc3…`), 867 MiB each; not committed |

## 3. `image/check-boot-layout.py IMAGE [UBOOT_BIN]`
| # | Check | Why |
|---|---|---|
| 1 | MBR 0x55AA, disk signature `0x48373030`, no `EFI PART` at LBA 1 | PARTUUID root; a GPT entry array would cover 8 KiB (R1 open-conflict item 1) |
| 2 | at 8 KiB: `eGON.BT0`, SPL length multiple of 512, checksum valid | the boot ROM's own acceptance test |
| 3 | bytes at 8 KiB == `UBOOT_BIN`; ends before 1 MiB (`0xbc211` today); 512 B–8 KiB empty; u-boot end → first partition empty; no valid eGON header at 128 KiB | nothing else in the boot area; the BROM's backup-SPL slot holds no stray SPL |
| 4 | p1 0x0c, bootable, at 16 MiB; p2 0x83 after p1; no partition inside the u-boot region | u-boot's env `:auto` picks the first **bootable** partition (§4) |
| 5 | DRAM type in image name == binary name == binary `.config`; DCDC3 1100 mV (LPDDR4) / 1200 mV (LPDDR3) | wrong type puts 1.2 V on 1.1 V DRAM |
| 6 | FAT has `extlinux.conf` **and** R8's `extlinux-fallback.conf`, both with `fdtdir`; every listed kernel present; both PE6 DTBs under `dtb-<ver>/allwinner/` | u-boot loads `fdtdir` + `fdtfile` (`allwinner/…-redux-panel.dtb` or `…-redux.dtb`) |
| 7 | u-boot `.config`: env in FAT, not redundant (`CONFIG_ENV_REDUNDANT`, v2026.10's name); root fs `fw_env.config` = `/boot/uboot.env 0x0000 0x10000` matches `CONFIG_ENV_FAT_FILE` and `CONFIG_ENV_SIZE` | `fw_setenv` (R8 hook) and u-boot must agree on the env format, or the CRC fails and the trial is lost |

Needs `python3`, `mtools`, `e2fsprogs` (`debugfs` with `?offset=`). Works on any image file; never opens a device.

### Negative controls (each fails, on the named check only)
| Change | Fails |
|---|---|
| LPDDR3 image checked against the LPDDR4 binary | 3 (bytes), 5 (both DRAM checks) |
| one byte flipped inside the SPL | 2 (checksum) |
| one stray byte at 2 MiB | 3 (gap not empty) |
| `EFI PART` written at LBA 1 | 1, 3 |
| PE6-high DTB deleted from the FAT | 6 |
| image name without a DRAM type | 5 |
| `.config` with `CONFIG_ENV_SIZE=0x20000` | 7 |
| LPDDR4-named binary with the LPDDR3 `.config` | 5 (type, DCDC3 1200 mV) |

`build-image.sh` also refuses, before writing anything: a binary named `u-boot-sunxi-with-spl.bin` (exit 2), and an
`…-lpddr4-…bin` whose `.config` is LPDDR3 (exit 2).

### Results on the real images
| Image | check-boot-layout | QEMU smoke (512 MB) | After first boot (root grown to 2.7 GiB) |
|---|---|---|---|
| `…-uboot-lpddr4.img` | 32/32 | 12/12 | 32/32: u-boot bytes, gaps and disk signature unchanged |
| `…-uboot-lpddr3.img` | 32/32 | not run (identical rootfs path) | — |

QEMU `virt` ignores the boot area and loads the kernel itself, so the smoke test says nothing about u-boot; it shows
the u-boot image is otherwise the same working image as CI's.

## 4. R8: is `sysboot mmc 0:1` the right device? (handoff item 3)
Yes, for a card in slot 1. From the u-boot v2026.10 source as built by `build-uboot.sh`:
1. u-boot's own DT is `sun50i-h700-anbernic-rg35xx-2024` (defconfig). It enables **only `&mmc0`** (SDC0, slot 1).
   `arch/arm/dts/sunxi-u-boot.dtsi` sets alias `mmc0 = &mmc0` (and `mmc1 = &mmc2` only if
   `CONFIG_MMC_SUNXI_SLOT_EXTRA == 2`; ours is `-1`). With `CONFIG_DM_SEQ_ALIAS=y`, slot 1 is **mmc 0**.
2. The environment: `CONFIG_ENV_FAT_DEVICE_AND_PART=":auto"`. `env/fat.c` replaces `:` with `mmc_get_env_dev()`,
   which (`board/sunxi/board.c`) returns **0** when the BROM loaded the SPL from SDC0 (`SUNXI_BOOTED_FROM_MMC0` or
   `…_HIGH`, the 128 KiB backup), and `CONFIG_ENV_MMC_DEVICE_INDEX=0` for FEL. `auto` (`disk/part.c`) takes the
   first **bootable** partition: p1. So the env lives on `mmc 0:1`, the same FAT `altbootcmd` reads.
3. Therefore `altbootcmd`'s `sysboot mmc 0:1 fat … /extlinux/extlinux-fallback.conf` and the saved env point at the
   same partition, and check 6 confirms the file is on it in the image.

**Caveat, now documented:** u-boot has no driver instance for slot 2 (SDC2). An image in slot 2 can't be a boot or
env target even if the BROM tried SDC2. Our images go in **slot 1**; slot 2 is data for Linux. (Enabling slot 2 in
u-boot would need `MMC_SUNXI_SLOT_EXTRA=2`, which would also make `mmc 1` = SDC2; not needed for v0.x.)

## 5. Not proven here (needs the device)
- That the BROM accepts this SPL from a real card, DRAM init on each type, BL31, u-boot's PE6 read: K3 → K4 (FEL,
  RAM only) first, then a spare card.
- That u-boot finds the env and extlinux on mmc 0:1 on hardware, and R8's rollback on real u-boot: K17.
- Slot-2 behaviour of the BROM with a bootable card in TF2 and none in TF1: not tested, not supported.

## 5a. Stock card facts (device-verified, Redux 2026-11-17) [V]
The stock layout this image must leave alone checks clean: p5 `linuxrootfs`, p6 `appfs` and p7 pass `e2fsck -n` (mounted,
read-only); p1 (FAT32) only shows the in-use flag while mounted (details: `stock-re-boot-and-userspace.md`, last section).
A FAT data partition will carry the same flag whenever it is mounted: the Phase 2 read-only design should treat
exit 1 from `fsck.vfat -n` on a mounted FAT as normal.

## 6. Recovery
Nothing here writes a card. When a card is written later: use only a spare card, the image matching the unit's DRAM
type (Q10: as Dale states it, v1.0 = LPDDR4, or from K3's `select dram para<N>`: 15 = LPDDR4, 14 or 0 = LPDDR3), and
keep the stock card untouched. A card that
doesn't boot is fixed by taking it out; the unit is unchanged.

**Dale's unit (Q10/Q11, 2026-11-17):** v1.0 hardware, 2 GB LPDDR4 (as Dale states, Q10), so its image is `…-uboot-lpddr4.img`;
K3's `select dram para15` is an optional cross-check. K3 + K4 may run now (Q11). Expected size 2 GiB (R1 §4).

## 7. How to reproduce
```sh
scripts/build-uboot.sh --dram all --sources                 # .work/u-boot-out/
scripts/workbench.sh --display && scripts/build-kernel.sh --display --build
deb=$(ls .work/linux-image-*.deb | grep -v -- -dbg_)
sudo KERNEL_DEB=$deb UBOOT_BIN=.work/u-boot-out/u-boot-rg34xxsp-lpddr4-2026.10.bin \
     SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) image/build-image.sh   # runs check-boot-layout.py at the end
python3 -I image/check-boot-layout.py out/reduxos-*-uboot-lpddr4.img .work/u-boot-out/u-boot-rg34xxsp-lpddr4-2026.10.bin
```

## 8. Sources
u-boot v2026.10 (`5508406`): `board/sunxi/board.c` `mmc_get_env_dev()`, `arch/arm/mach-sunxi/board.c`
`sunxi_get_boot_device()`, `env/fat.c`, `disk/part.c` (`auto` → first bootable), `arch/arm/dts/sunxi-u-boot.dtsi`,
`dts/upstream/src/arm64/allwinner/sun50i-h700-anbernic-rg35xx-2024.dts`, the built `.config`. This repo:
`docs/r1-boot-chain.md`, `docs/r7-image-tooling.md`, `docs/r8-update-rollback.md`, `image/genimage.cfg.in`.
