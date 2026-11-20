# W3.3: stock V1.0.6 device tree vs the mainline RG34XX-SP trees (Ghidra plan, 2026-11-15)

> **Update 2026-11-20:** the three mainline gaps are narrowed in [`dr-unknowns-and-rebuild-2026-11-20.md`](dr-unknowns-and-rebuild-2026-11-20.md): PE11 (`adc-en-gpios`) is read by no stock code, so mainline need not drive it; ALDO3 has no DT consumer (keep it on until its voltage is read); TF2's full stock wiring is listed there. Desk only.

Kernel Research chat, desk only. Stock = `dtb.dts` from the V1.0.6 `boot.img` (575 nodes; the DT the 4.9 kernel
boots with, before any u-boot fix-ups). Mainline = our trees in `dts/` (`sun50i-h700-anbernic-rg34xx-sp.dts`,
`-redux.dts`, `-redux-panel.dts` and the `redux-*.dtsi` includes), which build on upstream
`sun50i-h700-anbernic-rg35xx-sp.dts` → `-rg35xx-plus.dts` → `-rg35xx-2024.dts` → `sun50i-h616.dtsi` +
`sun50i-h616-cpu-opp.dtsi` (read from torvalds/linux **master on 2026-11-15**, not re-read at our pin `97d73c8`).
Tags: **[D]** device tree / source text (everything in this file), **[V]** none yet. DT values and node names only.
"Stock-only" = vendor properties no mainline driver reads.

## Answer: what matters for mainline
| # | Finding | Stock [D] | Mainline today [D] | Action |
|---|---|---|---|---|
| 1 | **Second card slot (TF2) is missing on mainline** | `sdmmc@04022000` (mmc2) enabled, 4-bit SD on the PC pins, card detect **PE22** with `broken-cd` (polled), slot power **PE4** high, `vqmmc` = **ALDO1** | `mmc2` stays `disabled` (upstream RG35XX family and ours) | Add an `&mmc2` node (pins as upstream `mmc2_pins`, `bus-width = <4>`, cd PE22 or `broken-cd`, a fixed regulator on PE4, `vqmmc` ALDO1); device check |
| 2 | **TF1 card detect differs** | `sdmmc@04020000` is `non-removable`, no cd GPIO | `cd-gpios` **PF6**, `disable-wp` (from RG35XX-2024) | Device check: does PF6 change on card insert on the SP? |
| 3 | **ALDO3 is always-on in stock, "unused" upstream** [N] | `aldo3` `regulator-always-on`, `boot-on` (no consumer named) | `reg_aldo3` empty node (no constraints) | Mainline may switch it off at late init. Unknown consumer: mark always-on until a device check proves it unused |
| 4 | Stick ADC enable pin **PE11** [N] | `adc-en-gpios` PE11, driven low | not driven | Check whether the sticks read correctly without it (K5); else add a GPIO hog |
| 5 | Wi-Fi control pins | No reset or host-wake GPIO; `wlan_power` = CLDO4, 32 kHz clock out on **PG10** | Reset **PG18** (`mmc-pwrseq-simple`), host-wake **PG15**, clock PG10 | Keep mainline; PG18/PG15 come from the RG35XX Plus and are unverified on the SP (stock never touches them) |
| 6 | Rumble motor | `pwm2@0300a000` enabled on **PH2** (PWM2, `clk_bypass_output`), `moto_pwm_gpio` PH2 in the battery node | no PWM2, no motor node | G6; needs the H616 PWM driver (display layer) and a `pwm-vibrator` node if the SP has a motor (K13) |
| 7 | Backlight PWM frequency | `lcd_pwm_freq` 50 kHz, `lcd_pwm_pol 1`, max 255, default 50 | 25 kHz, normal polarity, default 50 | K19 |
| 8 | Critical thermal trip | CPU 115 °C; GPU/VE/DDR zones without trips | upstream 110 °C on all four; our `-redux` restores 115 °C and removes the others (Q1) | Done (Q1) |
| 9 | GPU 648 MHz | 648 MHz @ 960 mV; 600–420 MHz @ 900 mV | ours: 420–600 MHz @ 940 mV (shared DCDC2), 648 left out | Unchanged |
| 10 | OTG host mode | `usbc0` OTG with ID detect **PI4** and VBUS drive **PI16**; USB-C | `dr_mode = "peripheral"` | Host mode later needs ID/VBUS handling (AXP717 Type-C) |
| 11 | External RTC | `rtc@51` `nxp,pcf8563` on the PMIC's I2C (R_I2C) | same, `rtc@51` on `r_i2c` (upstream SP tree) | Matches |
| 12 | HDMI | `hdmi@06000000` enabled (mini HDMI), CEC on | no H616 HDMI node | Later (display layer has no HDMI yet) |
| 13 | Camera block enabled with conflicting pins | `vind@0` okay: CSI1 on PE0–PE19, CCI0 **PG17/PG18**, MCLK1 **PE1** | – | Stock-only family node; ignore, but it explains why stock never uses PG18 |

