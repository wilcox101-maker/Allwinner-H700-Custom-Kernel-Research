# Stock firmware RE, boot chain and userspace (Deep Research part of the Ghidra plan)

> **Update 2026-11-20:** the open items left here are closed in [`dr-unknowns-and-rebuild-2026-11-20.md`](dr-unknowns-and-rebuild-2026-11-20.md) §1: `brightCtrl.bin` is not shipped in V1.0.6 and `/dev/vsgame` does not exist (both dead references); all 76 stock udev rules are unmodified Ubuntu files; "Fast Shutdown" has no documented effect. Desk only.

Items **G3, W3.4, W3.5, W3.6** of the Ghidra plan (Manager files 2026-11-15-e/-f; the plan itself is KR's
`docs/ghidra-plan.md`). One PR per item; this file is the record.

**Rules:** desk only; **[N]** marks a finding with no public source we know of (Dale, 2026-11-15 02:46); stock files read, never written, never committed; names, addresses, constants, tables and
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

**Result [G][N]:** one strap pin, **PE6**, read once in u-boot; the result reaches the kernel **only as the cmdline argument
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

**Result [G][N]:** BL31 is Allwinner's ATF fork `v1.0(debug):5a77824` (built 2024-08-02, `plat/sun50iw9p1`) offering
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

---

## W3.5. Stock launcher `dmenu.bin` and its scripts

*Drafted by a DR worker agent from the extracts; DR re-checked the key strings and scripts (`ANBERNIC-keys`, `deeplayer/debug_reg`, `axp_reg 0x1801`, `pwr_new.sh` → `mem`, `rtcwake`, `hallkey`, `localpad.map`). "I/my" in this section = that worker.*

**Summary (5 lines)**
1. `dmenu.bin` (32-bit armhf SDL1.2, stripped, Linaro GCC 4.9) reads the keypad by scanning `/dev/input/event*` for the device named `ANBERNIC-keys`, and reads the power key/lid from a hard-coded `/dev/input/event0`. It turns both into one 19-bit key mask (19 codes, which `/mnt/data/dmenu/localpad.map` can remap).
2. Sleep is always `system("/mnt/vendor/ctrl/pwr_new.sh auto")`, which writes `mem` to `/sys/power/state`. The triggers are: a power-key release after ≥100 ms, a lid KEY 110 press/release, `hallkey`=0 polled every 500 ms, or an idle timer of 1/2/5/10 min (off for index ≥4). Holding power for 2 s gives a goodbye splash and then `poweroff`.
3. Brightness has 8 levels (`5,10,20,50,70,140,200,255`) and is set with `/dev/disp` ioctl 0x102 (get 0x103). It changes with MENU(BTN_TL2 312)+VOL±. VOL± alone changes volume level 0–10. In the launcher that level only scales its own UI sounds; in games `portsCtrl.dge`/`ndsCtrl.dge` write it to ALSA card 0 control #2 (values `0..31`). The levels persist in the vendor sysfs attributes `axp2202-battery/brightness` and `openbor_volume`.
4. Battery: the launcher reads `axp2202-battery/{capacity,voltage_now,status}` once a second, picks the icon from capacity thresholds, and treats `status`=="Charging" as charging. It shuts down (lowpower splash, then `poweroff`) after more than 20 consecutive 1 s polls with capacity==0 and voltage ≤3420 mV while not charging. `charg.dge` is the boot-mode-1 charger UI: USB unplugged → `poweroff`, power held 2 s → `reboot`, idle 20 s or lid closed → suspend.
5. Notable **[G][N]**: there is a periodic challenge–response with a vendor kernel driver (`/sys/class/deeplayer/deeplayer/debug_reg`); if it fails, the launcher runs `reboot` in a loop. Brightness/volume/sleep policy is spread across dmenu, the ctrl daemons, and custom AXP2202 sysfs attributes. Nothing here has been checked on a device.

Tags: **[G]** = from disassembly (addresses are ELF virtual addresses), **[D]** = from strings/config/script text. Register-level reasoning is summarised in my own words. No code or scripts are reproduced. Nothing is device-verified.

---

### 0. Inputs, hashes, build info

