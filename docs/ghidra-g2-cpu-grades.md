# G2: stock CPU speed grade ↔ mainline speed grade (Ghidra plan, 2026-11-15)

Kernel Research chat, desk only. Stock = V1.0.6 kernel `4.9.170 #9` (names from kallsyms, G0.2). Mainline =
`drivers/cpufreq/sun50i-cpufreq-nvmem.c` and `sun50i-h616-cpu-opp.dtsi` (torvalds/linux master, read
2026-11-15), with ROCKNIX's H700 changes as in `dts/sun50i-h700-redux-cpu-opp.dtsi` (decision Q2).
Builds on [`stock-cpu-bin-decoder-and-dcdc2.md`](stock-cpu-bin-decoder-and-dcdc2.md) (Deep Research, 2026-11-13),
which decoded the stock decoder; this item names it, re-checks it and maps it to mainline.
Tags: **[G]** static analysis of the stock kernel, **[D]** device tree / strings / source, **[V]** none yet.

## Answer
- Stock and mainline read the **same 16-bit fuse** (SID + 0x200) but decode it differently [G][D]. Stock uses
  per-chip masks or voltage-name suffixes; mainline maps it to `speed0`–`speed5`.
- **For 4 of the 12 fuse values below, mainline (with ROCKNIX's table) allows a higher CPU step than stock
  ever runs on that chip** [G][D][N] (`0x2C00`, `0x5D00`, `0x6000`, any unknown value). K22 must treat those units as
  untested at the top steps; Dale's unit needs its fuse value first (device check 1).
- Both use the chip revision for some values, from different sources (stock: `sunxi_get_soc_ver`; mainline:
  SMCCC SOC_ID revision). Whether they agree is device task K8.

## Data table 1: fuse value → stock result → mainline grade
Stock tops from the stock DT per-bin tables (doc above, §2). Mainline tops are the ROCKNIX-adjusted upstream
table; `*` = 1512 MHz is boost only (Expert Mode).
| Fuse (SID+0x200) | Stock V1.0.6 result [G] | Stock top step | Mainline grade [D] | Mainline top step | Mainline vs stock |
|---|---|---|---|---|---|
| 0x2000 | name a1 | 1512 MHz @ 1160 mV | speed0 | 1416 @ 1100 | lower step, lower V |
| 0x2400 | mask 0x1 | 1512 @ 1120 | speed1 (rev A/B) / speed2 | 1512* @ 1100 / 1416 @ 1100 | same or lower step, lower V |
| 0x2800 | name a1 | 1512 @ 1160 | not listed → speed0 + warning | 1416 @ 1100 | lower step, lower V |
| 0x2C00 | mask 0x2 | **1296 @ 1100** | speed1 / speed2 | 1512* / 1416 @ 1100 | **higher step than stock** |
| 0x5000 | mask 0x1 | 1512 @ 1120 | speed3 | 1512* @ 1100 | same step, lower V |
| 0x5400 | mask 0x1 | 1512 @ 1120 | speed3 | 1512* @ 1100 | same step, lower V |
| 0x5C00 | c0 (rev 0) / c1 / c2 | 1344 @ 1120 (c0, c2), 1320 @ 1160 (c1) | speed4 | 1320 @ 1100 | lower or same step, lower V |
| 0x5D00 | not listed → mask 0x8 | **1296 @ 1120** | speed0 | 1416 @ 1100 | **higher step than stock** |
| 0x6000 | not listed → mask 0x8 | **1296 @ 1120** | speed3 | 1416 @ 1100, 1512* | **higher step than stock** |
| 0x6C00 | b0 (rev 0) / b1 | 1512 @ 1120 / 1160 | speed5 | 1512* @ 1160 (1416 @ 1100) | same step |
| 0x7400 | mask 0x1 | 1512 @ 1120 | speed1 / speed2 | 1512* / 1416 @ 1100 | same or lower step, lower V |
| 0x7C00 | b0 (rev 0) / b1 | 1512 @ 1120 / 1160 | speed1 / speed2 | 1512* / 1416 @ 1100 | same or lower step, lower V |
| other | mask 0x8 | **1296 @ 1120** | speed0 + warning | 1416 @ 1100 | **higher step than stock** |

## Data table 2: mainline OPPs per grade (ROCKNIX-adjusted upstream, MHz @ mV) [D]
| Grade | Steps |
|---|---|
| speed0 | 480, 720, 936 @ 900 · 1008 @ 950 · 1104 @ 1000 · 1200 @ 1050 · 1320, 1416 @ 1100 |
| speed1 | 480, 600, 792 @ 900 · 1008 @ 940 · 1200 @ 1020 · 1512* @ 1100 |
| speed2 | as speed0 |
| speed3 | as speed0, plus 1512* @ 1100 |
| speed4 | 480, 600 @ 900 · 792 @ 940 · 1008 @ 1020 · 1200, 1320 @ 1100 |
| speed5 | 480, 720, 1008 @ 900 · 1104 @ 950 · 1200 @ 1020 · 1320, 1416 @ 1100 · 1512* @ 1160 |

## Data table 3: stock functions and data involved (V1.0.6 addresses) [G]
| Name | Address | Role |
|---|---|---|
| `sun50i_cpufreq_nvmem_probe` | …8674940 | Reads the `speed` nvmem cell, decodes it (constants 0x2000 … 0x7C00, 0xA60, 0x3FF match table 1), sets `opp-supported-hw` or the `opp-microvolt-<name>` suffix, prints `vf versions` |
| `sun50i_cpufreq_match_list` | …8a539f0 | Match table (`allwinner,sun50i-operating-points`) |
| `sunxi_get_soc_ver` | …8465584 | Chip revision used for b0/b1, c0/c1/c2 (exported) |
| `sunxi_get_soc_bin`, `sunxi_get_soc_chipid`, `sunxi_efuse_readn` | …8465ad8, …8465a38, …8465e44 | SID helpers (exported) |
| `sunxi_sid_probe`, `sunxi_sid_read` | …86f4858, …86f4824 | nvmem provider for the SID cells |
| `dev_pm_opp_of_cpumask_add_table_by_soc_bin` | …84bec50 | Loads the bin's OPP table (see Redux map) |
| `sys_info_show`, `key_info_show` | …84975c0, …84974d4 | `sunxi_info` sysfs: chip id / SoC version text |

## How mainline would see Dale's unit
Unknown until the fuse is read. If it is one of the four "higher step" rows, K22 must start at stock's top step
for that chip and raise only after the stress test passes; the board tree can drop the extra steps for that
grade. Patch 0001 (our stock-decoder port, R12) remains the fallback that reproduces stock exactly.

## Device checks (optional, read-only on stock)
1. `dmesg | grep 'vf versions'` (stock's decoded result) and
   `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies`.
2. `cat /sys/class/sunxi_info/sys_info` (chip id and SoC version; path from strings, not traced).
3. Fuse value itself: the 2 bytes at SID + 0x200 (`/sys/bus/nvmem/devices/*/nvmem` if the stock kernel
   exposes it; K1 lists `0x03006200`).
