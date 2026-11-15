# G4: stock battery gauge and charger (Ghidra plan, 2026-11-15)

Kernel Research chat, desk only. Stock V1.0.6 kernel `4.9.170 #9` (names from kallsyms) and its DT. The PMIC is
the X-Powers AXP717 (stock driver name `axp2202`; mainline register names from `include/linux/mfd/axp20x.h`,
torvalds/linux master, read 2026-11-15). Tags: **[G]** static analysis of the stock kernel, **[D]** device
tree / strings / mainline source, **[V]** none yet. Register numbers and values only; no code reproduced.

## Answer
- **Battery % is the PMIC's own fuel gauge**, not a kernel OCV table or coulomb counting in software [G]: the
  driver reads register `0xA4` (`AXP717_BATT_PERCENT_DATA`), clamps it to 100 and shows 99 % as 100 % when the
  status is "full". Mainline's `axp20x_battery` reads the same register [D].
- At probe the stock driver **loads a 128-byte battery model into the gauge** (DT node `axp2202-parameter/
  battery-model`, property `parameter`; written byte by byte to `0xA1` with a handshake on `0xA2`) [G][D][N].
  **Mainline has no code for this** [D]; whether the gauge keeps the model across a mainline boot (it lives in
  the always-powered PMIC) is a device check.
- The 32 `pmu_bat_para*` values (an OCV curve) and `pmu_battery_rdc` in the stock DT are **not read by the
  kernel** (no such strings) [G][N]; if anything uses them it is the bootloader.
- **Charge current is 1472 mA, not 1500** [G][N]: the driver writes `mA >> 6` into `0x62` (64 mA steps, rounded
  down), capped at 3072 mA; DT asks for 1500 mA (`0x5DC`) in run, suspend and shutdown. Mainline uses 1024 mA
  (Q5).
- **Charge voltage 4.10 V** [G]: DT `pmu_init_chgvol = 4100` → `0x64` field 1 (thresholds below), the same cap
  as our mainline tree.
- **Low-battery warnings** [G][N]: register `0x1B` = (level1 − 5) in the high nibble, level2 in the low nibble;
  DT level1 = 15 %, level2 = 0 (off) → `0xA0`.
- **Gauge sanity fix at probe** [G][N]: if the gauge reports > 60 % but the battery voltage (`0xC4/0xC5`, 14-bit)
  is below 3500 mV, the driver resets the gauge MCU and sets `0x0C = 0x81`; while bit 7 of `0x0C` is set,
  the reported % comes from `0x0C`'s low 7 bits instead of `0xA4` (`axp2202_get_soc`).
- Battery temperature sensing is **off** (`pmu_bat_temp_enable = 0`, `TS_PIN_CFG 0x50` bit 4) [G][D]; JEITA off.

## Data table 1: registers the stock driver uses
| Reg | Mainline name | Stock use [G] |
|---|---|---|
| 0x0C | (not named) | Gauge override/flag: bit 7 set → % from bits 6:0; written 0x81/0 at probe |
| 0x19 | `AXP717_MODULE_EN_CONTROL_2` | bit 1 updated by the power monitor (depends on % and the charge-voltage setting) |
| 0x1B | (not named) | Low-battery warning levels (see above) |
| 0x50 | `AXP717_TS_PIN_CFG` | TS pin / temperature sense enable (bit 4) |
| 0x54–0x57 | (not named) | TS thresholds: charge LTF/HTF, shutdown LTF/HTF (from DT) |
| 0x58, 0x59, 0x5A, 0x5B | (not named) | JEITA enable, current fall, cool, warm (from DT) |
| 0x61 | (not named; precharge) | bits 3:0 = 2 |
| 0x62 | `AXP717_ICC_CHG_SET` | Charge current, `mA >> 6`, max 0xC00 mA |
| 0x63 | `AXP717_ITERM_CHG_SET` | Termination current, `mA >> 6` (default 128 mA → 2) |
| 0x64 | `AXP717_CV_CHG_SET` | Charge voltage field (table 2) |
| 0x70 | (not named) | Low 3 bits set from a DT option when enabled |
| 0xA1, 0xA2 | (not named) | Gauge model data port and control (bit 0 write mode, bit 4 model valid) |
| 0xA4 | `AXP717_BATT_PERCENT_DATA` | Battery % |
| 0xB0, 0xB2 | (not named) | Power monitor: writes 0xB0 = 0x2E, reads two bytes at 0xB2 when model valid |
| 0xC4–0xC5 | `AXP717_BATT_V_H/L` | Battery voltage (mV, 14 bit) |