| File | SHA-256 | Type / notes |
|---|---|---|
| appfs/bin/dmenu.bin | `5a6bbce625d7defcf31c501b436d7ac92b471683a58efffd0a9d88d1b1ef1c38` | ELF32 ARM EABI5 armhf, dynamic, stripped, BuildID `30bcfabc937b8169847e4069341da8762be34818`; entry 0x13585 (Thumb) |
| appfs/bin/charg.dge | `eeb7583e02b74ae10187a229ed97ca083b66d6cf5961f93ab24b75e0a20f074e` | ELF32 armhf, stripped, BuildID `cc4213d9…a45248` |
| appfs/bin/portsCtrl.dge | `b836f4a568419107827d8c94b2517c14e7bc581130c7b50810e6a4eedba30afe` | ELF32 armhf, stripped; in-game hotkey daemon |
| appfs/bin/ndsCtrl.dge | `eba357f3eb037f9b1d5743d123de44f25752282c136c89dc5fd022226fe83aca` | ELF32 armhf, stripped; DraStic hotkey daemon |
| appfs/bin/wiliwili/wiliwili | `39fe0fca009c938f0b0e6d06f0ec38988b1c7228096bdee8d0b02886caa42746` | ELF64 aarch64 PIE, not stripped (3rd-party Bilibili client; not analysed beyond launch.sh) |
| appfs/bin/wiliwili/launch.sh | `02439e7075c38b71d09585933db45829511e58628dfb1291c6d5531ae6a8ebb3` | PortMaster-style launcher |
| ctrl/*.sh, dmenu_ln, oem/*.ini | see hash list at end of §9 | |

Build/version strings [D]: `GCC: (crosstool-NG linaro-1.13.1-4.9-2014.08 - Linaro GCC 4.9-2014.08) 4.9.2 20140811` (all four 32-bit binaries); the system-info page shows the literal `Allwinner H700 Linux 4.9.170` (0x41416); `oem/version.ini`=`20260526`, `oem/board.ini`=`RG34xxSP`, `oem/language.ini`=`2` (index 2 = English, see §7). rootfs: Ubuntu 22.04 LTS "jammy", hostname `ANBERNIC`, kernel module path `/lib/modules/4.9.170/…`.

The extract has none of the appfs/bin items listed in the stock image: `cexpert, ebook, default.ttf, tinyplay, tinymixer, evtest, fbtest3, arcade-plus.csv, video, music, game, pdf, fileM, arcade-oem.csv, muos2.bin, muos1.bin`. dmenu references `default.ttf`, `arcade-plus.csv`, `game/`, `pdf/`, `muos1/2.bin`, `video/vp.dge`, so those paths cannot be checked from here. `/etc/init.d/launcher.sh` (1146 B, 5-Dec-2025) is in the rootfs listing but not in the `etc` extract. It is what starts `loadapp.sh` (per loadapp.sh/rc.local comments [D]).

---

### 1. Hotkey / input map

#### 1.1 Input devices [G]
| Node | How chosen | Used by | Events consumed |
|---|---|---|---|
| keypad | Scan `/dev/input/event*` (up to 6 entries); open each and keep the one whose `EVIOCGNAME` == `ANBERNIC-keys` (0x147b4). The error text names `/dev/input/event1`, but that path is not opened directly | dmenu, portsCtrl, ndsCtrl | EV_KEY (type 1) through the remap table; EV_ABS (type 3) codes 16/17 (HAT0X/Y) → d-pad bits; ABS 2/3 → d-pad bits; ABS 4/5 → extra bits, used only in UI states 30/31 (test/joy-map) |
| power/lid | `/dev/input/event0`, opened directly, O_RDONLY (0x148f8) | dmenu, charg.dge, portsCtrl, ndsCtrl | EV_KEY only; code 110 and 111 have special meaning (lid), any other code = power key |
| external pads | `/sys/class/input/*/device` + `…/device/uevent` scan, `EVIOCGBIT/EVIOCGID/EVIOCGABS` | dmenu joystick-map UI | builds RetroArch autoconfig (§7) |

Both fds are polled with a 300 ms timeout in thread `read_adc2key_thread` (0x143e8) [G].

#### 1.2 Default key table (`localpad.map` layout) [G]
`/mnt/data/dmenu/localpad.map` is a raw 38-byte file of 19 × int16 Linux key codes. If it is missing or short, the defaults at .data 0x55388 are copied (0x14790). The order of the table = the bit assignment below. SDL keysym = what dmenu's UI receives (0x28f94). "Likely button" is my inference from the dingux keysym convention and the UI strings. It is **not verified**.

| Idx | Default code | Linux name | Mask bit | dmenu SDL keysym | Likely button (unverified) |
|---|---|---|---|---|---|
| 0 | 103 | KEY_UP | — (table slot only; the d-pad actually comes from ABS_HAT0Y<0) | — | Up |
| 1 | 108 | KEY_DOWN | — | — | Down |
| 2 | 105 | KEY_LEFT | — | — | Left |
| 3 | 106 | KEY_RIGHT | — | — | Right |
| hat | ABS_HAT0Y<0 / >0 / HAT0X<0 / >0 | — | 0x1 / 0x2 / 0x4 / 0x8 | 273 UP / 274 DOWN / 276 LEFT / 275 RIGHT | D-pad |
| 4 | 304 | BTN_SOUTH | 0x10 | 306 LCTRL | A |
| 5 | 305 | BTN_EAST | 0x20 | 308 LALT | B |
| 6 | 307 | BTN_NORTH | 0x80 | 32 SPACE | X (or Y) |
| 7 | 306 | BTN_C | 0x40 | 304 LSHIFT | Y (or X) |
| 8 | 311 | BTN_TR | 0x100 | 13 RETURN | START (ndsCtrl treats 0x100 as START, per its "start to exit" string) |
| 9 | 310 | BTN_TL | 0x200 | 27 ESCAPE | SELECT |
| 10 | 308 | BTN_WEST | 0x400 | 8 BACKSPACE | R1 |
| 11 | 309 | BTN_Z | 0x800 | 9 TAB | L1 |
| 12 | 314 | BTN_SELECT | 0x1000 | 52 '4' | L2 or R2 |
| 13 | 315 | BTN_START | 0x2000 | 53 '5' | R2 or L2 |
| 14 | 313 | BTN_TR2 | 0x20000 | 54 '6' | ? |
| 15 | 316 | BTN_MODE | 0x40000 | 55 '7' (lowest priority) | ? |
| 16 | 312 | BTN_TL2 | 0x10000 | 51 '3' | **MENU/FN** (it changes VOL± to brightness) |
| 17 | 115 | KEY_VOLUMEUP | 0x4000 | not translated | VOL+ |
| 18 | 114 | KEY_VOLUMEDOWN | 0x8000 | not translated | VOL− |

The ABS handling has no deadzone. Any non-zero value sets the bit [G]. Bit 0x100000 is set when `poll()` fails (treated as "ctrl+c/quit") [G].

#### 1.3 Hotkey actions
| Context | Combination | Action | Source |
|---|---|---|---|
| Launcher | VOL+ / VOL− (edge) | volume level +1/−1, range 0–10; applied as the software gain for dmenu's own PCM playback (gain table `0,84,211,581,1460,3050,5181,6522,8211,10337,16384`, Q14) | [G] 0x12fe8, 0x13d74, 0x35ae0 |
| Launcher | MENU(0x10000) held + VOL+/VOL− | brightness level +1/−1, range 0–7 → `/dev/disp` 0x102; skipped while HDMI is active | [G] 0x12fe8–0x1301c |
| Launcher | MENU pressed and released alone (no VOL while held) | tap state machine at 0x225a60 → opens UI page state 20 via 0x2ac00. Which page this is: **not determined** | [G] 0x14360, 0x1c7b8 |
| Launcher | Power key press ≥100 ms then release | suspend: `pwr_new.sh auto` | [G] 0x1467e–0x146f8 |
| Launcher | Power key release <100 ms after press | ignored (debounce) | [G] 0x14692 |
| Launcher | Power key held 2000 ms | SDL timer → "ready to poweroff" → shutdown type 1 → goodbye splash (~2 s) → `poweroff` | [G] 0x31044, 0x31014 |
| Launcher | event0 KEY 110 press then release (lid "hall_down"), no HDMI | suspend (`pwr_new.sh auto`) | [G] 0x14618, 0x1463e |
| Launcher | event0 KEY 111 release | sets ready_sleep=1 (cancels sleep; lid-open path) | [G] 0x14668 |
| Launcher | SELECT (ESC) in some UI states | UI navigation (state 35) — UI only | [G] 0x13174 |
| Settings pages | START+SELECT | exit button-custom / factory test screens | [D] strings 0x3db1b…, 0x4413e… |
| Factory test (`/mnt/sdcard/test.ini`) | MENU+SELECT | motor test: writes `90`/`0` to `axp2202-battery/moto` | [D] 0x440d9, [G] 0x13d34 |
| Joystick-map UI | hold B 3 s | exit mapping | [D] 0x3d1b7 |
| In game (portsCtrl/ndsCtrl) | VOL+/VOL− | volume 0–10 → tinymixer card 0 ctl #2 = `0,5,10,16,19,21,23,25,27,29,31`; writes `openbor_volume` | [G] ports 0x11d58, 0x13420 |
| In game (portsCtrl/ndsCtrl) | MENU+VOL± | brightness 0–7 → `/dev/disp` 0x102 (same table), writes sysfs `brightness`; skipped if `/sys/class/extcon/hdmi/state` = 1 | [G] ports 0x11d58, 0x113cc |
| In game (portsCtrl/ndsCtrl) | Power held >2000 ms | portsCtrl: `poweroff` directly. ndsCtrl: writes shutdown type to `/tmp/shutdown.ini`, then `setNDS.sh stop` (dmenu then powers off on its next start, §2.4) | [G] ports 0x110b0–0x110de; nds 0x110ee–0x1115a |
| DraStic (ndsCtrl) | MENU + START (either order; strings "start to exit", "menu to exit") | `/mnt/vendor/ctrl/setNDS.sh stop` (kill drastic) | [G] nds 0x11148–0x1116c |
| Charger UI (charg.dge) | Power held 2 s | exit code 2 → `reboot` (boots into the normal OS) | [G] charg 0x1293c, 0x127d0, 0x1277c |
| Charger UI | Power ≥100 ms release / lid 110 | suspend (`pwr_new.sh`, no argument) | [G] charg 0x128c4–0x12904 |
| Retroarch games | — | no stock ctrl daemon runs. Hotkeys come from `/mnt/vendor/deep/retro/ANBERNIC-keys.cfg` (not in extract) | [D] setRA.sh |

When dmenu launches an app it writes the gating value to `nds_esckey`: 0 at launcher start, 1 for ports/case-29 apps, 3 for the video player [G 0x12626, 0x2320c, 0x23278, 0x164b6]. portsCtrl/ndsCtrl run only while `nds_esckey`==1 (polled every 40 ms tick) [G ports 0x10faa]. On exit they set volume level 10 (ctl #2 = 31) [G ports 0x1118e].

---

### 2. Sleep / lid / power-key policy

#### 2.1 Triggers (dmenu) [G]
| Trigger | Condition | Call |
|---|---|---|
| Power key | release ≥100 ms after press; global enable 0x55aa0≠0; ready_sleep≠1 | `enter_sleep_state(1)` 0x1439c |
| Lid via input | KEY 110 down sets hall_down=1; on 110 up, if HDMI is inactive and hall_down was set → sleep | same |
| Lid via sysfs | every 500 ms: `axp2202-battery/hallkey` reads 0, HDMI inactive, latch 0x22f742==0 → "++++ hall to sleep" | same (0x13424) |
| Idle timer | `now − last_activity > T[idx]`, idx = attr+28; T = `60000, 120000, 300000, 600000` ms (table at 0x3dcf0); idx>3 = never; suppressed while flag 0x21d0e8+1416 is set (likely music playback — unverified) | same (0x133ac) |
| Activity | any key/power event or UI action calls 0x29514 (records SDL_GetTicks) | — |

Default idle index = 0 (60 s) in the built-in attribute defaults [G 0x1232e]. The settings UI labels the options 1/2/5/10 and an off string [G 0x2ab66].

`enter_sleep_state(arg)` [G 0x1439c]: sets ready_sleep=1, builds `"%s auto"` when arg≠0, otherwise `"%s "`. **Every caller passes 1**, so the effective command is always `/mnt/vendor/ctrl/pwr_new.sh auto`, run with `system()` (it blocks until resume). The function then resets the idle timer.

#### 2.2 `pwr_new.sh` behaviour [D]
| Step | Effect |
|---|---|
| If `/mnt/mod/ctrl/pwr_new.sh` exists | delegates to it with the same argument (mod hook) |
| Else, if no lock `/tmp/.power_key` | creates the lock (mode 777), writes `mem` (no newline) to `/sys/power/state`, deletes the lock 0.3 s later in the background |
| Argument `auto` | not used by the stock script |
| Not touched | mem_sleep, backlight, cpufreq, wake sources (none written by dmenu or the script; any handling must be in the kernel) |

Related sysfs written at boot from attributes [G]: `axp2202-battery/workled_sleep` ← attr+132 bit0 (0x140d8); `axp2202-battery/os_sleep` ← attr+132 bit4 (0x14110). Strings "Super Standby" / "Normal Standby" / "<Need to restart the system>" [D] suggest os_sleep selects the standby type. That is an inference.

#### 2.3 Shutdown / reboot paths (dmenu `app_deinit` 0x295b4, type in 0x22f644) [G]
| Type | Set by | Splash | Final command |
|---|---|---|---|
| 0 | game/app launch (writes `/tmp/.next`) | "running" png (zh/en) | exits; `sync`; `echo 3 > /proc/sys/vm/drop_caches` |
| 1 | power held 2 s; settings item 16; `/tmp/shutdown.ini`=1 | `res1/shutdown/goodbye.png`, 200×10 ms | `poweroff` |
| 2 | low battery; `/tmp/shutdown.ini`=2 | `res1/shutdown/lowpower.png` | `poweroff` |
| 3 | settings "Reboot" (confirmation) | — | `reboot` |
| 4 | "Start Retroarch" | — | `/mnt/vendor/ctrl/setRA.sh run` |
| 5 | Moonlight start | — | moonlight path 0x2f404 |
| 6 | settings "Fast Shutdown" (快速关机) | — | [N] `echo 0x1801 > /sys/class/axp/axp_reg` (vendor AXP register poke; register 0x18, value 0x01 — meaning not determined) |

For types ≥1, before the final command dmenu writes `brightness` (level) and `openbor_volume` (level) to sysfs and creates `/tmp/stopAPP.ini`. That file stops the `loadapp.sh` relaunch loop. `forceOS.sh` [D] does `rest`/`shutdwn` = sync, sleep 1, reboot/poweroff (with commented-out axp_reg variants 0x270a/0x2709).

#### 2.4 Startup policy flags (dmenu main) [G]
`/mnt/mmc/dmenu.del` → delete it and `dmenu_attr.ini` (reset settings). `/mnt/sdcard/adfu.ini` → `reboot efex` (Allwinner FEL/USB-burn mode) and exit. `/mnt/sdcard/test.ini` + TF state → factory test. `/mnt/data/logo.ini` absent → shows `res1/boot/logo.png`. `/tmp/shutdown.ini` with value 1/2 → immediate shutdown of that type. `/tmp/boot.ini` absent (= first launch since boot) → create it and push all attributes to hardware/sysfs. Otherwise re-read `brightness`/`openbor_volume` sysfs (the in-game daemons may have changed them).

#### 2.5 Charger mode (`loadapp.sh` + `charg.dge`) [D]+[G]
`loadapp.sh` reads `axp2202-battery/boot_mode`. If it is 1: rfkill-block BT and Wi-Fi, stop and mask `bluetooth.service` and `NetworkManager.service`, run `charg.dge`, then `sleep 5; poweroff` if it returns. In charg.dge: cpu `powersave` at start; the loop polls power/lid on a 100 ms poll; idle >20000 ms or `hallkey`=0 → cpu `powersave`, `pwr_new.sh` (no argument), then cpu `full`. USB `axp2202-usb/online`≠1 → `poweroff`. Power held 2 s → `reboot`.

---

### 3. Brightness and volume

#### 3.1 Brightness [G]
| Item | Value |
|---|---|
| Levels | 8, index 0–7 |
| Table (all four binaries) | `5, 10, 20, 50, 70, 140, 200, 255` (dmenu .rodata 0x38480; charg 0x12b84; portsCtrl 0x139e8) |
| Default | index 5 (=140) |
| Set | `open("/dev/disp", O_RDWR)`, ioctl **0x102** with arg[0]=0 (screen 0), arg[1]=value (fn `set_brightness_ioctl` 0x13664) |
| Get | ioctl **0x103**, arg[0]=0 (0x139f4) |
| Blank | level path with value 0 at 0x13a54 |
| Persistence | `/sys/class/power_supply/axp2202-battery/brightness` ← level index (vendor attribute used as cross-process storage), plus dmenu_attr.ini +24 |
| HDMI | brightness changes are skipped when HDMI is active (0x56c94) |
| `/sys/class/backlight` | **not referenced** by any analysed binary |

#### 3.2 Volume / audio routing [G]+[D]
| Item | Value |
|---|---|
| Level | 0–10, default 10 (attr+36) |
| Launcher (dmenu) | software gain on its own sample playback (table above); hardware mixer forced at display init: card 0 ctl #1 → 63 if different, ctl #2 → 31, ctls #3, #5, #8 → 1 (0x13c7a–0x13cdc) |
| Game daemons | card 0 ctl #2 ← `0,5,10,16,19,21,23,25,27,29,31` (portsCtrl .rodata 0x143ec; ndsCtrl same values) |
| Persistence | `axp2202-battery/openbor_volume` ← level 0–10 |
| Speaker vs headphone | `/sys/module/snd_soc_sunxi_component_jack/parameters/jack_state` (1 = headphone). card 0 ctl #4 ← 0 when headphone or HDMI, else 1 (0x13d94). ctl #4 is probably the speaker switch — inference |
| HDMI audio | when HDMI is active and no headphone, PCM opened on card 2; launch commands prepend `AUDIODEV=hw:2,0` [D] |
| Control names | dmenu/daemons use **numeric ids only**, no names. asound.conf [D] names `LINEOUT Switch`, `SPK Switch`, `OutputL/R Mixer DACL/R Switch`, `digital volume` (63) on `hw:audiocodec`, and `playback_hdmi` = card `ahubhdmi`. Mapping id→name **not determined** (check with tinymix) |
| Card for HDMI state | dmenu: `/sys/class/switch/hdmi/state` ("HDMI=%d"); charg/ports/nds: `/sys/class/extcon/hdmi/state` — two different paths |

On HDMI plug/unplug (polled every 500 ms) dmenu does "reset sound": it switches output with `/dev/disp` ioctl 0x0F to HDMI type 4 mode 5 (720p60 per the disp2 enum; inference) or LCD type 1. After returning to LCD it runs `rtcwake -d rtc1 -m mem -s 1` (or `rtcwake -m mem -s 1` if `/sys/class/rtc/rtc1` is absent) to force a 1 s suspend/resume, then restores brightness and audio routing [G 0x13a94].

---

### 4. Battery

| Item | dmenu [G 0x17374] | charg.dge [G 0x11b6c] | portsCtrl/ndsCtrl [G] |
|---|---|---|---|
| Poll period | 1000 ms | 1000 ms | 1000 ms |
| Capacity | `axp2202-battery/capacity`, clamped 0–100 (101 = read error) | same | — |
| Voltage | `axp2202-battery/voltage_now` (µV); if >3,199,999 → /10000×10 = mV (10 mV steps), else 0 | same; shown as `voltage:%.2fv` | same |
| Charging | `axp2202-battery/status` starts with `Charging` | same | — |
| Other | — | `axp2202-usb/online` (≠1 → poweroff), `axp2202-battery/present` | `axp2202-usb/online` |
| Icon thresholds | cap>99 → 6 (full, no animation), >70 → 6, >50 → 5, >20 → 4, >10 → 3, >3 → 2, 1–3 → 1, 0 → 0; images `desktop_res/title/{lcd,hdmi}/bat_%d.png`; charging animation cycles a 0–4 counter | >99 → 4 (full), >85 → 4, >70 → 3, >55 → 2, >35 → 1, >10 → 0, ≤10 → 5; frames `res1/charg_mode/0..5.png` | — |
| Low-battery shutdown | not charging, cap==0, V≤3420 mV, >20 consecutive polls → type 2 (lowpower splash, poweroff) | — | USB offline and V≤3420 mV for >20 polls → poweroff (shutdown flag 2) |
| Low-battery warning UI | none found (only the icon) | — | — |

---

### 5. Paths, sysfs/procfs/dev, files, env vars, external commands

R/W = read/write as inferred from the open mode / fopen mode / write call.

#### 5.1 Kernel interfaces
| Path | R/W | Binary/script | Purpose |
|---|---|---|---|
| /dev/disp | RW ioctl | dmenu, charg, ports, nds | sunxi disp2: brightness, output switch, layers (§6) |
| /dev/fb0 | RW mmap | dmenu | clear 0x708000 B (1280×720×… buffer) at init |
| /dev/ion | RW ioctl | dmenu, charg | Allwinner ION buffer alloc (CdcIon*) |
| /dev/input/event0 | R | dmenu, charg, ports, nds | power key / lid |
| /dev/input/event* (name `ANBERNIC-keys`) | R | dmenu, ports, nds | keypad |
| /sys/class/input/*/device[/uevent] | R | dmenu | external gamepad discovery |
| /dev/snd/controlC%u | RW ioctl | dmenu, ports, nds | tinyalsa mixer |
| /dev/snd/pcmC%uD%u%c | W ioctl | dmenu | UI sound playback (44100 Hz, 2 ch, S16, period 1024×4) |
| /dev/mmcblk1 | R (exists) | dmenu | TF2 presence |
| /dev/rtc0, /dev/rtc1 | via hwclock | dmenu | `hwclock -lw -f /dev/rtc1` or `rtc0` after date change |
| /sys/class/rtc/rtc1 | access | dmenu | choose rtcwake device |
| /sys/class/rtc/rtc0/date | R | loadapp.sh | set RTC once if empty |
| /sys/class/switch/hdmi/state | R | dmenu | HDMI=%d |
| /sys/class/extcon/hdmi/state | R | charg, ports, nds | HDMI=%d |
| /sys/module/snd_soc_sunxi_component_jack/parameters/jack_state | R | dmenu, charg | headphone |
| /sys/class/power_supply/axp2202-battery/capacity | R | dmenu, charg | % |
| …/axp2202-battery/voltage_now | R | dmenu, charg, ports, nds | µV |
| …/axp2202-battery/status | R | dmenu, charg | "Charging" |
| …/axp2202-battery/present | R | charg | battery present |
| …/axp2202-usb/online | R | charg, ports, nds | USB power |
| …/axp2202-battery/hallkey | R | dmenu, charg | lid (0 = closed) |
| …/axp2202-battery/brightness | RW | dmenu, ports, nds | brightness level store (0–7) |
| …/axp2202-battery/openbor_volume | RW | dmenu, ports, nds | volume level store (0–10) |
| …/axp2202-battery/nds_esckey | RW | dmenu (W), ports/nds (R/W) | app-mode flag 0/1/3 that gates the ctrl daemons |
| …/axp2202-battery/nds_pwrkey | W | ports, nds | power-key mode flag (exact semantics not determined) |
| …/axp2202-battery/workled_sleep | W | dmenu | attr+132 bit0 |
| …/axp2202-battery/os_sleep | W | dmenu | attr+132 bit4 |
| …/axp2202-battery/moto | W | dmenu, ports, nds | rumble: `90` on / `0` off (factory test in dmenu) |
| …/axp2202-battery/led_test | W | dmenu | write 1 in factory test |
| …/axp2202-battery/otg_id | R | dmenu | factory test OTG-in/out |
| …/axp2202-battery/spk_state | R | dmenu | read, used by the UI speaker icon (exact use not traced) |
| …/axp2202-battery/boot_mode | R | loadapp.sh | 1 = charger boot |
| …/axp2202-battery/display_id | R | setFlycast, setSaturn, wiliwili launch.sh | "1" → HDMI audio env |
| …/axp2202-battery/work_led | W | dmenu_ln | LED cfg from `/mnt/mod/ctrl/configs/led_exit.cfg` / `led_launch.cfg` |
| /sys/class/axp/axp_reg | W | dmenu (fast shutdown) | vendor AXP register write `0x1801` |
| /sys/class/deeplayer/deeplayer/debug_reg | W then R | dmenu | anti-clone challenge/response (§9) |
| /sys/class/net/wlan0/address | R | dmenu | MAC display / Wi-Fi present |
| /sys/class/iommu | access | dmenu, charg | ION mem type check |
| /sys/power/state | W `mem` | pwr_new.sh | suspend |
| /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor, scaling_setspeed | W | cpu_setting.sh | governor |
| /sys/kernel/debug/sunxi_gpu/write | W | cpu_setting.sh (only the unused `adjust_ddr` function) | DDR DVFS |
| /sys/class/pwm/pwmchip0/{export,unexport,pwm2/*} | W | moto.sh | PWM rumble (no binary calls moto.sh) |
| /proc/mounts | R | dmenu, mmc*.sh, udisk.sh, loadapp.sh | mount state |
| /proc/sys/vm/drop_caches | W 3 | dmenu | before launches/shutdown |
| /proc/swaps | R | loadapp.sh (unused function) | swap |

#### 5.2 Files (config/state/resources)
| Path | R/W | Who | Purpose |
|---|---|---|---|
| /mnt/data/dmenu/dmenu_attr.ini | RW (136-B binary struct) | dmenu | global settings (§7) |
| /mnt/data/dmenu/localpad.map | RW (38 B) | dmenu, ports, nds | key remap (§1.2) |
| /mnt/data/misc/.favorite, .history, .mycore, .setcore, .hostap | RW | dmenu | lists (§7) |
| /mnt/data/.hide, /mnt/data/.wifi | RW | dmenu | game-hide flag; saved SSIDs |
| /mnt/data/save/, /mnt/data/misc/, /mnt/data/dmenu/ | mkdir | dmenu | |
| /mnt/data/debug.ini, /mnt/sdcard/debug.ini | access | dmenu_ln, dmenu | debug: console logging; dmenu adds `-v` to retroarch |
| /mnt/data/xudebug.ini | access | loadapp.sh | hold boot in a sleep loop |
| /mnt/data/logo.ini | access | dmenu | skip boot logo |
| /mnt/mmc/dmenu.del | access, rm | dmenu | reset settings |
| /mnt/mmc/dmenu.bin, /mnt/vendor/bin/muos1.bin, muos2.bin, /mnt/vendor/muos1.ini, muos2.ini | access | dmenu_ln, dmenu (creates muos*.ini) | alternate launcher selection |
| /mnt/mmc/appfs.img | access | loadapp.sh | loop-mounted over /mnt/vendor |
| /mnt/mmc/gpio_keys_polled.ko, gpio_keys_gpadc.ko | insmod | loadapp.sh | optional key drivers from SD |
| /mnt/mod/ctrl/{autostart,pwr_new.sh,RA_launch.sh,ndscheat,sw,configs/*} | exec/R | loadapp, pwr_new, dmenu, setNDS, setRA, dmenu_ln | mod hooks |
| /mnt/sdcard/test.ini, /mnt/sdcard/adfu.ini | access | dmenu | factory test; FEL reboot |
| /tmp/.next | W (+`chmod 777`) | dmenu → dmenu_ln | next command script |
| /tmp/stopAPP.ini, /tmp/boot.ini, /tmp/shutdown.ini, /tmp/vpRun.ini | RW | dmenu, ndsCtrl, loadapp, dmenu_ln | lifecycle flags |
| /tmp/.power_key, /tmp/.mmc_mount, /tmp/.init_bt | lock | pwr_new, mmc_new, setBluetooth | locks |
| /tmp/gameplace.cfg, /tmp/gamedir.cfg, /tmp/last_place.ext, /tmp/last_place.int, /tmp/search, /tmp/wifi_infor.log, /tmp/wifi_scan.log | RW | dmenu | UI state, nmcli output |
| /mnt/vendor/oem/version.ini, language.ini | R | dmenu | FW version display; default language |
| /mnt/vendor/bin/default.ttf | R | dmenu, charg | UI font |
| /mnt/vendor/bin/arcade-plus.csv | R | dmenu | arcade name map |
| /mnt/vendor/res1/{boot,loading,shutdown,theme,wallpapers,desktop_res/*,setjoy,setkey,sound,retro,res_apk,test,hostap,wifi,charg_mode}, /mnt/vendor/res2/{theme,desktop_res/misc} | R | dmenu/charg | images (`lcd/` and `hdmi/` variants), sounds `%d.wav`, `test.pcm` |
| /mnt/vendor/deep/retro/{retroarch,retroarch.cfg,cores,autoconfig/udev,joydefCFG,ANBERNIC-keys.cfg} | R/W | dmenu, setRA, loadapp | RetroArch |
| /.config/retroarch/retroarch.cfg | RW | dmenu (`-c`), setRA, loadapp | RA config (HOME=/) |
| /mnt/vendor/deep/{drastic,drastic-modify,ppsspp,openBOR,emuJava}, /emuelec/{saturn,flycast} | exec | dmenu & scripts | emulators |
| /mnt/mmc/Roms/…, /mnt/sdcard/Roms/…, …/APPS, …/PDF, /mnt/mmc/EXE/pico-8/ | R | dmenu | content roots ("TF1/INT." = /mnt/mmc, "TF2/EXT." = /mnt/sdcard) |
| /etc/hostapd/hostapd.conf | R (dmenu), W via sed (setHostapd) | | hotspot ssid/wpa_passphrase/channel |
| /etc/NetworkManager/system-connections/* | rm | dmenu | forget networks |
| /etc/allen_resize.cfg | W | loadapp.sh | one-shot resize2fs of `/dev/mmcblk0p5` |

#### 5.3 Environment variables
| Var | Where | Value/purpose |
|---|---|---|
| SDL_NOMOUSE | dmenu, charg (setenv) | 1 |
| LD_LIBRARY_PATH | dmenu_ln, loadapp, /etc/profile | `/usr/lib32:/usr/lib:/mnt/vendor/lib` (+ prepends `/mnt/vendor/lib`) |
| AUDIODEV | dmenu launch template, setFlycast/Saturn, wiliwili | `hw:2,0` when HDMI / display_id=1 |
| HOME | setFlycast/Saturn, wiliwili | per-card save dirs; `/root` |
| SDL_GAMECONTROLLERCONFIG_FILE | setFlycast | `/emuelec/flycast/gamecontrollerdb.txt` |
| PC_IP | dmenu (moonlight) | target PC IP |
| ACTION | mmc*.sh, udisk.sh | udev add/remove |
| PATH | /etc/environment | adds `/mnt/vendor/bin` |

#### 5.4 External commands (system()/popen/fork-exec)
| Command (template) | Binary | Purpose |
|---|---|---|
| `/mnt/vendor/ctrl/pwr_new.sh auto` | dmenu | suspend |
| `/mnt/vendor/ctrl/pwr_new.sh` | charg | suspend |
| `/mnt/vendor/ctrl/cpu_setting.sh {full,user,powersave,deflt}` | dmenu (full at startup, deflt before launching apps), charg (powersave/full) | governor |
| `/mnt/vendor/ctrl/setBluetooth.sh {init,enable,restart,all}` | dmenu | BT (init at boot if enabled, enable from the UI) |
| `/mnt/vendor/ctrl/setHostapd.sh {disable, ssid X, password X}` (enable via script) | dmenu | hotspot |
| `/mnt/vendor/ctrl/setSSH.sh` | dmenu | `systemctl restart ssh` |
| `/mnt/vendor/ctrl/setRA.sh {run,rest,language L,adv,easy}`; `setPSP.sh {language,recover}`; `setNDS.sh {run,savedir,recover,stop}`; `setSaturn.sh {HLE,BIOS}`; `setFlycast.sh`; `/mnt/vendor/deep/drastic-modify/recovery.sh` | dmenu, ndsCtrl | emulator setup/launch |
| `/mnt/vendor/ctrl/mmc_new.sh add`, `/mnt/vendor/ctrl/mmc.sh remove` | dmenu | TF2 hot-plug mount (on card-state change) |
| `rtcwake -d rtc1 -m mem -s 1` / `rtcwake -m mem -s 1` | dmenu | display re-init after HDMI→LCD |
| `reboot`, `poweroff`, `reboot efex`, `echo 0x1801 > /sys/class/axp/axp_reg`, `sync`, `echo 3 > /proc/sys/vm/drop_caches` | dmenu (+charg/ports) | power |
| `date -s …`, `hwclock -lw [-f /dev/rtc0|rtc1]` | dmenu | clock set |
| `nmcli dev wifi connect "%s" [password "%s"]`, `nmcli con up/c down "%s"`, `nmcli connection delete "%s"`, `nmcli networking on/off`, `nmcli -f NAME c show --active`, `nmcli -f IN-USE,SSID,SIGNAL,SECURITY dev wifi`, `nmcli -p networking connectivity`, `rm /etc/NetworkManager/system-connections/…` | dmenu | Wi-Fi (auto-scan every 10 s, up to 3 tries) |
| `bluetoothctl -- {power on/off, scan off, --timeout 15 scan on, devices, pairable on, pair/trust/connect/disconnect/remove MAC, info MAC}`, `hciconfig hci0 up/down`, `hcitool name/con` | dmenu | BT |
| `moonlight pair %s`, `/usr/bin/moonlight stream … -mapping … -fps` (fork/exec) | dmenu | game streaming |
| `./retroarch [-v] -c /.config/retroarch/retroarch.cfg -L <core>`, `./PPSSPPSDL`, `./pcsx`, `./OpenBOR.dge`, `./{fbaverti,fbasdl,xmame,gba_emu,vbanext,fc_emu,sfc_emu,smsgg_emu,md_emu,gbcgb_emu,pce,ngp,swanemu}.dge`, `./vp.dge`, `ap.dge`, `xplayerdemo2`, `reader_{mmc,sdcard}.dge`, `dinguxCommand_{zh,en}.dge`, `<dir>/launch.sh`, `rm -rf "%s"` | dmenu (written to /tmp/.next) | launches; per-app `cd "%s"` |
| `rtk_hciattach -n -s 115200 ttyS1 rtk_h5`, `hciconfig hci0 up / -a hci0 lm master / auth`, `systemctl stop/start bluetooth` | setBluetooth.sh | Realtek BT over UART ttyS1 |
| `ifconfig wlan0 192.168.1.1 up`, `hostapd -B /etc/hostapd/hostapd.conf`, `kill -9 hostapd`, `nmcli networking off`, `sed -i` on ssid/wpa_passphrase/channel | setHostapd.sh | hotspot |
| `ntpdate cn.pool.ntp.org` | ntpd.sh (no caller found in dmenu) | time |
| `mkfs.ext4/vfat`, `mount`, `resize2fs`, `mkswap/swapon` (unused), `rfkill`, `systemctl {mask,unmask,stop,restart} {bluetooth,NetworkManager}.service`, `insmod` | loadapp.sh | boot |
| `insmod …/8821cs.ko`, `insmod /lib/modules/mali_kbase.ko` | /etc/rc.local | Wi-Fi + GPU modules; `/etc/modules` loads `rtl_btlpm` |

---

### 6. ioctl numbers

| Request | Decoded (_IOC dir,type,nr,size) | Device | Meaning | Binary / evidence |
|---|---|---|---|---|
| 0x07, 0x08 | none,0,7/8,0 | /dev/disp | DISP_GET_SCN_WIDTH / HEIGHT | dmenu, charg [G]; name from Allwinner disp2 header (inference) |
| 0x0B | 0,0,11 | /dev/disp | DISP_VSYNC_EVENT_EN | [G]+[D] error string |
| 0x0C | 0,0,12 | /dev/disp | DISP_BLANK | [G]+[D] |
| 0x0D | 0,0,13 | /dev/disp | DISP_SHADOW_PROTECT | [G]+[D] |
| 0x0E | 0,0,14 | /dev/disp | DISP_HWC_COMMIT (also used for sync timeline create/destroy) | [G]+[D] |
| 0x0F | 0,0,15 | /dev/disp | DISP_DEVICE_SWITCH (args: screen 0, type 4 HDMI / 1 LCD, mode 5) | [G] in `allen_lcd_hdmi_switch`; name is an inference |
| 0x10 | 0,0,16 | /dev/disp | DISP_GET_OUTPUT (output info) | [G]+[D] |
| 0x49 | 0,0,0x49 | /dev/disp | DISP_LAYER_SET_CONFIG2 | [G]+[D] |
| 0x102 | 0,0,0x102 | /dev/disp | DISP_LCD_SET_BRIGHTNESS | [G] (`set_brightness_ioctl`) all 4 binaries |
| 0x103 | 0,0,0x103 | /dev/disp | DISP_LCD_GET_BRIGHTNESS | [G] |
| 0xC0144900 | RW,'I',0,20 | /dev/ion | ION_IOC_ALLOC (legacy 4.9 ABI) | dmenu, charg |
| 0xC0184900 | RW,'I',0,24 | /dev/ion | ION_IOC_ALLOC (new ABI fallback) | dmenu, charg |
| 0xC0044901 | RW,'I',1,4 | /dev/ion | ION_IOC_FREE | |
| 0xC0084902 | RW,'I',2,8 | /dev/ion | ION_IOC_MAP | |
| 0xC0084904 | RW,'I',4,8 | /dev/ion | ION_IOC_SHARE | |
| 0xC0084905 | RW,'I',5,8 | /dev/ion | ION_IOC_IMPORT | |
| 0xC0084906 | RW,'I',6,8 | /dev/ion | ION_IOC_CUSTOM (AW phys addr / TEE addr / pool info) | [D] strings |
| 0xC0084907 | RW,'I',7,8 | /dev/ion | ION_IOC_SYNC | |
| 0xC0184908 | RW,'I',8,24 | /dev/ion | ION_IOC_HEAP_QUERY | |
| 0x80804506 | R,'E',6,128 | evdev | EVIOCGNAME(128) | dmenu, ports, nds |
| 0x80044520 | R,'E',0x20,4 | evdev | EVIOCGBIT(0) | dmenu |
| 0x80604521 | R,'E',0x21,96 | evdev | EVIOCGBIT(EV_KEY) | dmenu |
| 0x80084523 | R,'E',0x23,8 | evdev | EVIOCGBIT(EV_ABS) | dmenu |
| 0x80084502 | R,'E',2,8 | evdev | EVIOCGID | dmenu |
| 0x80184540+axis | R,'E',0x40+n,24 | evdev | EVIOCGABS(axis) (base constant ORed with 0x41+i) | dmenu |
| 0x81785501 | R,'U',1,0x178 | controlC | SNDRV_CTL_IOCTL_CARD_INFO | dmenu, ports, nds |
| 0xC0485510 | RW,'U',0x10,0x48 | controlC | ELEM_LIST | |
| 0xC1105511 | RW,'U',0x11,0x110 | controlC | ELEM_INFO | |
| 0xC2C85512 / 0xC2C85513 | RW,'U',0x12/0x13,0x2c8 | controlC | ELEM_READ / ELEM_WRITE | |
| 0x81204101 | R,'A',1,0x120 | pcm | SNDRV_PCM_IOCTL_INFO | dmenu |
| 0xC25C4110 / 0xC25C4111 | RW,'A',0x10/0x11,0x25c | pcm | HW_REFINE / HW_PARAMS | |
| 0xC0684113 | RW,'A',0x13,0x68 | pcm | SW_PARAMS | |
| 0x40044103 | W,'A',3,4 | pcm | TTSTAMP | |
| 0xC0844123 | RW,'A',0x23,0x84 | pcm | SYNC_PTR | |
| 0x4140 / 0x4142 / 0x4143 | none,'A',0x40/42/43 | pcm | PREPARE / START / DROP | |
| 0x400C4150 / 0x800C4151 | W/R,'A',0x50/0x51,12 | pcm | WRITEI_FRAMES / READI_FRAMES | |
| 0x8915 | socket | AF_INET socket | SIOCGIFADDR on `wlan0` (IP display) | dmenu 0x35e8a |

No ioctl is used on `/dev/input` for grabbing (no EVIOCGRAB), on fb0 (mmap only), or on backlight [G].

---

### 7. Config / ini keys

| File | Format | Keys / fields |
|---|---|---|
| dmenu_attr.ini | 136-byte binary struct (copy of RAM 0x22f670) [G] | +20 =1 default; **+24 brightness idx** (def 5); **+28 idle-sleep idx** (def 0 → 60 s); +32 =1; **+36 volume** (def 10); **+40 sound enable** (def 1); **+44 language** (def 2); +48 =1; +52, +56, +60(byte), +124, +128 =0; **+132 flags** (def 1; bit0 → workled_sleep, bit4 → os_sleep). Other fields: theme/style/Wi-Fi/BT flags, not individually mapped |
| localpad.map | 19 × int16 [G] | §1.2 |
| /mnt/data/misc/.favorite | text, header `Version=1`, lines `%s:%s:%s:%d:%d:%d` (or `nul` in field 3) [D] | path:name:core:ids… |
| /mnt/data/misc/.history | `%s:%s:%s:%d:%d` [D] | |
| /mnt/data/misc/.mycore, .setcore | text lists [D] | per-game core association |
| /mnt/data/.hide | `gamehide=%d` [D] | |
| /tmp/gameplace.cfg | `start=`, `hight=`, `subdir=`, `parent_index=` [D] | list position |
| /tmp/gamedir.cfg, /tmp/last_place.{ext,int} | `[myEmu]`/`[retro]` sections, curpos/page/retro [D] | |
| /mnt/data/.wifi | `S:%s` lines [D] | saved SSIDs |
| hostapd.conf | `ssid=`, `wpa_passphrase=`, `channel=` (read and edited) [D] | |
| RetroArch autoconfig `/mnt/vendor/deep/retro/autoconfig/udev/<name>.cfg` | `%s = "%d"` / `%s = "%s"`: `input_driver, input_device, input_vendor_id, input_product_id, input_{b,y,select,start,up,down,left,right,a,x,l,r,l2,r2,l3,r3}_{btn,axis}, input_{l,r}_{x,y}_{plus,minus}_axis`, hat `h%dup/down/left/right` [D] | joystick mapping UI |
| retroarch.cfg (via setRA.sh) | `user_language`, `audio_device`, `audio_volume`, `menu_show_{latency,overlays,rewind,video_layout}`, `quick_menu_show_{reset_core_association,save_core_overrides,save_game_overrides,set_core_association,shaders}` [D] | |
| ppsspp.ini (setPSP.sh) | `Language` [D] | |
| oem/board.ini | `RG34xxSP` | not read by dmenu (no string) |
| oem/version.ini | `20260526` | firmware version shown in system info |
| oem/language.ini | `2` | language index: 0 zh-CN, 1 zh-TW, 2 en, 3 ja, 4 ko, 5 es, 6 ru [G from string table at 0x3e52c]; de/fr/pt strings also present (index not mapped) |
| asound.conf | default PCM = hooks on `hw:audiocodec` forcing LINEOUT/SPK/DAC switches=1, digital volume 63; `playback_hp`; `playback_hdmi` → card `ahubhdmi` [D] | |

---

### 8. CPU / rumble / storage / boot / network scripts

| Script | Args | What it changes [D] | Called by |
|---|---|---|---|
| cpu_setting.sh | `full` → `performance`; `powersave` → `powersave`; `user` → `userspace` + setspeed 792000; anything else → `interactive` | cpu0 `scaling_governor` (and setspeed). The DDR DVFS function (debugfs `sunxi_gpu/write`: frequency/voltage 648 MHz/960 mV) exists but its calls are commented out. The comment lists CPU OPPs 480000–1512000 kHz | dmenu: `full` at startup [G 0x127ea], `deflt` (→ interactive) before every launch [G 0x164b0, 0x1a83e]. charg: `powersave` at start/sleep, `full` after resume |
| moto.sh | start/stop | exports pwmchip0 channel 2, period 20 000 000 ns, duty 12 000 000 ns (60 %), normal polarity, enable/disable | **no caller in the analysed binaries**; dmenu/ports/nds use the `axp2202-battery/moto` attribute instead |
| mmc_new.sh | add/remove (or $ACTION) | mounts the first of mmcblk2p1/mmcblk2/mmcblk1p1/mmcblk1 on `/mnt/sdcard` by blkid type: vfat / ntfs-3g / exfat with uid/gid 1000, dmask/fmask 000, noatime; lock `/tmp/.mmc_mount`; remove = `umount -l` | loadapp (add), dmenu (add) |
| mmc.sh | add/remove | older version: vfat, falls back to exfat; no lock | dmenu (remove) |
| udisk.sh | add/remove | sda1/sda/sdb1/sdb → `/mnt/udisk` vfat or exfat | udev (rule not in extract) |
| loadapp.sh | — | resize rootfs `mmcblk0p5` once; mount/format data `mmcblk0p7` → `/mnt/data` (ext4, **auto-mkfs if blkid has no TYPE or mount fails**); ROMS `mmcblk0p8` (else p1) → `/mnt/mmc` vfat (**auto-mkfs.vfat** likewise); optional appfs.img over /mnt/vendor; seed RA cfg; charger branch (§2.5); otherwise unmask/restart NetworkManager + bluetooth and unblock rfkill; seed RTC; optional SD key modules; `mmc_new.sh add`; mod autostart; then loops dmenu_ln until `/tmp/stopAPP.ini` exists | /etc/init.d/launcher.sh (per comments) |
| dmenu_ln | — | picks launcher (`/mnt/mmc/dmenu.bin` overrides; muos1/2 via ini; `/tmp/vpRun.ini` → video player); writes LED cfgs to `work_led`; runs the launcher, then runs `/tmp/.next` with `sh`; if the launcher fails, sleeps 30 s | loadapp |
| forceOS.sh | rest/shutdwn | sync, 1 s, reboot/poweroff | not referenced by dmenu |
| setBluetooth.sh | init/enable/all/restart | `rtk_hciattach` on ttyS1 115200 H5 (lock `/tmp/.init_bt`), hci0 up/master/auth, restart bluetooth service | dmenu |
| setHostapd.sh | enable/disable/ssid/password/channel | static 192.168.1.1 on wlan0, hostapd -B, NetworkManager networking off, edits hostapd.conf | dmenu |
| setSSH.sh | — | restart ssh | dmenu |
| ntpd.sh | — | ntpdate cn.pool.ntp.org | no caller found |
| setMusic.sh | stop | kill mplayer | (not referenced by dmenu strings) |
| setNDS/setPSP/setRA/setSaturn/setFlycast | various | emulator cfg/launch; start portsCtrl/ndsCtrl (from `/mnt/mmc` if present); HDMI audio env | dmenu |

---

### 9. Strings groups, dependencies, symbols, integrity check

- **NEEDED (dmenu, charg, portsCtrl, ndsCtrl — same list)** [D]: libSDL_image-1.2.so.0, libSDL_ttf-2.0.so.0, libfreetype.so.6, libSDL-1.2.so.0, libSDL_gfx.so.15, libiconv.so.2, libpng12.so.0, libjpeg.so.9, libm.so.6, libz.so.1, libpthread.so.0, libc.so.6; interpreter `/lib/ld-linux-armhf.so.3` (needs armhf multiarch on the rootfs).
- **Imports, dmenu** [D]: SDL 1.2 (Init, SetVideoMode 1280×720×16 plus 720×480 / 1280×720 surfaces, AddTimer, GetTicks, EventState; **no SDL_PollEvent** — input is raw evdev), TTF, IMG_Load, zoomSurface; libc: system, popen/pclose, fork, execl, kill, waitpid, ioctl, mmap, poll, socket, inet_ntoa, statfs, sysinfo, scandir, pthread_*, libiconv.
- **Internal function names** (from `__func__` strings; useful as anchors) [D]: set/get_brightness_ioctl, allen_lcd_hdmi_switch, lcd_and_hdmi_init_fb, init_fb_info, enter_sleep_state, read_adc2key_thread, open_adc_bnt_input, readglobalkeypad, Savelocalkeypad, readglobalproperty, writeglobalattr, app_deinit, get_shutd_type, init_device_display, init_my_system, Loop_listend, adjust_ui_type_byTFcard, bluetooth_{init,deinit,scan_thread,Manual_Scan,manual_connect}, wifi_{init,deinit,scan_thread}, nmcli_{connect_ssid,connection_info,scan}, hostap_{readcfg,writecfg,…}, moonlight_{run,pair_pthread_start}, gamelist_{init,run,retro_run,…}, set_retro_emulib, factory_test_draw, testkey_pthread_Sound_brightness, play_sample, tinymixer_{get,set}_value, My_JoystickDetect, HandleInputEvents, SetDevicePlayer, ReadConvertFromFile, SaveConvertToFile. charg: draw_bat_state, handle_powerkey_input. Embedded third-party code: tinyalsa (pcm/mixer), Allwinner "Cdc" ION allocator, sunxi disp2 HWC helper.
- **Version strings**: §0.
- **Anti-clone check** [G 0x22d60, called every 500 ms main-loop tick at 0x133ca]: srand(time) → 16 random bytes → combined with a 16-byte constant at .rodata 0x3c0f5 → written as comma-separated decimals to `/sys/class/deeplayer/deeplayer/debug_reg` → 16 values read back and compared with a locally computed expectation. On mismatch it loops forever on `system("reboot")` and prints "deeplay encryption fail". The key and transform are deliberately not reproduced here. **Consequence: stock `dmenu.bin` needs the vendor `deeplayer` kernel driver.**
- Script/ini SHA-256: cpu_setting.sh 7c4f18fa…dee8; dmenu_ln ea880986…c1c7; forceOS.sh 806a1dfd…b719; loadapp.sh 06c8e574…d4b3; mmc.sh 94891469…60e3; mmc_new.sh 460d2139…4317; moto.sh a87f440b…89e7; ntpd.sh 1e6de7cf…7a41; pwr_new.sh dd3619ac…f0e7; setBluetooth.sh 445f21af…8b80; setFlycast.sh d25617a5…1502; setHostapd.sh c9a5cde5…c707; setMusic.sh 985ad06f…2a56; setNDS.sh c0ecea10…e253; setPSP.sh a4a613a3…7b35; setRA.sh 221a5e70…02629f1; setSSH.sh 6286b36b…065d; setSaturn.sh 633d241b…7eda; udisk.sh e0f3e340…ceec; board.ini 7dda8603…3c37697a; language.ini d4735e3a…ab35; version.ini cfccffd6…d9d9 (full hashes can be regenerated with `sha256sum` on the extract).

#### Not determined (stated plainly)
- Physical labels of codes 306–316 (only the dingux-convention inference above).
- ALSA control names for card-0 ids 1, 2, 3, 4, 5, 8 (only numeric ids are used).
- Meaning of AXP2202 reg 0x18 ← 0x01 ("Fast Shutdown"), and of `nds_pwrkey`, `os_sleep`, `workled_sleep`, `spk_state` values.
- Which UI page a lone MENU tap opens (state 20).
- What `/etc/init.d/launcher.sh` adds (file not extracted). RetroArch in-game hotkeys (ANBERNIC-keys.cfg not extracted).
- Whether the kernel enables wake sources, or what `mem` maps to (mem_sleep is never written).

---

### Optional device checks (stock unit, read-only except where noted)

1. `cat /proc/bus/input/devices` and `evtest` on the `ANBERNIC-keys` node and on event0 → confirm the physical button ↔ code map (§1.2) and whether the lid really sends KEY 110/111.
2. `for f in hallkey brightness openbor_volume nds_esckey nds_pwrkey os_sleep workled_sleep spk_state boot_mode display_id; do echo $f=$(cat /sys/class/power_supply/axp2202-battery/$f); done`, then repeat with the lid closed, a game running, and the charger attached.
3. `tinymix -D 0` (or `amixer -c 0 controls; amixer -c 0 contents`) → name the control ids 1/2/3/4/5/8 and their ranges (expect 63 and 31 maxima). `cat /proc/asound/cards`: is card 2 the HDMI card?
4. `cat /sys/power/state /sys/power/mem_sleep`; `ls /sys/class/switch /sys/class/extcon`; `cat /sys/class/power_supply/axp2202-battery/voltage_now capacity status`.
5. `ls -l /sys/class/deeplayer/deeplayer/` and `lsmod`/`dmesg | grep -i deeplay` → confirm the anti-clone driver exists and which module provides it (do not write to it).
6. `hexdump -C /mnt/data/dmenu/dmenu_attr.ini` before and after changing brightness/volume/sleep timer in the UI → confirm offsets +24/+28/+36/+44/+132.
7. `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` in the launcher and inside a game → expect performance vs interactive.

### What a replacement launcher / custom firmware must keep or stop doing

**Keep (or provide an equivalent):**
- A suspend path that works with the lid: either poll `axp2202-battery/hallkey` or handle KEY 110/111 on event0. Skip lid-sleep while HDMI is connected. Use a ≥100 ms power-key debounce, short press = suspend, 2 s hold = clean poweroff (`sync` first).
- A low-battery shutdown (stock: capacity 0 and ≤3420 mV for about 20 s while not charging). Use `status`/`usb online` for charging detection.
- Charger-mode handling when `boot_mode`=1 (keep radios off, show charge state, power off when USB is removed, power key → reboot into the OS).
- Brightness control. On a stock/BSP kernel it goes through `/dev/disp` 0x102/0x103 with a non-linear table and a minimum of 5 (avoid 0 = black). On mainline it would use the backlight class instead; the stock launcher never touches `/sys/class/backlight`.
- Headphone-jack speaker muting and HDMI audio routing (card 2 / `hw:2,0`). Restore the hardware mixer to sane maxima (ctl #1 63, ctl #2 31) or use one consistent volume mechanism.
- Global hotkeys while games run: volume/brightness on VOL± / MENU+VOL±. Stock does this through separate daemons gated by `nds_esckey`.
- Check whether a standalone mixer `sw` or `openbor_volume` state is expected by kept vendor emulators/scripts.

**Stop / do not copy:**
- The `deeplayer` challenge–response and its reboot loop (vendor DRM). A custom kernel without that driver would make stock dmenu reboot endlessly. That is another reason not to run stock dmenu on a custom kernel.
- The silent auto-format of data/ROM partitions in `loadapp.sh` (mkfs when blkid shows no TYPE or a mount fails). This risks data loss on a transient mount error.
- Using vendor `axp2202-battery/*` attributes (`brightness`, `openbor_volume`, `nds_esckey`) as IPC storage. Use a userspace state file instead.
- The raw AXP register poke `echo 0x1801 > /sys/class/axp/axp_reg` and `reboot efex` triggered by a file on the SD card.
- `cpu_setting.sh full` (performance governor) for the whole launcher session. Prefer schedutil/ondemand with a cap.
- Hard-coded `/dev/input/event0` (enumeration order can change). Match by device name or capabilities, as the stock code already does for `ANBERNIC-keys`.
- The `rtcwake … mem -s 1` hack after HDMI→LCD switching, unless a device test shows the display needs it.
- Running every UI/helper as root through `system()` string templates (shell injection risk from file names in `cd "%s"`, `rm -rf "%s"`, nmcli SSIDs).

---

## W3.6. Stock daemons, boot scripts and `/etc`

*Drafted by a DR worker agent from the extracts; DR re-checked `loadapp.sh`'s format conditions and the enabled units. Security findings held privately (Dale).*

**Summary (5 lines)**
1. Init is systemd. The stock app chain is a SysV script: `/etc/init.d/launcher.sh` (S50 only in `rc5.d`, so its generated unit is pulled in by graphical.target). It runs `resize2fs` on `/dev/mmcblk0p6` at every boot, mounts p6 ext4 at `/mnt/vendor`, then backgrounds `loadapp.sh` → endless `dmenu_ln`/`dmenu.bin` loop, all as root with `HOME=/`.
2. **[D][N]** `loadapp.sh` does all the "system" work at every boot: one-time `resize2fs /dev/mmcblk0p5`, mounts p7 ext4 at `/mnt/data` and p1 (or p8) FAT at `/mnt/mmc`, and **runs `mkfs.ext4`/`mkfs.vfat` on those partitions if blkid finds no filesystem or the mount fails**; it also unmasks and restarts NetworkManager and bluetooth (bluetooth isn't enabled otherwise), or runs the charger UI `charg.dge` when `axp2202-battery/boot_mode`=1.
3. Enabled at boot: NetworkManager, wpa_supplicant, systemd-resolved, rsyslog, cron, apparmor and the stock timers; hostapd, Bluetooth and timesyncd are not enabled. *Security findings held privately (Dale).*
4. `logind.conf` sets `HandlePowerKey=ignore` (power key and suspend are owned by the launcher → `pwr_new.sh` → `mem`); `sleep.conf` is all defaults; journald `Storage=none`; `/etc/udev/rules.d` and `hwdb.d` are empty; `modprobe.d` holds only stock Ubuntu blacklists, with no module options.
5. Kernel 4.9.170: `rc.local` insmods `8821cs.ko` and `/lib/modules/mali_kbase.ko`, and `modules-load.d` → `/etc/modules` loads `rtl_btlpm`; Bluetooth comes up through `rtk_hciattach ttyS1 rtk_h5 115200`. `fstab` is empty; ALSA default is `hw:audiocodec` with the speaker and line-out switches locked on and `digital volume` at 63. Build stamp: `RG34xxSP` / `20260526`.

Tags: **[D]** = from files, strings or the listing; **[G]** = from disassembly (none used here); **[I]** = inference from [D] facts. Nothing is device-verified.

**Inputs:** `rootfs/etc` (top-level files) plus `etc2/` (subdirectories: `systemd`, `init.d`, `rc?.d`, `ssh`, `udev`, `modprobe.d`, `modules-load.d`, `NetworkManager`, `bluetooth`, `hostapd`, `profile.d`, `network`, `wpa_supplicant`, `sudoers.d`, `security`, `default`), `rootfs-listing.txt`, `appfs/{ctrl,oem,bin}`. **Still not available:** `/lib/udev/rules.d`, `/etc/ufw/*` (`ufw.conf` ENABLED flag and the rules), `/etc/alsa`, `/var/lib/alsa/asound.state`, `/usr/lib/os-release`, the `cron.*` dirs, `/root` dotfiles, the `/mnt/mod` contents, and the original file modes in /etc (the extract normalised them to 0700 and uid 1016; `rc.local`'s executable bit is therefore unknown). The `default.target` link target is not shown either; it is inferred to be graphical.target (see §1).

---

### 1. Boot sequence

#### 1a. Enabled units (`/etc/systemd/system/*.wants`) [D]

| Target | Enabled units |
|---|---|
| sysinit.target | `apparmor.service`, `systemd-pstore.service` |
| sockets.target | `uuidd.socket` |
| network-online.target | `NetworkManager-wait-online.service` |
| multi-user.target | `NetworkManager`, `wpa_supplicant`, `systemd-resolved`, `networkd-dispatcher`, `rsyslog`, `cron`, `dmesg`, `e2scrub_reap`, `remote-fs.target`  *Security findings held privately (Dale).* |
| getty.target | `getty@tty1.service` (no autologin drop-in exists). A `serial-getty@ttyS0` is also created automatically by systemd-getty-generator from `console=ttyS0` [I] |
| timers.target | `dpkg-db-backup`, `e2scrub_all`, `fstrim`, `logrotate`, `man-db`, `motd-news` |
| Aliases | `syslog.service`→rsyslog, `dbus-fi.w1.wpa_supplicant1`→wpa_supplicant, `dbus-org.freedesktop.nm-dispatcher`→NM-dispatcher, `dbus-org.freedesktop.resolve1`→resolved |
| Masked | `sudo.service` → `/dev/null` (stock Ubuntu) |
| `/etc/systemd/system/rc-local.service` | A local copy of the unit, dated 13-Jun-2024: `ConditionFileIsExecutable=/etc/rc.local`, `After=network.target`, `Type=forking`, `ExecStart=/etc/rc.local start`, `RemainAfterExit=yes`, `TimeoutSec=0`, `[Install] WantedBy=multi-user.target`. It has **no wants link**, so it runs only through systemd-rc-local-generator, if `rc.local` is executable |
| **Not enabled** | `bluetooth` (started by `loadapp.sh`), `hostapd` (started by `setHostapd.sh`), `systemd-timesyncd` (so nothing syncs time over the network), `systemd-networkd`, `ModemManager`, `snapd*`, `upower`, `apt-daily*` |
| User units (desktop leftovers, unused because there is no user session) | `tracker-extract-3`, `tracker-miner-fs-3`, IBus GNOME, `session-migration`, `gpg-agent*` and `dirmngr` sockets |

#### 1b. SysV links (`/etc/rc?.d`) [D]

| Runlevel | Links |
|---|---|
| rcS | S01 `alsa-utils`, `apparmor`, `kmod`, `procps`, `udev`, `x11-common` |
| rc2, rc3 | S01 `cron`, `dbus`, `uuidd`; K01 `hostapd`; **K50 `launcher`** |
| rc5 | S01 `cron`, `dbus`, `uuidd`; K01 `hostapd`; **S50 `launcher`** |
| rc0, rc6 | K01 `alsa-utils`, `hostapd`, `udev`, `uuidd`; K50 `launcher` |
| rc1 | K01 `alsa-utils`, `hostapd`, `uuidd`; K50 `launcher` |
| rc4 | directory not present |

Every script except `launcher.sh` has a native unit, so systemd ignores its rc links. `launcher.sh` has **no LSB header** and **no native unit**, so systemd-sysv-generator creates `launcher.service`. Runlevel 5 maps to graphical.target, so it is pulled in only by graphical.target, and the shipped launcher works only if `default.target` is graphical.target (the Ubuntu default) [I]. Without LSB headers the generator gives it no ordering beyond the default dependencies, so its start can race NetworkManager and `rc.local` [I].

#### 1c. Start order (where determinable)

| # | Stage | What runs | User | Restart policy | Evidence |
|---|---|---|---|---|---|
| 0 | Kernel cmdline | `root=/dev/mmcblk0p5 rootwait quiet splash init=/init cma=64M selinux=0 console=ttyS0,115200 loglevel=4 gpt=1` (the mmc variant `setargs_mmc`) | — | — | [D] `/home/claude/re/env.txt` (outside the W3.6 inputs; context only) |
| 1 | PID 1 | `/init` → link, length 10; `/usr/sbin/init` → link, length 20; together consistent with `/sbin/init` → `/lib/systemd/systemd` | root | — | [D]/[I] |
| 2 | sysinit | udev (no local rules), `systemd-modules-load` (`modules-load.d/modules.conf` → `../modules` → `rtl_btlpm`), apparmor, pstore, alsa-restore | root | per unit | [D] |
| 3 | multi-user | units in §1a; `rc-local.service` (after network.target) → the two `insmod`s | root | rc-local: oneshot-like, forking, RemainAfterExit | [D] |
| 4 | graphical | generated `launcher.service` → `launcher.sh start` | root, no HOME set (scripts use `/.config`) | Generated SysV unit: Type=forking, RemainAfterExit=yes, KillMode=process [I]; no restart. `loadapp.sh` is backgrounded with `{ … }&`, so it survives the unit's start process | [D]/[I] |
| 5 | `launcher.sh start` | (a) runs `resize2fs /dev/mmcblk0p6` on **every boot**, even with the partition unmounted: it checks for `/etc/vendor_resize.cfg`, but the line that would create that flag is commented out; (b) prints "Starting deeplay_launcher"; (c) `mount -t ext4 -o rw,noatime,nodiratime /dev/mmcblk0p6 /mnt/vendor`; (d) backgrounds `/mnt/vendor/bin/brightCtrl.bin` and `/mnt/vendor/bin/cexpert` if they exist (neither is in the supplied `appfs/bin`); (e) backgrounds `/mnt/vendor/ctrl/loadapp.sh` | root | — | [D] |
| 6 | `loadapp.sh` | resize p5 → mount data → mount Roms → appfs.img overlay → retroarch cfg → charge-mode branch or radio enable → RTC → optional key modules → `mmc_new.sh add` → `/mnt/mod/ctrl/autostart` → debug hold → launcher loop (§2) | root | its own `while` loop | [D] |
| 7 | Launcher loop | `while [ -f /mnt/vendor/ctrl/dmenu_ln ]`: runs `dmenu_ln`; leaves the loop when `/tmp/stopAPP.ini` exists | root | the loop restarts it forever | [D] |
| 8 | `dmenu_ln` | Picks `/mnt/vendor/bin/dmenu.bin`; replaced by `/mnt/mmc/dmenu.bin` if present, by `muos{1,2}.bin` if `/mnt/vendor/muos{1,2}.ini` exists, or by `bin/video/vp.dge` if `/tmp/vpRun.ini` exists. Writes the LED cfgs. When the binary exits 0 and `/tmp/.next` exists, runs `sh /tmp/.next`; a non-zero exit sleeps 30 s. `debug.ini` on `/mnt/data` or `/mnt/sdcard` sends output to `/dev/console` | root | via the loop | [D] |
| 9 | Shutdown (`launcher.sh stop`, K50 in rc0/rc6) | `killall retroarch`, `rtk_hciattach`, `loadapp.sh`; SIGUSR1 to `dmenu.bin` and `muos.bin`; SIGINT to `charg.dge` and `ndsCtrl.dge`; `sync` | root | — | [D] |
| — | `hwclock.sh` | Exits at once under systemd; its stop action would write system time to rtc0 | — | — | [D] |
| — | cron | `/etc/crontab` is stock (hourly :17, daily 06:25, weekly Sun 06:47, monthly 1st 06:52) | root | — | [D] |
| — | profile | `/etc/profile` adds `LD_LIBRARY_PATH=/usr/lib32:/usr/lib:/mnt/vendor/lib`. `profile.d` holds only stock files: `01-locale-fix.sh`, `apps-bin-path.sh` (snap), `gawk`, `vte`, `im-config_wayland.sh`. No autostart | — | — | [D] |

### 2. Stock-specific scripts: what they change and when

All of these run as root. "Caller" comes from `strings` of the appfs binaries [D].

| Script | Caller / when | Writes or changes | Notes |
|---|---|---|---|
| `launcher.sh` | boot (graphical.target) | `resize2fs /dev/mmcblk0p6` on every boot; mounts p6 at `/mnt/vendor`; starts `brightCtrl.bin`, `cexpert`, `loadapp.sh` | The flag `/etc/vendor_resize.cfg` is checked but never created |
| `loadapp.sh` `RESIZE_ROOT_CMD` | boot | If `/etc/allen_resize.cfg` is missing: touches it, then `resize2fs /dev/mmcblk0p5` (online grow of the root fs) | Writes a flag file into **/etc** |
| `loadapp.sh` `FORMAT_DATA_CMD` | boot | If `/dev/mmcblk0p7` exists: creates `/mnt/data`; no blkid TYPE → **`mkfs.ext4`**; mounts ext4 `rw,noatime,nodiratime`; if it is still not in `/proc/mounts` → **mkfs.ext4 again** and mounts | Destructive on mount failure |
| `loadapp.sh` `FORMAT_ROMS_CMD` | boot | Device is `/dev/mmcblk0p1`, or `/dev/mmcblk0p8` if p8 exists. No TYPE → **`mkfs.vfat`**; mount vfat `rw,utf8,dmask=000,fmask=000,noatime,nodiratime` at `/mnt/mmc`; mount failure → **mkfs.vfat** and mount | Destructive on mount failure |
| `loadapp.sh` | boot | If `/mnt/mmc/appfs.img` exists → loop-mounts it on `/mnt/vendor` (on top of p6) | Root code taken from the FAT partition |
| `loadapp.sh` `check_retroarch_cfg` | boot | Creates `/.config/retroarch/` and copies `/mnt/vendor/deep/retro/retroarch.cfg` there if missing | — |
| `loadapp.sh` (`check_swap_device`, disabled) | — | Would `mkswap`+`swapon /dev/mmcblk0p7`, which conflicts with p7 being `/mnt/data` | Dead code |
| `loadapp.sh` charge branch | `axp2202-battery/boot_mode` = 1 | `rfkill block bluetooth` + stop + **mask** `bluetooth.service`; `rfkill block wifi` + stop + **mask** `NetworkManager.service`; runs `charg.dge`, then `sleep 5; poweroff` | Masks persist until the next normal boot |
| `loadapp.sh` normal branch | every normal boot | `unmask` + `restart` NetworkManager, `rfkill unblock wifi`; `unmask` + `restart` bluetooth, `rfkill unblock bluetooth` | This is the only thing that starts bluetooth |
| `loadapp.sh` RTC | boot | If `/sys/class/rtc/rtc0/date` is empty: `date -s <today>`, `hwclock -w` | — |
| `loadapp.sh` key modules | boot | If `/mnt/mmc/gpio_keys_polled.ko` exists: `insmod` `gpio_keys_gpadc.ko` and `gpio_keys_polled.ko` from `/mnt/mmc` | Kernel modules loaded from FAT |
| `loadapp.sh` | boot | `/mnt/vendor/ctrl/mmc_new.sh add`, then `/mnt/mod/ctrl/autostart` if present | Third-party "mod" hook |
| `loadapp.sh` debug hold | boot | While `/mnt/data/xudebug.ini` exists: sleep 30 s in a loop (the launcher never starts) | — |
| `dmenu_ln` | each launcher start | `/mnt/mod/ctrl/configs/led_exit.cfg`, then `led_launch.cfg` → `/sys/class/power_supply/axp2202-battery/work_led` | AXP vendor sysfs |
| `mmc_new.sh add/remove` | `loadapp.sh`; dmenu (`... add`); comment says `cexpert` calls it | Second card (`mmcblk1p1` › `mmcblk1` › `mmcblk2p1` › `mmcblk2`); lock `/tmp/.mmc_mount`; by blkid type: vfat / `/bin/ntfs-3g` / exfat, `uid=1000,gid=1000,dmask=000,fmask=000,noatime,utf8` at `/mnt/sdcard`; remove → `umount -l` | `ntfs-3g` is not in the rootfs listing |
| `mmc.sh add/remove` | dmenu (`mmc.sh remove`); also reads udev-style `$ACTION`, but no rule in `/etc/udev/rules.d` calls it (`/lib/udev/rules.d` not supplied) | vfat, falling back to exfat, `rw,utf8,noatime` at `/mnt/sdcard`; remove → `umount -l` | Hot-plug is probably polled by dmenu or cexpert [I] |
| `udisk.sh add/remove` | no caller found in /etc or the supplied binaries | `sd[ab]1`/`sd[ab]` → vfat, falling back to exfat, at `/mnt/udisk` | — |
| `pwr_new.sh [arg]` | dmenu.bin, charg.dge | Delegates to `/mnt/mod/ctrl/pwr_new.sh` if present; else lock `/tmp/.power_key` (mode 777), `mem` → `/sys/power/state`, remove the lock after 0.3 s | logind ignores the power key (§7) |
| `cpu_setting.sh {full,powersave,user,*}` | dmenu.bin, charg.dge | cpu0 `scaling_governor`: `performance` / `powersave` / `userspace` + `scaling_setspeed`=792000 / default `interactive`. DDR DVFS through `/sys/kernel/debug/sunxi_gpu/write` is commented out | OPPs in a comment: 480–1512 MHz; DDR 648@960 mV … 420@900 mV |
| `moto.sh start/stop` | not referenced | `pwmchip0` `pwm2`: period 20 ms (50 Hz), duty 12 ms (60 %), polarity normal | The binaries use `axp2202-battery/moto` instead |
| `forceOS.sh rest/shutdwn` | not found | `sync; sleep 1; reboot` or `poweroff` (commented: AXP reg writes `0x270a`/`0x2709`) | — |
| `ntpd.sh` | not found | `ntpdate cn.pool.ntp.org` | `ntpdate` absent; timesyncd not enabled |
| `setSSH.sh` | dmenu.bin | `systemctl restart ssh` | — |
| `setBluetooth.sh init/enable/all/restart` | dmenu.bin | Lock `/tmp/.init_bt`; `rtk_hciattach -n -s 115200 ttyS1 rtk_h5 &`; `hciconfig hci0 up`, `lm master`, `auth`; `restart` = stop/start `bluetooth` | — |
| `setHostapd.sh enable/disable/ssid/password/channel` | dmenu.bin | disable: `kill -9` hostapd, `nmcli networking off`. enable: `ifconfig wlan0 192.168.1.1 up`, `hostapd -B /etc/hostapd/hostapd.conf`. The other actions `sed -i` the ssid, passphrase or channel line in that file | DHCP for clients: held privately (Dale). The `ssid` pattern also matches `ignore_broadcast_ssid` |
| `setMusic.sh stop` | not found | `kill -9` mplayer (absent) | — |
| `setNDS.sh run/savedir/stop/recover` | dmenu.bin; ndsCtrl.dge | Runs `/mnt/mmc/ndsCtrl.dge` (FAT override), or `/mnt/mod/ctrl/ndscheat` + the vendor `ndsCtrl.dge`; then `drastic`. Re-links `savestates`/`backup` under `/mnt/vendor/deep/drastic` to `/mnt/{mmc,sdcard}/save_nds/*`; `recover` copies `drastic-back.cfg` → `drastic.cfg` | Writes into p6 |
| `setPSP.sh language/recover` | dmenu.bin | `sed` of `Language` in `deep/ppsspp/PSP/SYSTEM/ppsspp.ini`; copies `BACK/*` → `SYSTEM` | — |
| `setRA.sh run/rest/language/snd_card/volume/easy/adv` | dmenu.bin | `/.config/retroarch/retroarch.cfg` (copy and `sed` of `user_language`, `audio_device`, `audio_volume`, menu toggles); `rest` copies `ANBERNIC-keys.cfg` into `autoconfig/udev`; `language` also calls `/mnt/mod/ctrl/sw` | — |
| `setFlycast.sh <rom>` | dmenu.bin | HOME = `/mnt/{sdcard,mmc}/save_flycast`; seeds `emu.cfg` from `/emuelec/flycast`; starts `portsCtrl.dge` (FAT override first); `AUDIODEV=hw:2,0` when `axp2202-battery/display_id`=1 | **Bug**: that branch runs the undefined `$YA_BIN` |
| `setSaturn.sh HLE/BIOS <rom>` | dmenu.bin | `/emuelec/saturn/yabasanshiro -r 3 -i <rom> [-b …/saturn_bios.bin]`; `AUDIODEV=hw:2,0` when `display_id`=1 | — |

