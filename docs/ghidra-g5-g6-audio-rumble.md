# G5 + G6: stock audio (jack, speaker amp, mixer) and rumble (Ghidra plan, 2026-11-15)

Kernel Research chat, desk only. Stock V1.0.6 kernel `4.9.170 #9` (names from kallsyms), its DT, and mainline
for comparison (torvalds/linux master, read 2026-11-15: `sun50i-h616.dtsi`, `sun50i-h700-anbernic-rg35xx-2024.dts`;
our `dts/sun50i-h700-anbernic-rg34xx-sp*.dts`). Tags: **[G]** static analysis of the stock kernel, **[D]** device
tree / strings / mainline source, **[V]** none yet. Names, addresses, constants and behaviour only; no code reproduced.

## Answer
- **Headphone detect** [G][D]: GPIO **PI3** (`hp-det-gpio`), interrupt on **both edges**, **200 ms** debounce
  (the IRQ work sleeps 200 ms, then re-reads the pin; a 200 ms scan also runs once at init). Same pin as mainline
  (`hp-det-gpios = PI3`).
- **Speaker amp** [G][D]: enable pin **PI5** (`pa-pin-0`, active high, `pa-pin-level-0 = 1`), one pin
  (`pa-pin-max = 1`). Enable = **wait 100 ms (`pa-pin-msleep-0`), then drive the pin**; disable = drive the inverse
  level at once, no wait. Same pin as mainline (`allwinner,pa-gpios = PI5`); mainline has no delay (our patches
  0002/0003 add `allwinner,pa-delay-ms = 100`).
