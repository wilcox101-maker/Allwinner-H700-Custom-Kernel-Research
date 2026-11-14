# Phase 2 custom-patch designs: panel selection, CPU OPPs, sticks, thermal

Kernel Research chat, 2026-11-13. **Desk work only: nothing here has been built into an image or
booted.** The device tree drafts in `../dts/` compile cleanly (`cpp` + `dtc`) against torvalds/linux
`97d73c8` (v7.4-rc2), and decompiling them shows the intended result. The u-boot code below is a
sketch: it has not been compiled.

Everything here is original text. It describes hardware facts taken from the stock DTB and
upstream sources, and copies no other project's patches.

## 1. Safe panel selection in u-boot (no guessing)

> **Update 21:10. Superseded by the Deep Research chat's work**
> ([`rg34xxsp-panel-detect-and-uboot-patch.md`](rg34xxsp-panel-detect-and-uboot-patch.md); u-boot patch
> [`patches/u-boot/0001-sunxi-rg34xxsp-dt-selection.patch`](../patches/u-boot/0001-sunxi-rg34xxsp-dt-selection.patch), build-tested on u-boot v2026.01).
> - Stock reads a **single strap, PE6**, with the pull-up on, after a reset pulse on PI14:
>   **low = original panel, high = v2 panel** (V1.0.6).
> - The patch sets `fdtfile` in `misc_init_r()`. Setting `panel_autodetect=no` skips detection.
> - My sketch below is kept only for its idea of a no-panel fallback DT. With a 1-bit strap there
>   is no "unknown pattern" to fall back on.
> - The remaining risk is the third, `old` panel, which also reads PE6 high on 2025 firmware.
>   Deep Research's risk note covers it.


**Problem.** ROCKNIX has the user pick a DTB by hand and try the other one if the screen is
garbled. Our rule is never to drive an unknown panel.

**What exists already:**
- **Stock:** Anbernic's u-boot reads GPIO port E straps (`--allen--PE_pull` / `PE_data`) and passes
  `lcd_type=` to the kernel (Deep Research, [`anbernic-kernel-build-methodology.md`](anbernic-kernel-build-methodology.md)).
- **Mainline u-boot** (`6487c50`, 2026-11-13) has a hook for exactly this:
  - `board_fit_config_name_match()` in `board/sunxi/board.c` picks the DT from GPIO straps or the
    DRAM size, as the PinePhone (PL6) and Pine64 (RAM size) options do.
  - The name it picks reaches u-boot proper and becomes `fdtfile`, which extlinux then loads.

**Design: `CONFIG_ANBERNIC_RG34XXSP_DT_SELECTION`**, modelled on `PINEPHONE_DT_SELECTION`:

```c
/* board/sunxi/board.c, inside board_fit_config_name_match(), SPL. SKETCH, NOT COMPILED. */
#ifdef CONFIG_ANBERNIC_RG34XXSP_DT_SELECTION
	if (strstr(best_dt_name, "anbernic-rg34xx-sp")) {
		/* [PE_STRAP_PINS]: from Deep Research's decode of the stock u-boot routine. */
		static const int straps[] = { /* e.g. SUNXI_GPE(n), ... */ };
		unsigned int id = 0;
		int i;

		for (i = 0; i < ARRAY_SIZE(straps); i++) {
			sunxi_gpio_set_cfgpin(straps[i], SUNXI_GPIO_INPUT);
			sunxi_gpio_set_pull(straps[i], /* [STOCK_PULL] same pull as stock */);
		}
		udelay(100);
		for (i = 0; i < ARRAY_SIZE(straps); i++)
			id |= !!gpio_get_value(straps[i]) << i;
		for (i = 0; i < ARRAY_SIZE(straps); i++) {	/* leave pins as found */
			sunxi_gpio_set_cfgpin(straps[i], SUNXI_GPIO_DISABLE);
			sunxi_gpio_set_pull(straps[i], SUNXI_GPIO_PULL_DISABLE);
		}

		switch (id) {	/* [ID_TABLE]: stock lcd_type values, filled from the decode */
		case /* fog_fj035fhd05_v1 */ 0:
			best_dt_name = "sun50i-h700-anbernic-rg34xx-sp-panel-v1"; break;
		case /* rg34xxsp_v1 */ 1:
			best_dt_name = "sun50i-h700-anbernic-rg34xx-sp-panel-v2"; break;
		default:
			/* Unknown strap pattern: boot WITHOUT any panel node. */
			best_dt_name = "sun50i-h700-anbernic-rg34xx-sp-redux"; break;
		}
	}
#endif
```