Other hardware writes seen only in `dmenu.bin` strings (the launcher is out of scope) [D]: `echo 0x1801 > /sys/class/axp/axp_reg`, `echo 3 > /proc/sys/vm/drop_caches`, `hwclock -lw [-f /dev/rtc0|/dev/rtc1]`, `reboot efex` (FEL), and `axp2202-battery/{brightness,moto,os_sleep,workled_sleep,led_test,spk_state,otg_id,hallkey,nds_pwrkey,nds_esckey,openbor_volume}`.

### 3. Mounts

| Source | Mount point | FS / options | By |
|---|---|---|---|
| `/dev/mmcblk0p5` | `/` | ext4; `fstab` is only the "UNCONFIGURED FSTAB" comment, so there is no remount option | kernel `root=` [D] |
| `/dev/mmcblk0p6` (appfs) | `/mnt/vendor` | ext4 `rw,noatime,nodiratime`; resize2fs attempted every boot before the mount | `launcher.sh` [D] |
| `/mnt/mmc/appfs.img` (loop) | `/mnt/vendor` (on top of p6) | default | `loadapp.sh` [D] |
| `/dev/mmcblk0p7` | `/mnt/data` | ext4 `rw,noatime,nodiratime`; mkfs.ext4 if missing | `loadapp.sh` [D] |
| `/dev/mmcblk0p1`, or `p8` if present | `/mnt/mmc` (Roms) | vfat `rw,utf8,dmask=000,fmask=000,noatime,nodiratime`; mkfs.vfat if missing | `loadapp.sh` [D] |
| `mmcblk1p1`/`mmcblk1`/`mmcblk2p1`/`mmcblk2` | `/mnt/sdcard` | vfat / ntfs-3g / exfat, `uid=1000,gid=1000,dmask=000,fmask=000` | `mmc_new.sh` (`mmc.sh`: vfat→exfat) [D] |
| `sd[ab]1`/`sd[ab]` | `/mnt/udisk` | vfat→exfat | `udisk.sh` [D] |
| — | `/mnt/mod` | plain directory on rootfs (uid 1000) | [D] |
| swap | none | — | [D] |