- **Headphones mute the speaker in the kernel** [G]: the jack work calls `allen_spk_ctrl`, which turns the amp
  pin off while the detect pin reads "plugged" and on when unplugged; state in `allen_spk_state`, readable as
  `/sys/class/power_supply/axp2202-battery/spk_state` (0444). Line out itself always plays (the board routes
  speaker and jack from the same LINEOUT through a 74HC4052 mux, per mainline's comment).
- **Amp power** [G][D]: regulator named by DT `allen_amp_power = "axp2202-cldo1"`, set to **3.3 V** and enabled
  at codec probe. Codec analog supply `avcc` = `axp2202-aldo4` at **1.8 V** (`avcc-vol`).
- **Mixer** [G]: the stock card `audiocodec` exposes `digital volume` (0–63, inverted, reg 0x00 bit 12,
  −1.16 dB steps) and `lineout volume` (0–31, reg 0x310, 0 = mute, 1 = −43.5 dB … 31 = +1.5 dB, 1.5 dB steps;
  DT default 31), plus DAPM mixer switches and the pin switches `LINEOUT` and `SPK`.
- **Rumble (G6)** [G][D]: the motor is driven by **PWM channel 2 on PH2** (DT pin group `pwm2@0`, function
  `pwm2`), **period 500,000 ns (2 kHz)**, duty = level % of the period. The PWM is requested by the **battery
  driver**, not a motor driver. Two ways in: the joypad input device (`ANBERNIC-keys`) advertises
  **`EV_FF`/`FF_RUMBLE`** (memless): strong magnitude × 100 / 32768 → %, values below 37 % become 0; and sysfs
  **`/sys/class/power_supply/axp2202-battery/moto`** (0644, write 0–100). Allwinner's own motor driver
  (`sunxi_motor_*`, node `motor_para`) is built in but **unused: the stock DT has no `motor_para` node**.
  Whether the RG34XX-SP has a motor at all is still K13; the DT and driver are shared across the family.
- **Mainline gap**: `sun50i-h616.dtsi` has no PWM controller node yet (the display-layer series pins one, R19);
  rumble on mainline needs that plus a `pwm-vibrator` node on PWM2/PH2 and K13's answer.

## Data table 1: codec node `codec@0x05096000` (`allwinner,sunxi-snd-codec`) [D], read by kernel [G]
| Property | Stock value | Read by kernel | Meaning / driver default |
|---|---|---|---|
| `reg` | 0x05096000, size 0x31C | yes | same block as mainline `codec@5096000` |
| `allen_amp_power` | `"axp2202-cldo1"` | yes | amp supply; set to 3.3 V, enabled |
| `avcc-external` | present | yes | use an external avcc regulator |
| `avcc-supply` / `avcc-vol` | → `axp2202-aldo4` / 1,800,000 µV | regulator `avcc` / yes | default 1.8 V |
| `lineout-vol` | 31 | yes | default 0 if absent |
| `ramp-en`, `ramp-time-up`, `ramp-time-down` | present, 5, 5 | yes | max 7 each ("max value 7" warning) |
| `pa-pin-max` | 1 | yes | default 0 if absent |
| `pa-pin-0` | PI5, output, value 1 | yes (`pa-pin-%d`) | amp enable pin |
| `pa-pin-level-0` | 1 | yes (`pa-pin-level-%d`) | active level |
| `pa-pin-msleep-0` | 100 ms | yes (`pa-pin-msleep-%d`) | wait before enabling |
| `hp-det-gpio` | PI3, input | yes | headphone detect ("Headphone detection") |
| `tx-hub-en` | present | yes | route DAC through the audio hub |

## Data table 2: `codec_plat` and `codec_mach` [D]
| Node / property | Value | Read by kernel |
|---|---|---|
| `codec_plat` (`allwinner,sunxi-snd-plat-aaudio`): `playback-cma` / `capture-cma` | 128 / 128 (KiB) | yes |
| `tx-fifo-size` / `rx-fifo-size` | 128 / 128 | yes |
| `dac-txdata` / `adc-txdata` | 0x05096020 / 0x05096040 | yes |
| `codec_mach` (`allwinner,sunxi-snd-mach`): `soundcard-mach,name` | `audiocodec` | yes (prefix `soundcard-mach,` + name) |
| `soundcard-mach,playback-only` | present | yes (prefix) |
| `soundcard-mach,pin-switches` | `LINEOUT`, `SPK` | yes (prefix + `pin-switches`) |
| `soundcard-mach,routing` | LINEOUT←LINEOUTL_PIN, LINEOUT←LINEOUTR_PIN, SPK←LINEOUTL_PIN, SPK←LINEOUTR_PIN | yes (prefix + `routing`) |
| `soundcard-mach,codec/pll-fs` | 4 | **no** (no `pll-fs` string in the kernel) |

## Data table 3: stock mixer controls (`sunxi_codec_controls`, …8a73c00) [G]
| Control | Register | Bits | Range | dB |
|---|---|---|---|---|
| `digital volume` | 0x000 | shift 12, inverted | 0–63 | −1.16 dB per step from 0 dB, mute at the end |
| `lineout volume` | 0x310 | shift 0 | 0–31 | 0 = mute; 1–31 = −43.5 dB + 1.5 dB per step (31 = +1.5 dB) |
| `OutputL Mixer` `DACL Switch` / `DACR Switch` | 0x314 | bit 21 / bit 20 | 0–1 | – |
| `OutputR Mixer` `DACL Switch` / `DACR Switch` | 0x314 | bit 16 / bit 17 | 0–1 | – |
| `LINEOUT Switch`, `SPK Switch` (pin switches) | – | – | 0–1 | – |
Mainline's equivalents (R21): `Line Out Playback Volume`, `Line Out Playback Switch`, `Speaker` pin switch.

## Data table 4: DAPM widgets and routes (`sunxi_codec_dapm_widgets` …8a73ca0, `_routes` …8a746a0) [G]
| Widget | Event | Event behaviour |
|---|---|---|
| `DACL`, `DACR` (stream `Playback`) | `sunxi_codec_playback_event` | after power-up: set reg 0x000 bit 31 (DAC enable); after power-down: clear it only if reg 0x310 bits 15:14 are both 0 |
| `OutputL Mixer`, `OutputR Mixer` | – | mixers above |
| `LINEOUTL_PIN`, `LINEOUTR_PIN` | – | outputs |
| `LINEOUT` | `sunxi_lineout_event` | after power-up set reg 0x310 bits 13 and 11; before power-down clear them |
| `SPK` | `sunxi_spk_event` | does nothing (returns 0): the amp is driven by the jack logic, not DAPM |
Routes: OutputL Mixer ← DACL/DACR switches; OutputR Mixer ← DACL/DACR switches; LINEOUTL_PIN ← OutputL Mixer;
LINEOUTR_PIN ← OutputR Mixer; card routing adds LINEOUT and SPK ← both pins.

## Data table 5: audio hub controls [G]
`sunxi_ahub_dam_controls` (…8a75830): `APBIF0/1/2 Src Select`, `I2S0/1/2/3 Src Select`, `DAM0C0/C1/C2 Src Select`,
`DAM1C0/C1/C2 Src Select` (enums, `ahub_mux_text`); `sunxi_ahub_controls` (…8a76150): `loopback debug`.
DT cards also present [D]: `ahubdam`, `ahubi2s0` (I2S, 2 slots × 32 bit), `ahubhdmi`, `hdmi_codec`.

## Data table 6: rumble [G][D]
| Item | Value |
|---|---|
| PWM controller / channel | `pwm2@0300a000` (`allwinner,sunxi-pwm2`, status okay), `pwm_request(2)` in `axp2202_battery_probe` |
| Pin | PH2, function `pwm2` (mux 4) active; `io_disabled` (mux 7) sleep |
| DT marker | `bat-power-supply/moto_pwm_gpio = PH2` (not read by the kernel by that name) |
| Period | 500,000 ns (2 kHz); probe applies period 500,000 with duty 0 and leaves it disabled |
| Level → duty | level 0–100 % → duty = level × 5,000 ns; 0 disables the PWM (duty 1 ns) |
| Input FF | `EV_FF` (0x15) + `FF_RUMBLE` (0x50) on the `gpio-keys-polled` joypad, `input_ff_create_memless` → `allen_play_effect` |
| FF scaling | level = strong_magnitude × 100 / 32768, capped at 100; levels below 37 → 0 (weak magnitude ignored) |
| Worker | `allen_state_worker` → `pwm2_moto3_ctrl(level)` (exported) |
| sysfs | `axp2202-battery/moto` (0644, decimal 0–100, `store_pwm2_moto` / `show_pwm2_moto`) |
| Unused path | `sunxi_motor_startup` looks for DT node `motor_para` (`motor_shake` GPIO, `motor_ldo`, `motor_ldo_voltage`); absent in the SP DT |

## Data table 7: other battery-device sysfs files found on the way (`allen_power_attrs`) [G]
All under `/sys/class/power_supply/axp2202-battery/`: `work_led`, `lowpwr_led`, `led_test`, `moto` (0644);
`boot_mode`, `otg_id`, `spk_state` (0444); `brightness`, `openbor_volume`, `nds_esckey`, `nds_pwrkey`,
`workled_sleep` (0644); `display_id`, `hallkey` (0444); `os_sleep` (0644). (Full inventory: W3.1.)

## Data table 8: stock functions (V1.0.6) [G]
| Function | Address | Role |
|---|---|---|
| `snd_sunxi_jack_gpio_init` | …874ccac | requests `hp-det-gpio`, IRQ both edges, debounce 200 ms, initial scan |
| `jack_interrupt` / `sunxi_jack_det_irq_work` | …874caf8 / …874cc4c | IRQ → work that sleeps the debounce time |
| `sunxi_jack_det_work` / `sunxi_jack_det_scan_work` | …874cb50 / …874cbf4 | read pin, update state, call `allen_spk_ctrl` |
| `allen_spk_ctrl`, `allen_get_spk_state` | …8751744, …874fd60 | amp on/off by jack state |
| `snd_sunxi_pa_pin_init` / `_enable` / `_disable` | …874f9c0 / …874f7ec / …874f8d8 | `pa-pin-*` parsing, enable after msleep, disable at once |
| `sunxi_internal_codec_dev_probe` | …8751030 | reads table 1, regulators avcc (1.8 V) and amp (3.3 V) |
| `sunxi_codec_playback_event`, `sunxi_lineout_event`, `sunxi_spk_event` | …874fff0, …8750924, …874fd6c | table 4 |
| `snd_sunxi_jack_register`, `snd_sunxi_card_jack_new` | …874d100, …874d25c | ALSA jack object |
| `sunxi_jack_suspend` / `resume`, `sunxi_internal_codec_suspend` / `resume` | …874d060 / …874cfd4, …8750c00 / …8750f00 | PM |
| `allen_play_effect`, `allen_state_worker` | …85c1210, …85c11ac | FF rumble |
| `pwm2_moto3_ctrl`, `store_pwm2_moto`, `show_pwm2_moto` | …8645cf0, …86462e8, …86480e0 | PWM2 duty |
| `sunxi_motor_startup`, `sunxi_motor_init`, `sunxi_motor_free` | …85cd108, …85cd87c, …85cce58 | unused motor driver |

## Device checks (optional)
1. Stock: plug and unplug headphones; `cat /sys/class/power_supply/axp2202-battery/spk_state` each time.
2. Stock: `amixer -c 0 scontrols` (expect `digital volume`, `lineout volume`, mixer and pin switches).
3. Stock (K13): `echo 60 > /sys/class/power_supply/axp2202-battery/moto`, then `echo 0`; does the unit vibrate?
