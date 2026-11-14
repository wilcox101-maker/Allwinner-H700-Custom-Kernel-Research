# Findings for open questions 1–6 (2026-11-13)

From the Redux Kernel Research chat (read-only). **Desk research only: nothing here has run on
Dale's device.** It answers the desk questions in the Redux repo's `docs/kernel-research/open-questions.md`;
the device side is in [device-checklist-rocknix.md](device-checklist-rocknix.md).

Sources, all read on 2026-11-13:
- **Upstream**: torvalds/linux `97d73c8` (v7.4-rc2), from the GitHub mirror; release tags
  v6.10–v6.13, v6.17 and v7.0 for history.
- **ROCKNIX**: ROCKNIX/distribution main `4fc79d7`, and release tag `20261101` (`cefc143`, 2026-10-31).
- **Stock**: `reference/stock-202505/board.dts` in the Redux repo
  ([wilcox101-maker/Anbernic_RG34XXSP_Redux](https://github.com/wilcox101-maker/Anbernic_RG34XXSP_Redux)).
- **TF-A**: TrustedFirmware-A `v2.15.0`.
- **Mailing lists**: the ratatoskr.run archive and tracker, plus the lists.infradead.org and
  mail-archive.com archives. This chat could not reach git.kernel.org, lore.kernel.org or
  linux-next, so "queued" can't be confirmed directly. See Q2.

| # | Question | Answer in one line |
|---|---|---|
| 1 | Which version added upstream `rg35xx-sp.dts` | **v6.12** |
| 2 | H616 display DT / H616 PWM queued for 7.5? | **No sign of it.** PWM is at v12 (2026-11-04) and still pending; the display DT has no new version since 2025-07 |
| 3 | How ROCKNIX picks the v1 or v2 panel tree | **It doesn't detect anything.** The user copies a DTB by hand and tries the other one if the screen shows garbage |
| 4 | Real or fake suspend on H700 in 20261101 | **Real suspend-to-RAM is the default.** The "Fake Suspend" wiki entry is out of date |
| 5 | ROCKNIX OPPs and thermal vs stock | The bin encodings differ, so the tables can't be matched at the desk. Upstream's critical trip is **110 °C, stock's is 115 °C**. ROCKNIX's GPU table matches stock exactly |
| 6 | Can upstream `adc-joystick` + `io-channel-mux` describe the SP sticks | **Yes.** Upstream's RG35XX-H already does it on the same pins; inversion is a reversed `abs-range` |

## Q1. Upstream `sun50i-h700-anbernic-rg35xx-sp.dts`

- The file is **absent in v6.11 and present in v6.12** (`git ls-tree` on both tags). The first H700
  trees (RG35XX 2024, Plus, H) are in v6.10, as already recorded.
- Header: Ryan Walklin and Chris Morgan, 2024. It includes `sun50i-h700-anbernic-rg35xx-plus.dts`
  and adds the lid as `gpio-keys` **SW_LID on PE7** (wake source, `EV_ACT_DEASSERTED`).
- The RG35XX Plus and SP have no analog sticks, so **the upstream SP tree has no joystick nodes**.
  An RG34XX-SP tree must add them (see Q6).
- Ubuntu rows: v6.17 and v7.0 both contain the SP tree (checked), so the 24.04 HWE kernels 6.17 and
  7.0 have it. 24.04 GA 6.8 has no H700 tree at all.

## Q2. H616 display DT series and H616 PWM driver for 7.5

**Upstream at `97d73c8`:** `sun50i-h616.dtsi` has no display engine, TCON or PWM node (grep finds
none), and `drivers/pwm/` has no `pwm-sun8i.c`.

**H616 PWM:**
- The ratatoskr tracker (linux-sunxi PWM page, data through about 2026-11-14) lists **v12, posted
  2026-11-04 by James Hilliard, as PENDING with 1 of 5 patches reviewed**. v12 has 5 patches; a new
  one exports the bypass outputs as clocks. v9–v11 came out on 2026-09-22, 09-23 and 11-03.
- v1–v7 were Richard Genoud's (Bootlin), 2025-12-05 to 2026-07-03.
- ROCKNIX carries **v8** (2026-08-04), which is now four revisions old.

**H616 LCD/TCON display DT:**
- The newest version found is Ryan Walklin's **v2 of 2025-07-20**, "add LCD timing controller and
  display engine support" (12 patches, ending with "rg35xx: Enable LCD output"). Its cover says the
  backlight isn't modelled because no H616 PWM driver exists.
- A separate HDMI DT series (Barzin Lotfabadi, 2026-09-04, tested on an Orange Pi Zero 3) got a
  **NACK from Jernej Škrabec on 2026-09-05**. He said its hardware description is outdated and
  pointed to newer work. That newer work could not be read here (lore is blocked).

**Inference, not confirmed:** to make the 7.5 merge window, patches normally sit in linux-next by
late in the 7.4 rc cycle. A PWM series still waiting for review in mid-November, and a display DT
with no repost in 16 months, make 7.5 unlikely for either.
- **Plan on carrying both through 7.5 at least.**
- Re-check linux-next (`sunxi/dt-for-7.5`, the pwm tree) from a session that can reach git.kernel.org.

## Q3. How ROCKNIX picks `rg34xx-sp` or `rg34xx-sp-v2-panel`

- **Image:** `projects/ROCKNIX/config.xml` gives H700 (DDR4 and DDR3 alike) `fdt="dtb.img"`, so
  `extlinux.conf` always loads `/dtb.img`. The image ships every DTB in `device_trees/` and no
  `dtb.img`.
- **First boot:** the ROCKNIX "Anbernic H700 installation guide" (rocknix.org/configure/h700-installation/)
  has the user copy their device's DTB to the partition root and rename it `dtb.img`. If the
  screen displays garbage, they shut down (10 s press), reflash and try the other DTB.
  - The guide's table lists only `sun50i-h700-anbernic-rg34xx-sp.dtb` for the RG34XX SP. It has no
    v2 row, though the v2 tree and an `rg-sp` tree (model "Anbernic RG-SP", using the
    `rg34xx-sp-v2-panel` compatible) are both built.
- **Updates:** `devices/H700/bootloader/update.sh` reads `/proc/device-tree/rocknix-dt-id` from the
  running tree and copies the same-named DTB over `dtb.img`. Each H700 DT sets its own
  `rocknix-dt-id`. Updates keep the user's choice; they never detect anything.
- **u-boot:** the same script picks the u-boot build from the `vdd-dram` regulator voltage
  (1.2 V → DDR3 binary, 1.1 V → DDR4 binary) and writes it with `dd` at 8 KiB on the boot disk.
  - **That offset is ROCKNIX's card layout. Never reuse it on ours.**
- **For Redux:**
  - ROCKNIX's method is "try it and look". That breaks our rule from field-reports.md (identify
    the panel before driving it; never drive an unknown panel), so we can't copy it.
  - Candidate runtime IDs are still the ones in the V1.0.6 diff note: the DRAM strap GPIOs
    PH6/7/8/10, MemTotal, and stock's choice of `lcd_driver_name` (`rg34xxsp_v1` vs
    `fog_fj035fhd05_v1`).
  - Whether either panel answers a read-ID over its 3-wire SPI is unknown (not checked).