No UUIDs or labels are used anywhere; everything goes by the fixed `/dev/mmcblkXpN` name [D].

### 4. Kernel modules and firmware

| Item | Value | Evidence |
|---|---|---|
| Kernel | 4.9.170 | [D] |
| Wi-Fi | `rc.local`: `insmod /lib/modules/4.9.170/kernel/drivers/net/wireless/rtl8821cs/8821cs.ko`, no parameters | [D] |
| GPU | `rc.local`: `insmod /lib/modules/mali_kbase.ko` | [D] |
| Boot-loaded | `modules-load.d/modules.conf` → `../modules` → `rtl_btlpm` | [D] |
| Optional | `gpio_keys_gpadc.ko`, `gpio_keys_polled.ko` from `/mnt/mmc` | [D] |
| `modprobe.d` | Only stock Ubuntu files: `blacklist.conf`, `blacklist-ath_pci`, `blacklist-firewire`, `blacklist-framebuffer`, `blacklist-rare-network` (`net-pf-*` off), `iwlwifi.conf` (remove hook). **No `options` lines, nothing for any sunxi, Realtek or mali module** | [D] |
| initramfs-tools | `MODULES=most`, `COMPRESS=zstd`, `RUNSIZE=10%`, empty `modules` | [D] |
| Firmware paths | None named in /etc or the scripts; BT patch loading is inside `rtk_hciattach` (path not verified) | [I] |
| BT transport | `rtk_hciattach -n -s 115200 ttyS1 rtk_h5` | [D] |

