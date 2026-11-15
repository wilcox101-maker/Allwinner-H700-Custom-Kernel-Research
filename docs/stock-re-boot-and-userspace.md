# Stock firmware RE, boot chain and userspace (Deep Research part of the Ghidra plan)

Items **G3, W3.4, W3.5, W3.6** of the Ghidra plan (Manager files 2026-11-15-e/-f; the plan itself is KR's
`docs/ghidra-plan.md`). One PR per item; this file is the record.

**Rules:** desk only; stock files read, never written, never committed; names, addresses, constants, tables and
behaviour only, **no decompiled code**. Tags: **[G]** disassembly, **[D]** DT/strings/config, **[V]** device-verified
(only from a Dale hw-result note). Nothing here is [V].

**Input:** `RG34XXSP-V1.0.6-EN16GB-260526.IMG` (read-only, Dale's PC). Extracts (not committed) in
`Downloads\Anbernic RG34xxSP\.FW\re-extracts\`: `boot0.bin` (image 8–128 KiB, SHA-256 `84900f28…`),
`boot_package.bin` (16,400 KiB + 1,280 KiB, `a636f028…`), `env.img` (partition 2, `8dd964ef…`).

## Boot package layout (shared by G3 and W3.4)
`sunxi-package` TOC1, magic `0x89119800`, checksum valid, 4 items, valid length 0x140000 [D]:

| # | Name | Offset | Length | What |
|---|---|---|---|---|
| 0 | `u-boot` | 0x800 | 0x100000 | U-Boot 2018.05 (May 26 2026 15:48:53), **AArch32 Thumb-2**, runs at 0x4A000000 |
| 1 | `monitor` | 0x100800 | 0x1A2D0 | ATF BL31 (W3.4) |
| 2 | `dtbo` | 0x11AC00 | 0x920 | overlay: AXP1530 PMIC node + `standby_param` (W3.4) |
| 3 | `dtb` | 0x11B800 | 0x23200 | u-boot's own DT (sys_config-style nodes, 6,638 lines decompiled) |

No `scp` item: see W3.4.

---

## G3. Panel selection in stock u-boot

**Result:** one strap pin, **PE6**, read once in u-boot; the result reaches the kernel **only as the cmdline argument
`lcd_type=boe|old`**. u-boot does not edit the kernel DT and does not save the value to the env partition.

### Read and decide [G] (detail and both init sequences: Project doc `rg34xxsp-panel-detect-and-uboot-patch.md`, 2026-11-13)
| Step | Register / call | Value |
|---|---|---|
| Panel GPIOs to output | `PI_CFG1` 0x0300B124 | PI8 (SPI CS), PI9/PI10 (bit-banged SPI), PI14 (reset), PI15 |
| Reset pulse | `PI_DAT` bit 14 | 1, 15 ms; 0, 50 ms; 1, 100 ms |
| Strap as input, pull-up | `PE_CFG0` 0x0300B090 (PE6), `PE_PULL0` 0x0300B0AC = 01 | |
| Read | `lcd_type = !PE_DAT(0x0300B0A0).bit6` | printed as `===%s:L%d,lcd_type = %d` |
| PE6 **low** (`lcd_type`=1) | init sequence A (original panel, NV3052C-family) | env `lcd_type=boe` |
| PE6 **high** (`lcd_type`=0) | V1.0.6: v2-panel sequence (2025 builds: an older third panel) | env `lcd_type=old` |

Routine: `lcd_panel_uboot_fj035fhd05_v1_init`, 0x4A0262E4. The panel is chosen from u-boot's own DT: node
`lcd0@01c0c000` has `lcd_driver_name = "rg34xxsp_v1"` (read at 0x4A021682 with key `lcd%d`), which selects the
panel function table entry `rg34xxsp_v1` (string 0x4A0A40E8, table ref 0x4A0A4078) [G][D].

### Hand-off to the kernel [G]
| Where | Address | What happens |
|---|---|---|
| boe branch tail | 0x4A026B04 → 0x4A026B0C | `env_set("lcd_type", "boe")` (tail call to 0x4A00E620, the same `env_set` used for `bootargs`) |
| old branch | 0x4A0279FE → 0x4A026B06 | `env_set("lcd_type", "old")` |
| cmdline builder | function 0x4A005734; 0x4A00592C–0x4A00594A | `env_get("lcd_type")`, append ` lcd_type=%s`, then `env_set("bootargs", …)` |
| `lcd_driver_name` | 0x4A021682 | **read** from u-boot's DT only; no `fdt_setprop` of panel properties into the kernel DTB was found |
| env partition | `env.img` | **no `lcd_type` key** stored: decided fresh every boot |

### Data: everything the builder appends to the kernel cmdline [G]
Base `bootargs` comes from env `setargs_mmc` (chosen at 0x4A005770 when booting from MMC; env's own `bootcmd` names
`setargs_nand`). Then, in order: ` androidboot.mode=normal` (or `=charger` in charger mode), ` androidboot.serialno=%s`
(env `snum`), ` mac_addr=%s`, ` wifi_mac=%s`, ` bt_mac=%s`, ` androidboot.hardware=sun50iw9p1`, ` boot_type=%d`,
` androidboot.boot_type=%d`, ` androidboot.secure_os_exist=%d`, `dram_clk` from DT `soc/dram_para`, ` gpt=1`,
` androidboot.verifiedbootstate=%s`, ` uboot_message=2018.05(05/26/2026-15:48:53)`, ` disp_reserve=%s`,
` bootreason=%s`, ` aw-ubi-spinand.ubootblks=%s`, ` lcd_type=%s`.

### What this means for mainline (open question 3)
Stock's identification is the same single PE6 read our u-boot patch does (`CONFIG_ANBERNIC_RG34XXSP_DT_SELECTION`,
Q3 mapping), so nothing new is needed. The stock kernel learns the panel from `lcd_type=` on the cmdline; our design
passes it as a DTB choice (`fdtfile`). A stock-kernel-based Redux must keep `lcd_type=` in any custom bootargs.

### Optional device checks (Redux Device test queue)
- *optional:* on stock, `tr ' ' '\n' </proc/cmdline | grep lcd_type` → expect `lcd_type=boe` on an original-panel unit.
- *optional:* stock serial log at boot: the `lcd_type = 1` line (PE6 low) next to the panel init.

---

## W3.4. Boot package: u-boot, ATF BL31, (no) SCP

**Result:** BL31 is Allwinner's ATF fork `v1.0(debug):5a77824` (built 2024-08-02, `plat/sun50iw9p1`) offering
**PSCI 1.0 with `SYSTEM_SUSPEND`**. **There is no SCP/AR100 firmware** anywhere in boot0 or the boot package: BL31
performs "universal standby" itself on the ARM core (DRAM controller and PHY, RTC/PRCM registers) and **emulates the
`arisc` wakeup-source API locally**. u-boot reaches the kernel only through the cmdline (G3 table) and its env.

### Components [D]
| Part | Version / identity |
|---|---|
| boot0 (SPL, 8 KiB) | eGON.BT0, build tag `ac58e911-dirty`, has `DRAM.ext`; DRAM sets: see below and Project doc `rg34xxsp-panel-detect-and-uboot-patch.md` |
| u-boot | `U-Boot 2018.05 (May 26 2026 - 15:48:53 +0800) Allwinner Technology`, AArch32 Thumb-2 at 0x4A000000; tools tag `v1.17 2021-02-22 16:10` |
| BL31 (`monitor`) | ATF `v1.0(debug):5a77824`, `Built : 15:20:22, 2024-08-02`, files `plat/sun50iw9p1/{bl31_sunxi_setup,plat_pm,plat_gic,plat_topology}.c`; also carries Allwinner's USB **FEL/efex** stack and an **efuse key burn/read** service (`burn key start`, `read key start`) |
| SCP | **none**: no `scp` TOC1 item, no AR100/OpenRISC image in boot0. u-boot DT keeps legacy `arisc` nodes (below) |

### PSCI functions offered by BL31 [G]
Standard-service dispatch at offset 0x8044 (`(fid & 0xffe0)==0` → PSCI handler 0x98DC; 0x8400FF00/FF01/FF03 = call
count / UID / revision). Jump tables at 0x17FD8 (SMC32) and 0x17FE8 (SMC64).

| Function | SMC32 | SMC64 |
|---|---|---|
| PSCI_VERSION | 0x84000000 → returns **0x10000 (1.0)** | — |
| CPU_SUSPEND | ✓ | ✓ (0xC4000001) |
| CPU_OFF | ✓ | (SMC32 only by spec) |
| CPU_ON | ✓ | ✓ |
| AFFINITY_INFO | ✓ | ✓ |
| MIGRATE | returns NOT_SUPPORTED (−1) | same |
| MIGRATE_INFO_TYPE | returns 2 (no trusted OS needing migration) | (SMC32 only) |
| MIGRATE_INFO_UP_CPU | ✓ | ✓ |
| SYSTEM_OFF / SYSTEM_RESET | ✓ / ✓ | (SMC32 only) |
| PSCI_FEATURES | ✓ | (SMC32 only) |
| CPU_FREEZE, CPU_DEFAULT_SUSPEND, NODE_HW_STATE | **not implemented** | not implemented |
| **SYSTEM_SUSPEND** | **✓ 0x8400000E** | **✓ 0xC400000E** |

u-boot DT: `/psci` = `arm,psci-1.0`, method `smc`; CPU idle state `cpu-sleep-0` with `arm,psci-suspend-param = 0x10000`.

### Suspend / standby inside BL31 [G][D]
| Item | Finding |
|---|---|
| Where standby runs | in BL31 on the A53 (no co-processor). BL31 code touches **MCTL_COM 0x047FA000**, **MCTL_CTL 0x047FB000** and the **DRAM PHY 0x04800000** (hundreds of accesses: self-refresh / re-training), **RTC 0x07000000** (0x100–0x208, 0x440–0x544), **R_PRCM 0x07010000**, CCU 0x03001000, SID 0x03006000, PIO 0x0300B000, GIC-400 0x03021000/0x03022000, R_PIO 0x07022000, R_CIR 0x07040000, UART0 0x05000000, CPU-subsystem 0x08100000/0x08120000 |
| DT it reads | `/aliases`, `pmu%d` (`device_type` `twi`, `reg`), `standby_param` (`vdd-cpua`, `vdd-cpub`, `vdd-sys`, `vcc-io`, `vcc-pll`, `vcc-dram`, `vdd-res1`), `universal-standby`, compatibles `allwinner,h616` / `allwinner,t507`, `ir0` (`ir_power_key_code`, `ir_addr_code`), `/box_start_os0` (`start_type`), pin groups (`allwinner,pins/muxsel/data/drive/pull`) |
| Standby type | printed as `standby_type: 0x%x` (0x1B68); u-boot DT `pm_para/standby_mode = 1`; dtbo `no_suspend = 1` on the PMIC fragment |
| PMIC | dtbo overlay: **AXP1530** at TWI address 0x36, `wakeup-source`, `standby_param/vcc-dram` → DCDC1; BL31 checks the PMU ID (`pmu id is err, pmu id is 0x%08x`) |
| Wake sources | `arisc_set_wakeup_source` at 0x23F0 is **local**: the ID's low 10 bits set a bit in a 32-word IRQ bitmap (BSS +0x750); IDs with bits 31:30 = 0b11 go to a separate word (+0x748). Clear counterpart at 0x23A8. So wake sources = **GIC interrupt numbers** chosen by the kernel |
| Reserved memory | u-boot DT `arisc_space`: 0x48040000+0x14000, 0x48100000 (offset 0x18000, 0x4000), 0x48104000+0x1000, 0x48105000+0x1000; `standby_space` (`allwinner,sun50iw9-usbstandby`) 0x40020000+0x800; `secure/dram_region_mbytes` = 80 |

**For G1 (KR):** "real suspend" exists at the firmware level (PSCI `SYSTEM_SUSPEND`, DRAM self-refresh in BL31).
Whether the stock *kernel* uses it (`mem_sleep`, `platform_suspend_ops`) is G1's kernel side. For mainline, our
TF-A (upstream `sun50i_h616`) has its own PSCI implementation; this stock BL31 is not in our boot chain.

### u-boot env, boot commands [D]
`env.img` (partition 2): CRC-32 OK, 4-byte header, 0x20000 bytes, 25 variables. Notable: `bootdelay=0`,
`bootcmd=run setargs_nand boot_normal` (u-boot switches to `setargs_mmc` at runtime when booting from MMC),
`boot_normal=sunxi_flash read 45000000 boot;bootm 45000000` (Android boot image at 0x45000000),
`boot_recovery` (partition `recovery`), `boot_fastboot=fastboot`, `mmc_root=/dev/mmcblk0p5`, `nand_root=/dev/nand0p4`,
`init=/init`, `loglevel=4`, `cma=64M`, `selinux=0`, `console=ttyS0,115200`, `earlyprintk=sunxi-uart,0x05000000`,
`keybox_list=hdcpkey,widevine`, key windows `recovery_key_value_min/max = 0x10/0x13`, `fastboot_key_value_min/max =
0x2/0x8`, empty `mac`/`wifi_mac`/`bt_mac`/`specialstr`. **No `lcd_type` stored** (G3).
u-boot DT `/chosen/bootargs` default: `earlyprintk=sunxi-uart,0x05000000 loglevel=8 initcall_debug=…`.

### u-boot DT: board data (decompiled locally, 6,638 lines; tables below, full dump kept out of git)
**Buttons** (`gpio_keys`, `gpio-keys-polled`, label `ANBERNIC-keys`, poll 20 ms; analog-mux pins `amux-en` PI0,
`A0` PI1, `A1` PI2, `adc-en` PE11):
| Button | Pin | Code |
|---|---|---|
| UP | PA6 | 0x11 ABS_HAT0Y -1 |
| DOWN | PE0 | 0x11 ABS_HAT0Y +1 |
| Left | PA8 | 0x10 ABS_HAT0X -1 |
| Right | PA9 | 0x10 ABS_HAT0X +1 |
| A | PA0 | 0x130 BTN_SOUTH |
| B | PA1 | 0x131 BTN_EAST |
| X | PA3 | 0x132 BTN_C |
| Y | PA2 | 0x133 BTN_NORTH |
| Start | PA4 | 0x137 BTN_TR |
| SEl | PA5 | 0x136 BTN_TL |
| L1 | PA10 | 0x134 BTN_WEST |
| L2 | PA11 | 0x13a BTN_SELECT |
| R1 | PA12 | 0x135 BTN_Z |
| R2 | PA7 | 0x13b BTN_START |
| L3 | PE8 | 0x139 BTN_TR2 |
| R3 | PE9 | 0x13c BTN_MODE |
| Menu | PE3 | 0x138 BTN_TL2 |
| Vol+ | PE1 | 0x73 KEY_VOLUMEUP |
| vol- | PE2 | 0x72 KEY_VOLUMEDOWN |

Note the **codes don't follow the labels** (Start → `BTN_TR`, Select → `BTN_TL`, L2 → `BTN_SELECT`, R2 →
`BTN_START`, Menu → `BTN_TL2`…): stock apps expect this mapping. A disabled LRADC `keyboard` node
(`keyboard_1350mv`) is a leftover.

**DRAM selection** (`dram_select_para`): `select_mode = 1`, `gpadc_channel = 1`, straps **PH6, PH7, PH8, PH10**
(input, pull-up). Sets 1–13 are identical DDR3-792 placeholders; the two real ones:
| Set | clk | type | dx_odt | dx_dri | ca_dri | para1 | para2 | mr1 | mr2 | mr3 | mr11 | mr12 | mr13 | mr14 | mr22 | tpr6 | tpr10 | tpr11 | tpr12 | tpr13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 14 | 672 | LPDDR3 | 6060606 | d0d0d0d | 1919 | 30fa | 1000 | c3 | 6 | 1 | 0 | 0 | 0 | 0 | 0 | 2fb08080 | 402f4489 | e0e0f0e | f10110f | 8c60 |
| 15 | 672 | LPDDR4 | 8080808 | e0e0e0e | e0e | 310a | 0 | 34 | 1b | 33 | 4 | 72 | 0 | 9 | 24 | 40808080 | 402f6633 | 0 | 0 | 2008c60 |

**CPU OPP table** in u-boot's DT (`opp_l_table`, `allwinner,sun50i-operating-points`, nvmem cell `speed`;
Allwinner bin numbers, **not** mainline `speed0–5`, mapping is KR's G2):
| OPP node | MHz | mV | opp-supported-hw (bits = bins) |
|---|---|---|---|
| 480000000-0 | 480 | 900 | 0x33 = bins 0,1,4,5 |
| 480000000-1 | 480 | 900 | 0xc = bins 2,3 |
| 600000000-0 | 600 | 900 | 0x3 = bins 0,1 |
| 600000000-1 | 600 | 900 | 0xc = bins 2,3 |
| 720000000 | 720 | 900 | 0x30 = bins 4,5 |
| 792000000-0 | 792 | 900 | 0x3 = bins 0,1 |
| 792000000-1 | 792 | 940 | 0xc = bins 2,3 |
| 936000000 | 936 | 900 | 0x30 = bins 4,5 |
| 1008000000-0 | 1008 | 920 | 0x1 = bins 0 |
| 1008000000-1 | 1008 | 900 | 0x2 = bins 1 |
| 1008000000-2 | 1008 | 1020 | 0xc = bins 2,3 |
| 1008000000-3 | 1008 | 950 | 0x30 = bins 4,5 |
| 1104000000 | 1104 | 1000 | 0x30 = bins 4,5 |
| 1200000000-0 | 1200 | 980 | 0x1 = bins 0 |
| 1200000000-1 | 1200 | 960 | 0x2 = bins 1 |
| 1200000000-2 | 1200 | 1100 | 0xc = bins 2,3 |
| 1200000000-3 | 1200 | 1050 | 0x30 = bins 4,5 |
| 1296000000-0 | 1296 | 1100 | 0x2 = bins 1 |
| 1296000000-1 | 1296 | 1120 | 0x8 = bins 3 |
| 1320000000 | 1320 | 1100 | 0x30 = bins 4,5 |
| 1344000000 | 1344 | 1120 | 0x4 = bins 2 |
| 1416000000-0 | 1416 | 1150 | 0x10 = bins 4 |
| 1416000000-1 | 1416 | 1160 | 0x20 = bins 5 |
| 1512000000 | 1512 | 1120 | 0x1 = bins 0 |

Plus 14 `*-ab` nodes (opp-microvolt-a1/b0/b1/c0/c1/c2 per-grade voltages) for frequencies: 480, 600, 720, 792, 936, 1008, 1032, 1104, 1200, 1296, 1320, 1344, 1416, 1512

**Other board nodes** [D]:
| Node | Values |
|---|---|
| `lcd0` | `lcd_driver_name = rg34xxsp_v1`, `lcd_x` 720 (and the rest of the RGB timing set), backlight PWM ch 0, 50 kHz, `lcd_pwm_max_limit` 255, `lcd_backlight` 50; `lcd_gpio_0..4` = PI9, PI10, PI8, PI14, PI15 (panel SPI + reset, G3) |
| `power_sply` | `bldo1_vol` 1800, `bldo2_vol` 1001800, `cldo4_vol` 1103300 (raw; Allwinner encodes an "always on" flag above 1,000,000, so likely 1.8 V and 3.3 V, not confirmed), DCDC1/2 mode 1, `bc12_mode` 0, `ntc_status` 0 |
| `charger0` | `pmu_safe_vol` 3450 mV |
| `pm_para` | `standby_mode` 1 |
| `boot_init_gpio` | PI11 → 0, PI12 → 1 at boot |
| `gpio_para` (disabled) | LED on PH6 |
| `key_boot_recovery` | long press 2000 ms on **PH9** enters recovery |
| `card_boot` | `logical_start` 0xA000 (sectors = 20 MiB), sprite GPIO PH6 |
| `card0_boot_para` / `card2_boot_para` | SDC0 4-bit high speed; SDC2 8-bit (eMMC-style, unused on the SP) |
| `wlan` | bus 1 (SDC1), power `axp2202-cldo4` |
| `bt` / `btlpm` | `bt_rst_n` PG19, `bt_wake` PG17, `bt_hostwake` PG16 (EINT), UART1 |
| `gpadc` | channel 1 compare low/high 1,700,000 / 1,200,000 µV, 100 kHz |
| thermal (u-boot copy) | CPU trips 70 °C passive (0x11170 = 70,000), 115 °C critical; GPU zone sustainable-power 1100 |
| `product` / `platform` / `target` | `version 100`, `machine evb`; `debug_mode 3`; `boot_clock` 1008 MHz |
| `arisc` | legacy: `power_reg 0x2309621`, `system_power 50`, `powchk_used 0` |

### What this means
- **Mainline:** nothing in the stock boot chain needs to be kept. Our chain (u-boot + upstream TF-A) replaces all of
  it; the DRAM sets, key map and pins above are reference data (already consistent with R1 and Q3).
- **Redux (stock kernel):** suspend support is present in firmware; the stock key-code mapping above is what apps rely
  on; the boot partition is an Android boot image loaded at 0x45000000.

### Optional device checks
- *optional:* stock serial log: the `BL3-1:` and `standby_type` lines, and the `PSCI` version the kernel prints.
- *optional:* on stock, `cat /sys/power/state /sys/power/mem_sleep` (with KR's G1).
- *optional:* `evtest` on the stock key device: Start reports `BTN_TR`, L2 reports `BTN_SELECT`.