## Q4. Real or fake suspend in ROCKNIX 20261101 on H700

**Real suspend-to-RAM is the default in 20261101.** Evidence at tag `20261101` (the same files are on main `4fc79d7`):
- **TF-A:** `projects/ROCKNIX/packages/tools/atf/package.mk` pins **TF-A 2.12.0 for H700** (other
  devices get 2.10.0; the generic `packages/tools/atf` is 2.15.0). It builds with
  `SUNXI_SYSTEM_SUSPEND=1`, LPDDR4 stub as `SUNXI_SUSPEND_STUB`, LPDDR3 stub as `SUNXI_SUSPEND_STUB2`.
- **TF-A patch** `patches/H700/001-allwinner-h616-psci-system-suspend.patch` (Kailash R S, from
  "H700_rocknix_enhancement"): BL31 copies the stub to SRAM A1, puts DRAM in self-refresh, waits in
  WFI and re-inits DRAM on wake.
  - **It picks the stub whose DRAM type and clock match at boot. If none matches, system suspend
    is left unavailable.**
  - Upstream TF-A v2.15.0 has no such code (no `sunxi_suspend_params.h`), so this is ROCKNIX-only.
- **Userspace:** quirk `platforms/H700/030-suspend_mode` runs a one-time migration. It deletes an
  old `suspendmode=off` setting and a `HandlePowerKey=ignore` override, then sets `suspendmode mem`.
  `suspendmode mem` writes systemd `SuspendState=mem standby freeze`.
- **Fallback:** `rocknix-fake-suspend` remains for when `suspendmode` is `off`.
- **Kernel side present:** 0157, 0160, 0161, 0162, 0163 and 0210 (480 MHz suspend OPP).
- **Still unknown:**
  - whether `/sys/power/mem_sleep` defaults to `deep` or `s2idle` (not traced);
  - battery drain asleep (no figures published);
  - whether the stub matches Dale's DRAM clock.
  All three are on the device checklist.

## Q5. ROCKNIX OPPs and thermal vs stock

**CPU, frequency sets.** Stock `opp_l_table` has 24 entries for 13 frequencies (480, 600, 720, 792,
936, 1008, 1104, 1200, **1296**, 1320, **1344**, 1416, 1512 MHz).

**Correction:** `hardware-map.md` and `ui-spec.md` list 8 steps; that is the common subset, not the
whole table. 720/936/1104/1320 also exist, for some bins.