### 5. Network, SSH, time, hostname

| Area | Fact | Evidence |
|---|---|---|
| Hostname | `ANBERNIC`; `/etc/hosts` has no `127.0.1.1` line | [D] |
| NetworkManager | `plugins=ifupdown,keyfile`, `[ifupdown] managed=false`, `wifi.scan-rand-mac-address=no`; conf.d `wifi.powersave = 3` (enabled); `system-connections/` **empty** (no Wi-Fi credentials shipped); `dispatcher.d/01-ifupdown` stock; `dnsmasq.d` and `dnsmasq-shared.d` empty. dmenu drives it through `nmcli` | [D] |
| `/etc/network` | Only the stock `if-*.d` hooks (wpasupplicant, hostapd, wireless-tools, ethtool); no `interfaces` file in the extract | [D] |
| wpa_supplicant | Unit enabled (D-Bus backend for NM); `/etc/wpa_supplicant` holds only stock ifupdown helper scripts, no `.conf` | [D] |
| Bluetooth | `main.conf`: only `[Policy] AutoEnable=true` set; `input.conf` and `network.conf` all defaults. Service not enabled; `loadapp.sh` starts it. BlueZ tools and `bluealsa` rebuilt in June 2024 | [D] |
| DNS | `systemd-resolved` enabled, `resolved.conf` all defaults; `resolv.conf` → stub | [D] |
| Time | `timesyncd.conf` defaults, but **timesyncd is not enabled**; `ntpdate` absent; time comes from the RTC (`loadapp`) and dmenu `date -s`/`hwclock -lw` | [D] |
| networkd | `networkd-dispatcher` enabled (`--run-startup-triggers`) although `systemd-networkd` is not; `/etc/systemd/network` empty | [D] |
| Locale | `/etc/default/locale`: `LANG=zh_CN.UTF-8`, `LANGUAGE=zh_CN:zh`, but `locale.gen` generates nothing (`01-locale-fix.sh` falls back to C.UTF-8 in login shells); `/etc/default/im-config` prefers fcitx5 for zh | [D] |