- **The default case is the safety net.** An unknown board gets `rg34xx-sp-redux.dtb`, which has
  no panel node. The device still boots, so serial, HDMI (once enabled) and SSH work, but the panel
  is never touched.
- **DRAM type can be checked in the same place.** The SPL is built per DRAM type, so the LPDDR3
  build only lists LPDDR3-board DTs and the LPDDR4 build only LPDDR4 ones.
- **Blocked on:** the strap pins, their pulls and the ID-to-panel table. Deep Research is decoding
  them now. Also verify that the SPL can read port E on the H616 (PinePhone has to gate the R_PIO
  for port L; port E is on the main PIO).

**DT layout this implies.** Three DTBs are built from one base:
- `...-redux.dts`: the base, with no panel;
- `...-panel-v1.dts` and `...-panel-v2.dts`: each includes the base and adds one panel's nodes
  from the display patch set.

All three go into the u-boot FIT (`CONFIG_OF_LIST`) and into `/boot/dtbs`.

## 2. CPU OPPs that never undervolt

**Facts (desk, 2026-11-13):**
- **Same fuse cell.** Stock and upstream read the same 16-bit speed fuse at physical
  `0x03006200`:
  - stock: `sunxi-sid-ng`, `speed@0`, read by the BSP SID driver with `value_offset = 0x200`
    (Orange Pi 4.9.170 `drivers/nvmem/sun50i_sid.c`, `sun50iw9p1_cfg`);
  - upstream: `cpu_speed_grade` at SID `0x0`, with `value_offset = 0x200` for A64/H6-class SIDs.
- **Upstream decodes it into speed0–5** (`sun50i_h616_efuse_xlate`). Some fuse values also depend
  on the chip revision read through SMCCC.
- **Stock uses six bins** (`opp-supported-hw` bits 0–5) with its own decoder. It is **not**
  Orange Pi's public 4.9 decoder, which has only three bins, so Anbernic's BSP is newer. The
  decoder lives only in the stock kernel binary.
- **Superseded:** an early fit-by-shape attempt is replaced by the decoded mapping in §2a.

**Decided 2026-11-14 (Q2, Dale):** the Redux trees use ROCKNIX's H700 table, i.e. upstream's H616
table with ROCKNIX's changes (1032 MHz dropped, 1320 MHz also for speed5, 1512 MHz boost-only via
Expert Mode, 480 MHz as suspend OPP), in `dts/sun50i-h700-redux-cpu-opp.dtsi`; stress test on
Dale's unit before use, raise a failing step to stock's voltage. The bin-agnostic stage below is
**dropped**; stages 2–3 (stock per-bin tables, `-reduxstock`) stay as the fallback.

**Design, in three stages (history):**
1. **Was (until 2026-11-14): a bin-agnostic table.**
   - It offers only the steps **every** stock bin has: 480, 1008 and 1200 MHz.
   - Each runs at the **highest** voltage any stock bin uses for it: 900, 1020 and 1100 mV.
   - It can't undervolt any chip relative to stock, and it stays inside stock frequencies and the
     upstream `vdd-cpu` limits (0.90–1.16 V).
   - The cost is losing the top steps (1296–1512) until stage 2 or 3.
2. **Per unit:** read the fuse and the stock frequency list on Dale's unit (checklist step 0,
   updated). That gives one fuse→stock-bin pair, enough to give **his** chip its full stock table
   under the upstream speed index the same fuse decodes to.
3. **General (custom kernel patch).** Recover Anbernic's decoder from the stock kernel binary,
   then add a small xlate to `sun50i-cpufreq-nvmem.c`:
   - compatible `anbernic,rg34xx-sp-operating-points` (name to agree);
   - fuse value → stock bit;
   - an OPP table that carries stock's six bins **as values** (frequencies and voltages are
     hardware facts).
   About 30 lines; upstreamable if the H700 bins are confirmed. Deep Research has folder access
   to the stock image, so the decoder extraction is offered to it in `research-sync.md`.