## Data table 1: enabled stock nodes and their mainline counterpart
"–" = no node. `okay*` = no `status` property (enabled by default).
| Stock node | Stock compatible | Mainline node | Mainline status | Note |
|---|---|---|---|---|
| `pinctrl@0300b000` / `@07022000` | `sun50iw9p1-pinctrl` / `-r-pinctrl` | `pio` / `r_pio` | okay | upstream adds `vcc-pX-supply` (CLDO3, PG = ALDO4) |
| `uart@05000000` (UART0) | `sun50i-uart` | `uart0` | okay | PH0/PH1 both |
| `uart@05000400` (UART1) | `sun50i-uart` | `uart1` | okay | PG6–PG9 with RTS/CTS (Bluetooth) both |
| `twi@0x05002c00` (TWI3) | `sun50i-twi` | `i2c3` | disabled | stock: PH4/PH5, 100 kHz, **no children** |
| `twi@0x07081400` (TWI5 = R_I2C) | `sun50i-twi` | `r_i2c` | okay | stock 200 kHz, `no_suspend`; children PMIC @0x34, RTC @0x51 both |
| `pmu` (AXP717 @0x34) | `x-powers,axp2202` | `axp717: pmic@34` | okay | see tables 3–4 |
| `rtc@51` | `nxp,pcf8563` | `rtc_ext: rtc@51` | okay | match |
| `rtc@07000000` | `sunxi-rtc` (`wakeup-source`, `auto_switch`) | `rtc` | okay | |
| `usbc0@0` + `udc-controller` + `ehci0`/`ohci0` | otg-manager, udc, ehci0/ohci0 | `usbotg`, `usbphy`, `ehci0`, `ohci0` | okay | stock OTG, mainline peripheral |
| `usbc1–3`, `ehci1–3`, `ohci1–3` | sunxi ehci/ohci | `ehci1…3`, `ohci1…3` | disabled | stock-only family defaults; `usbc1` VBUS drive PE19 |
| `codec@0x05096000` + `codec_plat` + `codec_mach` | `sunxi-snd-codec` | `codec` | okay | table 6 |
| `hdmi_codec`, `ahub*` | sunxi audio hub | – | – | HDMI audio, stock-only |
| `sdmmc@04020000` (mmc0, TF1) | `sunxi-mmc-v4p1x` | `mmc0` | okay | table 5 |
| `sdmmc@04021000` (mmc1, Wi-Fi) | `sunxi-mmc-v4p1x` | `mmc1` | okay | table 5 |
| `sdmmc@04022000` (mmc2, TF2) | `sunxi-mmc-v4p6x` | `mmc2` | **disabled** | finding 1 |
| `disp`, `lcd0`, `lcd1`, `tv0`, `tr`, `boot_disp` | sunxi display | `de`, `tcon_top`, `tcon_lcd0` (display layer, `-redux-panel` only) | okay (ours) | table 7 |
| `hdmi@06000000` | `sunxi-hdmi` | – | – | finding 12 |
| `pwm@0300a000`, `pwm0`, `pwm2` | `sunxi-pwm*` | `pwm` (display layer) | okay (ours, PWM0) | PWM2 = motor (finding 6) |
| `gpadc` | `sunxi-gpadc` | `gpadc` | okay | 1 channel, 100 kHz sample rate (stock-only props) |
| `gpio_keys` | `gpio-keys-polled` ("ANBERNIC-keys") | `gpio-keys-gamepad`, `gpio-keys-volume`, `gpio-keys-lid`, `adc-joystick` | okay | table 8 |
| `wlan`, `bt`, `btlpm`, `addr_mgt` | sunxi rfkill/BT power | `wifi_pwrseq`, `sdio_wifi`, `bluetooth` | okay | table 9 |
| `thermal_sensor` + `thermal-zones` | `arm,sun50iw9p1` | `ths` + `thermal-zones` | okay | table 10 |
| `gpu@0x01800000` | `arm,mali-midgard` | `gpu` (`sun50i-h616-mali`, Panfrost) | okay | table 11 |
| `cpus`, `opp_l_table`, `idle-states` | per-bin OPP v2 | `cpu0..3`, `cpu_opp_table` | okay | table 12 |
| `iommu@030f0000` | sunxi IOMMU | – | – | display/video only |
| `msgbox`, `hwspinlock`, `arisc`, `arisc_space`, `standby_space` | SCP mailbox, standby | – | – | firmware interfaces (G1, W3.4) |
| `dramfreq` | `sunxi-dramfreq` | – | – | DRAM DVFS, stock-only |
| `vind@0` (camera), `vdevice@0`, `deinterlace`, `pcie`, `ve`, `vp9`, `g2d`, `ce`, `emce` | vendor | – (`ve`, `crypto` exist upstream, unused here) | – | stock-only family nodes |
| `wlan`/`bt` power, `auto_print`, `ir_boot_recovery`, `boot_init_gpio`, `box_start_os0` | vendor | – | – | bootloader or vendor helpers |
| `firmware/optee` | `linaro,optee-tz` | – | – | stock runs OP-TEE (W3.4) |

