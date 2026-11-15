# Ghidra plan: stock firmware reverse engineering

Landed by the Kernel Research chat from the Redux Manager's `FROM-REDUX-MANAGER-2026-11-15-e.md`
(Dale, 2026-11-15 01:54: "Roll out Ghidra testing plan and document."). Plan text unchanged below.
Status: Wave 0 and Wave 1 assigned to KR 2026-11-15; Wave 2 waits for Dale's GO after Beta.
Stock binaries and the Ghidra project stay on DLN-DALEW2 (`REA\BootImage`); never in this repo.

## New findings
Findings with no public source we know of, tagged **[N]** in the result docs (Dale, 2026-11-15 02:46). Repo only;
not published elsewhere. KR adds its own entries here.

| Item | Finding | Tag | Where |
|---|---|---|---|
| G3 | Stock u-boot hands the panel choice to the kernel **only** as cmdline `lcd_type=boe\|old` (env_set → builder 0x4A005734); no kernel-DT edit, not stored in env | [G][N] | `stock-re-boot-and-userspace.md` G3 |
| W3.4 | Stock BL31 `v1.0(debug):5a77824` offers PSCI 1.0 incl. `SYSTEM_SUSPEND`; no SCP firmware; standby runs in BL31 and `arisc_set_wakeup_source` is emulated as a local GIC-IRQ bitmap | [G][N] | W3.4 |
| W3.5 | `dmenu.bin` runs a challenge–response with a vendor `deeplayer` kernel driver every 500 ms and loops `reboot` on failure: the stock launcher can't run on a kernel without it | [G][N] | W3.5 |
| W3.5 | "Fast Shutdown" = `echo 0x1801 > /sys/class/axp/axp_reg` (meaning of AXP reg 0x18 bit 0 unknown) | [D][N] | W3.5 |
| W3.6 | `loadapp.sh` runs `mkfs.ext4` on p7 / `mkfs.vfat` on p1 or p8 at boot when blkid finds no type **or** the mount fails | [D][N] | W3.6 |
| W3.6 | Every unit ships the same SSH host private keys; sshd allows root + password login; dnsmasq DHCP on wlan0 enabled | [D][N] | W3.6 |

Owner: Redux Manager (plan) · Executor: Kernel Research chat · Results: Redux
`docs/kernel-research/stock-kernel-ghidra.md` (stock behaviour Redux depends on) and this repo (mainline work).

## Ground rules
- Desk only. Stock images and binaries are read, never written. No device work by agents.
- Record names, addresses, constants and behaviour only. **Never reproduce decompiled Anbernic/Allwinner code.**
- Addresses are for the V1.0.6 build (`4.9.170 #9 … May 26 2026`) unless stated.
- Tag every claim: **[G]** Ghidra, **[D]** DT/strings/config, **[V]** device-verified (only from a Dale
  hw-result note). Nothing is called "verified" without [V].
- Each item ends with its device checks, written as *optional* lines for the Redux Device test queue.
- Reports: result first, at most 5 lines; detail goes in the doc.

## Inputs
- Ghidra 12.2 project on DLN-DALEW2: `REA\BootImage\ghidra-project\RG34XXSP-V106-kernel` (kernel `Image`,
  raw AArch64 at `0xffffff8008080000`).
- For G3: the u-boot boot package from the V1.0.6 image (TOC at 16,400 KiB), imported as a new program.
- Stock DTB from the same `boot.img` (`dtb.dts`).

## Wave 0: housekeeping (now; small)
| Id | Task | Done when |
|---|---|---|
| G0.1 | Rename `…815a2b0` to `printk` (mislabelled as `axp2202_battery_probe`); re-export. | Export shows `printk`; map's correction note closed. |
| G0.2 | **Name all functions** from kallsyms (open question 14): second attempt with a stdlib reader for the 4.9 base-relative tables (`kallsyms_offsets`, `relative_base`, `num_syms`, `names`, `token_table`, `token_index`). | ≥ 30,000 of 36,849 functions named; 20 known names spot-checked against `__func__` names. If the reader fails again, stop and ask Dale (DECIDE) about installing `vmlinux-to-elf`. |
| G0.3 | Trace the sysfs file behind `joypad_store_adc_cal` (stick recentre). | Path and attribute name recorded [G]; optional device check: write 1 with sticks at rest. |
| G0.4 | Doc fixes: backlight row in the map still says "real max between 20 and 254" (resolved: 0–100 slot, `/dev/disp` is the control); Redux open question 13 is answered. | Lines to change sent to the Owner in the package. |

## Wave 1: sleep path (now; helps Redux F4/F5 and H700 deep suspend)
| Id | Question | Leads | Done when |
|---|---|---|---|
| G1 | What does stock do on sleep: real suspend-to-RAM (PSCI `SYSTEM_SUSPEND` via ATF/SCP), Allwinner "scene"/dynamic standby, or screen-off idle? Which `/sys/power/state` and `mem_sleep` modes exist, what are the wake sources (power key, lid, RTC, USB, charger), and what do the display/PWM standby hooks do? | `wakeup_reason_init`, `disp_register_standby_func`, `disp_suspend`/`resume`, `sunxi_pwm_suspend`, `cpufreq_suspend`, `platform_suspend_ops` users, `psci_*`, "scene"/"standby" strings; SDK path `dynamic_standby` | One section in the map: mode(s), call order, wake sources, each tagged [G]/[D]; device checks listed: `cat /sys/power/state /sys/power/mem_sleep`, `cat /sys/kernel/debug/wakeup_sources` (if present), battery % before/after 30 min asleep. |

## Wave 2: Phase 2, after Beta (do not start before Dale's Beta sign-off)
| Id | Question | Done when | Feeds |
|---|---|---|---|
| G2 | **CPU grade mapping:** how stock reads the chip bin (SID/efuse read, `dev_pm_opp_of_*_by_soc_bin`) and how that maps to mainline `speed0`–`speed5` (cpufreq-nvmem sun50i). | Table stock bin ↔ mainline speed grade, with sources; device check: read the bin/SID on Dale's unit (with Redux queue 13 `scaling_available_frequencies`). | K22 stress test, Redux CPU table decision |
| G3 | **Panel selection in stock u-boot:** which straps/pins u-boot reads (PE straps → `lcd_type`), and how it tells the kernel which panel (`rg34xxsp_v1` vs the original). | Pins, values, mapping and hand-off (DT edit / cmdline / env) recorded. | Mainline "identify the panel before driving it" (open question 3) |
| G4 | **Battery gauge:** how `axp2202` computes percent (OCV table vs coulomb counter), charge-current set points, low-battery thresholds; DT vs code. | Values and where they're set; device check: reported % vs voltage at 3 points. | Redux battery %, R13's 1024 mA figure |
| G5 | **Audio jack and speaker amp:** jack GPIO and debounce, PA enable order (`snd_sunxi_jack_*`, `snd_sunxi_pa_pin_init`). | Pins and sequence recorded. | Mainline audio DT |
| G6 | **Rumble:** is the motor driver enabled in the SP's DT, and on which PWM? | DT answer [D]; optional device check if a stock app vibrates. | Redux feature list |

## Order and checkpoints
G0.1 → G0.2 (DECIDE if it fails) → G0.3 → G0.4 → G1 → package to Redux → **HALT**.
Wave 2 starts only on Dale's GO after Beta, one item per PR, each followed by its package.
The weekly audit checks the tags: a [V] without a hw-result note is an S1 finding.