### 2a. Stock decoder recovered (2026-11-13; corrected 21:10 ET)
**Method.** Read-only disassembly of Dale's two stock kernels: the 2025 image partition 4
(`#19`, decoder at file offset `0x5f41c0`) and V1.0.6 `3.boot.img` (`#9`, at `0x5f4a90`). Tools:
`aarch64-linux-gnu-objdump` and `../tools/findconst.py`. The Deep Research chat decoded the same
routine independently ([`stock-cpu-bin-decoder-and-dcdc2.md`](stock-cpu-bin-decoder-and-dcdc2.md)), and the results agree except
for one fuse value (`0x7c00`, below).

**Inputs:**
- `F`: the 16-bit speed fuse at `0x03006200`;
- `rev`: the chip revision, low 3 bits;
- `S20`: SID byte at `+0x220`, shifted left 5;
- `S28`: SID word at `+0x228`, `& 0x3ff`.

| F | Stock result | Redux bit |
|---|---|---|
| `0x2400`, `0x5000`, `0x5400`, `0x7400` | mask 0x1 | 0 |
| `0x2c00` | mask 0x2 | 1 |
| `0x2000`, `0x2800` | name `a1` | 2 |
| `0x6c00` | name `b0` if `rev == 0`, else `b1` | 4 / 5 |
| `0x7c00` | **2025 (#19): mask 0x2. V1.0.6 (#9): name `b0`/`b1`** | 4 / 5 (follow V1.0.6) |
| `0x5c00` | `c0` if `rev == 0`. Else `c1` if `S28` is in [0x26, 0x2D] and `S20` is in [0xA60, 0x13A0]; else `c2` | 6 / 7 / 8 |
| anything else | mask 0x8 (stock default) | 3 |

**Correction (21:10).** My first write-up said the voltage-name outcomes had "no usable table".
That was wrong. The stock DT has `opp@…-ab` nodes with no `opp-supported-hw` and per-name
voltages (`opp-microvolt-a1` … `-c2`), and my first parser skipped them. Each name has a real table.
Stock mask bits 2, 4 and 5 are still never selected.

**The nine reachable stock tables (MHz @ mV)**, generated from `reference/stock-202505/board.dts`
by `../tools/gen_cpu_opp_stock.py`:

| Redux bit | Stock outcome | Table |
|---|---|---|
| 0 | mask 0x1 | 480@900 600@900 792@900 1008@920 1200@980 1512@1120 |
| 1 | mask 0x2 | 480@900 600@900 792@900 1008@900 1200@960 1296@1100 |
| 2 | a1 | 480@900 720@900 1032@900 1104@950 1200@1000 1296@1050 1416@1100 1512@1160 |
| 3 | mask 0x8 | 480@900 600@900 792@940 1008@1020 1200@1100 1296@1120 |
| 4 | b0 | same as bit 0 |
| 5 | b1 | 480@900 720@900 936@900 1008@950 1104@1000 1200@1050 1320@1100 1416@1150 1512@1160 |
| 6 | c0 | 480@900 600@900 792@940 1008@1020 1200@1100 1344@1120 |
| 7 | c1 | 480@900 720@950 936@950 1008@1000 1104@1050 1200@1100 1320@1160 |
| 8 | c2 | same as bit 6 |

**Redux xlate (custom kernel patch, our own code): written and compile-tested (21:40 ET).**
- **Patch:** `../patches/linux/0001-cpufreq-sun50i-add-Anbernic-RG34XX-SP-speed-bin-deco.patch`,
  against torvalds/linux `97d73c8` (v7.4-rc2). It changes one file, +86/−1:
  - an optional `efuse_xlate_np` hook, for decoders that need more cells of the OPP node;
  - a helper that reads a named nvmem cell;
  - `anbernic_rg34xxsp_efuse_xlate()`;
  - the compatible `anbernic,rg34xx-sp-operating-points`.
  Existing H6/A100/H616 boards are unchanged.
- **Compile:** `make ARCH=arm64 defconfig` plus `W=1 drivers/cpufreq/sun50i-cpufreq-nvmem.o` with
  aarch64-linux-gnu-gcc 13.3: no warnings. `checkpatch.pl`: 0 errors and 0 warnings
  (`--no-signoff`; Dale adds his Signed-off-by if it ever goes upstream).
- **Logic test:** `../tests/xlate_test.c` builds the patched function against stubs. 28 cases pass:
  every fuse value, the c1/c2 range edges, missing aux cells, unknown revision, and `rev & 7`.
- **DT side.** The generated `../dts/sun50i-h700-redux-cpu-opp-stock.dtsi` now declares the two
  aux cells on `&sid` (`@20`, `@28`) and lists `nvmem-cell-names = "speed", "speed-aux-a",
  "speed-aux-b"`. It compiles. The speed cell must stay first, because the driver reads cell index 0.
- **Not done:** no boot. (Binding entries and `dtbs_check` are now done; see §9.)

- **Upstream probe.** It turns the index into `supported_hw = 1U << speed`. The xlate signature
  grows by `rev`, `s20` and `s28`, so the patch also adds two nvmem cells (`0x20` and `0x28`,
  2–4 bytes each) on the SID node.
- **Unknown revision falls back to bit 3**, stock's own default, which tops out at 1296 MHz
  at 1.12 V.
- **Open item:** stock reads `rev` through the SRAM controller. Upstream gets it via SMCCC
  SOC_ID from TF-A. Confirm that both are the same value before trusting the b0/b1 and c0/c1/c2
  splits. One device read on stock and one on mainline would settle it.
- **Table:** `../dts/sun50i-h700-redux-cpu-opp-stock.dtsi`, generated (do not edit by hand).
  - 14 OPP nodes, one per frequency, with `opp-microvolt-speed<N>` where the bins differ (the
    driver selects `speed<index>`). That is the form the upstream binding schema accepts.
  - It compiles with the board DT, and the decompiled DTB round-trips to exactly the nine tables
    above.
  - It replaces the interim table once the patch is in.
- **Interim table (dropped by Q2, 2026-11-14).** 480/1008/1200 MHz at 900/1020/1100 mV for every chip.
  - That is at or above every stock bin's voltage at those steps.
  - Note that stock bin a1 has no 1008 step (it has 1032 at 900 mV). 1008 at 1020 mV sits
    inside a1's own curve (1032 at 900, 1104 at 950), so it overvolts but never undervolts.
- **Dale's chip.** Checklist step 0 reads the fuse, and on stock `dmesg | grep 'vf versions'` shows
  the stock result directly (Deep Research found that log line).

## 3. Sticks

These are in the draft DT:
- upstream `adc-joystick` over `io-channel-mux`, with a `gpio-mux` on PI1/PI2;
- PI0 as the mux enable, as in stock's `amux-en-gpios` (bank 8, pin 0);
- polling at **16 ms**, one 60 Hz frame. Stock polls at 20 ms and the upstream RG35XX-H at 60 ms.

- **stick clicks L3/R3 on PE8/PE9** (added 2026-11-13 22:00 ET; see §10). Stock's `keyL3`/`keyR3`
  use these pins, as does upstream's RG35XX-H; the first Redux draft left them out.

Axis order and signs must be checked with `evtest` on the device (K5). Whether both stick
clicks exist physically on the RG34XX-SP is part of the same check.

The **CPU cost of 16 ms polling** (four mux settles and four GPADC reads per poll) still needs
measuring. If it's high, the next step is an IIO buffered or triggered read.

## 4. Thermal (Dale decides)
- **Default (draft DT):** upstream's trips: CPU 60/70 °C passive and 110 °C critical; GPU, VE and
  DDR 110 °C critical.
- **Option (a):** `sun50i-h700-redux-stock-thermal.dtsi` puts the CPU critical trip back to 115 °C
  and removes the GPU/VE/DDR critical trips stock doesn't have. It compiles and decompiles as
  intended.
  - Checked at the desk: `drivers/thermal/thermal_of.c` at `97d73c8` accepts a zone with no
    trips and only logs "No trip points found", so deleting those trips is safe.

## 5. Not done here (and why)
- **Panel nodes:** they depend on the display patch set and on a confirmed panel. See §1.
- **GPU 648 MHz:** left out for now; see §6.

## 6. GPU OPPs on a shared rail (draft: `../dts/sun50i-h700-redux-gpu-opp.dtsi`, included by the board DT)
- **Update 21:10 (Deep Research, [`stock-cpu-bin-decoder-and-dcdc2.md`](stock-cpu-bin-decoder-and-dcdc2.md)).** In the stock
  DT, DCDC2's only consumer is a `virtual-dcdc2` test node, and Mali has no supply. So stock GPU
  DVFS most likely changes the clock only, and DCDC2 stays at its boot value. One read on stock
  (`/sys/class/regulator/*/microvolts`) gives that value; then set our fixed DCDC2 to it.
- **Rails.**
  - Upstream feeds the GPU from DCDC2, named `vdd-gpu-sys` and fixed at 0.94 V. The rail is shared
    with the system logic.
  - Stock's GPU node has no supply link, and its standby parameters name DCDC2 as `vdd-sys`. So
    nobody knows yet whether stock ever moves DCDC2 for GPU speed.
  - ROCKNIX (0007) lets DCDC2 move between 0.90 and 0.96 V with GPU load. That also drops the
    system rail to 0.90 V; the risk is not measured.
- **Draft policy:**
  - DCDC2 stays fixed at 0.94 V;
  - 420/456/504/552/600 MHz each declare 0.94 V, at or above stock's 0.90 V (no undervolt);
  - **648 MHz is left out.**
  It compiles and decompiles as intended.
- **To enable 648 MHz:** read DCDC2 on stock at idle and while a game runs (checklist step 0, the
  regulator loop). If stock really goes to 0.96 V, allow DCDC2 0.94–0.96 V and add 648 MHz at 0.96 V.
  Never set the rail below 0.94 V.

## 7. Deep suspend for our image (integration plan; desk)
**Why a stub at all.**
- TF-A's Allwinner page says the H616 has no ARISC management processor (SCP), so Crust can't run
  on it. Jernej Škrabec said the same in 2023: R40 and H616 have no co-processor.
- Upstream BL31 therefore logs "PSCI: Suspend is unavailable" on H616/H700, and Linux falls back
  to s2idle.
- ROCKNIX's EL3 SRAM stub is the only known route to real suspend-to-RAM.

**Components** (linked by name and version, nothing copied; ROCKNIX tag `20261101`):

| Part | Source | Licence |
|---|---|---|
| TF-A | v2.12.0 + ROCKNIX `projects/ROCKNIX/packages/tools/atf/patches/H700/001-allwinner-h616-psci-system-suspend.patch` (Kailash R S) | BSD-3 (TF-A) |
| Stub | `MagnominusGit/h700-suspend-stub` @ `712653d`. Built once per DRAM type against our own u-boot tree, with its own 28-line DRAM-resume patch | GPL-2.0-or-later |
| Kernel | ROCKNIX H700 patches 0157, 0160, 0161, 0162, 0163, 0210 | GPL-2.0 |

**Licence note (not legal advice).** BL31 embeds the GPL stub. Distribute the combined `bl31.bin`
(inside `u-boot-sunxi-with-spl.bin`) with its source and build recipe, as for any GPL binary.

**Build order** (the dependency is source-only, which avoids a loop):
1. u-boot source for the DRAM type;
2. build the stub (it reuses u-boot's DRAM code plus the resume patch);
3. build TF-A with `SUNXI_SYSTEM_SUSPEND=1 SUNXI_SUSPEND_STUB=<lpddr4 stub>` and optionally
   `SUNXI_SUSPEND_STUB2=<lpddr3 stub>`;
4. build u-boot with `BL31=` that bl31, giving one SPL image per DRAM type.

**Expected behaviour (inference from kernel code, to confirm).** When PSCI reports
SYSTEM_SUSPEND, the PSCI driver registers suspend-to-RAM, and `/sys/power/mem_sleep` should offer
`deep` and select it.

**Test ladder** (Dale, spare card only, UART if available). BL31 prints to the UART:
1. Boot log: `PSCI: System suspend available (SRAM stub …, DRAM type 8 @ 672 MHz)`.
   `No suspend stub matches this DRAM` means a stub or DRAM-config mismatch; stop there.
2. `cat /sys/power/mem_sleep` shows `[deep]`.
3. `sync; rtcwake -m mem -s 30`. Expect `PSCI: System suspend`, then
   `PSCI: Resumed from system suspend (wake IRQ …)`, and the shell comes back.
   The messages `skipped: DRAM did not enter self-refresh` or `stub did not report` are failures.
4. Wake by power key and by lid. The power press should not reach the frontend (patch 0157).
5. Battery: % before and after 1 h asleep, compared with s2idle.
6. A soak of 50 suspend/resume cycles with a game paused. Check `dmesg` for MMC or Wi-Fi errors
   after resume.

**Risk.** If DRAM doesn't re-train correctly on resume, the session is lost or the system crashes.
Run `sync` before every test, and use a spare card only.

## 8. Audio, battery/charger, Wi-Fi/BT: stock vs upstream (desk, 2026-11-13 21:45 ET)
Sources: Redux `reference/stock-202505/board.dts`; torvalds/linux `97d73c8`
(`sun50i-h700-anbernic-rg35xx-2024.dts`, `-plus.dts`, `-sp.dts`, `sound/soc/sunxi/sun4i-codec.c`,
`drivers/power/supply/axp20x_battery.c`).

| Area | Stock | Upstream (RG35XX 2024/Plus/SP chain) | Redux draft |
|---|---|---|---|
| Speaker amp enable | PI5, active high, then **100 ms** wait (`pa-pin-msleep-0`) | `allwinner,pa-gpios` PI5, but the driver waits a fixed **700 ms** | Patches 0002/0003 add `allwinner,pa-delay-ms` (default 700); board DT sets 100 |
| Headphone detect | PI3 | PI3 (`hp-det-gpios`) | inherited |
| Amp supply | CLDO1 (`allen_amp_power`) | CLDO1 `vcc-spkr-amp`, always on | inherited |
| Output routing | LINEOUT and SPK from the same pins | Speaker + Headphone on LINEOUT (74HC4052 mux comment) | inherited |
| **Charge voltage** | **4.10 V** (`pmu_init_chgvol = 0x1004`) | **4.20 V** (`voltage-max-design-microvolt`; AXP717 driver programs CV from it) | **4.10 V** (stock; less wear) |
| Charge current | 1500 mA run/suspend/off | 1024 mA | 1024 mA for now; stock's 1500 mA after a charging-temperature check (device task) |
| Capacity / resistance | 3000 mAh, 170 mΩ | not set | set from stock (informational in mainline) |
| Fuel-gauge curve | 32-point OCV table (`pmu_bat_para1..32`) | not programmed by the mainline driver | not carried; the gauge runs on the PMIC's own default |
| USB input limit | adapter 2500 mA, PC 500 mA | 1500 mA | upstream (below stock) |
| Battery thermistor | `pmu_bat_temp_enable = 0` | driver default | to check: if the board has no thermistor, `x-powers,no-thermistor` |
| Wi-Fi | RTL8821CS SDIO, power CLDO4 | mmc1 + pwrseq (reset PG18), CLDO4/ALDO4, host-wake PG15 | inherited |
| Bluetooth | reset PG19, wake PG17, host-wake PG16, UART1 | same pins, `realtek,rtl8821cs-bt` | inherited |
| LEDs | low-power LED PI11 | gpio-leds PI12 power, PI11 status | inherited |
| Rumble | `moto_pwm_gpio` PH2 | none | **not added**: Anbernic's one-DT-for-the-family; motor presence unconfirmed (device task) |

Also found: Redux's `docs/hardware-map.md` says the SP lacks "the analog-stick mux". The same document
confirms two sticks on Dale's unit, so that header note is stale for the mux.

## 9. Verification status (2026-11-13 21:50 ET, updated 22:10 ET; all desk)
Against torvalds/linux `97d73c8` (v7.4-rc2) with aarch64-linux-gnu-gcc 13.3 and dtschema (PyPI,
current):

| Item | Check | Result |
|---|---|---|
| 0001 cpufreq xlate | `W=1` object build; `checkpatch`; host test (28 cases) | clean; 0/0; 28/28 pass |
| 0002 + 0003 codec delay | `dt_binding_check` (codec schema); `W=1` object build; `checkpatch` | pass; clean; 0/0 |
| 0004 + 0005 bindings | `dt_binding_check` (OPP schema, sunxi.yaml); `checkpatch` | pass; 0/0 |
| Board DT (interim OPPs, upstream thermal) | `make CHECK_DTBS=y` | **0 warnings** |
| Board DT + stock OPPs + stock thermal | `make CHECK_DTBS=y`; table round-trip from the DTB | **0 warnings**; all 9 stock tables reproduced |
| 0006 upstream-style board DT (§10) | `make CHECK_DTBS=y`; `checkpatch --strict` | **0 warnings**; 0 errors, 1 warning (MAINTAINERS reminder; the directory is already covered) |
| Whole set | `scripts/workbench.sh --bindings` from an empty work directory | see the README for the last run |

Schema fixes this needed: OPP table node names (`opp-table-reduxcpu`, `-reduxgpu`, `-reduxstock`;
the pattern allows one suffix), no `opp-suspend` in the H616 OPP schema, and per-bin voltages as
`opp-microvolt-speed<N>`.

## 10. R16: upstream-style `sun50i-h700-anbernic-rg34xx-sp.dts` (patch 0006; 2026-11-13 22:10 ET)
**What it is.** A board tree in upstream's own style, for a possible upstream submission and as
the base the Redux tree could later include. Patch 0006 adds it plus its Makefile line; the
binding entry is patch 0005.

**Contents** (on top of `sun50i-h700-anbernic-rg35xx-sp.dts`):
- model `Anbernic RG34XX-SP`, compatible `anbernic,rg34xx-sp`, `allwinner,sun50i-h700`;
- sticks: the same `adc-joystick` + `io-channel-mux` + `gpio-mux` nodes and labels as upstream's
  RG35XX-H (`adc_mux`, `gpio_mux`, `joy_mux_pin`), polling at 16 ms, right stick reversed;
- stick clicks: `button-thumbl` PE8 and `button-thumbr` PE9 in `gpio_keys_gamepad`, as on the
  RG35XX-H;
- battery: 3000 mAh, 170 mΩ, `voltage-max-design-microvolt` 4.10 V (stock's charge target);
- `allwinner,pa-delay-ms = <100>` on the codec (needs patches 0002/0003; without them the
  property is ignored).

**Deliberately left out** (Redux-only policy stays in the `-redux` tree and its dtsi files):
- OPP and thermal overrides. The upstream-style tree inherits upstream's
  `sun50i-h616-cpu-opp.dtsi` and its trips **unchanged**. That means upstream's lower voltages at
  some steps (§2), so **Redux images must keep using the `-redux` tree** until Q2 is decided and
  the bins are mapped (K8). The upstream-style tree is for upstream review, not for our image.
- Panel, rumble (K13), charge current changes (Q5).

**Key check against stock** (Redux `reference/stock-202505/board.dts`, node `ANBERNIC-keys`):
every stock key pin matches the upstream 2024 base (PA0–PA12, PE0–PE3) except L3/R3, which the
SP tree lacks. Key *codes* follow upstream's gamepad convention, not stock's.

**Checks** (torvalds/linux `97d73c8`, aarch64-linux-gnu-gcc 13.3.0, dtschema from PyPI):
- `make CHECK_DTBS=y allwinner/sun50i-h700-anbernic-rg34xx-sp.dtb`: 0 warnings. A deliberately
  wrong property (`poll-interval = "x"`) produced a warning, so the check is live.
- The compiled DTB holds the intended values (read back with `fdtget`): L3/R3 codes 317/318,
  battery 4100000 µV / 3000000 µAh / 170000 µΩ, `pa-delay-ms` 100, 4 stick axes.
- `checkpatch.pl --strict --no-signoff`: 0 errors, 1 warning ("does MAINTAINERS need
  updating?"). `get_maintainer.pl` shows `arch/arm64/boot/dts/allwinner/` already listed under
  ARM/Allwinner sunXi, so no MAINTAINERS change is needed.
- **Not run:** no boot. Axis signs and stick clicks need K5.

**Before any upstream submission** (Dale's call, not before K5):
- The kernel's AI-assistant rules (`Documentation/process/coding-assistants.rst` and
  `generated-content.rst` at `97d73c8`) say a tool must never add `Signed-off-by`; the human
  submitter adds it after reviewing. They also ask for the tool's part to be disclosed in the
  changelog. Patch 0006 already says so; **0001–0005 need the same disclosure line added**.
- The author line `Redux Kernel Research <redux@invalid>` must become the submitter's identity.
- `scripts/get_maintainer.pl` gives the recipients (sunxi maintainers, devicetree, linux-sunxi).