## Data table 2: every GPIO property on enabled stock nodes [D]
Stock cell order: bank, pin, mux (function), pull (0 off, 1 up, 2 down), drive, data. "-" = default.
| Stock node / property | Pin | Mux | Pull | Data | Mainline |
|---|---|---|---|---|---|
| `gpio_keys/keyUP` … all 17 keys | see table 8 | 0 (in) | up | – | same pins, `GPIO_ACTIVE_LOW` |
| `gpio_keys/amux-en-gpios` | PI0 | 1 (out) | down | 1 | `joy-mux-pin` PI0 `gpio_out` (not driven high explicitly) |
| `gpio_keys/A0_gpio`, `A1_gpio` | PI1, PI2 | out | down | 0 | `gpio-mux` PI1, PI2 active low |
| `gpio_keys/adc-en-gpios` | **PE11** | 0 | down | 0 | **none** (finding 4) |
| `pmu/powerkey@0/hall_key` | PE7 | in | up | – | `gpio-keys-lid` PE7, `SW_LID`, wakeup |
| `pmu/bat-power-supply/work_led` | PI12 | out | up | 0 | `led-0` PI12 power, default on |
| `pmu/bat-power-supply/low_pwr_led` | PI11 | out | up | 0 | `led-1` PI11 status |
| `pmu/bat-power-supply/moto_pwm_gpio` | PH2 | out | up | 0 | none (G6) |
| `pmu/usb_power_supply/allen_usb_id_det` | PI4 | out | off | 0 | none |
| `usbc0@0/usb_drv_vbus_gpio` | PI16 | in | up | – | none |
| `usbc1@0/usb_drv_vbus_gpio` | PE19 | in | up | – | none (family default) |
| `codec/pa-pin-0` | PI5 | out | up | 1 (level 1, 100 ms) | `allwinner,pa-gpios` PI5 active high |
| `codec/hp-det-gpio` | PI3 | 1 | – | 0 | `hp-det-gpios` PI3 active high |
| `sdmmc@04022000/cd-gpios` | **PE22** | 6 (eint) | up | – | none (finding 1) |
| `sdmmc@04022000/pwr-gpios` | **PE4** | out | – | 1 | none (finding 1) |
| `lcd0/lcd_gpio_0…4` | PI9, PI10, PI8, PI14, PI15 | out | – | 1 | SPI SCK PI9, MOSI PI10, CS PI8; reset PI14; power PI15 (ours, `-redux-panel`) |
| `bt/bt_rst_n` | PG19 | out | – | 0 | `enable-gpios` PG19 |
| `btlpm/bt_wake` | PG17 | out | – | 1 | `device-wake-gpios` PG17 |
| `btlpm/bt_hostwake` | PG16 | 6 (eint) | – | 0 | `host-wake-gpios` PG16 |
| `vdevice@0/test-gpios` | PA0 | out | down | 1 | none (vendor test node; PA0 is key A) |
| `boot_init_gpio/gpio0`, `gpio1` | PI11, PI12 | out | – | 0, 1 | LEDs above (bootloader sets them) |
| `card_boot/sprite_gpio0` | PH6 | out | – | 1 | none (bootloader) |
| `key_boot_recovery/recovery_key` | PH9 | in | – | – | none (bootloader) |
| `dram_select_para/select_gpio0…3` | PH6, PH7, PH8, PH10 | in | up | – | none (boot0 DRAM straps, R3) |
| `pmu/usb_power_supply/pmu_acin_usbid_drv`, `pmu_vbus_det_gpio` | AXP GPIO (4-cell form) | – | – | – | none |

