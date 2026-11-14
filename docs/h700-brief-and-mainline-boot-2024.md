# H700 product brief + early mainline boot (rg35xx-cfw #205)

Research note, 2026-11-13. Research only: nothing here was tested on the RG34XXSP.

## 1. Allwinner H700 product brief
Source: https://www.allwinnertech.com/uploads/pdf/2021070513595227.pdf. Copyright 2020; no version number; Allwinner says it's for reference only and may change without notice.

| Area | Brief says | What it means for the project |
|---|---|---|
| CPU | 4× Cortex-A53, 64-bit (no clock given) | Matches the project brief. Clocks come from the OPP tables, not this document |
| GPU | Mali-G31 MP2, **OpenGL ES 3.2, Vulkan 1.1** (hardware) | Software caps what we get: Mesa Panfrost exposes **GLES 3.1** on Bifrost v7. Don't promise GLES 3.2 |
| Memory | 32-bit bus; **DDR4, DDR3, DDR3L, LPDDR3, LPDDR4**; max 4 GB | Confirms the SoC handles both LPDDR3 (revised boards) and LPDDR4. It says nothing about which type a given board has (see `docs/r3-v106-boot0-dram-sets.md`) |
| Display out | HDMI 2.0a up to 4K60; dual-link LVDS; **RGB888/666/565 up to 1080p60**; CVBS; max 4096×2048 | The RG34XXSP panel is RGB (stock `lcd_if=0`, 720×480), well within limits. Mainline LCD output still needs the out-of-tree DE33 work |
| Video engine | Decode H.265 Main10 4K60, VP9 P2 4K60, AVS2, H.264 4K30; encode H.264 | **Open:** mainline driver support for the H616/H700 VPU is not established for this project. Assume software decode until verified |
| Audio | 2 DAC channels, one audio output; **Audio Hub** with internal mixing; 3× I2S/PCM (TDM, 8 ch, 32-bit); DMIC | The analog codec is upstream (6.13). The Audio Hub (needed for HDMI audio) is out of tree; ROCKNIX's `sunxi_v2` AHUB patch is currently *disabled* |
| I/O | SD3.0/eMMC5.0; SDIO 3.0; 3× USB2 host + 1× OTG; **6× UART**; 6× TWI; 2× SPI; 6-ch PWM; 4-ch GPADC; LRADC; 2× EMAC | GPADC drives the analog sticks (mainline since 6.11 on the RG35XX-H). PWM drives the backlight (H616 PWM driver still out of tree) |
| Security | TrustZone, secure boot, eFuse, 2 Kbit SID, crypto engine, TRNG | Secure boot is not used on retail units as far as we know (*unverified*; stock and mainline SPLs both boot). The TRNG could seed early entropy |
| Package | TFBGA-421, 15×15 mm, 0.65 mm pitch | — |
| **Not in the brief** | Boot sources and order, process node, power figures, clocks | Boot order has to come from linux-sunxi and testing |

## 2. rg35xx-cfw issue #205: "Is there a tutorial to build kernel for rg35xxh?"
Source: https://github.com/rg35xx-cfw/rg35xx-cfw.github.io/issues/205. Boot logs date from April 2024. Devices: RG35XX Plus/H (SoC reported as "Allwinner H616 SoC (1823)", 1 GiB). The RG34XX family is not discussed.

### Findings
- **Mainline booted the RG35XX Plus/H in spring 2024:** SPL → u-boot 2024.04-rc3 → **extlinux** (`/boot/extlinux/extlinux.conf`, `/boot/Image` from mmc 0:1) → Linux 6.8.2 (loki666's buildroot branch) → login prompt. Serial console `ttyS0,115200` at `serial@5000000`.
- **No stock pieces needed:** acmeplus notes that mainline needs no boot0 or boot-package. The SPL does DRAM init itself. This confirms that our card can be self-contained.
- **Image layout:** acmeplus suggests reusing Batocera's Orange Pi Zero 2 (H616) recipe and genimage config.
- **DTB fallback:** the DTB path in extlinux was wrong, but the kernel still booted using u-boot's own DTB. Useful for debugging, but our image must point at the right DTB **explicitly**. The DTB carries the panel selection.
- **Wrong DT doesn't work:** the Orange Pi Zero3 DT does not boot the device. Use the board's own DT.
- **HDMI** worked with Jernej Škrabec's H616/H618 HDMI patch series (fetched with `b4`).
- **Wi-Fi failed:** `rtw_8821cs` couldn't load its firmware. That's the rootfs missing `rtw88/rtw8821c_fw.bin`, not a driver bug.
- Alternative BSP kernel: `chainsx/linux-t527` (5.15 with Allwinner's out-of-tree drivers, sun50iw9/10). Not recommended for us: it's vendor code with no upstream path.

### What it means for our build
1. **Boot flow confirmed:** mainline SPL/u-boot at 8 KiB + extlinux on a FAT `/boot` is the proven pattern. It matches the layout in the assessment.
2. **Firmware is a packaging item:** our image must ship `rtw88/rtw8821c_fw.bin` and `rtl_bt/rtl8821cs_fw.bin` + `_config.bin`. Answered since: noble's `linux-firmware-realtek` has them (`docs/r4-noble-firmware-audit.md`).
3. **Image tool candidate:** genimage (used by Batocera/Buildroot) for the card layout, with mmdebstrap for the noble rootfs. To decide in R7.
4. **Serial testing tip:** acmeplus tested with the UART connected and **the battery removed**, a way to make sure power-off and power-on cycles really reset the board.

## Sources
- Allwinner H700 product brief: https://www.allwinnertech.com/uploads/pdf/2021070513595227.pdf
- rg35xx-cfw issue #205: https://github.com/rg35xx-cfw/rg35xx-cfw.github.io/issues/205
- loki666 buildroot branch: https://github.com/loki666/buildroot/tree/rg35xx-plus
- chainsx/linux-t527: https://github.com/chainsx/linux-t527
- Panfrost driver matrix: https://docs.mesa3d.org/drivers/panfrost.html
