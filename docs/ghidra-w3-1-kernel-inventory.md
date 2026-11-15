# W3.1: stock kernel inventory, sysfs, `/dev/disp` ioctls, module parameters, input and devices (Ghidra plan, 2026-11-15)

Kernel Research chat, desk only. Stock V1.0.6 kernel `4.9.170 #9`: names from kallsyms (G0.2), struct
contents from the kernel's relocation table (`R_AARCH64_RELATIVE`, 84,896 pointers) and Ghidra 12.2 on a copy of
Dale's project; stock DT `dtb.dts` from the same `boot.img`. Tags: **[G]** static analysis of the stock kernel,
**[D]** device tree / strings / config, **[V]** none yet. Names, addresses, constants and behaviour only.
Full machine-readable lists (all 1,135 attributes, 286 module parameters) are in Dale's
`REA\BootImage\kallsyms\` (`sysfs-attributes-v106.tsv`, `module-params-v106.tsv`), not in this repo.

## Answer
- **1,135 sysfs attribute structures** in the kernel [G] (name, mode, show/store found mechanically: a string
  pointer, a valid mode and code pointers). **139 are vendor (Allwinner/Anbernic) files**, listed below with their
  folder and the function that registers them; the rest are upstream 4.9 (counts in table 2).
- New Anbernic files on the battery device: `moto` (rumble, 0–100 %), `work_led`, `lowpwr_led`, `led_test`,
  `workled_sleep`, `boot_mode`, `otg_id`, `spk_state`, `display_id`, `hallkey`, `openbor_volume`,
  `nds_esckey`, `nds_pwrkey`, plus the known `brightness` and `os_sleep` [G][N].
- **`/dev/disp` takes 49 command numbers** [G]; each call passes four 64-bit arguments (32 bytes copied in). Names
  come from Allwinner's BSP header `sunxi_display2.h` and are **inferred** where the binary has no string;
  `0x102 DISP_LCD_SET_BRIGHTNESS` is confirmed by its call path.
- **Keys** [D][G]: 19 DT keys (table 5), power key = `KEY_POWER` (116), lid = `KEY_DELETE`/`KEY_INSERT` (G0
  map), and the joypad input device also declares **force feedback (`FF_RUMBLE`)** [G] (relevant to G6).

## Table 1: vendor sysfs files, by folder [G]
Mode is the file permission in the kernel; "R/W" is derived. Notes give the constants a store handler checks
(from comparisons in the handler; no code reproduced). Folders marked "likely" are inferred from the group name.

**`/sys/class/power_supply/axp2202-battery/`** (registered by `axp2202_battery_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `work_led` | 0644 | RW | `show_work_led` | `store_work_led` | sets the work-LED GPIO |
| `lowpwr_led` | 0644 | RW | `show_lowpwr_led` | `store_lowpwr_led` | sets the low-power LED GPIO |
| `led_test` | 0644 | RW | `show_led_test` | `store_led_test` |  |
| `moto` | 0644 | RW | `show_pwm2_moto` | `store_pwm2_moto` | 0–100 % duty on the rumble PWM, period 500000 ns (2 kHz) |
| `boot_mode` | 0444 | R | `show_boot_mode` | `-` | boot mode |
| `otg_id` | 0444 | R | `show_otg_id` | `-` | USB OTG id (allen_get_otg_id) |
| `spk_state` | 0444 | R | `show_spk_state` | `-` | speaker state (allen_get_spk_state) |
| `brightness` | 0644 | RW | `show_brightness` | `store_brightness` | accepts 0–100, else ignored (stores only; no backlight effect, Redux map) |
| `openbor_volume` | 0644 | RW | `show_openbor_volume` | `store_openbor_volume` | stores a value; consumer not traced (stock UI) |
| `nds_esckey` | 0644 | RW | `show_nds_esc_key` | `store_nds_esc_key` | stores a value; consumer not traced |
| `nds_pwrkey` | 0644 | RW | `show_nds_pwr_key` | `store_nds_pwr_key` | stores a value; consumer not traced |
| `workled_sleep` | 0644 | RW | `show_workled_sleep` | `store_workled_sleep` |  |
| `display_id` | 0444 | R | `show_display_id` | `-` | display id; source not traced |
| `hallkey` | 0444 | R | `show_hallkey` | `-` | lid state (get_hallkey_state) |
| `os_sleep` | 0644 | RW | `show_os_sleep` | `store_os_sleep` | 0 = power-key/lid wake on, non-zero = off (G1) |