## Data table 3: pin groups used by enabled stock nodes [D]
| Node | Pins | Function (mux) | Drive / pull | Mainline group |
|---|---|---|---|---|
| UART0 | PH0, PH1 | uart0 (2) | – / up | `uart0_ph_pins` |
| UART1 | PG6–PG9 | uart1 (2) | 1 / up | `uart1_pins` + `uart1_rts_cts_pins` |
| TWI3 | PH4, PH5 | twi3 (5) | 1 / off | – |
| R_I2C | PL0, PL1 | s_twi0 (3) | 1 / off | `r_i2c_pins` |
| mmc0 | PF0–PF5 | sdc0 (2) | 3 / up; alt `uart0_jtag` (3) | `mmc0_pins` (30 mA, pull-up) |
| mmc1 | PG0–PG5 | sdc1 (2) | 3 / up | `mmc1_pins` |
| mmc2 | PC0 (pull down), PC1, PC5, PC6, PC8–PC11, PC13–PC16 | sdc2 (3) | 2 / up | `mmc2_pins` (same pin list, pull-up on all) |
| LCD | PD0–PD27 | rgb24 | – | `lcd0_rgb888_pins` (display layer) |
| PWM0 (backlight) | PD28 | pwm0 (2) | – | `pwm0_pin` (display layer) |
| PWM2 (motor) | PH2 | pwm2 (4) | – | – |
| Wi-Fi 32 kHz | PG10 | x32kfout (3) | 2 / up | `x32clk_fanout_pin` |
| `vind` camera | PE0–PE19, PG17/PG18, PE20/PE21, PG19, PE1 | csi1 / cci / mclk | – | – (stock-only) |
| `vdevice` | PA1, PA2 | Vdevice (5) | 1 / up | – (keys B/Y on mainline) |
| `box_start_os0` | PH6, PH7 | gpio_out (standby states) | – | – |
| bootloader groups | PF0–PF5, PC (card boot), PH14/PH15 (`twi_para`), PH0/PH1 (`uart_para`), PH9–PH12 (`jtag_para`) | – | – | – |
Every other stock pin group (UART2–5, TWI0–2/4, SPI0/1, NAND, GMAC, LVDS, SPDIF, DMIC, I2S, smartcard, TS) belongs to a disabled node.

