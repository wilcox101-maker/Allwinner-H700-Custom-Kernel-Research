# R21: Redux frontend on mainline — compatibility map

Kernel Research (KR), 2026-11-14. Task R21, assigned by the Redux Manager, approved by Dale (GO).
**Desk only. Nothing here has run on an RG34XX-SP.** Every mainline claim comes from source or from
our own build config; the "expected" rows still need the device checks named in §4.

## 1. What was compared
| Side | Source |
|---|---|
| Redux frontend (stock kernel 4.9) | `Anbernic_RG34XXSP_Redux` main `frontend/src/*`, `frontend/vsync/redux_vsync.c`, `docs/hardware-map.md` (read 2026-11-14, read-only) |
| Our mainline kernel | torvalds/linux `97d73c8` (v7.4-rc2) + `patches/linux/0001-0007` + display layer, DTBs from `dts/`; final `.config` from `WORK=/tmp/w scripts/build-kernel.sh --display` (config step, 2026-11-14) |

Every stock-kernel interface the frontend touches (found by grepping `frontend/` for `/dev`, `/sys`,
`/proc`, ioctls, input codes and ALSA names) is in the table below. Paths under `/mnt/mod`,
`/mnt/data` and stock scripts (`pwr_new.sh`, `RA_launch.sh`, `nmcli`) are userspace, not kernel;
they are listed in §3 only as pointers.

## 2. The map
Verdict key: **none** = works unchanged; **shim** = can be bridged outside the frontend (udev rule,
symlink, config file); **code** = the frontend has to change.

