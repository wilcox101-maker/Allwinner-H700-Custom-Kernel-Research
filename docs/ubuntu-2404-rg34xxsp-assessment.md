# Ubuntu 24.04 LTS arm64 for the Anbernic RG34XXSP: compatibility assessment

Stage 2 (research and compatibility assessment), 2026-11-13. Research only: nothing was built, flashed or tested on hardware.

## 1. Goal and current understanding

**Goal:** a maintainable **Ubuntu 24.04 LTS (noble) arm64** distribution for H700 handhelds, starting with the RG34XXSP. No such image exists today. The handheld distros that do exist are either built on the stock 4.9 BSP kernel with Anbernic's Ubuntu 22.04 userspace (stock, StockOS-Mod, Knulli, muOS) or are mainline but not Ubuntu (ROCKNIX, postmarketOS).

**Why 24.04 and not 22.04:** 22.04 standard security support ends **May 2027** (about 6 months from now). 24.04 standard support runs to **May 2029**, and ESM runs to 2034 (ubuntu.com/about/release-cycle). 26.04 LTS exists (released 2026-04-23) and is the next step after this.

**Reference material:** the `Anbernic_RG34XXSP_Redux` repo (Dale's) is read-only input. Its Phase 0 dissection of the stock firmware is reused here (`docs/stock-boot-chain.md`, `docs/hardware-map.md`, `docs/field-reports.md`, `reference/stock-202505/`).

## 2. Verified facts, assumptions and open questions

### Stock baseline (from the stock image and Dale's device, via the Redux repo)
| Item | Value | Status |
|---|---|---|
| Boot chain | BROM → boot0 at 8 KiB (DRAM training) → Allwinner BSP u-boot → Android boot image v2 on p4 → BusyBox initramfs → `switch_root` to ext4 p5 | Confirmed |
| Kernel | 4.9.170 BSP, no matching source, closed Mali driver, `HZ=100`, `ZRAM` off | Confirmed (`kernel.config`) |
| Userspace | Ubuntu 22.04 base + Anbernic launcher on appfs (p6) | Confirmed |
| Panel | `fog_fj035fhd05_v1`, RGB (`lcd_if=0`), 720×480 | Confirmed (stock `board.dts`) |
| PMIC | AXP2202 at I²C 0x34; lid hall sensor on PE7 inside the power-key node | Confirmed |
| Wi-Fi / BT | Realtek RTL8821CS over SDIO, BT reset on PG19 | Confirmed |
| DRAM | Stock DTB says `dram_type=3`, `dram_clk=792`, but these are template values. boot0: LPDDR4 @ 672 MHz on the 2025 image; strap-selected LPDDR3/LPDDR4 in V1.0.6 (`docs/r3-v106-boot0-dram-sets.md`) | Desk-confirmed from boot0; boot test pending |

### Mainline status (primary sources)
| Area | Upstream status | Evidence |
|---|---|---|
| H700 board DTs | `sun50i-h700-anbernic-rg35xx-{2024,plus,h,sp}.dts` are upstream. The RG35XX SP DT has the lid as a `gpio-keys` switch on PE7. **There's no RG34XX-SP DT upstream.** | kernel tree |
| PMIC | AXP717 driver upstream (MFD, regulators, battery, USB power). Andre Przywara's series notes the BSP's "AXP2202" appears to be the same chip | lore, 2024-03 |
| CPU OPPs, audio codec | H616 codec upstream (applied for 6.13). Line-out routing for RG35XX boards included | linux-sunxi, 2024-10 |
| GPU | Mali-G31 MP2 node + PRCM PPU power domain upstream; Panfrost H616 compatible. Mesa Panfrost: Bifrost v7 (G31) gets GLES 3.1 and Vulkan 1.3 (PanVK) | linux-sunxi 2025-04; docs.mesa3d.org |
| Display (DE33 + RGB LCD) | **Not fully upstream.** The early DE33 code was a proof of concept, and the DE33 binding is being redone (planes shared between mixers; v2 series May–June 2026). Working LCD output still needs out-of-tree patches | dri-devel / LKML 2025-10 → 2026-06 |
| Panel driver | Out of tree: generic `panel-mipi-dpi-spi` (kikuchan98 v2, 2025-02) plus a **per-panel init blob** loaded as firmware | ROCKNIX patch 0110 |
| Wi-Fi | rtw88 SDIO with RTL8821CS upstream (`rtw88_8821cs`), firmware `rtw88/rtw8821c_fw.bin` | kernel tree |
| Bootloader | Mainline u-boot: `anbernic_rg35xx_h700` defconfig (2025.01), H616 DRAM driver with DDR3/LPDDR3/LPDDR4 and the H700 PHY address map | u-boot lists |

### What ROCKNIX ships for H700 today (ROCKNIX/distribution @ `4fc79d7`, 2026-11-13)
- **Kernel 7.2** (kernel.org tarball) + **32 H700 patches** + their own DTS directory (15 files).
- **u-boot v2026.01**, built twice: `anbernic_rg35xx_h700_lpddr4_defconfig` ("DDR4" image) and `..._lpddr3_defconfig` ("DDR3" image), plus TF-A bl31. Two u-boot patches: a DRAM driver update and AXP717 charge-only boot.
- **RG34XX-SP DT** = the RG35XX SP DT + a different panel compatible + joypad axis settings. **There are two panel variants:** `anbernic,rg34xx-sp-panel` and `anbernic,rg34xx-sp-v2-panel`, each with its own init blob from `kernel-firmware`.
- Patch areas: the DE33 rework (Jernej, 21 parts), HDMI+LCD, the generic MIPI panel driver, PWM backlight (H616 PWM v8, 2026-08), the out-of-tree `rocknix-joypad` input driver, USB OTG fixes, suspend fixes (display, codec, LCD pads, axp20x-pek wake key), GPU OPPs.
- A ROCKNIX fork commit says it was tested on an "Anbernic RG34XX-SP (LPDDR4)".

### Open questions (each blocks something)
1. **DRAM type on Dale's unit.** Original 2 GB is probably LPDDR4 (ROCKNIX test note; 2025 boot0); revised boards are reported as LPDDR3. Blocks the u-boot build. *Verify:* boot ROCKNIX's DDR4 image on a **spare** card (K2) or FEL (K4).
2. **Which panel blob matches Dale's panel** (`rg34xx-sp` vs `-v2`). Driving a panel with the wrong init sequence is a reported screen-damage risk. *Answered at the desk:* PE6 strap (`docs/rg34xxsp-panel-detect-and-uboot-patch.md`); confirm on hardware (K4).
3. **UART pads** are not found. Needed for any bring-up that fails before display. Blocks safe M2 (K3).
4. **Revised-board handling:** stock V1.0.6 notes a non-removable TF1 on revised units. How those units boot from a card has to be confirmed before supporting them.
5. **Licensing of the panel init blobs** in ROCKNIX `kernel-firmware`. Needed before we redistribute them (R9).

## 3. Recommendation and alternatives

| | A: 24.04 userspace on the stock 4.9 kernel | **B: mainline kernel + mainline u-boot + 24.04 (recommended)** | C: wait for full upstream |
|---|---|---|---|
| Kernel | Frozen BSP binary, no source, no security fixes | Kernel 7.2 + about 32 patches, rebaseable | Upstream only |
| systemd 255 (noble) | 4.9 is above the 3.15 minimum but below the 4.15 "recommended baseline" (*verify against noble's README*) | Fine | Fine |
| GPU | Closed libmali built for the old userspace; integrating it with noble is a risk | Panfrost + noble's Mesa 25.2.8 (noble-updates) | Panfrost |
| Display | Works | Works with out-of-tree DE33/panel patches | Not yet usable |
| Time to first boot | Short | Medium | Unknown |
| Maintenance | Dead end | Rebase cost on each kernel move | Lowest, but not available |

**Recommendation: B.** Ubuntu 24.04 is a five-year commitment, and option A pins it to a kernel nobody can fix. Option B is proven on this exact device by ROCKNIX. The cost is carrying the out-of-tree patch set until DE33, the panel driver and PWM land upstream. Keep A only as an emergency fallback, not as a product.

**Ubuntu's own kernel is not an option.** It has no RG34XX-SP display support. We ship our own `linux-image` package.

## 4. Architecture

```
layer              source                              per-device?
-----------------  ----------------------------------  -----------
boot ROM           SoC                                 no
SPL + u-boot       mainline v2026.01 + 2 patches,      yes (LPDDR4 / LPDDR3 builds)
                   TF-A bl31
kernel             7.2 + H700 patch set (from ROCKNIX) shared H700 kernel
DTB                rg34xx-sp / rg34xx-sp-v2-panel      yes
firmware           rtw88, rtl_bt, panel blobs          per panel
initramfs          initramfs-tools (noble)             shared
rootfs             Ubuntu 24.04 arm64 via mmdebstrap   shared
device config      board package (udev, ALSA UCM,      yes
                   input map, power/lid)
```

- **Card layout (proposal, revised 2026-11-13):** an **MBR** partition table (as ROCKNIX's H700 build does, `PARTITION_TABLE="msdos"`), u-boot-sunxi-with-spl at 8 KiB, partitions from 16 MiB or later, a FAT `/boot` with extlinux.conf + kernel + DTBs + initramfs, an ext4 rootfs, and an exFAT ROM partition first for Windows visibility (as stock does). A *standard* GPT can't be used: its 128 entries fill LBA 2–33 (1–17 KiB) and the SPL at 8 KiB would overwrite them. Stock gets away with GPT because it uses a **limited GPT of 8 entries** (LBA 2–3, ending at 2 KiB; read from the 2025 and V1.0.6 images). That's a valid fallback if GPT is ever needed, but it has to be created explicitly (`sgdisk -n`-style tools default to 128 entries).
- **Board selection:** one image per DRAM type (as ROCKNIX does). The DTB/panel is selected in u-boot by board detection where possible; otherwise it's fixed per image. **Never boot an unknown panel.**
- **RAM tiers:** 512 MB / 1 GB get zram on by default and no desktop. 2 GB gets the same minimal session. A full desktop session is not a goal on 512 MB. (Per-tier spec: task R13.)
- **Updates:** kernel and board packages from our own apt repo. The noble archive for everything else. Keep the last kernel as an extlinux fallback entry.

## 5. Plan and milestones

| # | Milestone | Done when | Risk |
|---|---|---|---|
| M0 | Build host + serial console | Cross toolchain on WSL2/Linux; UART pads found and a 115200 console captured from stock | Low |
| M1 | **Hardware baseline (no building)** | ROCKNIX DDR4 image on a **spare card** boots Dale's unit: record DRAM type, panel variant, dmesg | Low: separate card, stock card untouched |
| M2 | Our boot chain | Our u-boot + kernel 7.2 + patches + RG34XX-SP DTB boot to a BusyBox shell on serial | Medium |
| M3 | Ubuntu 24.04 rootfs | mmdebstrap noble arm64 boots to a login on the panel; apt works | Medium |
| M4 | Hardware enablement | Display, input, audio (speaker + jack), Wi-Fi, BT, battery, lid suspend/resume, HDMI | High (suspend, panel) |
| M5 | Reproducible image | Scripted build (mmdebstrap + genimage or debos), checksums, versioned artifacts, CI | Medium |
| M6 | Release 0.1 (original 2 GB board only) | Test matrix passes on hardware; recovery documented | — |

Revised (512 MB / 1 GB, LPDDR3, new panel) boards come after M6 and need their own hardware.

## 6. Test and recovery notes

- **Every step stays on the microSD card.** The stock card and its raw first 36 MiB are kept as an untouched image (`RG34XXSP.img` already exists). A bad card is recovered by reflashing it. Nothing in this plan writes to internal storage.
- Writing u-boot at 8 KiB **replaces boot0 on that card**. Do it only on a test card, never on the stock card.
- Hardware tests need the device: DRAM/boot, panel, input, audio, Wi-Fi/BT, battery/charging, lid suspend/resume, HDMI, both SD slots.

## 7. Risks and next steps

- **Panel:** the wrong init blob or driver could damage the screen. Mitigation: use only the blob confirmed in M1, and refuse to start on an unknown board.
- **Patch debt:** about 32 out-of-tree kernel patches. Track ROCKNIX and upstream DE33; drop patches as they land.
- **Suspend/lid:** the most-reported problem area on every H700 firmware. ROCKNIX carries 5+ suspend patches.
- **Panfrost on G31:** GLES 3.1 is fine for emulators; performance versus the closed Mali driver has to be measured (K11).
- **Next step:** M1 on a spare card (needs Dale), and M0 in parallel. Both wait for the device (v0.5).

## Sources
- Ubuntu release cycle: https://ubuntu.com/about/release-cycle
- RG35XX DTs (Ryan Walklin): https://lore.kernel.org/linux-sunxi/20240420104042.334259-1-ryan@testtoast.com/
- AXP717 support (Andre Przywara): https://lore.kernel.org/all/20240328095631.GW13211@google.com/T/
- H616 audio codec: https://lists.infradead.org/pipermail/linux-arm-kernel/2024-October/973558.html
- H616 Mali GPU node: https://lists.infradead.org/pipermail/linux-arm-kernel/2025-April/1022086.html
- Panfrost driver matrix: https://docs.mesa3d.org/drivers/panfrost.html
- DE33 rework (Jernej Škrabec): https://lkml.org/lkml/2025/10/31/301 and https://ratatoskr.run/dri-devel/2026/05/8992458/t
- rtw88 SDIO / RTL8821CS: https://lkml.iu.edu/hypermail/linux/kernel/2304.0/04920.html
- u-boot RG35XX-2024 / H700 DRAM: https://lists.denx.de/pipermail/u-boot/2024-October/567745.html
- ROCKNIX H700 sources: https://github.com/ROCKNIX/distribution (`projects/ROCKNIX/devices/H700`, commit 4fc79d7)
- ROCKNIX 20260901 release (kernel 7.2, DDR3/DDR4 images): https://github.com/ROCKNIX/distribution/releases/tag/20260901
- RG34XX-SP LPDDR4 test note: https://github.com/UzuCore/ROCKNIXK/pull/482
- Noble Mesa versions: https://ubuntuupdates.org/package/core/noble/main/updates/mesa
- systemd kernel requirements: https://chromium.googlesource.com/chromiumos/third_party/systemd/+/refs/tags/upstream/v256.9/README