### 6. Users, groups, sudo, autologin

| Account | uid:gid | Shell | Home |
|---|---|---|---|
| root | 0:0 | `/bin/bash` | `/root` (dir mode 0777) |
| sync | 4:65534 | `/bin/sync` | /bin |
| daemon, bin, sys, games, man, lp, mail, news, uucp, proxy, www-data, backup, list, irc, gnats, nobody, _apt, messagebus, systemd-network/-resolve/-timesync, syslog, dnsmasq, sshd, uuidd, usbmux | system | `nologin` | various |

- There is no uid ≥ 1000 account, but `/emuelec`, `/roms` and `/mnt/*` are owned by uid 1000 and the sdcard mounts use uid/gid 1000, so a user was probably removed at build time [I]. `/home` is empty. `/etc/default/useradd` `SHELL=/bin/sh` [D].
- `sudoers` is stock; `sudoers.d` holds only the README; `sudo.service` is masked (stock). [D].
- `/etc/security/*` is all stock defaults (`capability.conf` `none *`; `limits.d` and `namespace.d` empty; `opasswd` empty) [D].
- Autologin: **none** (no getty drop-ins). Console logins: `getty@tty1` plus the generated serial getty on `ttyS0` [I]. **The launcher runs as root from `launcher.service`**, not from a login session [D/I].

### 7. udev, input, power key, sleep

| Item | Finding |
|---|---|
| `/etc/udev/rules.d` | **Empty.** `udev.conf` holds only defaults, `hwdb.d` is empty. `/lib/udev/rules.d` is not in the inputs, so package rules can't be checked; no stock-specific rule exists in /etc. The `$ACTION` handling in `mmc.sh`/`udisk.sh` is therefore unused or only reachable from rules under /lib [D]/[I] |
| Input devices | Apps open `/dev/input/event0`, `/dev/input/event1` and scan `/dev/input/*` and `/sys/class/input`; pad map `/mnt/data/dmenu/localpad.map`; RetroArch `autoconfig/udev/ANBERNIC-keys.cfg` [D] |
| `logind.conf` | Only `HandlePowerKey=ignore` is set. Everything else is the systemd 249 default: `HandleLidSwitch=suspend`, `HandleSuspendKey=suspend`, `IdleAction=ignore`. Whether the AXP hall sensor appears as an input `SW_LID` (which would make logind suspend too) is unknown [D]/[I] |
| `sleep.conf` | All defaults (`[Sleep]` only), so `systemctl suspend` uses `mem`/`deep` defaults [D] |
| Power key path | dmenu or charg.dge → `pwr_new.sh` → `echo mem > /sys/power/state`; lid sleep through `axp2202-battery/hallkey` ("hall to sleep" string) [D] |
| journald | `Storage=none`, `SystemMaxUse=64M`, `ForwardToSyslog=no`: no journal is kept. rsyslog is enabled but gets only kernel messages (imklog) [I]. `dmesg.service` writes `/var/log/dmesg` [D] |

### 8. Audio, display, environment

| Item | Value |
|---|---|
| `asound.conf` `pcm.!default` | `type hooks` over `hw:audiocodec`; `ctl_elems` with `preserve true`, `lock true`: `LINEOUT Switch`=1, `SPK Switch`=1, `OutputL Mixer DACL Switch`=1, `OutputR Mixer DACR Switch`=1, `digital volume`=63 |
| `pcm.playback_hp` | Same without `SPK Switch` |
| `pcm.playback_hdmi` | `type hw`, `card ahubhdmi` |
| Cards | `audiocodec`, `ahubhdmi`; the HDMI path uses `AUDIODEV=hw:2,0` (card 2 [I]); jack state from `/sys/module/snd_soc_sunxi_component_jack/parameters/jack_state` |
| ALSA state | `alsa-utils` (rcS S01) and `alsa-restore` are present; the state file is not in the inputs |
| Display | No X server or display manager; apps use `/dev/disp`, `/dev/fb0`, `/dev/ion`; HDMI state from `extcon/hdmi/state` or `switch/hdmi/state`; `axp2202-battery/display_id`. `x11-common` (rcS) is a leftover |
| `vdpau_wrapper.cfg` | `enable_flash_uv_swap=1`, `disable_flash_pq_bg_color=1` (stock libvdpau) |
| `/etc/environment` | Stock PATH **plus `/mnt/vendor/bin`** |
| `/etc/profile` | Appends `export LD_LIBRARY_PATH=/usr/lib32:/usr/lib:/mnt/vendor/lib` |
| Userland ABI | Appfs binaries are ELF32 ARM EABI5 hard-float (`ld-linux-armhf.so.3`) on an arm64 rootfs |

### 9. Security-relevant facts (stated, not judged)

*Security findings held privately (Dale).*

### 10. Version and build identification

| Source | Value |
|---|---|
| `/etc/os-release` | link → `../usr/lib/os-release` (target not supplied) |
| `/etc/lsb-release` | `DISTRIB_ID=Ubuntu`, `DISTRIB_RELEASE=22.04`, `DISTRIB_CODENAME=jammy`, `DISTRIB_DESCRIPTION="Ubuntu 22.04 LTS"` |
| `issue`, `issue.net` | `Ubuntu 22.04 LTS` |
| `debian_version` | `bookworm/sid` |
| `appfs/oem/board.ini` | `RG34xxSP` |
| `appfs/oem/version.ini` | `20260526` |
| `appfs/oem/language.ini` | `2` |
| File dates | rootfs base 2022-04/05; vendor additions 2024-04…2024-12; `launcher.sh` and `charg.dge` 2025-12-05; `dmenu.bin` 2026-05-26 |
| Kernel | 4.9.170 |
| "deeplay_launcher" | the stock launcher's name (from the `launcher.sh` message) |

---

### Optional device checks (stock unit, read-only; run as root over the serial console)

```sh
systemctl get-default; systemctl status launcher.service; systemctl cat launcher.service
systemctl list-units --type=service --state=running
ls /lib/udev/rules.d | grep -viE '^[0-9]{2}-(systemd|udev|dm|lvm)'; udevadm monitor -k -u   # then insert a card
cat /proc/bus/input/devices | grep -A4 -iE 'lid|hall|power|gpio'   # is there an SW_LID that logind would act on?
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS; lsblk -o NAME,SIZE,FSTYPE,LABEL
lsmod; cat /proc/cmdline; cat /proc/asound/cards
ls -l /etc/rc.local /mnt/vendor/bin/brightCtrl.bin /mnt/vendor/bin/cexpert; ls /mnt/mod/ctrl
cat /usr/lib/os-release
```

### What a replacement firmware or installer must keep, stop or watch for

| Item | Action | Why |
|---|---|---|
| `loadapp.sh` format-on-mount-fail (p7 → mkfs.ext4, p1/p8 → mkfs.vfat) | **Watch**: never let stock boot see a card with the Redux layout on those partition numbers; a dual-boot layout must keep p7 ext4 and p1/p8 FAT, or stock will wipe them | §2 |
| `launcher.sh` resize2fs on p6 at every boot, `loadapp.sh` resize on p5 (flag `/etc/allen_resize.cfg`) | Watch: they grow p6 and p5 to fill their partitions | §2 |
| `systemctl mask/unmask` + restart of NetworkManager and bluetooth every boot | Stop in Redux: enable services declaratively | §2 |
| Charge-only boot (`boot_mode`=1 → `charg.dge` → poweroff) | Keep the behaviour; on mainline the boot reason must come from the AXP717 power-on status, not the vendor sysfs | §2 |
| Power key: `HandlePowerKey=ignore` + userspace `mem` | Keep a single owner. If Redux hands it to logind, also decide `HandleLidSwitch` (default suspend) | §7 |
| `cpu_setting.sh` (`interactive` governor) | Replace with `schedutil` on mainline | §2 |
| rc.local `insmod`s (4.9.170 paths), `rtl_btlpm` in `/etc/modules`, `rtk_hciattach ttyS1 rtk_h5 115200` | Stop; use in-tree rtw88 SDIO, panfrost and serdev `btrtl` from the DT, with `modules-load.d` for the remainder. Keep the UART facts | §4 |
| Mount points `/mnt/{mmc,sdcard,data,vendor,udisk}`, uid/gid 1000, save dirs `save_nds`/`save_flycast` | Keep the paths if stock ROM and save layouts should carry over | §3 |
| ALSA control names (`LINEOUT Switch`, `SPK Switch`, `Output[LR] Mixer DAC[LR] Switch`, `digital volume`) | Watch: these are vendor names; mainline needs a new UCM or asound.conf | §8 |
| `/etc/environment` and `/etc/profile` pointing at `/mnt/vendor` | Stop on Redux | §8 |
| journald `Storage=none` | Stop: keep at least a volatile journal for debugging | private |
| `default.target` = graphical + SysV `launcher.sh` without LSB headers | Replace with a native unit with explicit ordering (After=local-fs, NetworkManager as needed) and a Restart policy | §1b |

---

## W3.5/W3.6 gaps: Expert-name helper `cexpert`, muOS skins, emulators, launcher.sh, ALSA, udev

*Drafted by a DR worker agent from extracts dumped 2026-11-15; DR re-checked the `deeplayer` string in every binary and `cexpert`'s uevent strings. No tools installed by the worker.*


**Summary (5 lines)**
1. `cexpert` is **not** an "Expert Mode" or CPU tool. It is an 8 KB netlink uevent listener: on a udev block event that carries `ID_FS_TYPE` it runs `/mnt/vendor/ctrl/mmc_new.sh add` or `… remove`, so it is the stock TF2 (second card) hot-plug mounter. It touches no cpufreq, governor, voltage or sysfs path.
2. `muos1.bin`/`muos2.bin` are re-skinned builds of `dmenu.bin` ("muOS-style" themes, resources in `/mnt/vendor/res3` and `res4`). Every hardware path, ioctl constant table, the sleep/brightness/volume logic and the `deeplayer` check are identical to dmenu. They differ only in theme/UI, a "Return to old style" item that adds or removes `/mnt/vendor/muos{1,2}.ini`, and (muos2 only) a UI-state file `/tmp/mnos.ini`.
3. **All 11 stock emulators** (fc, gba ×2, gbc, md, ngp, sfc, sms, pce, wswan, pcsx) carry their own AES-based `deeplayer` check (`checkEncryption`, run once at start). On failure they run `reboot` every 2 s forever. The media and other apps (vp, ap, reader, dinguxCommander, green, xplayerdemo2) and cexpert do not have it.
4. `vbanext.dge` ships with DWARF macro info that exposes the vendor's platform header. It names every key-mask bit (A/B/X/Y/L1/R1/L2/R2/L3/R3/START/SELECT/MENU/VOL±), lid codes 110/111, `BATTERY_FULL_VAL 4500`, and Actions-Semi leftovers. `asound.state` names the card-0 controls the launchers address by number: id1 `digital volume` 0–63, id2 `lineout volume` 0–31, id4 `SPK Switch`.
*Security findings held privately (Dale).*

Tags: **[G]** = from disassembly (addresses are ELF virtual addresses), **[D]** = from strings, config or script text, **[I]** = inference. No code, scripts or configs are reproduced. No keys, passwords or hashes are copied. `stock-gaps/keep.txt` (a 43-line list of the extracted paths) was present but is not an analysis input.

---

### 0. Inputs (SHA-256, first 16 hex digits)