## Data table 4: AXP717 regulators [D]
Stock gives every rail a wide range and lets drivers set it; the bootloader's `power_sply` node sets some at boot.
| Rail | Stock range (mV) | Stock flags | Stock consumer | Bootloader (`power_sply`) | Mainline (upstream RG35XX) |
|---|---|---|---|---|---|
| DCDC1 | 500–1540 | always-on, boot-on, ramp 250 | `cpu@0` | mode 1 | vdd-cpu 900–1160, always-on |
| DCDC2 | 500–3400 | always-on, boot-on | none (GPU has no supply) | mode 1 | vdd-gpu-sys fixed 940, always-on |
| DCDC3 | 500–1840 | always-on | DRAM | – | vdd-dram 1100, always-on |
| DCDC4 | 1000–3700 | – | none | – | – |
| RTCLDO | 1800 | always-on, boot-on | – | – | – |
| ALDO1 | 500–3500 | – | **mmc2 `vqmmc`** (TF2) | – | "unused" |
| ALDO2 | 500–3500 | – | none | – | "unused" |
| ALDO3 | 500–3500 | **always-on, boot-on** | none named | – | **"unused", no constraints** (finding 3) |
| ALDO4 | 500–3500 | always-on, boot-on | codec `avcc` (1.8 V, `avcc-vol`) | – | avcc 1800 (also PG and mmc1 `vqmmc`) |
| BLDO1 | 500–3500 | – | none | 1800 | "unused" |
| BLDO2 | 500–3500 | always-on, boot-on | – | 1800 (on) | vcc-pll 1800, always-on |
| BLDO3, BLDO4 | 500–3500 | – | none | – | "unused" |
| CLDO1 | 500–3500 | – | speaker amp (`allen_amp_power`) | – | vcc-spkr-amp 3300, **always-on** |
| CLDO2 | 500–3500 | – | none | – | "unused" |
| CLDO3 | 500–3500 | always-on, boot-on, ramp 2500 | I/O | – | vcc-io 3300, always-on |
| CLDO4 | 500–3500 | – | Wi-Fi (`wlan_power`), camera iovdd | 3300 (on) | vcc-wifi 3300 (mmc1 `vmmc`) |
| CPUSLDO | 500–1400 | always-on, boot-on | – | – | 900, always-on, boot-on |
| VMID, DRIVEVBUS | – | VMID always-on | USB VBUS out (`ehci0/ohci0`) | – | `boost` 5000–5200 |
Stock-only: `virtual-*` test consumers for every rail; `standby_param` (vdd-cpua, vdd-sys = DCDC2, vcc-io) for the SCP firmware.

## Data table 5: MMC [D]
| Property | mmc0 (TF1) stock | mmc0 mainline | mmc1 (Wi-Fi) stock | mmc1 mainline | mmc2 (TF2) stock | mmc2 mainline |
|---|---|---|---|---|---|---|
| bus width | 4 | 4 | 4 | 4 | 4 | – |
| card detect | none, `non-removable` | PF6 active low | – | `non-removable` | PE22, `broken-cd` | – |
| power | – | `vmmc` CLDO3 | `wlan_power` CLDO4 | `vmmc` CLDO4, `vqmmc` ALDO4 | PE4 high, `vqmmc` ALDO1 | – |
| max frequency | 50 MHz | upstream default | 150 MHz | default | 50 MHz | 150 MHz (dtsi) |
| modes | SD high speed; no SDIO/MMC | – | SDR50/DDR50/SDR104, 1.8 V I/O, `keep-power-in-suspend` | – | SD high speed, `cap-erase` | `cap-sd-highspeed`, `mmc-ddr-3_3v` |
| stock-only | `sunxi-power-save-mode`, `sunxi-dis-signal-vol-sw`, `ctl-spec-caps`, `max-busy-timeout`, timing tables `sdc_tm4_*`, `sunxi-dly-*` |||||

## Data table 6: audio [D]
| Item | Stock | Mainline |
|---|---|---|
| Codec | internal H616 codec, playback only (`soundcard-mach,playback-only`) | `codec` okay |
| Routing | line out to the analog mux (speaker / headphone) | `Speaker`→`LINEOUT`, `Headphone`→`LINEOUT` |
| PA enable | PI5 high, 100 ms after enable (`pa-pin-msleep-0`) | `allwinner,pa-gpios` PI5; delay 700 ms upstream, 100 ms with our patch 0002/0003 |
| Headphone detect | PI3 | `hp-det-gpios` PI3 |
| Analog supply | ALDO4, 1.8 V (`avcc-external`, `avcc-vol`) | ALDO4 via pio |
| Speaker amp power | CLDO1, switched by the codec driver | CLDO1 always-on |
| Stock-only | `lineout-vol = 0x1F`, `ramp-en` (5/5), `tx-hub-en`, CMA/FIFO sizes | – |

## Data table 7: display and backlight [D]
| Item | Stock | Mainline (ours, `-redux-panel`) |
|---|---|---|
| Panel | `lcd_driver_name = "rg34xxsp_v1"`, 720×480 RGB, 26 MHz, ht 820 / vt 536, hbp 46, hspw 2, vbp 20, vspw 5, clock phase 1, sync polarity 3, dithering on | NV3052C panel entry (Q8), RGB888 |
| Panel control | `lcd_gpio_0..4`: PI9, PI10, PI8, PI14, PI15 | 3-wire SPI (SCK PI9, MOSI PI10, CS PI8), reset PI14, power PI15 |
| Backlight | PWM0 PD28, 50 kHz, polarity 1, max 255, default 50, no curve | `pwm-backlight` 25 kHz, levels 0–255, default 50 |
| Outputs | screen0 LCD, screen1 HDMI (`dev1_do_hpd 1`) | LCD only |
| Stock-only | `disp_*`, `fb*`, `screen*`, `lcd_gamma_en`, `smart_color`, `deu_mode`, `chn_cfg_mode` | – |