## Data table 2: charge voltage field (`0x64` bits 2:0) [G]
| DT `pmu_init_chgvol` (mV) | Field |
|---|---|
| < 4100 | 0 |
| 4100–4199 | **1 (stock: 4100)** |
| 4200–4349 | 2 |
| 4350–4399 | 3 |
| 4400–4999 | 4 |
| ≥ 5000 | 7 |

## Data table 3: stock DT battery properties (`bat-power-supply`) [D] and whether the kernel reads them [G]
Driver defaults are what `axp2202_bat_dt_parse` uses when a property is missing (paired heuristically).
| Property | Stock DT | Read by kernel | Driver default |
|---|---|---|---|
| `pmu_battery_cap` | 3300 mAh | yes | 4000 |
| `pmu_battery_rdc` | 170 mΩ | **no** | – |
| `pmu_runtime_chgcur` / `suspend` / `shutdown` | 1500 / 1500 / 1500 mA | yes | 500 / 1200 / 1200 |
| `pmu_prechg_chgcur`, `pmu_terminal_chgcur` | (absent) | yes | 100, 128 mA |
| `pmu_init_chgvol` | 4100 mV | yes | 4200 |
| `pmu_battery_warning_level1` / `level2` | 15 % / 0 | yes | 15 / 0 |
| `pmu_chgled_func` / `type` | 0 / 0 | yes | 1 / 0 |
| `pmu_bat_temp_enable` | 0 | yes | 0 |
| `pmu_bat_charge_ltf` / `htf`, `pmu_bat_shutdown_ltf` / `htf` | 0x69F / 0x97, 0x84D / 0x83 | yes | 0x520 / 0xB0, 0x7C0 / 0x98 |
| `pmu_jetia_en`, `cool`, `warm`, `jcool_ifall`, `jwarm_ifall` | 0, 0x551, 0xD0, 0, 0 | yes | 0, 0x370, 0xF0, 1, 0 |
| `pmu_bat_temp_para1`–`16` | 0x111A … 0x53 (NTC curve) | yes | 0 |
| `pmu_bat_para1`–`32` | 0,0,0,0,0,0,2,3,4,6,9,14,26,38,49,52,56,60,64,70,77,83,87,90,95,99,99,100,100,100,100,100 (%) | **no** | – |
| `work_led`, `low_pwr_led` | PI12, PI11 | `low_pwr_led` yes; no `work_led` property string (the driver logs a work-LED pin) | – |
| `moto_pwm_gpio` | PH2 | see G6 | – |
| `param` | → `axp2202-parameter` | yes (model, table 4) | – |

## Data table 4: gauge model (`/axp2202-parameter/battery-model`, `parameter`, 128 bytes) [D]
Written in DT order to `0xA1`; first bytes `01 F5 40 00`. Full value (32 cells):
```
0x01F54000 0x1B1E280F 0x0C1E3202 0x14050A04 0x74FBE10D 0x431036FB 0x4B01EA0A 0x88063606
0x0D0AD50F 0x670F0E09 0xB80E5B0E 0x54044604 0x39092E0E 0x1E0E1809 0x0A0DED0D 0xE403CE03
0xB408990D 0x830D6A07 0xED743D34 0x28151B0E 0xC5987E66 0x4E44381A 0x120AF600 0x00F600F6
0x00FB0000 0xFB0000FB 0x0000F600 0x00F600F6 0x00FB0000 0xFB0000FB 0x0000F600 0x00F600F6
```

## Data table 5: stock functions (V1.0.6) [G]
`axp2202_battery_probe` (…8649220: model load, charger setup, gauge check), `axp2202_bat_dt_parse` (…86489c4),
`axp2202_get_soc` (…86471b0), `axp2202_set_ichg` (…8645ed8), `axp2202_bat_power_monitor` (…8646c6c),
`axp2202_bat_power_curve_monitor` (…86469d0, reads and updates the `0x0C` override), `axp2202_reset_mcu` (…8646bb0),
`axp2202_bat_suspend` / `resume` (…8648228 / …864815c), `store_brightness` / `store_os_sleep` (battery sysfs,
see Redux map and G1).

## For mainline and Redux
- Mainline reads the same % register, so percent should match stock **if the model stays loaded**. If device check 2
  shows a drift, a small mainline change would be needed to load the model (no upstream support today).
- Redux on stock: the % Redux shows is the gauge value as stock shows it; no correction needed.

## Device checks (optional)
1. Stock: `cat /sys/class/power_supply/axp2202-battery/{capacity,voltage_now,constant_charge_current}`
   while charging (expect about 1472 mA if exposed).
2. % vs voltage at three points (full, about 50 %, about 15 %) on stock; later the same on mainline (K23).
3. Low-battery warning appears at 15 % on stock.
