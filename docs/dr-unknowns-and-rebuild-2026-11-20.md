# Remaining firmware unknowns (Ghidra and desk) and a full rebuild from source

Date: 2026-11-20. Deep Research, at Dale's request ("use Ghidra to solve all remaining unknowns; completely rebuild the
firmware"), plus two repositories Dale pointed at during the work. **Desk only: nothing here ran on an RG34XX-SP.**
Tags: [G] Ghidra/static on stock V1.0.6, [D] stock file or device tree, [S] public source, [N] no public source known.
Ghidra 12.2 ran headless and read-only on Dale's project (`REA\BootImage\ghidra-project`). No stock data is committed.

## Result
1. Five unknowns are settled on the desk and one earlier statement is confirmed for our pinned TF-A (§1). None needs a change to our trees.
2. Four more are narrowed but still need the device, and the rest can only be answered on the device (§2).
3. The firmware was rebuilt from source: both u-boot binaries here (SHA-256 identical to R1 and R24, a third machine), and
   the kernel packages and image (§3).
4. The two repositories are useful as references only; neither changes our plan (§4).

## 1. Settled on the desk
| Unknown | Answer | Evidence |
|---|---|---|
| "Fast Shutdown" (`echo 0x1801 > /sys/class/axp/axp_reg`) | The write is register **0x18 := 0x01** on the PMIC. 0x18 is the gauge-reset register; bits 1:0 are **reserved** in the AXP717 datasheet (bit 2 = gauge reset keeping registers, bit 3 = full gauge reset). So the setting has no documented effect; soft power-off is register 0x27 bit 0. Nothing to port | [G] `axp_reg_store` `0xffffff800850e80c`: value ≥ 0x100 → reg = bits 15:8, data = bits 7:0, one regmap write; `axp2202_reset_mcu` `0xffffff8008646bb0` pulses 0x18 bit 2. [S] AXP717 datasheet V1.2 REG 18h/27h; BSP name `AXP2202_RESET_CFG` |
| PE11 (`adc-en-gpios`) | **Nobody reads it.** The property exists in the stock kernel DT and in u-boot's DT, but the string `adc-en` occurs in neither the kernel image, any of the 17 stock modules, nor u-boot's code. The stick driver's own flag is `allen_gpadc_enable_flg`, unrelated to a GPIO. Mainline need not drive PE11 (K5 still checks the sticks) | [G][D] string search of `Image`, `modules-v106`, u-boot item of the boot package |
| ALDO3 | No consumer anywhere in the stock DT: only its own node (`regulator-always-on`, `boot-on`, range 0.5–3.5 V) and the `virtual-aldo3` test regulator. Its voltage is whatever boot0/u-boot left. Desk can't say what it feeds; keep it on in our tree until K1 reads its voltage | [D] `dtb.dts` phandle 0x56 has two references |
| TF-A deep suspend | Our pinned TF-A **v2.14.0** has no `SYSTEM_SUSPEND` for H616: the platform uses the native PSCI ops (CPU on/off, system off, reset) only. This confirms, for the version we pin, what `kernel-custom-patches.md` §7 already says; the ROCKNIX patch plus SRAM stub named there stay the only known route (the patch has no licence statement, R9) | [S] `plat/allwinner/sun50i_h616/platform.mk` (`SUNXI_PSCI_USE_NATIVE := 1`), `plat/allwinner/common/sunxi_native_pm.c` |
| Stock udev rules (contents) | All **76** rules files in `/lib/udev/rules.d` match their Ubuntu packages' MD5 sums; `/etc/udev/rules.d` is empty. No vendor rule exists | [D] rootfs `dpkg` `*.md5sums` vs the files |
| `brightCtrl.bin`, `/dev/vsgame` | Both are dead references. `launcher.sh` starts `/mnt/vendor/bin/brightCtrl.bin` only if it exists, and V1.0.6 does not ship it. `fc_emu.dge` opens `/dev/vsgame`, but no such device exists in the kernel image, its symbol table or the modules | [D] appfs `/bin` listing; [G] string and kallsyms search |