**gpio-keys-polled device dir (`/soc@03000000/gpio_keys`)** (registered by `gpio_keys_polled_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `amux_debug` | 0644 | RW | `-` | `joypad_store_amux_debug` |  |
| `adc_cal` | 0644 | RW | `joypad_show_adc_cal` | `joypad_store_adc_cal` | non-zero = recentre sticks (G0.3) |

**`/sys/power/sunxi_debug/`** (registered by `arisc_init`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `dram_crc_result` | 0644 | RW | `dram_crc_result_show` | `dram_crc_result_store` |  |
| `dram_crc_paras` | 0644 | RW | `dram_crc_paras_show` | `dram_crc_paras_store` |  |
| `time_to_wakeup_ms` | 0644 | RW | `time_to_wakeup_ms_show` | `time_to_wakeup_ms_store` | ms → arisc timer wake (G1) |
| `debug_baudrate` | 0644 | RW | `debug_baudrate_show` | `debug_baudrate_store` | accepts 9600, 57600, 115200 (to arisc) |
| `debug_mask` | 0644 | RW | `debug_mask_show` | `debug_mask_store` | arisc debug level, < 4 |

**`/sys/class/sunxi_info/`** (registered by `sunxi_sys_info_init`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `sys_info` | 0644 | RW | `sys_info_show` | `-` |  |
| `key_info` | 0644 | RW | `key_info_show` | `key_info_store` |  |

**`/sys/class/axp/`** (registered by `axp20x_device_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `axp_reg` | 0644 | RW | `axp_reg_show` | `axp_reg_store` | register access: reg < 0x100 checked |

**power-key (`axp20x-pek`) device dir** (registered by `axp20x_pek_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `shutdown` | 0644 | RW | `axp20x_show_ext_attr` | `axp20x_store_ext_attr` | PEK startup/shutdown time from a fixed list |
| `startup` | 0644 | RW | `axp20x_show_ext_attr` | `axp20x_store_ext_attr` | PEK startup/shutdown time from a fixed list |

**disp device, group `attr` (likely `/sys/class/disp/disp/attr/`)** (registered by `disp_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `capture_dump` | 0660 | RW | `-` | `disp_capture_dump_store` |  |
| `colorbar` | 0660 | RW | `-` | `disp_colorbar_store` | pattern < 8 |
| `yres` | 0660 | RW | `disp_yres_show` | `-` |  |
| `xres` | 0660 | RW | `disp_xres_show` | `-` |  |
| `boot_para` | 0660 | RW | `disp_boot_para_show` | `-` |  |
| `color_temperature` | 0660 | RW | `disp_color_temperature_show` | `disp_color_temperature_store` | signed value, bound −256 |
| `runtime_enable` | 0660 | RW | `disp_runtime_enable_show` | `disp_runtime_enable_store` | checks < 2 |
| `cvbs_enhacne_mode` | 0660 | RW | `disp_cvbs_enhance_show` | `disp_cvbs_enhance_store` |  |
| `enhance_denoise` | 0660 | RW | `disp_enhance_denoise_show` | `disp_enhance_denoise_store` |  |
| `enhance_detail` | 0660 | RW | `disp_enhance_detail_show` | `disp_enhance_detail_store` |  |
| `enhance_edge` | 0660 | RW | `disp_enhance_edge_show` | `disp_enhance_edge_store` |  |
| `enhance_force_fmt` | 0660 | RW | `disp_enhance_force_fmt_show` | `disp_enhance_force_fmt_store` |  |
| `enhance_contrast` | 0660 | RW | `disp_enhance_contrast_show` | `disp_enhance_contrast_store` |  |
| `enhance_saturation` | 0660 | RW | `disp_enhance_saturation_show` | `disp_enhance_saturation_store` |  |
| `enhance_bright` | 0660 | RW | `disp_enhance_bright_show` | `disp_enhance_bright_store` |  |
| `enhance_mode` | 0660 | RW | `disp_enhance_mode_show` | `disp_enhance_mode_store` | mode checks 3, 4 |
| `disp` | 0660 | RW | `disp_disp_show` | `disp_disp_store` |  |
| `sys` | 0660 | RW | `disp_sys_show` | `disp_sys_store` |  |

**hdmi device, group `attr` (likely `/sys/class/hdmi/hdmi/attr/`)** (registered by `hdmi_module_init`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `dvi_mode` | 0664 | RW | `dvi_mode_show` | `dvi_mode_store` |  |
| `phy_power` | 0664 | RW | `phy_power_show` | `phy_power_store` |  |
| `avmute` | 0664 | RW | `hdmi_avmute_show` | `hdmi_avmute_store` |  |
| `hdmi_source` | 0664 | RW | `hdmi_source_show` | `-` |  |
| `rxsense` | 0664 | RW | `hdmi_rxsense_show` | `-` |  |
| `hdmi_sink` | 0664 | RW | `hdmi_sink_show` | `-` |  |
| `hpi_read` | 0664 | RW | `hpi_read_show` | `hpi_read_store` |  |
| `hpi_write` | 0664 | RW | `hpi_write_show` | `hpi_write_store` |  |
| `esm_dump` | 0664 | RW | `esm_dump_show` | `esm_dump_store` |  |
| `hdcp_dump` | 0664 | RW | `hdcp_dump_show` | `-` |  |
| `hdcp_status` | 0664 | RW | `hdcp_status_show` | `hdcp_status_store` |  |
| `hdcp_enable` | 0664 | RW | `hdmi_hdcp_enable_show` | `hdmi_hdcp_enable_store` |  |
| `hdcp_type` | 0664 | RW | `hdmi_hdcp_type_show` | `hdmi_hdcp_type_store` |  |
| `cec_simulation` | 0664 | RW | `-` | `hdmi_cec_simulation_store` |  |
| `cec_enable` | 0664 | RW | `hdmi_cec_enable_show` | `hdmi_cec_enable_store` |  |
| `cec_dump` | 0664 | RW | `hdmi_cec_dump_show` | `-` |  |
| `debug` | 0664 | RW | `hdmi_debug_show` | `hdmi_debug_store` |  |
| `scdc_write` | 0664 | RW | `scdc_write_show` | `scdc_write_store` |  |
| `scdc_read` | 0664 | RW | `scdc_read_show` | `scdc_read_store` |  |
| `set_ddc` | 0664 | RW | `hdmi_set_ddc_show` | `hdmi_set_ddc_store` |  |
| `phy_read` | 0664 | RW | `phy_read_show` | `phy_read_store` |  |
| `phy_write` | 0664 | RW | `phy_write_show` | `phy_write_store` |  |
| `write` | 0664 | RW | `hdmi_test_reg_write_show` | `hdmi_test_reg_write_store` |  |
| `read` | 0664 | RW | `hdmi_test_reg_read_show` | `hdmi_test_reg_read_store` |  |
| `reg_dump` | 0664 | RW | `hdmi_test_reg_dump_show` | `hdmi_test_reg_dump_store` |  |
| `edid_test` | 0664 | RW | `hdmi_edid_test_show` | `hdmi_edid_test_store` |  |
| `edid` | 0664 | RW | `hdmi_edid_show` | `hdmi_edid_store` |  |
| `hpd_mask` | 0664 | RW | `hdmi_hpd_mask_show` | `hdmi_hpd_mask_store` |  |

**MBUS PMU device (hwmon-style, bandwidth counters)** (registered by `mbus_pmu_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `port_bw_satu` | 0644 | RW | `mbus_show_value` | `mbus_store_value` |  |
| `port_abs_bwl` | 0644 | RW | `mbus_show_value` | `mbus_store_value` |  |
| `port_abs_bwlen` | 0644 | RW | `mbus_show_value` | `mbus_store_value` |  |
| `port_bwlen` | 0644 | RW | `mbus_show_value` | `mbus_store_value` |  |
| `port_bwl2` | 0644 | RW | `mbus_show_value` | `mbus_store_value` |  |
| `port_bwl1` | 0644 | RW | `mbus_show_value` | `mbus_store_value` |  |
| `port_bwl0` | 0644 | RW | `mbus_show_value` | `mbus_store_value` |  |
| `port_acs` | 0644 | RW | `mbus_show_value` | `mbus_store_value` |  |
| `port_watt` | 0644 | RW | `mbus_show_value` | `mbus_store_value` |  |
| `port_qos` | 0644 | RW | `mbus_show_value` | `mbus_store_value` |  |
| `port_prio` | 0644 | RW | `mbus_show_value` | `mbus_store_value` |  |
| `pmu_totddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_gpuddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_iommu_ddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_ve1_ddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_g2d_ddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_csi1_ddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_di_ddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_csi0_ddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_de_ddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_ce_ddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_ve_ddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_dma_ddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_mahb_ddr` | 0400 | R | `mbus_show_value` | `-` |  |
| `pmu_cpuddr` | 0400 | R | `mbus_show_value` | `-` |  |

**each UART device** (registered by `sw_uart_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `dev_info` | 0444 | R | `sunxi_uart_dev_info_show` | `-` |  |
| `status` | 0444 | R | `sunxi_uart_status_show` | `-` |  |
| `loopback` | 0644 | RW | `sunxi_uart_loopback_show` | `sunxi_uart_loopback_store` |  |
| `ctrl_info` | 0444 | R | `sunxi_uart_ctrl_info_show` | `-` |  |

**deinterlace device** (registered by `di_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `tnrmode` | 0644 | RW | `di_device_tnrmode_show` | `di_device_tnrmode_store` |  |
| `timeout` | 0644 | RW | `di_device_timeout_show` | `di_device_timeout_store` |  |
| `client` | 0644 | RW | `di_device_client_show` | `di_device_client_store` |  |
| `info` | 0644 | RW | `di_device_info_show` | `-` |  |
| `debug` | 0644 | RW | `di_device_debug_show` | `di_device_debug_store` |  |
| `debug_mode` | 0644 | RW | `di_device_debug_mode_show` | `di_device_debug_mode_store` |  |

**IOMMU device** (registered by `sunxi_iommu_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `enable` | 0644 | RW | `sunxi_iommu_enable_show` | `sunxi_iommu_enable_store` |  |
| `profilling` | 0444 | R | `sunxi_iommu_profilling_show` | `-` |  |

**NAND driver** (registered by `nand_create_sys_fs`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `sunxi_nftl_version` | 0444 | R | `nand_nftl_version_show` | `-` |  |
| `nand_device_arch` | 0444 | R | `nand_arch_show` | `-` |  |
| `nand_badblock` | 0444 | R | `nand_badblock_show` | `-` |  |
| `nand_gcinfo` | 0444 | R | `nand_gcinfo_show` | `-` |  |
| `nand_gcone` | 0644 | RW | `nand_gcone_show` | `nand_gcone_store` |  |
| `nand_gcall` | 0644 | RW | `nand_gcall_show` | `nand_gcall_store` |  |
| `sunxi_ndfc_reg` | 0444 | R | `nand_ndfc_reg_show` | `-` |  |
| `sunxi_nand_clk_reg` | 0444 | R | `sunxi_nand_clk_reg_show` | `-` |  |
| `sunxi_nand_pio_reg` | 0444 | R | `sunxi_nand_pio_reg_show` | `-` |  |
| `nand_debug` | 0644 | RW | `nand_debug_show` | `nand_debug_store` |  |

**USB host/OTG controller** (registered by `(USB glue)`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `phy_threshold` | 0644 | RW | `show_phy_threshold` | `ehci_phy_threshold` |  |
| `phy_range` | 0644 | RW | `show_phy_range` | `ehci_phy_range` |  |
| `otg_phy_range` | 0644 | RW | `show_phy_range` | `udc_phy_range` |  |

**RTC device** (registered by `sunxi_rtc_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `min_year` | 0444 | R | `sunxi_rtc_min_year_show` | `-` |  |
| `max_year` | 0444 | R | `sunxi_rtc_max_year_show` | `-` |  |

**each TWI (I2C) controller device** (registered by `sunxi_twi_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `debug_chan` | 0644 | RW | `sunxi_debug_chan_show` | `sunxi_debug_chan_store` |  |
| `info` | 0444 | R | `sunxi_twi_info_show` | `-` |  |
| `status` | 0444 | R | `sunxi_twi_status_show` | `-` |  |
| `freq` | 0200 | W | `-` | `sunxi_twi_freq_store` | 100000, 200000 or 400000 |
| `twi_mode` | 0644 | RW | `sunxi_twi_mode_show` | `sunxi_twi_mode_store` |  |
| `slave_reset` | 0200 | W | `-` | `sunxi_twi_slave_reset_store` |  |

**camera (VIN) device** (registered by `vin_core_probe / vin_probe`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `vin_log_mask` | 0664 | RW | `vin_log_mask_show` | `vin_log_mask_store` |  |
| `subdev_api` | 0644 | RW | `vin_md_sysfs_show` | `vin_md_sysfs_store` |  |

**`car_reverse` class** (registered by `(car reverse driver)`) [G]

| File | Mode | R/W | show | store | Notes |
|---|---|---|---|---|---|
| `status` | 0775 | RW | `car_reverse_status_show` | `-` |  |
| `needexit` | 0775 | RW | `car_reverse_needexit_show` | `car_reverse_needexit_store` |  |
| `format` | 0775 | RW | `car_reverse_format_show` | `car_reverse_format_store` |  |
| `rotation` | 0775 | RW | `car_reverse_rotation_show` | `car_reverse_rotation_store` |  |
| `src` | 0775 | RW | `car_reverse_src_show` | `car_reverse_src_store` |  |
| `oview` | 0775 | RW | `car_reverse_oview_show` | `car_reverse_oview_store` |  |

## Table 2: upstream 4.9 attributes, by subsystem (count) [G]
`mmc` 36, `f2fs` 42, PMU events (`armv8pmu`) 48, block queue 25+, `input` 21, `regulator` 20, SCSI 20,
`wacom` 20, `cfq` 17, USB CDC 14, power/wakeup 18, generic `*_show` helpers 159, others (each ≤ 12).
Total generic: 996. Full list in the TSV.

## Table 3: `/dev/disp` ioctl commands [G] (names: BSP header, inferred unless noted)
Dispatcher `disp_ioctl` (…83f91ac), 32-bit compat `disp_compat_ioctl` (…83fa7d4); extra handlers can be
registered at run time (`disp_register_ioctl_func`, used by `composer_init`). Argument: pointer to
`unsigned long[4]` (0x20 bytes copied); some commands copy a further structure (0x10, 0x58 bytes, or a
length from the arguments). Commands at or above 0x280 are refused with a log line.
| Cmd | BSP name | Handler evidence |
|---|---|---|
| 0x0 | DISP_RESERVE0 |  |
| 0x3 | DISP_SET_BKCOLOR |  |
| 0x7 | DISP_GET_SCN_WIDTH |  |
| 0x8 | DISP_GET_SCN_HEIGHT |  |
| 0x9 | DISP_GET_OUTPUT_TYPE |  |
| 0xB | DISP_VSYNC_EVENT_EN |  |
| 0xC | DISP_BLANK | `disp_blank`, runtime PM |
| 0xD | DISP_SHADOW_PROTECT |  |
| 0xF | DISP_DEVICE_SWITCH |  |
| 0x10 | DISP_GET_OUTPUT |  |
| 0x11 | DISP_SET_COLOR_RANGE |  |
| 0x12 | DISP_GET_COLOR_RANGE |  |
| 0x14 | DISP_DEVICE_SET_CONFIG |  |
| 0x15 | DISP_DEVICE_GET_CONFIG |  |
| 0x16 | (device config, newer) |  |
| 0x17 | (device config, newer) |  |
| 0x18 | (vsync timestamp) | `bsp_disp_get_vsync_timestamp` |
| 0x47 | DISP_LAYER_SET_CONFIG | `mutex_lock`, `mutex_unlock` |
| 0x48 | DISP_LAYER_GET_CONFIG |  |
| 0x49 | DISP_LAYER_SET_CONFIG2 |  |
| 0x4A | DISP_LAYER_GET_CONFIG2 | `bsp_disp_hdmi_check_support_mode`, `mutex_lock` |
| 0xC4 | (HDMI/TV) |  |
| 0xC5 | (TV hot-plug) | `bsp_disp_tv_set_hpd` |
| 0x102 | DISP_LCD_SET_BRIGHTNESS | → `disp_lcd_set_bright` via the LCD device's `set_bright` (Redux map) [G]; Redux uses it |
| 0x103 | DISP_LCD_GET_BRIGHTNESS |  |
| 0x104 | DISP_LCD_BACKLIGHT_ENABLE |  |
| 0x105 | DISP_LCD_BACKLIGHT_DISABLE |  |
| 0x10B | DISP_LCD_SET_GAMMA_TABLE | `kfree`, `kmem_cache_alloc` |
| 0x10C | DISP_LCD_GAMMA_CORRECTION_ENABLE |  |
| 0x10D | DISP_LCD_GAMMA_CORRECTION_DISABLE |  |
| 0x10F | DISP_LCD_CHECK_OPEN_FINISH |  |
| 0x111 | DISP_TV_SET_GAMMA_TABLE | `kmem_cache_alloc` |
| 0x140 | DISP_CAPTURE_START |  |
| 0x141 | DISP_CAPTURE_STOP |  |
| 0x142 | DISP_CAPTURE_COMMIT |  |
| 0x143 | DISP_CAPTURE_COMMIT2 |  |
| 0x180 | DISP_ENHANCE_ENABLE |  |
| 0x181 | DISP_ENHANCE_DISABLE |  |
| 0x185 | DISP_ENHANCE_SET_MODE |  |
| 0x186 | DISP_ENHANCE_GET_MODE |  |
| 0x187 | DISP_ENHANCE_DEMO_ENABLE |  |
| 0x188 | DISP_ENHANCE_DEMO_DISABLE |  |
| 0x200 | DISP_SMBL_ENABLE |  |
| 0x201 | DISP_SMBL_DISABLE |  |
| 0x203 | DISP_SMBL_SET_WINDOW |  |
| 0x2C0 | DISP_MEM_REQUEST | `disp_ion_malloc` |
| 0x2C1 | DISP_MEM_RELEASE | `disp_ion_free` |
| 0x2C2 | DISP_MEM_GETADR |  |
| 0xFFFF | (sentinel / unsupported) |  |

## Table 4: module parameters (`/sys/module/<m>/parameters/`) [G]
286 parameters. Vendor ones:
| Parameter | Type | Mode |
|---|---|---|
| `cedar_ve.g_dev_major`, `g_dev_minor` | int | 0444 |
| `deinterlace.debug_mask` | int | 0644 |
| `snd_soc_sunxi_component_jack.jack_state` | int | 0644 |
| `sunxi_car_reverse.rotate` | int | 0644 |
| `vin_v4l2.act_name` / `ccm` (string), `act_slave` / `i2c_addr` / `use_sensor_list` (uint) | | 0644 |
| `xpad.auto_poweroff` (bool, 0644), `dpad_to_buttons` / `sticks_to_null` / `triggers_to_buttons` (bool, 0444) | | |
Upstream by module (count): rcutree 11, usbcore 10, core 10, vt 9, tcp_cubic 9, snd_usb_audio 9, ramoops 9,
scsi_mod 8, dm_mod 8, dm_bufio 8, snd_seq 7, atkbd 7, others ≤ 6.

## Table 5: input devices and codes
**`ANBERNIC-keys`** (`gpio-keys-polled`, poll 20 ms, DT `/soc@03000000/gpio_keys`) [D]: every key pin is an input with pull-up
(sunxi `gpios` cells: bank, pin, mux 0, pull 1, drive 2, data 1). Analog mux: `amux-en` PI0, `A0` PI1, `A1` PI2; `adc-en` PE11.
| Key | Pin | Event (code, decimal, kernel name of that number) |
|---|---|---|
| Up / Down | PA6 / PE0 | `EV_ABS` `ABS_HAT0Y` (0x11) −1 / +1 |
| Left / Right | PA8 / PA9 | `EV_ABS` `ABS_HAT0X` (0x10) −1 / +1 |
| A, B | PA0, PA1 | 0x130 (304, `BTN_SOUTH`), 0x131 (305, `BTN_EAST`) |
| X, Y | PA3, PA2 | 0x132 (306, `BTN_C`), 0x133 (307, `BTN_NORTH`) |
| L1, R1 | PA10, PA12 | 0x134 (308, `BTN_WEST`), 0x135 (309, `BTN_Z`) |
| Select, Start | PA5, PA4 | 0x136 (310, `BTN_TL`), 0x137 (311, `BTN_TR`) |
| Menu | PE3 | 0x138 (312, `BTN_TL2`) |
| L3 | PE8 | 0x139 (313, `BTN_TR2`) |
| L2, R2 | PA11, PA7 | 0x13A (314, `BTN_SELECT`), 0x13B (315, `BTN_START`) |
| R3 | PE9 | 0x13C (316, `BTN_MODE`) |
| Vol+ / Vol− | PE1 / PE2 | 0x73 `KEY_VOLUMEUP` / 0x72 `KEY_VOLUMEDOWN` |
**Note [D][N]:** the DT labels PA3 "x" (306) and PA2 "y" (307); Redux's stock remap table has 306 = Y and 307 = X.
One of the two is a labelling difference (DT name vs printed button); check with `evtest` (device check 4).

The same input device carries the sticks (axes set at run time from the joypad channel records, codes not
fixed in the binary; Redux reads them as `ABS_Z`/`ABS_RX` and `ABS_RY`/`ABS_RZ`) [G][D] and declares
`EV_FF`/`FF_RUMBLE` with a memoryless force-feedback handler [G].
| Other input | Codes [G] |
|---|---|
| Power key (`axp20x_pek_irq`) | `KEY_POWER` (0x74) press/release |
| Lid (`hall_press_work_func`) | `KEY_DELETE` (111) on close, `KEY_INSERT` (110) on open, released 1 s later |

## Table 6: character and misc devices [G]
| Device | Kind | Registered by |
|---|---|---|
| `disp` | char + class | `disp_module_init` |
| `cedar_dev` (video engine) | char + class | `sunxi_cedar_probe` |
| `deinterlace` | char + class | `di_probe` |
| `hdmi`, `cec` | char + class | `hdmi_module_init`, `hdmi_cec_init` |
| `sunxi_soc_info` | misc (dynamic minor) | `soc_info_ops` |
| `sst_storage` | misc | (secure storage) |
| `mtp_usb`, `usb_accessory` | misc | Android gadget functions |
| `ashmem`, `uinput`, `uhid`, `tun`, `rfkill`, `loop-control`, `device-mapper`, `autofs`, `cuse` | misc | upstream |
| `optee-clnt`, `optee-supp` | TEE | upstream OP-TEE |
No vendor `/proc` entries found (callers of `proc_create_data` are all upstream: `key_proc_init`,
`proc_version_init`, network and SCSI) [G].

## For Redux and mainline
- Redux on stock can use the battery-device files above (`moto`, the LEDs, `hallkey`, `spk_state`) instead of
  guessing; none of them exist on mainline (each has a mainline equivalent or none: rumble → G6, LEDs → `leds`
  class if the board tree adds them, lid → `SW_LID`).
- `/dev/disp` has no mainline equivalent (DRM/KMS); Redux's backlight path changes on mainline (R21 map).

## Device checks (optional, read-only on stock)
1. `ls /sys/class/power_supply/axp2202-battery/` and `cat` each read-only file in table 1 (`boot_mode`,
   `otg_id`, `spk_state`, `display_id`, `hallkey`).
2. `ls /sys/class/disp/disp/attr/ /sys/class/hdmi/hdmi/attr/` (confirms the two "likely" folders).
3. `cat /sys/class/sunxi_info/sys_info`; `ls /sys/power/sunxi_debug/`.
4. `evtest` on `ANBERNIC-keys`: press the printed X and Y and note the codes (306/307).
