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