## 2. Narrowed, or still needing the device
| Unknown | What the desk adds | Still needed |
|---|---|---|
| HDMI | Stock: `hdmi@06000000` (`allwinner,sunxi-hdmi`), HDCP 1.4/2.2 and CEC on, supplies named `vcc-hdmi`/`vdd-hdmi` that **no regulator in the DT provides** (so the rails are always-on). Mainline `97d73c8` has H6 `dw-hdmi` and PHY drivers but no H616 HDMI nodes; series 1158750 (watched in R11) adds them | take the series when it settles; board nodes (connector, HPD, DDC); a device test |
| Second card slot (TF2) | Stock wiring in full: `mmc2`, 4-bit, PC pins, card detect **PE22** polled (`broken-cd`), slot power **PE4**, `vqmmc` = ALDO1, 50 MHz, SD high-speed, no 1.8 V switching, no SDIO/eMMC | a DT node for our tree and a device test (W3.3 finding 1) |
| Battery gauge registers | 0x0C = `CURVE_CHECK`, 0xA1 = `GAUGE_BROM`, 0xA2 = `GAUGE_CONFIG`, 0xB0/0xB2 = gauge FG address/data in the BSP header: the "not in the datasheet" registers of G4 have BSP names | whether mainline needs the 128-byte model (K-task on battery accuracy) |
| Older third panel (2025 firmware, PE6 high) | not traced: no 2025 image is on Dale's PC | a 2025 image, then the same method as K9 |
| Your unit's DRAM set, panel, CPU speed grade, chip revision | not answerable from an image | K1, K3, K4, K8 |
| Bluetooth config's 4 extra entries | not traced (Realtek config offsets are undocumented) | K16 |

## 3. Rebuild from source (2026-11-20)
Built in a cloud workspace (Ubuntu 24.04, gcc 13.3.0 aarch64, 2 cores) from `main` at `7620069`, with the repo's own
scripts and nothing else. **No binary is committed and nothing was written to a card.** The image exists only in that
workspace and is reproducible with the commands below.

