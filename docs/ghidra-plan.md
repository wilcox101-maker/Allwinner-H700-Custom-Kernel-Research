# Ghidra plan: stock firmware reverse engineering

Landed by the Kernel Research chat from the Redux Manager's `FROM-REDUX-MANAGER-2026-11-15-e.md`
(Dale, 2026-11-15 01:54: "Roll out Ghidra testing plan and document."). Plan text unchanged below.
Status: **Wave 0 and Wave 1 done 2026-11-15** (desk; results sent to Redux as KR package m, see "Results" at the end).
**Amended 02:31** (below): Wave 2 no longer waits for Beta, new Wave 3, items split between KR and DR.
Stock binaries and the Ghidra project stay on DLN-DALEW2 (`REA\BootImage`); never in this repo.

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

## Amendment 2026-11-15 02:31: full scope (`FROM-REDUX-MANAGER-2026-11-15-f.md`, text unchanged)
**Manager advice, not a command.** Dale, 02:31: "Skip LZO. Leverage reverse engineering to find all the data
possible." So: no LZO support; Wave 2 is no longer held for Beta (it is desk research, nothing ships in Redux
until Beta); a new Wave 3 covers the rest of the stock firmware. Split between KR and DR to run in parallel.


### Ground rules (unchanged, plus one)
Desk only; stock files read, never written, never committed; record names, addresses, constants, tables
and behaviour, **never decompiled code**; tag [G]/[D]/[V]; each item ends with optional device checks.
**New:** for every item, also list the data that can be pulled mechanically (tables, enums, attribute
names, ioctl numbers) as a table in the doc: that is the "all the data" part.

### Who does what
| Chat | Items (in order) |
|---|---|
| **KR** (kernel and modules) | G0.1–G0.4 (G0.2 with `vmlinux-to-elf`, no LZO) → G1 sleep → G2 CPU grades → G4 battery gauge → G5 audio → G6 rumble → W3.1 → W3.2 → W3.3 |
| **DR** (boot chain and userspace) | G3 u-boot panel select → W3.4 → W3.5 → W3.6 |

### Wave 3: everything else in the stock firmware
| Id | Target | Data to extract | Feeds |
|---|---|---|---|
| W3.1 | Kernel, after kallsyms naming | **Inventory tables:** every sysfs attribute (driver, path, R/W, range check), every `/dev/disp` ioctl (number, name, arguments), module parameters, input key codes per driver | Redux features (display, input), mainline gaps |
| W3.2 | Kernel modules in the stock rootfs (`mali_kbase.ko`, `8821cs.ko`, others in `/lib/modules`) | GPU DVFS table and voltages; Wi-Fi module parameters (power save, country); any board-specific module | Mainline GPU/Wi-Fi, Redux battery life |
| W3.3 | Stock DT, full | Every node the stock kernel uses vs the mainline SP tree: pins, regulators, clocks, thermal trips, GPU OPPs (a diff table) | Mainline DT patches |
| W3.4 | Boot package (TOC at 16,400 KiB): u-boot, **ATF bl31, SCP (AR100) firmware** | ATF version and PSCI functions offered; SCP suspend/standby flow and wake sources; u-boot env, bootcmd, DT fix-ups | G1 (real suspend), mainline boot chain |
| W3.5 | Stock launcher `dmenu.bin` and the shell scripts it uses (`pwr_new.sh` etc.) | Hotkey map, sleep/lid/power-key policy, brightness and volume steps, battery % shown, files and sysfs paths it touches | Redux parity checks (F4/F5), Redux sleep behaviour |
| W3.6 | Other stock userspace daemons and `/etc` config | Services started at boot, what each one writes (to find anything Redux must keep or stop) | Redux installer and safety |

### Checkpoints
- KR still stops and asks (DECIDE) before installing anything else.
- One item per PR; each PR's doc section is the record; results that change Redux go to the Owner as a
  `FROM-REDUX-KERNEL-*` (KR) or `FROM-REDUX-DEEP-*` (DR) package. Redux code changes wait for Beta.
- Each chat HALTs when its list is done, or earlier if its chat gets long (SWAP rule: ~25 PRs or entries).

## Results (Kernel Research, 2026-11-15)
Full text: Redux `docs/kernel-research/stock-kernel-ghidra.md` via KR package m (`FROM-REDUX-KERNEL-2026-11-15-m.md`).
| Id | Result |
|---|---|
| G0.1 | `…815a2b0` = `printk` (kallsyms); renamed by `ReduxApplyKallsyms.java` (tested on a project copy, export shows `printk`). Dale's own project changes when he runs the script (optional). |
| G0.2 | `tools/kallsyms_49.py` (stdlib): 90,760 symbols; **36,849 of 36,849** functions named (36,271 exact, 578 split pieces); 17/17 spot checks reference their own `__func__`; 480 earlier guessed names corrected. Why attempt 1 failed: 256-byte padding between tables and `relative_base` = 0 in a relocatable Image. Cross-checked with `vmlinux-to-elf` 1.4.0 (Dale's decision, 2026-11-15 02:22): identical list, 0 differences; its ELF is a new file in Dale's `REA\BootImage\kallsyms`. |
| G0.3 | `adc_cal` (0644) + `amux_debug` on the stock `gpio-keys-polled` device (`/soc@03000000/gpio_keys`) [G][D]. |
| G0.4 | Backlight row and open questions 13/14 updated (in the package). |
| G1 | Real suspend-to-RAM: `mem` → PSCI `SYSTEM_SUSPEND` to BL31 + `arisc`, registered only if firmware supports it; no `mem_sleep` in 4.9; wake: power key, lid (when power-key wake is on), RTC, `time_to_wakeup_ms`; `os_sleep` switch turns power-key/lid wake off [G][D]. Device checks listed in the package. |

For mainline (deep suspend, K6): stock relies on firmware `SYSTEM_SUSPEND`; deep `mem` on mainline needs it too, from our
TF-A build (R1; not checked yet), and the lid wake becomes a `SW_LID` wake source in the board tree.

| Wave 2 | Result |
|---|---|
| G2 | [`ghidra-g2-cpu-grades.md`](ghidra-g2-cpu-grades.md): fuse → stock bin → mainline `speedN` table; for 4 fuse values (0x2C00, 0x5D00, 0x6000, unknown) mainline allows a higher step than stock. |
| G4 | [`ghidra-g4-battery-gauge.md`](ghidra-g4-battery-gauge.md): % comes from the PMIC gauge (reg 0xA4), stock loads a 128-byte gauge model mainline doesn't; 1472 mA charge (64 mA steps), 4.10 V, warnings at 15 %. |