| | Upstream `sun50i-h616-cpu-opp.dtsi` | ROCKNIX (0200, 0210) |
|---|---|---|
| Steps | 480, 600, 720, 792, 936, 1008, **1032**, 1104, 1200, 1320, 1416, 1512 | drops 1032 (speed5 only) |
| 1320 | speeds 0, 2, 3, 4 (`0x1d`) | also speed5 (`0x3d`) |
| 1512 | speeds 1, 3, 5 | marked `turbo-mode`, a boost OPP. ROCKNIX sets `DEVICE_TURBO_MODE="true"`; whether boost is on by default was not traced |
| 480 | normal OPP | `opp-suspend` |
| Not present | 1296, 1344 | 1296, 1344 |

**CPU, voltages.**
- The two tables encode bins differently. Stock uses `allwinner,sun50i-operating-points` with a
  "speed" nvmem cell and its own mask bits; upstream uses speed0–5 from `sun50i-cpufreq-nvmem`.
  So **a stock bin can't be matched to an upstream speed index at the desk**.
- Per frequency, the voltages differ:

| MHz | Stock range | Upstream range |
|---|---|---|
| 1416 | 1.15–1.16 V | 1.10 V |
| 1512 | 1.12 V, one bin | 1.10 V (speed1/3), 1.16 V (speed5) |
| 1200 | 0.96–1.10 V | 1.02–1.10 V |

- Lower than stock at the same frequency counts as undervolting under our hard rule, unless it
  is shown to be the same silicon bin.
- **Suggestion: Redux's mainline DT carries a stock-derived table** (stock frequencies and
  voltages per bin). Use upstream's only once the bin mapping is confirmed on the device.

**GPU.** ROCKNIX's 0007 table matches stock's `operating-points` exactly: 420/456/504/552/600 MHz
at 0.90 V and 648 MHz at 0.96 V. ROCKNIX caps at 600 by default and calls 648 an "overclock". For
Redux, **648 MHz is a stock value**, so it's allowed by default.

**Thermal.**

| Zone | Stock | Upstream | ROCKNIX |
|---|---|---|---|
| CPU passive trips | 60 / 70 °C (power allocator: sustainable 1000 mW, k_po 20, k_pu 40) | 60 / 70 °C | Inherits upstream. None of its 32 H700 kernel patch files touches trips |
| CPU critical | **115 °C** | **110 °C** | 110 °C |
| GPU / VE / DDR | no trips | **110 °C critical** on each | 110 °C |

**Rule conflict for Dale.** The hard rule says the critical trip is never changed. Taking
upstream's dtsi as-is would lower it to 110 °C and add critical trips stock doesn't have. The
change is in the safe direction, but it is still a change. Options:
- (a) override to stock's 115 °C, with no GPU/VE/DDR critical trips;
- (b) accept upstream's 110 °C and amend the rule's wording.

Not decided here.

## Q6. Sticks with upstream `adc-joystick` + `io-channel-mux`

**Yes, without ROCKNIX's out-of-tree joypad driver.**
- **Upstream already does it.** `sun50i-h700-anbernic-rg35xx-h.dts` (since 6.10) has:
  - `adc-joystick` over `io-channel-mux`: 4 channels on GPADC channel 0, `settle-time-us = <100>`,
    `poll-interval = <60>`;
  - `gpio-mux` selects on **PI1 / PI2** (active-low);
  - **PI0** driven as `gpio_out` through `joy_mux_pin`.
- **Same pins on the SP.** Stock `board.dts` (`ANBERNIC-keys`) has `amux-en-gpios` = **PI0**,
  `A0_gpio` = PI1 and `A1_gpio` = PI2.
  - `adc-en-gpios` = PE11 is set as an input; neither upstream nor ROCKNIX uses it.
  - ROCKNIX's joypad node (0140, for the 2024 family the SP includes) uses the same GPADC 0,
    PI1/PI2 and PI0.
- **Inversion.** `drivers/input/joystick/adc-joystick.c` marks an axis inverted when its
  `abs-range` minimum is greater than its maximum. ROCKNIX's `invert-absrx; invert-absry`
  becomes reversed `abs-range` on the two right-stick axes.
- **Work and unknowns:**
  1. Our SP tree adds about 60 lines modelled on `rg35xx-h.dts`: joystick, mux, gpio-mux,
     `joy_mux_pin`.
  2. Channel order and signs need `evtest` on the device. ROCKNIX maps channels as `<0 2 1 3>`;
     upstream H names them left_x, left_y, right_x, right_y in mux order.
  3. 60 ms polling is slower than stock's 20 ms. It can be set lower; the cost is four mux settles
     and GPADC reads per poll (CPU cost not measured).
  4. The codes change from stock's ABS_Z/RX/RY/RZ to ABS_X/Y/RX/RY. Buttons stay on `gpio-keys` as
     a separate input device, so the frontend input layer must handle two devices.

**Correction for `hardware-map.md`.** It says `amux-en-gpios (PI8)`. The value
`<0x4B 0x8 0x0 …>` is bank I (8), pin 0, so it is **PI0**. The same encoding gives PA6 for D-pad Up,
which the table already has right. This matters because ROCKNIX's display patch uses **PI8 as the
panel SPI chip-select** (`spi-gpio`: CS PI8, SCK PI9, MOSI PI10, reset PI14, LCD power PI15).
