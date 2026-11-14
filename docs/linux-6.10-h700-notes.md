# Linux 6.10 and the Allwinner H700 / RG34XXSP

Research note, 2026-11-13. Source: https://kernelnewbies.org/Linux_6.10, checked against the upstream patch threads it summarizes. Research only: nothing here has been tested on hardware.

## 1. Summary

Linux 6.10 (released **14 July 2024**) is the **first mainline kernel with H700 handheld support**. It added three things this project depends on:

| 6.10 change | What it gives the RG34XXSP |
|---|---|
| Device trees for the Anbernic RG35XX 2024 / Plus / H (Ryan Walklin) | The base DT that the RG35XX SP, and later ROCKNIX's RG34XX-SP DT, are built on |
| X-Powers AXP717 PMIC support, MFD + regulators (Andre Przywara) | Power rails. Nothing on the board works without them. The BSP calls this chip "AXP2202" |
| cpufreq: sun50i H616 support (Martin Botka, Andre Przywara) | CPU frequency/voltage scaling (DVFS) through the H6 nvmem driver |

**6.10 alone can't run the RG34XXSP usefully.** It has no RG35XX-SP / RG34XX-SP DT, no battery or charger reporting, no audio, no GPU, and no LCD. Those arrived in 6.11–6.16, and the display is still out of tree (section 4). For this project, 6.10 is the historical floor, not a target.

## 2. 6.10 headline features (general)

From the kernelnewbies summary, with a note on each one's relevance here:

| Feature | Relevance to this project |
|---|---|
| `mseal(2)`: lock memory mappings against changes | Low. Userspace hardening, used by glibc/Chrome later |
| Memory allocation profiling (`/proc/allocinfo`) | **Useful for development.** Find kernel memory hogs on the 512 MB / 1 GB boards. Needs `CONFIG_MEM_ALLOC_PROFILING` (debug builds only) |
| `/dev/ntsync` (NT sync primitives for Wine) | None on arm64 handheld targets |
| TPM2 bus encryption | None (no TPM) |
| Multi-size THP NUMA balancing | None (single NUMA node) |
| Zone write plugging | None (SD cards are not zoned devices) |
| io_uring zerocopy send coalescing | None |
| zram: `max_pages` for recompression; zswap moved to xarray | **Relevant** to the zram plan for low-RAM boards (both carry forward into later kernels) |
| arm64: faster linear-map creation at boot, Arm errata 3194386 / 3312417 workarounds | Small boot-time gain on the Cortex-A53. The errata target newer cores, not A53 |

## 3. The H700-relevant changes in detail

### 3.1 RG35XX device trees
- Series: "arm64: dts: allwinner: Add Anbernic RG35XX (Plus/H/2024) support", v6, 2024-04-27. Pulled by Jernej Škrabec as `sunxi-dt-for-6.10-2`.
- Adds `sun50i-h700-anbernic-rg35xx-2024.dts` (base), `-plus.dts` (adds Wi-Fi/BT) and `-h.dts` (second USB port and analog sticks).
- The base DT includes `sun50i-h616.dtsi`. In mainline the H700 is described as an H616 variant (`compatible = "anbernic,…", "allwinner,sun50i-h700"`). Serial console on `uart0` at 115200.
- **Why it matters:** the RG35XX SP DT (6.12) includes `-plus.dts`. ROCKNIX's `sun50i-h700-anbernic-rg34xx-sp.dts` includes the SP DT and only changes the panel and joypad settings. So this 6.10 DT is the root of the RG34XXSP description.

### 3.2 AXP717 PMIC
- Series: "regulator: Add X-Powers AXP717 PMIC support" (Andre Przywara, 2024-03). Follow-up fixes: "regulator: Fix AXP717 PMIC support" v2, April 2024.
- The cover letter notes that Allwinner's BSP "AXP2202" appears to be the same chip: a boot0 AXP2202 driver drove a chip labelled AXP717. **This links the stock firmware's `axp2202` driver to mainline's `axp717`.**
- 6.10 covers the MFD core and regulators only. Battery, USB charger and ADC support came later (section 4).
- At first the RG35XX DTs reached the PMIC over RSB. 6.12 moved them to I²C (`r_i2c`).