| # | Stock interface (Redux file) | Mainline equivalent (our DTS/config) | Verdict |
|---|---|---|---|
| D1 | `/dev/fb0` + `FBIO_WAITFORVSYNC`, LD_PRELOAD vsync shim for stock SDL 2.0.12 apps (`vsync/redux_vsync.c`, `src/vsync.c`) | `sun4i-drm` (H616 DE33/TCON, display layer) gives `/dev/dri/card0` with KMS page-flip vblank. `/dev/fb0` still exists: `DRM_FBDEV_EMULATION=y`, `FB_DEVICE=y`, and `drm_fb_helper_ioctl()` implements `FBIO_WAITFORVSYNC` on CRTC 0 (`drivers/gpu/drm/clients/drm_fbdev_helper.c:955`). Only with `-redux-panel.dtb` (PE6 low); `-redux.dtb` has no display and no fb0 (Q3) | **none** for the shim (it works, and switches itself off if fb0 is missing). It is only needed for stock SDL binaries, which ReduxOS does not ship |
| D2 | Frontend presents with `SDL_RENDERER_ACCELERATED`, no vsync flag (`src/main.c:123`); stock SDL ignores vsync | noble's SDL2 uses the KMSDRM backend; vsync is honoured through page flips (panfrost renders, `sun4i-drm` scans out) | **code** (small): add `SDL_RENDERER_PRESENTVSYNC`. Needs DRM master / seat access for the frontend user (logind seat or root) |
| D3 | Backlight: `/dev/disp` ioctl `DISP_LCD_SET_BRIGHTNESS` (0x102), 16–255, plus the storage-only `axp2202-battery/brightness` (`src/brightness.c`) | `pwm-backlight` node `backlight` in `dts/sun50i-h700-redux-display.dtsi`: `/sys/class/backlight/backlight/brightness`, `max_brightness` 255 (`brightness-levels = <0 255>`, 255 interpolated steps), PWM0 25 kHz. Panel DTB only. No `/dev/disp`, no AXP attribute | **code**: write the same 16–255 value to sysfs. Plus a **shim** for permissions (udev rule giving the frontend's group write access, or run as root). `DISP_MIN` 16 to re-check under K19 (PWM is 25 kHz, stock 50 kHz) |
| B1 | `/sys/class/power_supply/axp2202-battery/{capacity,status,voltage_now}` (`src/platform_stock.c`) | AXP717 driver `axp20x_battery.c`: `/sys/class/power_supply/axp20x-battery/` with `capacity`, `status` (same strings), `voltage_now` (µV), plus `present`, `health`, `voltage_min/max`, `constant_charge_current_max`. Charger: `axp20x-usb` (`online`) | **code**: new path (best: find the supply whose `type` is `Battery` instead of a fixed name). A symlink is not possible in sysfs |
| B2 | `current_now` (stock: absent, so `platform_battery_ma_known()` = 0) | Present on mainline, but the driver says the AXP717 value is **raw with an unknown offset of about 450 mA** (`axp20x_battery.c`, `axp717_battery_get_prop`) | **code**: keep "current unknown" until a device check (new **K23**) shows the number is usable |
| B3 | Battery temperature (stock dummy 300) | Board DT has `x-powers,no-thermistor`: no `temp` property | **none** (frontend already reports it unknown) |
| B4 | Lid state `axp2202-battery/hallkey` (not read by the frontend; stock `pwr_new.sh` handles the lid) | No attribute. Lid = `SW_LID` on input device **`gpio-keys-lid`** (PE7, upstream RG35XX-SP DT, inherited), wake source on lid open | **code** in whatever owns sleep (F4 power daemon or logind `HandleLidSwitch=`), not in the current frontend |
| C1 | `/sys/devices/system/cpu/cpu%d/cpufreq/scaling_cur_freq`, `cpu0/cpufreq/{scaling_governor,cpuinfo_min_freq,cpuinfo_max_freq}` (`platform_stock.c`, `sysinfo.c`) | Same paths: `cpufreq-dt` via `sun50i-cpufreq-nvmem` (=m, `ARM_ALLWINNER_SUN50I_CPUFREQ_NVMEM`), one policy for all four cores. Table from `dts/sun50i-h700-redux-cpu-opp.dtsi` (Q2): `cpuinfo_max_freq` 1416000 while boost is off, 1512 MHz only with boost on | **none** |
| C2 | Governors (stock default `performance`; stock `cpu_setting.sh` also writes `interactive`) | Default `schedutil`; built in: performance, userspace, ondemand, schedutil; modules: powersave, conservative. **No `interactive`** (Android-only governor) | **none** for the frontend (it only reads). Anything that writes governors must not use `interactive` |
| C3 | `cpu%d/online` (`platform_stock.c`) | `HOTPLUG_CPU=y`: files exist for cpu1–3; the frontend falls back to "online" if a file is missing | **none** |
| T1 | `/sys/class/thermal/thermal_zone0/temp` read **as the CPU** (`platform_stock.c:47`) | `sun8i_thermal` registers sensors in index order 0–3 (`sun8i_ths_register`), and the H616 DT maps ths 0 = GPU, 1 = VE, 2 = CPU, 3 = DDR. Expected: `thermal_zone0` = `gpu-thermal`, `thermal_zone2` = `cpu-thermal` | **code**: find the zone by `type` (as `sysinfo.c` already does). Otherwise the status bar shows the GPU temperature |
| T2 | Zone types `cpu_thermal_zone`, `gpu_…`, `ve_thermal_zone`, `ddr_…` matched by prefix (`sysinfo.c` `zone_index`) | Types are the DT node names: `cpu-thermal`, `gpu-thermal`, `ve-thermal`, `ddr-thermal`. `cpu`/`gpu`/`ddr` prefixes still match; `ve` is matched only as `ve` or `ve_` | **code** (one line): also accept `ve-`. Trips: CPU 60/70 °C passive, 115 °C critical (`…-stock-thermal.dtsi`, Q1); GPU/VE/DDR have no trips, as stock |
| I1 | Buttons + sticks on **`/dev/input/event1`** (`ANBERNIC-keys`), power key on **`/dev/input/event0`** (`axp2202-pek`), opened by number (`src/evdev_reader.c`) | Five devices, numbered by probe order (not stable): **`gpio-keys-gamepad`** (buttons, `gpio-keys`, built in), **`gpio-keys-volume`** (built in), **`gpio-keys-lid`** (built in), **`adc-joystick`** (sticks, module), **`axp20x-pek`** (power key, module). Names from `gpio_keys.c:885` / `adc-joystick.c:274` (no `label` on the nodes, so the platform device name) and `axp20x-pek.c:242` | **code**: open devices by name (`EVIOCGNAME`) or by `/dev/input/by-path/platform-<name>-event`; poll all five. A udev symlink rule is a possible **shim**, but the code change is needed anyway for I2–I4 |
| I2 | Button codes (`src/remap_device.c`): 304 A, 305 B, 306 Y, 307 X, 308 L1, 309 R1, 310 Select, 311 Start, 312 Menu, 314 L2, 315 R2 | Upstream RG35XX-2024 DT, inherited: A = `BTN_EAST` 305, B = `BTN_SOUTH` 304, X = `BTN_NORTH` 307, Y = `BTN_WEST` 308, L1 = `BTN_TL` 310, R1 = `BTN_TR` 311, L2 = `BTN_TL2` 312, R2 = `BTN_TR2` 313, Select = `BTN_SELECT` 314, Start = `BTN_START` 315, Menu = `BTN_MODE` 316; our patch 0006 adds L3 = `BTN_THUMBL` 317 (PE8), R3 = `BTN_THUMBR` 318 (PE9) | **code**: a second remap table. **Danger: same numbers, different buttons** (304/305 swap A/B; 308 is Y not L1; 310/311 are L1/R1 not Select/Start; 312 is L2 not Menu; 314/315 are Select/Start not L2/R2). The stock table on mainline would be silently wrong, not just missing |
| I3 | D-pad as `ABS_HAT0X/Y` (16/17) on event1 | D-pad as **keys** `BTN_DPAD_UP/DOWN/LEFT/RIGHT` (0x220–0x223) on `gpio-keys-gamepad` | **code**: map the four keys (the hat branch stays for stock) |
| I4 | Sticks `ABS_Z`/`ABS_RX` (left), `ABS_RY`/`ABS_RZ` (right), centred on 0, thresholds ±1500 (`remap_device.h`) | `adc-joystick` (our patch 0006): `ABS_X`/`ABS_Y` left, `ABS_RX`/`ABS_RY` right, raw ADC 0–4096 (X axes inverted by `abs-range`), centre about 2048, `abs-flat`/`abs-fuzz` 32, polled every 16 ms | **code**: new axis codes, and thresholds relative to the centre from `EVIOCGABS` (min/max), not to 0. Axis order and sign are K5 |
| I5 | Volume `KEY_VOLUMEUP`/`DOWN` (115/114) on event1 | Same codes, on `gpio-keys-volume`, with `autorepeat` | **none** for codes; covered by I1 (other device). Repeats (`value` 2) are already ignored |
| I6 | Power key: `axp2202-pek`, any `EV_KEY` press → `pwr_new.sh` | `axp20x-pek`, `KEY_POWER` (116), both edges. **Was not in our kernel:** `INPUT_AXP20X_PEK` is off in arm64 defconfig, and the PEK is an MFD cell with no DT node, so `dt_driver_coverage.py` could not catch it. **Fixed in this PR** (`config/rg34xxsp.config`, module; config check passes, object compiles) | **code** for the action (no `pwr_new.sh` on ReduxOS: suspend/shutdown via logind or the F4 daemon). Note: on AXP717 the PEK's `startup`/`shutdown` sysfs files use the AXP20x time table, so ignore them |
| A1 | `AUDIODEV=hw:2,0` for every launch (`src/launcher.c`) | One sound card in the board DT: `sun4i-codec`, name "H616 Audio Codec", ALSA id **`Codec`** (last word of the name, `sound/core/init.c` `retrieve_id_from_card_name`). Expected index 0 (no HDMI or other audio node enabled) | **code**: use `hw:CARD=Codec,DEV=0` (or `plughw:` for rate conversion), never a number |
| A2 | `amixer sset 'lineout volume' N` (`src/volume.c`) | Controls: `Line Out Playback Volume` (simple name `Line Out`), `DAC Playback Volume`, `Line Out Playback Switch`, routing `Line Out Source Playback Route` (Stereo / Mono Differential), pin switch `Speaker`; jack detect on PI3 (`hp-det-gpios`), amp on PI5 with our 100 ms delay (patches 0002/0003) | **code**: control name, and the volume scale (stock steps vs mainline TLV range). **Shim**: a default mixer state (asound.state or UCM) in the board package so routing and switches are on at boot |

## 3. Not kernel, but breaks with the same move (pointers only)
- `/mnt/mod/ctrl/pwr_new.sh`, `RA_launch.sh`, `SimpleTerminal`, `/mnt/data/redux/*`, `/mnt/vendor`: stock partitions and scripts that ReduxOS does not have.
- `src/wifi.c` drives `nmcli`; the ReduxOS image uses iwd + systemd-networkd (R5/R7), so Wi-Fi needs `iwctl` or iwd's D-Bus API. `wlan0/carrier` should still exist (rtw88, interface name to confirm on the device).
- Emulators through SDL will see the buttons (`gpio-keys-gamepad`) and sticks (`adc-joystick`) as **two** devices; stock had one. Redux decides whether to merge them in userspace (uinput is built as a module).

## 4. Device checks this adds
- **K23** *(proposed)*: on our kernel (spare card), list `cat /proc/bus/input/devices`, `/sys/class/thermal/thermal_zone*/type`, `aplay -l`, `amixer -c Codec scontrols`; read `axp20x-battery/current_now` while charging and while discharging and compare with a USB meter (is the ~450 mA offset real?); press the power key and close the lid under `evtest`.
- Existing: K5 (stick order/sign, I4), K18 (fb0/KMS, D1/D2), K19 (backlight levels, D3), K15 (speaker start-up, A2).

## 5. Recommendation
Shims cover only fb0 vsync (already works) and permissions/mixer defaults. Everything else differs in
path, name, number or meaning, so the clean route is **a second platform file in the frontend**
(`platform_mainline.c` next to `platform_stock.c`, chosen at build time like `REDUX_PLATFORM_STOCK`)
holding: device-by-name input with the mainline remap table, sysfs backlight, `axp20x-battery`,
thermal by type, `hw:CARD=Codec`, and the `Line Out` mixer control. That keeps the stock build
untouched. Work order for Redux: I1–I4 and I6 first (without them the UI cannot be driven), then
D3, A1–A2, B1–B2, T1–T2, D2.