## Data table 8: keys and sticks [D]
Stock codes from `gpio_keys`; the D-pad is two hat axes in stock, four keys on mainline. Labels are the DT's own.
| Stock key (label) | Pin | Stock code | Mainline code |
|---|---|---|---|
| keyUP / keyDOWN | PA6 / PE0 | `ABS_HAT0Y` (EV_ABS) | `BTN_DPAD_UP` / `BTN_DPAD_DOWN` |
| keyLeft / keyRight | PA8 / PA9 | `ABS_HAT0X` (EV_ABS) | `BTN_DPAD_LEFT` / `BTN_DPAD_RIGHT` |
| keyA | PA0 | 0x130 `BTN_SOUTH` | `BTN_EAST` |
| keyB | PA1 | 0x131 `BTN_EAST` | `BTN_SOUTH` |
| keyX | PA3 | 0x132 `BTN_C` | `BTN_NORTH` |
| keyY | PA2 | 0x133 `BTN_NORTH` | `BTN_WEST` |
| keyL1 / keyR1 | PA10 / PA12 | 0x134 / 0x135 | `BTN_TL` / `BTN_TR` |
| keySEl / keyStart | PA5 / PA4 | 0x136 / 0x137 | `BTN_SELECT` / `BTN_START` |
| keyMenu | PE3 | 0x138 | `BTN_MODE` |
| keyL3 / keyR3 | PE8 / PE9 | 0x139 / 0x13C | `BTN_THUMBL` / `BTN_THUMBR` (ours) |
| keyL2 / keyR2 | PA11 / PA7 | 0x13A / 0x13B | `BTN_TL2` / `BTN_TR2` |
| keyVol+ / keyvol- | PE1 / PE2 | `KEY_VOLUMEUP` / `KEY_VOLUMEDOWN` | same (separate `gpio-keys-volume`, autorepeat) |
| Lid | PE7 (`hall_key`, PMU node) | keys 110/111 from the PMU driver (Redux map) | `SW_LID`, wakeup |
| Sticks | GPADC ch 0 via 4-way mux: enable PI0, A0 PI1, A1 PI2; `adc-en` PE11 | | `adc-joystick` + `io-channel-mux` (PI1/PI2), PI0 pin group; PE11 not driven |
| Poll interval | 20 ms (all keys and sticks) | | 16 ms sticks (ours); keys are interrupt-driven |
Note: Redux's on-device remap table (from device tests) lists X/Y as 307/306; this table is only what the DT labels say.

## Data table 9: Wi-Fi and Bluetooth [D]
| Item | Stock | Mainline |
|---|---|---|
| Wi-Fi bus | SDIO on mmc1 (`wlan_busnum 1`) | `mmc1`, `sdio_wifi: wifi@1` |
| Wi-Fi power | CLDO4 (`wlan_power`), `chip_en`, `power_en` (no GPIO) | `vmmc` CLDO4 |
| Wi-Fi reset | none | `mmc-pwrseq-simple`, PG18 active low, 200 ms |
| Wi-Fi host wake | none | PG15 level low |
| 32 kHz clock | `losc_out` on PG10 | RTC `CLK_OSC32K_FANOUT` on PG10 |
| BT UART | UART1 (`uart_index 1`), RTS/CTS | `uart1` + `uart-has-rtscts` |
| BT enable / wake / host wake | PG19 / PG17 / PG16 | PG19 / PG17 / PG16 |
| MAC addresses | `addr_mgt` (type 0 for Wi-Fi/BT/Ethernet) | from the chip/OTP |

