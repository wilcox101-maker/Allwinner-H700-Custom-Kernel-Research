# R1: boot chain and card layout for our images

Date: 2026-11-14. Task R1 (Kernel Research). **Built and checked on the desk only. Nothing here has
run on an RG34XX-SP**, and no card has been written. First use: by FEL, in RAM only (R2,
`docs/r2-fel-test-kit.md`), after the serial console (K3).

## 1. The chain
| Stage | What | Where it lives | Ours |
|---|---|---|---|
| Boot ROM (BROM) | in the SoC; reads the SPL from SD slot 1 at 8 KiB (eGON header + checksum), falls back to USB FEL | SoC | — |
| SPL | u-boot SPL: DRAM init (LPDDR4 or LPDDR3, one binary each), AXP717 rails | card, 8 KiB | `scripts/build-uboot.sh` |
| BL31 | TF-A v2.14.0, `PLAT=sun50i_h616` (PSCI: CPU on/off, reset, power-off) | inside the same binary (FIT) | same script |
| u-boot | mainline u-boot v2026.10 + our PE6 patch; picks the DTB, counts boots (R8), runs `extlinux.conf` | inside the same binary | same script |
| Kernel + DTB | `/vmlinuz-<ver>` and `/dtb-<ver>/allwinner/<fdtfile>` via `extlinux.conf` (`fdtdir`), written by `u-boot-menu` | FAT `/boot` | R10/R17 kernel package, R7 image |
| Root | ext4, `root=PARTUUID=…-02`, no initramfs needed (R20 boot-path check) | card partition 2 | R7 image |

## 2. Card layout (MBR)
| Offset | Size | Content | Notes |
|---|---|---|---|
| 0 | 512 B | MBR, disk signature `0x48373030` | GPT is not used: its 16 KiB entry array would overlap the SPL at 8 KiB (R1 open-conflict item 1, agreed with Deep Research) |
| 8 KiB | ≤ 1016 KiB | `u-boot-rg34xxsp-<dram>-2026.10.bin` (SPL + BL31 + u-boot, 745 KiB today) | the BROM also looks at 128 KiB for a backup SPL; our binary covers that offset with non-SPL data, which the BROM ignores |
| 1 MiB – 16 MiB | — | unused (alignment) | room for a later backup u-boot or larger builds |
| 16 MiB | 256 MiB | FAT32 `BOOT`, bootable flag: `extlinux/`, kernels, `dtb-<ver>/`, `uboot.env` | u-boot's environment lives here (`:auto` = the boot device's FAT partition, 64 KiB) |
| after | content + 20 % | ext4 `rootfs`, grown to the card on first boot (R7) | |

This is the layout R7's `image/genimage.cfg.in` already writes; R1 confirms it and fills the u-boot
slot. `image/build-image.sh UBOOT_BIN=…/u-boot-rg34xxsp-lpddr4-2026.10.bin …` puts the binary at 8 KiB.
DR's R24 (`docs/r24-image-with-uboot.md`) built both images that way, names them `…-uboot-<dram>.img`, and
checks the layout with `image/check-boot-layout.py` on every such build.

## 3. Why these versions
- **u-boot v2026.10** (`5508406`), not v2026.01: v2026.01's H616 DRAM driver reads the LPDDR3 TPR6
  value from the wrong bits. Andre Przywara's fix (*sunxi: H616: dram: fix LPDDR3 TPR6 parsing*,
  accepted 2026-04-27; ROCKNIX carries the same change as a local patch) is in v2026.10. Our PE6 patch
  applies unchanged; Deep Research's D2 check on v2026.01 still holds for its content.
- **TF-A v2.14.0** (`1d5aa93`), the newest release; `sun50i_h616` platform, release build.
- **Defconfig:** mainline's `anbernic_rg35xx_h700_defconfig` (the H700 handheld family; RG34XX-SP
  shares SoC, PMIC and DRAM wiring with the RG35XX 2024/Plus/H/SP), plus
  `config/u-boot/rg34xxsp.config`:
  - `ANBERNIC_RG34XXSP_DT_SELECTION=y` (our patch): PE6 low → `…-redux-panel.dtb`, high → `…-redux.dtb` (Q3);
  - R8's boot counter and fallback (`BOOTCOUNT_ENV`, `PREBOOT` with `bootlimit 3`, `altbootcmd`);
  - version `2026.10-rg34xxsp`, no git hash.
- **u-boot's own DT** stays the RG35XX 2024 tree (the defconfig's); u-boot prints *Model: Anbernic
  RG35XX 2024*. Only u-boot uses it; the kernel gets our DTB via `fdtfile`.

## 4. One binary per DRAM type
| File | DRAM | `vdd-dram` (DCDC3) | Values from |
|---|---|---|---|
| `u-boot-rg34xxsp-lpddr4-2026.10.bin` | LPDDR4 @ 672 MHz (original units) | 1.10 V | mainline defconfig = stock LPDDR4 on every field mainline exposes except TPR11/12 (R3) |
| `u-boot-rg34xxsp-lpddr3-2026.10.bin` | LPDDR3 @ 672 MHz (revised units) | 1.20 V | `config/u-boot/lpddr3.config`: stock's drive/ODT/TPR6/TPR10 (R3); TPR11/12 as ROCKNIX ships for the mainline driver |

