# Stock H700 CPU speed-bin decoder, per-bin OPP tables, and DCDC2

Research note, 2026-11-13 (Deep Research chat), answering the Kernel Research chat's 20:20 and 20:45 requests. Static analysis (capstone, arm64) of the stock kernels `4.9.170 #19` (2025-04-12) and `#9` (V1.0.6, 2026-05-26) and their DTBs, read-only copies on Dale's PC. **Desk only; nothing ran on a device.** Only hardware facts are recorded here; no vendor code is copied.

> **Correction (2026-11-13, 21:20 ET):** the two kernels are **not** identical. In the 2025 kernel (#19), fuse **0x7C00 → mask 0x2**: it shares the 0x2C00 compare, at file offset 0x5f423c → `mov w0,#2`. In V1.0.6 (#9) it gives name b0/b1 (0x5f4b18 → 0x5f4b98). Every other value maps the same way in both. The Kernel Research chat found this; my earlier "same constants" check didn't test where each branch goes. The table below is **V1.0.6**. Consequence: a chip with fuse 0x7C00 runs the 0x2 table on 2025 firmware (max 1296 MHz @ 1100 mV) but b0/b1 on V1.0.6 (b1 reaches 1512 MHz @ 1160 mV).

## 1. The decoder (BSP `sun50i-cpufreq-nvmem`; V1.0.6 shown, 2025 differs only for 0x7C00)
Inputs:
- **speed fuse:** nvmem cell `speed` on the `allwinner,sun50i-operating-points` node (SID + 0x200, 16 bit);
- **rev:** chip revision (read through the SRAM controller), low 3 bits;
- **S20:** SID word at +0x220, low byte, shifted left 5;
- **S28:** SID word at +0x228, `& 0x3ff`.

| speed fuse | Result | Mechanism |
|---|---|---|
| 0x2400, 0x5000, 0x5400, 0x7400 | mask **0x1** | `opp-supported-hw` |
| 0x2C00 | mask **0x2** | `opp-supported-hw` |
| 0x2000, 0x2800 | name **a1** | `opp-microvolt-a1` |
| 0x6C00, 0x7C00 (V1.0.6) | name **b0** if rev == 0, else **b1** (2025 kernel: 0x7C00 → mask **0x2**) | `opp-microvolt-b*` |
| 0x5C00 | **c0** if rev == 0. Else **c1** if S28 ∈ [0x26, 0x2D] **and** S20 ∈ [0xA60, 0x13A0]; otherwise **c2** | `opp-microvolt-c*` |
| anything else | mask **0x8** (fallback) | `opp-supported-hw` |

- Masks **0x4, 0x10 and 0x20 are never produced**. The DT entries that use only those bits are dead weight inherited from Allwinner's generic table.
- The kernel prints the result at boot: `sun50i_cpufreq_nvmem: sun50iw9p1 vf versions:0x<mask>, name:<suffix>`. **Dale's bin is one `dmesg` line away** (below).

### How the stock OPP core uses it (BSP changes vs mainline 4.9)
- **Mask path:** standard `opp-supported-hw` filtering.
- **Name path:** no mask is set. The BSP OPP core then **skips every node that has `opp-supported-hw`** (a BSP change; mainline 4.9 would keep them). `opp_parse_supplies` tries `opp-microvolt-<name>` and falls back to `opp-microvolt`. The `-ab` nodes have no plain value, so nodes without that bin's suffix get 0 V. [Inferred, mainline 4.9 behaviour, not decoded in the BSP: 0 V fails the regulator check and the OPP is marked unavailable.]

## 2. Effective stock CPU OPP tables (MHz @ mV), from the V1.0.6 DTB (2025 identical)
| Bin | Table |
|---|---|
| mask 0x1 | 480, 600, 792 @ 900 · 1008 @ 920 · 1200 @ 980 · 1512 @ 1120 |
| mask 0x2 | 480, 600, 792, 1008 @ 900 · 1200 @ 960 · 1296 @ 1100 |
| mask 0x8 (fallback) | 480, 600 @ 900 · 792 @ 940 · 1008 @ 1020 · 1200 @ 1100 · 1296 @ 1120 |
| a1 | 480, 720, 1032 @ 900 · 1104 @ 950 · 1200 @ 1000 · 1296 @ 1050 · 1416 @ 1100 · 1512 @ 1160 |
| b0 | 480, 600, 792 @ 900 · 1008 @ 920 · 1200 @ 980 · 1512 @ 1120 |
| b1 | 480, 720, 936 @ 900 · 1008 @ 950 · 1104 @ 1000 · 1200 @ 1050 · 1320 @ 1100 · 1416 @ 1150 · 1512 @ 1160 |
| c0 | 480, 600 @ 900 · 792 @ 940 · 1008 @ 1020 · 1200 @ 1100 · 1344 @ 1120 |
| c1 | 480 @ 900 · 720, 936 @ 950 · 1008 @ 1000 · 1104 @ 1050 · 1200 @ 1100 · 1320 @ 1160 |
| c2 | 480, 600 @ 900 · 792 @ 940 · 1008 @ 1020 · 1200 @ 1100 · 1344 @ 1120 |

What this means for us:
- **Highest stock voltage at each common step:** 480 @ 900 · 1008 @ 1020 (0x8/c0/c2) · 1200 @ 1100 (0x8/c*) · 1512 @ 1160 (a1/b1). The Kernel Research "never undervolt" draft (480/1008/1200 at each step's maximum) agrees with this table.
- **Only some bins run above 1344 MHz** (0x1, a1, b0, b1). A single table for all units must stop at 1200 MHz or 1344 MHz unless the bin is known.
- Custom patch: a mainline `sun50i-cpufreq-nvmem` decoder variant with this mapping was written and compile-tested by the Kernel Research chat (master list R12). Per-chip voltages vs the conservative table is Dale's decision Q2.

## 3. DCDC2 (Kernel Research 20:45 question)
- **Stock kernel DT:** DCDC2 (`axp2202-dcdc2`, 0.5–3.4 V, always-on, boot-on) has **no consumer** except Allwinner's `virtual-dcdc2` test node. The Mali node (`arm,mali-midgard`) has **no `*-supply`**. Its GPU table is v1 `operating-points`: 648 MHz @ 960 mV; 600/552/504/456/420 MHz @ 900 mV; `dvfs_status = 1`.
- **Mali module:** `r20p0-01rel0`. It probes regulators by name (the strings `mali`/`gpu` and "Regulators probed: %u"), and the sunxi glue logs "set gpu regulators err". With no supply in the DT, it most likely finds none → **GPU DVFS changes the clock only, and DCDC2 stays at its boot value** [inferred].
- **Bootloaders:** u-boot's `power_sply` sets `dcdc1_mode`/`dcdc2_mode = 1` but **no `dcdc2_vol`**. boot0 has a PMU name table (dcdc1/2/3/5, aldo…) and an AXP2202 driver. Its DCDC2 setpoint isn't decoded.
- **Conclusion:** the desk evidence says stock never changes DCDC2 at runtime. The actual boot value needs one read on the running stock unit (below).

## 4. Read-only commands for Dale (stock firmware over SSH; nothing is written)
```sh
dmesg | grep -E 'vf versions|Regulators probed'
for r in /sys/class/regulator/regulator.*; do
  printf '%s %s uV users=%s\n' "$(cat $r/name)" "$(cat $r/microvolts 2>/dev/null)" "$(cat $r/num_users 2>/dev/null)"
done
```
Expected: one `vf versions:0x… name:…` line (Dale's bin) and the live `axp2202-dcdc2` voltage. If DCDC2 reads ≥ 960 mV, stock's 648 MHz GPU step is covered at boot; if it reads below that, stock runs 648 MHz under-volted against its own table.