| File | SHA-256 | Type / build |
|---|---|---|
| bin/cexpert | c2b07ab424581440… | ELF32 armhf, **not stripped**, source `cexpert.c`, Linaro GCC 4.9-2014.08; NEEDED libc only |
| bin/muos1.bin | 9dbdedf93f0076b8… | ELF32 armhf, stripped; same NEEDED list as dmenu.bin |
| bin/muos2.bin | 37cd7573467bbb76… | same |
| bin/tinymixer / tinyplay | d13a1efda1bf21a6… / 25b378c257e83f78… | ELF32 armhf, not stripped; tinyalsa `tinymix` and `tinyplay` |
| bin/evtest | 787145811e184fe5… | **ELF64 aarch64**, GCC 12.2.0; evtest 1.33 |
| bin/fbtest3 | 38d838520dde785e… | ELF32 armhf, not stripped; sunxi disp2/ION layer test (defaults "lcd 640x480x16", "hdmi 1280x720x16") |
| d_game/* (11 binaries) | see §C | ELF32 armhf, built 24-Mar-2025, Linaro GCC 4.9.2 (except as noted) |
| d_video/vp.dge, d_music/ap.dge | 3b92469f8bfc083a… / fffd3ddcc00fd25c… | ELF32 armhf, stripped, 5-Dec-2025, same SDL1.2 code base as dmenu |
| d_video/xplayerdemo2 | 1ecfd6c25876f9d8… | ELF32 armhf with DWARF, GCC 7.5; libcedarx demo |
| d_pdf/green (+ libcairo, launch.sh) | bac892763bcfd47d… | ELF32 armhf PIE, poppler-glib PDF viewer |
| d_ebook/reader_{mmc,sdcard}.dge | 5e0e66f914d8cc67… / a209963622fbfdaa… | ELF32 armhf PIE C++, GCC 7 |
| d_fileM/dinguxCommand_{en,zh}.dge | 28c2742df4ea6bfd… / 594741d2a48aca02… | ELF32 armhf PIE C++ |
| sys/_etc_init.d_launcher.sh | 0fa2fda8da2b18c7… | bash |
| sys/_var_lib_alsa_asound.state | 8844df6e0c626c60… | alsactl state |
| sys/udev-rules-list.txt | 250296ad4a2fcde7… | debugfs-style directory listing |

---

### A. cexpert (high priority)

**Bottom line:** cexpert is the stock **block-device hot-plug watcher** (probably "card expert"). It has **no** CPU frequency, governor, boost, voltage, menu or key handling. Its only imports are `socket, bind, recv, getpid, memset, strcmp, strstr, system, puts, printf, strerror, close` [D].

| Aspect | Finding | Tag |
|---|---|---|
| Started by | `/etc/init.d/launcher.sh start` → `/mnt/vendor/bin/cexpert &` (if present), as root, before `loadapp.sh` | [D] |
| Socket | `socket(AF_NETLINK=16, SOCK_RAW=3, NETLINK_KOBJECT_UEVENT=15)`; `bind` with `nl_family=16`, `nl_pid=getpid()`, **`nl_groups=0xFFFFFFFF`** (all groups, so kernel group 1 and udev group 2) | [G] main 0x10624–0x106de |
| Receive | Blocking `recv` into a 1 MiB stack buffer (0x100000). It prints "receive overflow!" and skips the message if the length is ≥1 MiB, and "state < 0" on error. The loop runs forever with no timeout | [G] 0x1073a–0x107aa |
| Parsing | Walks the message as NUL-separated tokens. It sets four flags: token **equals** `ACTION=add`; token **equals** `ACTION=remove`; token **contains** `SUBSYSTEM=block`; token **contains** `ID_FS_TYPE` | [G] 0x10822–0x1090e |
| Action | Only if both the `SUBSYSTEM=block` and `ID_FS_TYPE` flags are set: add → `system("/mnt/vendor/ctrl/mmc_new.sh  add")`; otherwise remove → `system("/mnt/vendor/ctrl/mmc_new.sh  remove")`. It then prints a banner line | [G] 0x10910–0x10976 |
| Effective trigger | Kernel uevents never carry `ID_FS_TYPE`; only **udev's re-broadcast** (after blkid in `60-persistent-storage.rules`) does. So cexpert depends on systemd-udevd running and reacts once per block device or partition that has a recognised filesystem. That includes mmcblk1/2 partitions and also USB disks and loop devices; it does not check which device it was | [I] from [G] logic + standard udev behaviour |
| What runs | `mmc_new.sh` ignores which device fired: `add` mounts the first of mmcblk1p1/mmcblk1/mmcblk2p1/mmcblk2 on `/mnt/sdcard` (lock `/tmp/.mmc_mount`, per W3.6). `remove` does `umount -l /mnt/sdcard`. **A USB stick removal would therefore also lazily unmount the TF2 card** | [I] (script behaviour from W3.6) |
| Overlap | dmenu also polls card state and calls `mmc_new.sh add` / `mmc.sh remove` (W3.5); the lock file serialises the two | [D] |
| Stop | `launcher.sh stop` does not kill cexpert | [D] |

So the W3.6 note that "hot-plug is probably polled by dmenu or cexpert" resolves to: **cexpert is event-driven (netlink); dmenu also polls.** No udev rule calls `mmc*.sh` or `udisk.sh` (see §F).

---

### B. muos1.bin / muos2.bin

| Item | dmenu.bin | muos1.bin | muos2.bin | Tag |
|---|---|---|---|---|
| What it is | stock launcher | Alternative "muOS-style" skin of the same launcher | Second alternative skin (different layout: top bar, type-left list, setting pages, background sets for apk/game/retro) | [D] |
| Chosen by | default | `dmenu_ln` when `/mnt/vendor/muos1.ini` exists | `dmenu_ln` when `/mnt/vendor/muos2.ini` exists | [D] (W3.6) |
| Theme root | `/mnt/vendor/res1` (+`res2`), with `lcd/` and `hdmi/` image variants | `/mnt/vendor/res3/{boot/logo.png, desktop_res/{bottom,title}, theme}`; no `lcd/`/`hdmi/` variants | `/mnt/vendor/res4/` (+`desktop_res/misc`, `sound`); `%sbackgrouds/{apk,game,retro}/…` | [D] |
| Style switching | creates `muos*.ini` (W3.5) | menu action: if `muos1.ini` exists → `remove()` it, then creates `muos2.ini`; "Return to old style" → removes both (→ dmenu next loop) | mirror image: removes `muos2.ini` and creates `muos1.ini`, or removes both. The settings-reset path (`/mnt/mmc/dmenu.del`) also removes `muos2.ini` | [G] muos1 0x2840c–0x28452; muos2 0x2a1e0–0x2a226, 0x12332 |
| Extra state | — | — | `/tmp/mnos.ini` (keys `saved_ui_type`, `saved_retro_step`, `saved_retro_selemu`, `saved_retro_emu_dir`, `saved_desktop_focus`, `saved_retro_selcard`, `saved_apk_selmodule`); written before launches, read at start | [G] muos2 0x12428, 0x26cd8, fn 0x2bb10/0x2bba8 |
| Hardware strings (60 checked: `/dev/disp`, `/dev/fb0`, `/dev/ion`, event0, `ANBERNIC-keys`, all 14 `axp2202-battery/*` attributes, `axp_reg 0x1801`, `switch/hdmi`, `jack_state`, `pwr_new.sh`, `cpu_setting.sh`, `rtcwake`, `reboot efex`, nmcli, bluetoothctl, moonlight, `hw:2,0`, the `/tmp/*.ini` flags …) | — | **identical counts to dmenu** | **identical** | [D] |
| Constant tables | brightness `5…255`, Q14 gain table, idle table `60000…600000`, 19-entry default keymap | all four present (at file offsets 0x21c38 / 0x2d324 / 0x27160 / 0x2e418) | all four present (0x244fc / 0x3041c / 0x29d48 / 0x31518) | [D] byte search |
| `deeplayer` anti-clone | yes | **yes** (`debug_reg`, "deeplay encryption fail") | **yes** | [D] |
| Firmware string | `V1.0.6`, "Allwinner H700 Linux 4.9.170" | same | same | [D] |

**Differences vs the W3.5 path table:** none at the hardware level. Only the resource roots (`res3`, `res4`), the ini toggles and `/tmp/mnos.ini` are new. ioctl immediates were not re-traced one by one; the same strings and constant tables make a shared code base very likely [I].

Note: `launcher.sh stop` sends SIGUSR1 to `muos.bin`, but the processes are named `muos1.bin`/`muos2.bin`. With a muOS skin active, the launcher therefore gets no SIGUSR1 at shutdown [D]/[I].

---

### C. Applications and emulators (*.dge and friends)

#### C.1 Shared vendor platform layer in the emulators ("umido" layer) [G]+[D]

Function names come from symbol tables (gba_emu, md, ngp, sfc, sms, wswan, pcsx). Behaviour was traced in `gba_emu.dge`. The stripped binaries (fc, gbc, pce) carry the same strings.

| Behaviour | Detail | Evidence |
|---|---|---|
| Input | Raw evdev, not SDL events: keypad found by `EVIOCGNAME`==`ANBERNIC-keys` (falls back to `/dev/input/event1`), power/lid from `/dev/input/event0`; remap from `/mnt/data/dmenu/localpad.map`; external pads through `/sys/class/input`, RetroArch `autoconfig/udev` + `joydefCFG` | strings, `read_adc2key_thread`, `My_JoysOpen` |
| Key-mask names | From vbanext DWARF macros: UP 1<<0, DOWN 1<<1, LEFT 1<<2, RIGHT 1<<3, **A 1<<4, B 1<<5, Y 1<<6, X 1<<7, START 1<<8, SELECT 1<<9, L1 1<<10, R1 1<<11, L2 1<<12, R2 1<<13, VOLUME_UP 1<<14, VOLUME_DOWN 1<<15, MENU 1<<16, L3 1<<17, R3 1<<18** | [D] vbanext macro table |
| → applied to the W3.5 default keymap | 304→A, 305→B, 306 (BTN_C)→**Y**, 307 (BTN_NORTH)→**X**, 311 (BTN_TR)→START, 310 (BTN_TL)→SELECT, 308 (BTN_WEST)→**L1**, 309 (BTN_Z)→**R1**, 314→L2, 315→R2, 313 (BTN_TR2)→**L3**, 316 (BTN_MODE)→**R3**, 312 (BTN_TL2)→MENU, 115/114→VOL+/VOL−. This **corrects W3.5's guesses for 0x400/0x800 (L1/R1 swapped) and fills in 0x20000/0x40000 (L3/R3)**. It is the vendor's logical naming; the physical buttons are still unverified | [D]+[I] |
| Other macros | `HALL_PRESS_CODE 110`, `HALL_RELEASE_CODE 111`, `POWER_INPUT /dev/input/event0`, `ADCKEY_INPUT /dev/input/event1`, `BRIGHT_MAX_VAL 7`, `VOLUME_MAX_VAL 10`, `SOFT_VOLUME_SHIFT_BIT 14`, `BATTERY_FULL_VAL 4500`, `DRAW_BAT_DELAY 1000`, `LCD 720×480`, `HDMI 1280×720`, `H700_HDMI_STATE /sys/class/extcon/hdmi/state`, `ENCRYP_DEV …/deeplayer/debug_reg`, `EXT_RTC_DEVICE /sys/class/rtc/rtc1`, `TF_DEV_NAME /dev/mmcblk1`, `SHUTDOWN_FILE /tmp/shutdown.ini`, `KEY_PLAYER_CFG /tmp/pair.ini`. Actions-Semi leftovers (unused on H700 [I]): `BACKLIGHT_DEV /sys/class/backlight/act_pwm_backlight/brightness`, `DSP_DEVICE /dev/snd/actsnd` | [D] |
| Volume | VOL± (no MENU): level 0–10 → `volume_set` → **`tiny_set_softvolume`** (software gain in the emulator's own tinyalsa output, not the hardware mixer). Level stored in `axp2202-battery/openbor_volume` | [G] `umido_read_VolumeKey` 0x105c60, `volume_set` 0xff90c |
| Brightness | MENU+VOL±: level 0–7 → `/dev/disp` ioctl **0x102** (skipped while an HDMI flag is set); level stored in `axp2202-battery/brightness`; there is also an in-game menu item "Backlight brightness" | [G] `set_brightness` 0xff7e8 |
| Mixer at start | card 0: id1 ← 63 (`digital volume`), ids 3, 5, 8 ← 1 (`LINEOUT Switch`, `OutputL Mixer DACL Switch`, `OutputR Mixer DACR Switch`); id4 (`SPK Switch`) ← 0 on headphone/HDMI, else 1, from `jack_state`. **id2 (`lineout volume`) is not touched** (it relies on dmenu having set 31) | [G] 0xfefe8–0xff040, 0xff9e4–0xffab8; names from §E |
| HDMI | `/sys/class/extcon/hdmi/state` (dmenu uses `switch/hdmi`); output switched via `/dev/disp` like dmenu; `rtcwake` strings present | [D] |
| Sleep | Power-key release ≥100 ms → `enter_sleep_state` → `/mnt/vendor/ctrl/pwr_new.sh auto`; lid KEY 110 press/111 release handled the same way as in dmenu. **No idle-timer or `hallkey` polling** in the emulators (no "timer to sleep"/"hall to sleep" strings) | [G] 0x10b7a8–0x10b824, 0x10b5dc |
| Power-off | Power held >2000 ms → writes `1` to `/tmp/shutdown.ini` and leaves the game; the launcher then powers off (W3.5 §2.4). The emulators never call `poweroff` themselves | [G] `check_shutdown` 0x113b7c–0x113d70 |
| Low battery | USB offline and voltage ≤3420 mV for >20 one-second polls → `/tmp/shutdown.ini`=`2` | [G] `check_bat_low` 0x111f30, `check_shutdown` 0x113cb0 |
| Rumble | `axp2202-battery/moto` ← `90`/`0` | [G] `set_moto_onoff` 0xff8ac |
| TF2 | `/mnt/vendor/ctrl/mmc_new.sh add` / `mmc.sh remove` strings present | [D] |
| ION/disp | Allwinner `CdcIon*` + disp2 HWC helper. "this kernel version we no support" is the ION legacy/new ABI probe (`CdcIonIsLegacy`, `uname`), **not** a firmware lock | [D]+[I] |
| Zip ROMs | Extracts to `/tmp/allen_unzip`, cleared with `rm %s/*` (gba, vbanext, ngp, pce, wswan) | [D] |
| **deeplayer check** | `checkEncryption` → tiny-AES (`KeyExpansion`, `Cipher`, …) + `deeplay_aes_compute/parity`. It seeds `rand` from `time`, writes a challenge to `/sys/class/deeplayer/deeplayer/debug_reg`, reads the reply back and compares 16 values. **On mismatch it loops forever: `system("reboot")`, print "deeplay encryption fail,jk=%d", `sleep(2)`.** If the node can't be opened it prints "can't open deivce" and continues to the compare with a zeroed buffer, so on a kernel without the driver it is expected to hit the reboot loop [I]. One call site per binary (gba 0x105dfc in init, md 0x1a164, pcsx 0xa7d80, sfc 0x96910), so it runs once per launch. Key and transform deliberately not reproduced | [G] gba 0x110420–0x11074c |

#### C.2 Per-binary table

"dl" = contains the `deeplayer/debug_reg` check. "UL" = the umido platform layer from C.1.

| Binary | What it is (version strings) | dl | Notable hardware paths (beyond the UL set) | Input | Power / sleep / brightness / volume | External commands | Tag |
|---|---|---|---|---|---|---|---|
| game/fc/fc_emu.dge | NES: **FCEUX 2.2.3-interim svn**, built 14:20:07 Mar 24 2025 | **yes** | `/dev/vsgame` (opened, "open /dev/vsgame fail" if missing; purpose not determined) | UL | UL | `pwr_new.sh auto`, `reboot` (dl loop), `mkdir -p` | [D] |
| game/gba/gba_emu.dge | GBA: **gpSP** (requires a GBA BIOS); `game_config.txt` = gpSP per-game database (comment header + settings) | **yes** | `/proc/warm` + `/sbin/insmod %s verbose=1` (gpSP's legacy "warm" cache module loader; no module shipped [I]) | UL | UL | same + `insmod` | [D]/[G] |
| game/gba/vbanext.dge | GBA: **VBA-Next** (build tree `…/rg34xxsp/game/vba-next-portable`), with full DWARF incl. macros; saves `/mnt/data/.vbanext` | **yes** | macro leftovers above; `EVIOCGRAB` appears only as a header macro | UL | UL | same | [D] |
| game/gbc/gbcgb_emu.dge | GB/GBC: **Gambatte SDL** (`/.gambatte/…` dirs) | **yes** | — | UL | UL | same | [D] |
| game/md/md_emu.dge | MD/Genesis: **PicoDrive 1.93** (build r0, Mar 24 2025 14:28:44) | **yes** | — | UL | UL | same | [D] |
| game/ngpc/ngp.dge | NGP/NGPC: Mednafen NeoPop-derived core (`MDFNNGPC*`, `NGP_*SaveState`) | **yes** | — | UL | UL | same | [D] |
| game/sfc/sfc_emu.dge | SNES: **PocketSNES** (snes9x 1.x base; `pocketsnes/snes9x/*.cpp`) | **yes** | — | UL | UL | same | [D] |
| game/sms/smsgg_emu.dge | SMS/GG: SMS Plus SDL port (`sdlsms_init`, `sms_init`) | **yes** | — | UL | UL | same | [D] |
| game/temper/pce.dge | PC Engine: **Temper** (`temper.cfg`) | **yes** | — | UL | UL | same | [D] |
| game/wswan/swanemu.dge | WonderSwan: **Oswan** ("Starting Oswan", Mednafen-derived parts) | **yes** | — | UL | UL | same | [D] |
| game/pcsx_rearmed/pcsx | PS1: **PCSX-ReARMed r23** (build Mar 24 2025 14:33:17); `skin/` = stock pcsx skin readme + colours | **yes** | — | UL | UL | same | [D] |
| video/vp.dge | Video browser/launcher, dmenu code base (5-Dec-2025) | no | `switch/hdmi`, `hallkey`, `nds_esckey`, `nds_pwrkey`, `workled_sleep`, `/tmp/{.next,vpRun.ini,videodir.cfg,videoplace.cfg}`; roots `/mnt/{mmc,sdcard}/Video` | raw evdev like dmenu | dmenu-equivalent: power/lid/**idle timer** sleep (`pwr_new.sh auto`), 2 s hold → goodbye splash + `poweroff`, low-battery splash; `cpu_setting.sh full/user/deflt` | writes `/tmp/.next` (+`chmod 777`) to run `./FFplay.sh "<file>" [hdmi]` or `xplayerdemo2`; sets `/tmp/vpRun.ini` so `dmenu_ln` returns to vp.dge | [D]/[G] 0x1b32e |
| video/FFplay.sh | Wrapper: runs `./ffplay -fs -autoexit -vf scale=640:-2` with SDL_NOMOUSE=1, 2 channels; adds `AUDIODEV=hw:2,0` when arg 2 is `hdmi`; `sync` after | — | — | — | — | `ffplay` (not in extract; `/usr/bin/ffplay` exists in the rootfs listing, 19-May-2022) | [D] |
| video/xplayerdemo2 | Allwinner **libcedarx** demo player ("Hello xplayerdemo2"), built in an **`rg35xxsp`** tree; RPATH points to build-host paths | no | uses libVE/libcedarc (hardware decoder) + libasound; device nodes are inside the libs (not visible here) | none of its own (vp.dge handles UI) [I] | none | — | [D] |
| music/ap.dge | Music player front-end, dmenu code base (5-Dec-2025) | no | `/mnt/data/music/ap_attr.ini`, `/mnt/{mmc,sdcard}/Music`, fifo **`/tmp/mp_cmd`** | raw evdev | as vp.dge (incl. idle-timer sleep, poweroff, low battery); `cpu_setting.sh full/deflt` | drives **`/mnt/vendor/bin/music/mplayer2`** in slave mode (`-ac mad`, optional 10-band `-af equalizer`, `-vo null`, `-input file=/tmp/mp_cmd`); `setMusic.sh stop`. mplayer2 is **not in the extract** | [D]/[G] 0x1d1f6 |
| ebook/reader_mmc.dge / reader_sdcard.dge | EPUB/TXT reader; state dir `.pixel_reader_store` suggests the open-source "Pixel Reader" [I]; the two builds differ only in root (`/mnt/mmc/Ebook/` vs `/mnt/sdcard/Ebook/`) | no | `hallkey`, `voltage_now`, `axp2202-usb/online`, `/tmp/shutdown.ini`, `oem/language.ini` | SDL events + joystick, plus raw event0/event1 thread | power/lid sleep (`pwr_new.sh`, "hall to sleep"); `/tmp/shutdown.ini` on power hold [I]; no brightness/volume code | `pwr_new.sh` | [D] |
| fileM/dinguxCommand_{en,zh}.dge | DinguxCommander file manager (icons from GNOME "Humanity" theme, GPL per README) | no | `/dev/disp` (brightness 0x102 + LCD/HDMI switch helpers), `axp2202-battery/brightness`, `/dev/mmcblk0p6` (string present; use not traced), `/mnt/mmc/Roms` | SDL events + joystick, raw event0/1 | brightness restore; power-hold → `/tmp/shutdown.ini` [I]; **no sleep handling** | `popen`/`execl` (file operations) | [D] |
| pdf/green (+launch.sh, bundled libcairo 1.15.10) | "green" PDF viewer (poppler-glib + SDL1.2, GPLv3) | no | `/dev/disp`, `/dev/ion`, `extcon/hdmi/state`, `jack_state`, `axp2202-battery/brightness`, `axp2202-usb/online` | SDL events + raw evdev | `set_brightness`, `brightness_dim`, `check_shutdown` (power hold → `/tmp/shutdown.ini`); no sleep | launch.sh writes **`3` → `axp2202-battery/nds_esckey`** (disables the in-game ctrl daemons, same as dmenu does for video), then runs `green` with `LD_PRELOAD` of the bundled libcairo | [D] |

#### C.3 Tools and data

| Item | What it is | Notes | Tag |
|---|---|---|---|
| tinymixer / tinyplay | tinyalsa `tinymix` (`/dev/snd/controlC%u`) and `tinyplay` (WAV) | used by vendor scripts / factory test [I] | [D] |
| evtest | evtest 1.33, **aarch64** (the only 64-bit item here), supports `--grab` / `--query` | shipped 0777 in `/usr/bin` too (W3.6) | [D] |
| fbtest3 | Allwinner disp2/ION layer test; reads `extcon/hdmi/state`; defaults "640x480x16" LCD / "1280x720x16" HDMI; reads `/vendor/etc/cedarc.conf` log level | the 640×480 default suggests it is reused from another model [I] | [D] |
| arcade-oem.csv | UTF-8 CSV, header row with 4 columns (game zip name, Chinese name, English name, type); **419 data rows**, all with 3 columns (type empty) | name map | [D] |
| arcade-plus.csv | UTF-8 CSV, **no header**, **21 124 rows**: romname (no `.zip`), Chinese name, English/MAME description, empty 4th column (4 rows have 3 columns) | used by dmenu for arcade names (W3.5) | [D] |

#### C.4 Which binaries contain the `deeplayer` check

| Contains it | Does not |
|---|---|
| dmenu.bin (W3.5), **muos1.bin, muos2.bin**, **fc_emu, gba_emu, vbanext, gbcgb_emu, md_emu, ngp, sfc_emu, smsgg_emu, pce, swanemu, pcsx** | cexpert, vp.dge, ap.dge, xplayerdemo2, reader_*.dge, dinguxCommand_*.dge, green, tinymixer, tinyplay, evtest, fbtest3 |

---

### D. `/etc/init.d/launcher.sh` (behaviour only)

| Phase | Behaviour | Tag |
|---|---|---|
| Header | No LSB header; a commented-out sourcing of `/etc/profile` | [D] |
| Every invocation (before `case`) | If `/etc/vendor_resize.cfg` is absent (always, since the line that would create it is commented out) → `resize2fs /dev/mmcblk0p6`. This runs on start **and on stop** | [D] |
| `start` | Prints "Starting deeplay_launcher"; mounts `/dev/mmcblk0p6` ext4 `rw,noatime,nodiratime` on `/mnt/vendor`; if present, backgrounds `/mnt/vendor/bin/brightCtrl.bin` (not in any extract, so its role is undetermined) and `/mnt/vendor/bin/cexpert` (§A); backgrounds `/mnt/vendor/ctrl/loadapp.sh` in a subshell | [D] |
| `stop` / `restart` | `killall` retroarch, rtk_hciattach, loadapp.sh; SIGUSR1 to `dmenu.bin` and to `muos.bin` (wrong name, §B); SIGINT to `charg.dge` and `ndsCtrl.dge`; prints "stop deeplay_launcher"; `sync`. It does **not** stop cexpert, brightCtrl.bin, portsCtrl.dge, vp/ap or emulators, and **`restart` does not start again** | [D] |
| Other | Usage message, exit 1 for unknown args | [D] |

Consistent with W3.6 §1c; the new points are the resize running on `stop` too, `restart` = stop only, the `muos.bin` mismatch, and cexpert's role.

---

### E. ALSA `/var/lib/alsa/asound.state` (mechanically extracted) [D]

"tinymix id" = 0-based element index, as used by the stock `tinymixer_set_value(card, id, …)` calls. It assumes the kernel's element order equals the state-file order (alsactl stores by numid). That assumption is [I]; check with `tinymix -D 0`.

| Card | ctl (state #) | tinymix id [I] | Name | Type | Value | Range / items |
|---|---|---|---|---|---|---|
| audiocodec | 1 | 0 | tx hub mode | ENUMERATED | Off | Off, On |
| audiocodec | 2 | **1** | **digital volume** | INTEGER | 63 | 0–63 (dbmin −9999999, dbmax 4121460, dbvalue 4121460 — implausible TLV, as stored) |
| audiocodec | 3 | **2** | **lineout volume** | INTEGER | 31 | 0–31 (dbmin −9999999, dbmax 150, dbvalue 150) |
| audiocodec | 4 | **3** | LINEOUT Switch | BOOLEAN | true | — |
| audiocodec | 5 | **4** | **SPK Switch** | BOOLEAN | true | — |
| audiocodec | 6 | **5** | OutputL Mixer DACL Switch | BOOLEAN | true | — |
| audiocodec | 7 | 6 | OutputL Mixer DACR Switch | BOOLEAN | false | — |
| audiocodec | 8 | 7 | OutputR Mixer DACL Switch | BOOLEAN | false | — |
| audiocodec | 9 | **8** | OutputR Mixer DACR Switch | BOOLEAN | true | — |
| ahubdam | 1 | 0 | APBIF0 Src Select | ENUMERATED | NONE | NONE, APBIF_TXDIF0, APBIF_TXDIF1, APBIF_TXDIF2, I2S0_TXDIF, I2S1_TXDIF, I2S2_TXDIF, I2S3_TXDIF, DAM0_TXDIF, DAM1_TXDIF (same 10 items for all ahubdam controls) |
| ahubdam | 2 | 1 | APBIF1 Src Select | ENUMERATED | **I2S1_TXDIF** | as above |
| ahubdam | 3 | 2 | APBIF2 Src Select | ENUMERATED | NONE | as above |
| ahubdam | 4 | 3 | I2S0 Src Select | ENUMERATED | NONE | as above |
| ahubdam | 5 | 4 | I2S1 Src Select | ENUMERATED | **APBIF_TXDIF1** | as above |
| ahubdam | 6 | 5 | I2S2 Src Select | ENUMERATED | NONE | as above |
| ahubdam | 7 | 6 | I2S3 Src Select | ENUMERATED | NONE | as above |
| ahubdam | 8 | 7 | DAM0C0 Src Select | ENUMERATED | NONE | as above |
| ahubdam | 9 | 8 | DAM0C1 Src Select | ENUMERATED | NONE | as above |
| ahubdam | 10 | 9 | DAM0C2 Src Select | ENUMERATED | NONE | as above |
| ahubdam | 11 | 10 | DAM1C0 Src Select | ENUMERATED | NONE | as above |
| ahubdam | 12 | 11 | DAM1C1 Src Select | ENUMERATED | NONE | as above |
| ahubdam | 13 | 12 | DAM1C2 Src Select | ENUMERATED | NONE | as above |
| ahubhdmi | 1 | 0 | loopback debug | BOOLEAN | false | — |
| ahubhdmi | 2 | 1 | audio data format | ENUMERATED | PCM | NULL, PCM, AC3, MPEG1, MP3, MPEG2, AAC, DTS, ATRAC, ONE_BIT_AUDIO, DOLBY_DIGITAL_PLUS, DTS_HD, MAT, DST, WMAPRO |

Every control has `iface MIXER` and `access 'read write'`, count 1. Three cards: `audiocodec`, `ahubdam`, `ahubhdmi`. If card order matches the file, `ahubhdmi` is card 2, which fits `AUDIODEV=hw:2,0` [I]. The ahub routing (APBIF1 ← I2S1 TX, I2S1 ← APBIF TX1) is the HDMI audio path in the BSP AHUB driver [I].

**This resolves the W3.5 "not determined" item for card-0 ids:** id1 = `digital volume` (launcher sets 63), id2 = `lineout volume` (the in-game daemons' 0–31 volume), id3 = `LINEOUT Switch`, id4 = `SPK Switch` (the headphone mute, as W3.5 guessed), id5 = `OutputL Mixer DACL Switch`, id8 = `OutputR Mixer DACR Switch` [D]+[I].

---

### F. `/lib/udev/rules.d` (76 files, names only)

| Group | Files | Origin (Ubuntu 22.04) |
|---|---|---|
| udev | 40-vm-hotadd, 50-firmware, 50-udev-default, 60-autosuspend, 60-block, 60-cdrom_id, 60-drm, 60-evdev, 60-fido-id, 60-input-id, 60-persistent-alsa, 60-persistent-input, 60-persistent-storage, 60-persistent-storage-tape, 60-persistent-v4l, 60-sensor, 60-serial, 61-persistent-storage-android, 64-btrfs, 70-joystick, 70-memory, 70-mouse, 70-power-switch, 70-touchpad, 71-power-switch-proliant, 73-special-net-names, 75-net-description, 75-probe_mtd, 78-graphics-card, 78-sound-card, 80-debian-compat, 80-drivers, 80-net-setup-link, 81-net-dhcp | Confirmed against the jammy `udev` 249.11-0ubuntu3 file list ([aptpeek](https://aptpeek.dev/ubuntu/jammy/main/armhf/udev/249.11-0ubuntu3)) |
| systemd | 70-uaccess, 71-seat, 73-seat-late, 99-systemd | `systemd` package [I, standard] |
| dmsetup | 55-dm, 60-persistent-storage-dm, 95-dm-notify | [I, standard] |
| ModemManager | 77-mm-* (23 files), 80-mm-candidate | [I, standard] |
| NetworkManager | 84-nm-drivers, 85-nm-unmanaged, 90-nm-thunderbolt | [I, standard] |
| Others | 39-usbmuxd (usbmuxd), 40-usb_modeswitch (usb-modeswitch-data), 66-snapd-autoimport (snapd), 90-alsa-restore (alsa-utils), 90-console-setup (console-setup), 95-upower-hid / 95-upower-wup (upower), 96-e2scrub (e2fsprogs) | [I, standard] |

**No file name is non-standard.** No vendor rule (sunxi, mmc, anbernic, joystick remap) exists, which confirms that card hot-plug is cexpert's job (§A). **What can't be judged:** only names were supplied, so modified *contents* of any of these 76 files can't be ruled out (`debsums`/`dpkg --verify` on a unit would settle it). Origins marked [I] were not checked against a package list.

---

### G. ufw

*Security findings held privately (Dale).*

---

### H. New findings (conservative; [N] = I believe no public source exists. Based on one quick web search for the deeplayer path that found nothing relevant, not an exhaustive search)

1. **[N]** `cexpert` is a netlink-uevent block hot-plug daemon (udev `ID_FS_TYPE` + `SUBSYSTEM=block` → `mmc_new.sh add/remove`), not an "Expert Mode" or CPU tool. Any filesystem-bearing block device, including USB or loop devices, triggers a TF2 mount/unmount.
2. **[N]** The `deeplayer` anti-clone check is also inside **every stock emulator** (AES-based `checkEncryption`, once per launch, endless 2-second reboot loop on failure), and in muos1/muos2. The media apps, reader, file manager and PDF viewer don't have it.
3. **[N]** `vbanext.dge` leaks the vendor platform header through DWARF macros: logical names of every key-mask bit (this corrects W3.5's L1/R1 guess and adds L3/R3), lid codes 110/111, `BATTERY_FULL_VAL 4500`, `/tmp/pair.ini`, and Actions-Semi leftovers (`act_pwm_backlight`, `/dev/snd/actsnd`).
4. **[N]** The stock emulators handle VOL± themselves as **software gain** (0–10, Q14) and leave `lineout volume` (id2) untouched; MENU+VOL± uses `/dev/disp` 0x102; power hold and low battery hand off to the launcher through `/tmp/shutdown.ini`.
5. **[N]** muos1/muos2 are dmenu re-skins (res3/res4) with identical hardware logic. Style switching goes through `/mnt/vendor/muos{1,2}.ini`; muos2 adds `/tmp/mnos.ini` UI state. `launcher.sh stop` signals the non-existent `muos.bin`.
6. **[N]** `ap.dge` is a front-end for `/mnt/vendor/bin/music/mplayer2` in slave mode through the fifo `/tmp/mp_cmd`; `xplayerdemo2` is the libcedarx demo built from an RG35XXSP tree; the PDF viewer `green` sets `nds_esckey`=3 from its launch script.
7. Not new, but resolved here: card-0 tinymix ids 1/2/3/4/5/8 = digital volume / lineout volume / LINEOUT Switch / SPK Switch / OutputL DACL / OutputR DACR (control names are public in the BSP; the id mapping is from §E).

---

### Optional device checks (stock unit; read-only unless noted)

```sh
pgrep -a cexpert; pgrep -a brightCtrl; ls -l /mnt/vendor/bin/{cexpert,brightCtrl.bin}
udevadm monitor --udev --property --subsystem-match=block   # insert/remove TF2 and a USB stick; confirm ID_FS_TYPE events
ls /mnt/vendor/muos*.ini /mnt/vendor/res3 /mnt/vendor/res4 2>&1; cat /tmp/mnos.ini 2>/dev/null
cat /proc/asound/cards; tinymix -D 0                        # confirm id1=digital volume, id2=lineout volume, id4=SPK Switch
ls -l /sys/class/deeplayer/deeplayer/ 2>&1                  # do not write to it
ls -l /mnt/vendor/bin/music/mplayer2 /mnt/vendor/bin/video/ffplay /usr/bin/ffplay 2>&1
evtest   # on ANBERNIC-keys: map each physical button to its code; compare with the C.1 logical names
dpkg -S /lib/udev/rules.d/*.rules | sort; debsums -c udev systemd 2>/dev/null   # package ownership and modified files
cat /sys/class/extcon/hdmi/state /sys/class/switch/hdmi/state 2>&1   # both HDMI paths used by different binaries
```

### Keep / stop for a replacement firmware (Redux)

| Item | Keep / stop | Why |
|---|---|---|
| TF2 hot-plug auto-mount | **Keep the function, replace the mechanism**: a udev rule + systemd mount unit (or udisks), keyed on the specific device (mmcblk1/2), not on "any block device with a filesystem" | cexpert runs root shell commands for every block event and unmounts TF2 when a USB stick is removed |
| Stock emulators / muos / dmenu on a Redux kernel | **Stop**: don't ship or run them on a kernel without the vendor `deeplayer` driver | Endless reboot loop (C.1, C.4) |
| vp/ap/reader/dinguxCommander/green | Reusable only on the BSP stack (they need `/dev/disp`, ION, `axp2202-*` vendor attributes); otherwise replace them | no deeplayer, but BSP-bound [I] |
| Mixer defaults (BSP kernel) | **Keep**: `digital volume` 63, `lineout volume` as the user volume (0–31), `SPK Switch` driven by jack state, LINEOUT and the DACL→L / DACR→R switches on, ahubdam APBIF1↔I2S1 routing and ahubhdmi format PCM for HDMI audio | §E, C.1 |
| One volume mechanism | **Stop** mixing software gain (emulators, launcher) with hardware `lineout volume` (ctrl daemons) | stock levels drift between apps |
| Key naming | **Keep** the logical mapping in C.1 as the starting point for a Redux keymap; verify physically with evtest | vendor naming, not device-verified |
| `/tmp/shutdown.ini` hand-off, `nds_esckey` gating | **Stop**: use a proper power-key service (logind or a daemon) and a userspace state file instead of vendor sysfs attributes as IPC | fragile, root-only |
| launcher.sh resize on every invocation, `restart` = stop only, `muos.bin` typo | **Stop** (don't copy) | §D |
| udev rules | Nothing vendor-specific to carry over | §F |

### Tool installs

None. Only the preinstalled python3, strings, file, readelf, arm-linux-gnueabi-objdump and `/home/claude/re-tools/annot.py` were used, plus two helper scripts in `/tmp/gwscripts/` (a feature matrix and an ARM movw/movt resolver; scratch files, not deliverables).

## Device-verified (Redux 2026-11-17, stock, Dale's v1.0 2 GB unit) [V]
- `/mnt/mod/ctrl/configs/led_exit.cfg` and `led_launch.cfg`, from which stock `dmenu_ln` writes `work_led`, **don't
  exist** on Dale's unit; `moto` appears only inside emulator binaries (Redux note `2026-11-17-dale-hw-result-7ee31d1.md` #11).
- Filesystem state on the stock card (`fsck -n`, mounted, read-only; `…-2917a5c.md` #2, `…-070427e.md` #4): p5
  `linuxrootfs`, p6 `appfs`, p7 clean. p1 (FAT32) exits 1 only for the dirty/in-use flag (boot-sector offset 65,
  byte 0x41: 01 vs backup 00) while mounted, 29,670 files. TF2's p1 reports "Weird DATE" (rest of the output cut).