**Wrong-binary risk.** LPDDR3 settings on an LPDDR4 board put 1.2 V on 1.1 V memory; the other way
round DRAM init most likely fails. Neither image can tell by itself which board it is on. So: name
images by DRAM type, and know a unit's type before the first write: Dale's statement of the hardware version
(Q10, 2026-11-17: v1.0 = 2 GB LPDDR4, Dale's unit), or stock boot0's UART line `select dram para<N>` (K3): 15 = LPDDR4, 14 or 0 = LPDDR3 (R3). A single SPL that reads the
DRAM straps (PH6/7/8/10) is possible later (R3 §4), not now.

**Size on Dale's unit (Q11, 2026-11-17):** 2 GB LPDDR4, so expect SPL `DRAM: 2048 MiB` and u-boot `DRAM:  2 GiB`.
Nothing in our build sets the size; the SPL measures it and u-boot only clamps it (u-boot v2026.10):

| Step | Where | What |
|---|---|---|
| Rank and bus width | `arch/arm/mach-sunxi/dram_dw_helpers.c:12` | tries 32-bit/2 ranks first, down to 16-bit/1 rank; the first that inits wins |
| Rows and columns, size | same file `:87`, `:144` | address-bit probe; size = 2^(cols+rows+3) × width × ranks |
| SPL prints, stores | `board/sunxi/board.c:655-661` | `DRAM: %d MiB`, size into the SPL header for u-boot proper |
| u-boot proper clamps | `board/sunxi/board.c:282-283` | `gd->ram_size` capped at `CONFIG_SUNXI_DRAM_MAX_SIZE` |
| The cap | `arch/arm/mach-sunxi/Kconfig:352-354` | `0x100000000` (4 GiB) for `MACH_SUN50I_H616`; no prompt, so a fragment can't change it, only a source patch |

CI guards it: `scripts/build-uboot.sh --config-only` (docs-check workflow, every PR) fails if either `.config` has
`CONFIG_SUNXI_DRAM_MAX_SIZE` below `0x80000000`, or if the clamp line in `board/sunxi/board.c` moves (so the check
gets reviewed, not silently passed). A wrong rank/width detection can still show 1 GiB on hardware; only K4 shows that.
The DRAM *type* check (K3 `select dram para15`) is a safety step, not a cap, and still comes first.

## 5. Desk results (2026-11-14)
| Check | Result |
|---|---|
| Sources at pinned commits, our patch applies | yes (v2026.10 `5508406`, TF-A `1d5aa93`) |
| Every fragment line holds after `olddefconfig` | lpddr4 8/8, lpddr3 19/19 |
| Build | both binaries, 762 385 bytes; BL31 45 164 bytes |
| eGON header + checksum (what the BROM checks) | ok for both; SPL 40 960 bytes. A one-byte change is caught (tested) |
| Fits the card gap (≤ 1016 KiB) | yes, 745 KiB |
| PE6 code + our DTB names, R8 `altbootcmd`, version string `U-Boot SPL 2026.10-rg34xxsp` | present in both |
| DRAM type and DCDC3 in `.config` | LPDDR4 / 1100 mV; LPDDR3 / 1200 mV |
| DRAM size cap in `.config` (Q11, added 2026-11-17, `--config-only`) | `SUNXI_DRAM_MAX_SIZE=0x100000000` (4 GiB) in both; two negative controls (cap patched to 1 GiB; clamp line changed) fail |
| Reproducible | two clean builds: identical SHA-256 |

SHA-256 (this build): lpddr4 `1d0381e1cb846ab2…`, lpddr3 `c0c3de979a2bc127…` (full values in the
build's `SHA256SUMS`). Binaries are not committed; they are build outputs, rebuilt by the script.

## 6. Recovery
- First runs are by **FEL, in RAM only** (R2): nothing is written; a power-off undoes everything.
- A card with our u-boot that does not boot: take it out, the unit is unchanged (stock lives on its own
  card). Rewrite the card from the release image.
- Kernel failures after an update: R8's automatic fallback; then the rescue entry over serial.
- Never write u-boot to the stock card or any card with data on it.

## 7. Open, needs the device
1. **K3** (serial). Dale's unit is LPDDR4 (Q10, v1.0 hardware); the stock line `select dram para<N>` is an optional cross-check. Allowed now on his 2 GB unit (Q11).
2. **K4** (FEL, `docs/r2-fel-test-kit.md`): SPL DRAM init (expect 2 GiB on Dale's unit, Q11), BL31, u-boot, the PE6 line.
3. First card boot on a spare card: extlinux, kernel, root; then R8's rollback on hardware (K17).
4. Not in this build, possible later: charge-only power-on (the PMIC powers the board on when USB is
   plugged in; ROCKNIX carries an unmerged AXP717 patch for that); a status LED in SPL; boot delay 2 s
   (default; lower once the serial path is proven).

## 8. Sources
- u-boot v2026.10 source: `configs/anbernic_rg35xx_h700_defconfig`, `arch/arm/mach-sunxi/dram_sun50i_h616.c`,
  `env/Kconfig` (`ENV_FAT_DEVICE_AND_PART` `:auto` for sunxi), `scripts/setlocalversion`.
- u-boot patchwork: 2228921 (*fix LPDDR3 TPR6 parsing*, v3, Andre Przywara, accepted 2026-04-27).
- TF-A v2.14.0, `plat/allwinner/sun50i_h616`.
- ROCKNIX tag 20261101 (`cefc143`): `projects/ROCKNIX/devices/H700/packages/u-boot-DDR3/` (LPDDR3
  defconfig values and the same TPR6 fix), referenced, not copied.
- This repo: `docs/r3-v106-boot0-dram-sets.md`, `docs/r7-image-tooling.md`, `docs/r8-update-rollback.md`,
  `docs/rg34xxsp-panel-detect-and-uboot-patch.md`.