| Step | Command | Result |
|---|---|---|
| Boot chain | `scripts/build-uboot.sh --dram all` | u-boot v2026.10 + TF-A v2.14.0. SHA-256 lpddr4 `1d0381e1cb846ab2…`, lpddr3 `c0c3de979a2bc127…`: **identical to R1 and R24** (third machine). Fragment, DRAM-cap, SPL-checksum and PE6-code checks pass |
| Kernel checks | `scripts/workbench.sh --display --bindings` | all pass (R29) |
| Kernel packages | `scripts/build-kernel.sh --display --build` | `linux-image-7.4.0-rc2-rg34xxsp_7.4.0~rc2-1_arm64.deb`, 12.8 MB (27.2 MB installed), 167 modules, SHA-256 `64cd310a6220aadf…` |
| Image | `image/build-image.sh` with that package and the **lpddr4** u-boot (Dale's unit, Q10) | `reduxos-rg34xxsp-noble-20261120-deb-uboot-lpddr4.img`, 867 MB, 192 packages, SHA-256 `53c6485e27eeb59e…`. Licence, display and boot-layout checks: PASS |
| QEMU smoke test | `image/qemu/smoke-test.sh <img> 512` | **12 passed, 0 failed** (virt + Cortex-A53, 512 MB): multi-user boot, root grown to 2.7 G, our kernel, networking, no panic |
| CI | `image-smoke` on `74bed19` (the R29 merge) | success: the same kernel and image built and booted independently |

The image carries both panel modules (`panel-newvision-nv3052c`, `panel-galaxycore-gc9703`) and five board DTBs; u-boot
picks `-redux-panel` (PE6 low) or `-redux` (PE6 high) as before.

What "rebuilt" does not mean: QEMU is not the handheld. Display, input, audio, wireless, charging and suspend are untested
until K3/K4 and the K-tasks. The first use of this u-boot is by FEL (R2), never by writing a card that holds stock.

## 4. The two repositories
### fotlim/android_device_anbernic_rg34xxsp_h700_lineage (Apache-2.0; read at `fa90b3a`, 2026-11-20)
A LineageOS 18.1 device tree for the RG34XX-SP on mainline 7.1.2 plus ROCKNIX's H700 patches. Its hardware table is read
from a real unit on the same stock build as ours (4.9.170 #9, 2026-05-26). Third-party claims, not checked by us:
- **Agrees with our records:** panel SPI/reset/power pins, PWM0/PD28 at 50 kHz, key pins and codes (including stock X = 306,
  Y = 307), stick mux PI0/PI1/PI2, rumble PWM2/PH2, PCF8563 RTC at 0x51, lid Hall sensor on PE7, TF2 on PE22/PE4, Wi-Fi/BT
  pins, speaker amp PI5, headphone detect PI3.
- **New to us:** an unidentified I2C device at `3-003c` (twi3); USB-C runs as host only under mainline; their unit reads
  DCDC3 = 1.2 V and 1 GiB, which by ROCKNIX's rule is an **LPDDR3 1 GB** unit (a tier our project defers).
- **Real-hardware results on mainline (theirs):** boots to the Android launcher; display works with ROCKNIX's generic panel
  driver and the original-panel file; Panfrost renders; audio, Wi-Fi and deep suspend are not working yet.
- **Doubtful:** it says the system is on a 58 GiB eMMC. The stock DT marks `sdc0` `non-removable`, and a 64 GB card
  reads as 58.2 GiB, so this is probably the stock card in slot 1. Treat as unconfirmed.
- Use: a second source for K-task expectations. Nothing is copied (repo rule); its DTS relies on ROCKNIX patches we do not carry.

### oauramos/omega-zero (GPL-3.0; read at `1a9196b`, release 1.2.0)
A Rust game frontend (GB/GBC/GBA/SNES/PS1) for H700 handhelds on **BaseOS** (pvaibhav/BaseOS), a mainline-based system.
It lists the RG34XX SP as "untested" and lays out for 720×480. It reaches hardware only through generic interfaces
(`/sys/class/power_supply`, `/dev/input`, `fb0`, rfkill), which is the same contract R21 maps for Redux on mainline.
Use: a reference for a frontend on mainline, and BaseOS as a second mainline H700 base to compare with ROCKNIX. Not a
dependency; GPL-3.0 code can't be mixed into our GPL-2.0-only pieces.

## 5. Sources and tools
- Stock (Dale's PC, read-only): `REA\BootImage\{Image,dtb.dts,kallsyms,modules-v106}`, the V1.0.6 rootfs/appfs images, `re-extracts`.
- New local helper (not in git): `REA\ghidra_scripts\DRDecompRegex.java`; outputs in `REA\BootImage\decomp-dr-*` (deletable).
- Public: [AXP717 datasheet V1.2](https://server7.whycan.com/files/members/3946/AXP717_Datasheet_V1.2_en.pdf);
  [BSP `axp2101.h`](https://github.com/sipeed/LonganPi-3H-SDK/blob/HEAD/bsp/include/power/axp2101.h) and
  [`axp2202_charger.c`](https://github.com/CrealityTech/sonic_pad_os/blob/HEAD/lichee/linux-4.9/drivers/power/supply/axp2202_charger.c);
  [TF-A v2.14.0](https://github.com/ARM-software/arm-trusted-firmware/tree/v2.14.0/plat/allwinner);
  [the Lineage device tree](https://github.com/fotlim/android_device_anbernic_rg34xxsp_h700_lineage);
  [omega-zero](https://github.com/oauramos/omega-zero).
- Build tools were installed in the cloud workspace only; nothing was installed on Dale's PC or written to any card.