## Data table 10: thermal [D]
| Zone | Stock trips (°C) | Stock polling (ms) | Upstream | Ours (`-redux`) |
|---|---|---|---|---|
| CPU (sensor 2) | 60 passive, 70 passive, **115 critical** | 500 / 1000 | 60, 70, **110** | 60, 70, 115 (Q1) |
| GPU (sensor 0) | none (IPA power model, `sustainable-power` 1100) | 500 / 1000 | 110 critical | none (Q1) |
| VE (sensor 1) | none | 0 / 0 | 110 critical | none |
| DDR (sensor 3) | none | 0 / 0 | 110 critical | none |
| CPU cooling | trip 70 °C → map0 CPU (cpu0), map1 **GPU**, both `contribution 1024`; IPA: `sustainable-power 1000`, `k_po 20`, `k_pu 40`, `k_i 0` | – | none in master; we add Jernej's CPU cooling map (base layer R11) | base layer (no GPU cooling) |
Stock-only: IPA coefficients (`k_*`, `sustainable-power`, `dynamic-power-coefficient = 100` on cpu0), `ts`/`ss-coefficient`/`ff-coefficient` on the GPU power model.

## Data table 11: GPU [D]
| Item | Stock | Mainline (ours) |
|---|---|---|
| Driver | Mali Midgard/Bifrost blob (`mali_kbase.ko`), `gpu_idle 1`, `dvfs_status 1` | Panfrost (`sun50i-h616-mali`) |
| OPPs | 648 @ 960 mV; 600, 552, 504, 456, 420 @ 900 mV (OPP v1) | 420–600 MHz @ 940 mV, 648 left out |
| Supply | none (DCDC2 untouched) | `mali-supply` DCDC2 fixed 940 mV |
| Power model | `arm,mali-simple-power-model`, static 17000, dynamic 750 | – |

## Data table 12: CPU, idle, memory, boot [D]
| Item | Stock | Mainline |
|---|---|---|
| CPU OPPs | per-bin table `opp_l_table` (38 entries; see `stock-cpu-bin-decoder-and-dcdc2.md` and G2) | ROCKNIX-adjusted upstream (Q2) |
| CPU supply | DCDC1 on cpu@0 | DCDC1 on cpu0 |
| Idle | PSCI `cpu-sleep-0`, param 0x10000, entry 46 µs, exit 59 µs, residency 3570 µs | none |
| PSCI | `arm,psci-1.0`, smc | `arm,psci-0.2` |
| Memory node | 512 MB at 0x40000000 (placeholder; u-boot fixes it) | from u-boot |
| Reserved | ION heaps (system, CMA, secure); `secure/dram_region_mbytes = 80` (OP-TEE) | `secmon@40000000` 256 KiB (TF-A) |
| `chosen/bootargs` | `earlyprintk=sunxi-uart,0x05000000 loglevel=8 initcall_debug=1 console=ttyS0 init=/init` (u-boot replaces it) | `stdout-path = serial0:115200n8` |
| DRAM (`/dram`, boot0 data) | `dram_type 8` (LPDDR4), 672 MHz, ZQ/ODT/MR values; 15 `dram_paraN` sets selected by PH6/PH7/PH8/PH10 | – (R3, u-boot DRAM configs) |
| Bootloader-only | `power_sply`, `charger0` (`pmu_safe_vol` 3450), `pm_para` (`standby_mode 1`), `standby_param`, `card_boot`, `key_boot_recovery` (PH9, 2 s long press), `ir_boot_recovery`, `target`, `platform`, `product`, `clock` (PLL values) | – |

## Device checks (optional)
1. TF2: insert a card in the second slot on stock, `dmesg | grep mmc`; note whether removal is seen (stock polls: `broken-cd`).
2. TF1: on stock, `cat /sys/kernel/debug/gpio | grep -i pf6` with and without a card (does PF6 follow the card?).
3. ALDO3: on stock, `cat /sys/class/regulator/*/name` with `microvolts` and `num_users`; then (mainline, later) whether anything stops working if ALDO3 is off.
4. PE11: on stock, `cat /sys/kernel/debug/gpio | grep -i pe11` (does the stick driver hold it low?).

## Follow-up (2026-11-15)
The five upstream files this comparison used (`sun50i-h700-anbernic-rg35xx-sp.dts`, `-rg35xx-plus.dts`, `-rg35xx-2024.dts`,
`sun50i-h616.dtsi`, `sun50i-h616-cpu-opp.dtsi`) are **byte-identical at our pin `97d73c8` and at master (2026-11-15)**
(SHA-256 compared), so every "Mainline" value above holds for the pinned tree. The same is true for
`sun50i-cpufreq-nvmem.c`, `axp20x_battery.c` and `axp20x.h` used by G2 and G4.