### 3.3 H616 cpufreq
- Series: "cpufreq: sun50i: Add Allwinner H616 support", v5, 2024-04-18 (Martin Botka's original, reworked by Andre Przywara). Applied by Viresh Kumar.
- Adds `opp-supported-hw` handling, speed-bin decoding through SMCCC SoC-ID, and the `sun50i-h616-cpu-opp.dtsi` OPP table. It also blocklists H616/H618 (and so the H700) from the generic `cpufreq-dt` driver.
- **Caveat:** v5 *removed* the explicit H700 speed-bin support because it "proved to be problematic/unstable in testing". The H700 runs on the H616 tables. ROCKNIX carries extra OPP patches (`0200-h700-update-opps`, `0210-h616-cpu-opp-mark-480MHz-as-suspend-opp`). DVFS for the RG35XX boards was switched on in 6.11. (Stock's own decoder is in `docs/stock-cpu-bin-decoder-and-dcdc2.md`.)

### 3.4 Other 6.10 items worth knowing
- ASoC: jack detection for the A64 codec, and 32-bit formats in `sun4i-i2s`. Not the H616 codec, which came in 6.13.
- Panfrost: only an fdinfo/debugfs change. 6.10 also introduced **Panthor**, but that driver is for CSF-based Mali (Valhall gen 10+). The H700's **Mali-G31 (Bifrost) stays on Panfrost**.
- rtw88: nothing new for RTL8821CS (its SDIO support landed in 6.4). 6.10 added RTL8723CS through `rtl8xxxu`, which doesn't apply here.

## 4. What came after 6.10 (H700 timeline)

| Kernel | H700 / RG35XX change | Status for RG34XXSP |
|---|---|---|
| **6.10** | RG35XX 2024/Plus/H DTs; AXP717 MFD + regulators; H616 cpufreq | Base |
| 6.11 | H616 GPADC; ADC joysticks on RG35XX-H; DVFS enabled for RG35XX boards | Sticks/DVFS groundwork |
| 6.12 | **RG35XX-SP DT** (lid as `SW_LID` on PE7, wake on lid open); PMIC moved RSB→I²C; AXP717 charger in the DTs | Lid and battery |
| 6.13 | H616 audio codec driver + node; codec enabled for RG35XX (with speaker-amp supply) | Audio |
| 6.16 | Mali-G31 node + H6/H616 PRCM PPU power domain (Panfrost); DE33 clocks; headphone-detect GPIO for RG35XX | GPU |
| Out of tree (Nov 2026) | Full DE33 display engine (binding rework v2, May–Jun 2026), RG35XX LCD output, generic MIPI-DPI-SPI panel driver + per-panel blobs, H616 PWM (v12 posted 2026-11-04), RG34XX-SP DT | **Display is still the blocker** |

ROCKNIX's H700 build today is Linux 7.2 with 32 patches covering the out-of-tree rows (see `docs/ubuntu-2404-rg34xxsp-assessment.md`).

## 5. What this means for the Ubuntu 24.04 build

- **The floor for a working kernel is well past 6.10.** GPU support needs 6.16 or later, and the display needs out-of-tree patches on any version. Base the project on the ROCKNIX-proven 7.2 tree, not on 6.10.
- **Ubuntu's own noble kernels don't help.** Their configs and DTBs don't cover the RG34XX-SP panel or the DE33 LCD path whatever the version, so we ship our own kernel package.
- **Kernel config items traced to 6.10:** `CONFIG_MFD_AXP20X_I2C` + `CONFIG_REGULATOR_AXP20X` (AXP717), `CONFIG_ARM_ALLWINNER_SUN50I_CPUFREQ_NVMEM` (H616 DVFS), `CONFIG_ZRAM` (with the 6.10 recompression knob). `CONFIG_MEM_ALLOC_PROFILING` goes in debug builds only.
- **Check before relying on it:** that the mainline H616 OPP table is safe on the H700 bins of Dale's unit (the H700 bins were dropped upstream as unstable), and how it compares with stock's OPP table. The Kernel Research draft uses a never-undervolt table until then.

## Sources
- Linux 6.10 changelog: https://kernelnewbies.org/Linux_6.10
- RG35XX DT series v6 (Ryan Walklin): https://lore.kernel.org/all/20240427110225.727472-8-ryan@testtoast.com/T/
- sunxi-dt-for-6.10-2 pull (Jernej Škrabec): https://yhbt.net/lore/linux-sunxi/20240427133006.GA146501@jernej-laptop/
- AXP717 series (Andre Przywara): https://lore.kernel.org/all/20240328095631.GW13211@google.com/T/
- H616 cpufreq v5 (H700 speed-bin dropped): https://lore.kernel.org/all/20240418154408.1740047-7-andre.przywara@arm.com/T/
- Linux 6.11 Arm changes: https://www.cnx-software.com/2024/09/16/linux-6-11-release-notable-changes-arm-risc-v-and-mips-architectures/
- Allwinner DT changes for 6.12 (RG35XX-SP, PMIC to I²C, charger): https://lists.infradead.org/pipermail/linux-arm-kernel/2024-September/959066.html
- AXP717 battery and USB supply: https://lists.infradead.org/pipermail/linux-arm-kernel/2024-September/958527.html
- H616 audio codec (6.13): https://lists.infradead.org/pipermail/linux-arm-kernel/2024-October/973558.html
- H616 Mali GPU (6.16): https://lists.infradead.org/pipermail/linux-arm-kernel/2025-April/1022086.html
- Linux 6.16 Arm changes: https://www.cnx-software.com/2025/07/28/linux-6-16-release-main-changes-arm-risc-v-and-mips-architectures/
- RG35XX headphone detection (6.16): https://lists.infradead.org/pipermail/linux-arm-kernel/2025-April/1018474.html
- DE33 rework: https://lkml.org/lkml/2025/10/31/301
