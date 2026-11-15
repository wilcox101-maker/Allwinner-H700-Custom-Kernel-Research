# W3.2: stock kernel modules (Ghidra plan, 2026-11-15)

Kernel Research chat, desk only. The 17 `.ko` files in `/lib/modules` of the V1.0.6 rootfs (`4.rootfs.img`, read
with `debugfs -c`, never mounted or written), their `modinfo`, symbol tables and strings, the stock DT and
`/etc/rc.local`. Copies stay in Dale's `REA\BootImage\modules-v106`. Tags: **[G]** static analysis (ELF symbols,
initialised data), **[D]** strings / DT / config. No code reproduced.

## Answer
- **Only two modules are loaded by the stock rootfs** [D]: `/etc/rc.local` runs `insmod` for `8821cs.ko`
  (Wi-Fi) and `/lib/modules/mali_kbase.ko` (GPU), with **no module parameters**. The other 15 (camera sensors,
  UVC/gspca, BT low-power, backlight class) are shipped but not loaded there; other loaders (appfs scripts) are
  Deep Research's W3.6.
- **GPU: Mali `r20p0-01rel0`** (UK 11.17), sunxi glue `mali_kbase_config_sunxi.c`, DVFS through `devfreq` with
  the stock DT's v1 `operating-points` (table 2). It imports `regulator_*` and `sunxi_get_soc_bin`, but the DT
  GPU node has **no supply**, so voltage changes have no target (matches the DCDC2 finding) [G][D].
- **Wi-Fi: Realtek `8821cs` v5.5.1_32758.20190403** with BT-coex `COEX20180712-3232`, firmware **built in**
  (version 20, sub 1; NIC 137,616 bytes, SPIC 71,264 bytes) [G]. **Power save is on by default**:
  `rtw_power_mgnt = 2` (max), `rtw_ips_mode = 1`, `rtw_lps_level = 1`, `rtw_smart_ps = 2` [G].
  Country: `rtw_channel_plan = 0xFF` (not set → from efuse/default) [G]. It looks for an efuse map at
  `/system/etc/wifi/wifi_efuse_8821cs.map` [D].
- Build path in the Mali module: `…/allwinner/h700/rg34xxsp/sdk/dynamic_standby/kernel/linux-4.9/…` [D]: the
  SDK branch is named "dynamic_standby", but the kernel itself has no dynamic-standby code (G1).

## Data table 1: modules [D]
| Module | Version / description | Size | Loaded by rc.local | Depends |
|---|---|---|---|---|
| `mali_kbase.ko` (top of `/lib/modules`) | r20p0-01rel0 (UK 11.17) | 17.6 MB | **yes** | – |
| `kernel/drivers/net/wireless/rtl8821cs/8821cs.ko` | v5.5.1_32758.20190403_COEX20180712-3232 | 3.9 MB | **yes** | – |
| `kernel/drivers/bluetooth/rtl_btlpm.ko` | Bluetooth Sleep Mode Driver 1.2 | 0.4 MB | no | – |
| `kernel/drivers/bluetooth/bcm_btlpm.ko` | Bluetooth Sleep Mode Driver 1.3 | 0.4 MB | no | – |
| `…/sunxi-vin/modules/sensor/{gc030a,gc0310,gc2355,gc2385,gc5024,imx317}_mipi.ko`, `ov5640.ko` | camera sensors | 0.3–0.4 MB each | no | – |
| `kernel/drivers/media/usb/uvc/uvcvideo.ko` | 1.1.1 | 2.3 MB | no | videobuf2-vmalloc |
| `kernel/drivers/media/usb/gspca/gspca_main.ko` | 2.14.0 | 0.6 MB | no | – |
| `kernel/drivers/media/v4l2-core/videobuf2-vmalloc.ko` | – | 0.3 MB | no | – |
| `kernel/drivers/video/backlight/{backlight,lcd,generic_bl}.ko` | backlight / LCD class | 0.2–0.3 MB | no | generic_bl → backlight |
All: `vermagic=4.9.170 SMP preempt mod_unload modversions aarch64`, GPL. `8821cs` SDIO aliases: vendor 0x024C,
devices 0xC821 and 0xB821.

## Data table 2: GPU OPPs and power model (stock DT `gpu@0x01800000`) [D]
| Freq (MHz) | Voltage in table (mV) |
|---|---|
| 648 | 960 |
| 600 | 900 |
| 552 | 900 |
| 504 | 900 |
| 456 | 900 |
| 420 | 900 |
Other GPU node properties: clocks `clk_parent`, `clk_mali`, `clk_bak`; `gpu_idle = 1`, `dvfs_status = 1`,
`#cooling-cells = 2`; interrupts JOB 95, MMU 96, GPU 97 (SPI). Power model `ipa_dvfs`
(`arm,mali-simple-power-model`): static-coefficient 17000, dynamic-coefficient 750, `ts` = 254682, 9576, −104, 4,
thermal zone `gpu_thermal_zone`, ss-coefficient 36, ff-coefficient 291.

## Data table 3: Mali module interfaces [G][D]
| Kind | Names |
|---|---|
| Module parameters | `corestack_driver_control` (bool, 0), `platform_power_down_only` (bool, 0), `override_l2_hash`, `override_l2_size` (byte) |
| sysfs (GPU device) | `command`, `core_mask`, `dvfs_period`, `gpuinfo`, `js_ctx_scheduling_mode`, `js_scheduling_period`, `js_timeouts`, `lp_mem_pool_max_size`, `lp_mem_pool_size`, `mem_pool_max_size`, `mem_pool_size`, `pm_poweroff`, `power_policy`, `reset_timeout`, `soft_job_timeout` |
| Power policies | `coarse_demand`, `always_on` |
| devfreq governor | `simple_ondemand` |
| sunxi debugfs `sunxi_gpu` (entry names from strings) | `dump`, `dvfs`, `enable`, `freq`, `frequency`, `man_freq`, `power`, `scenectrl`, `status`, `voltage`, `write` |
| Scene modes | `SCENE_CTRL_NORMAL_MODE`, `SCENE_CTRL_PERFORMANCE_MODE` |
| Kernel imports of note | `sunxi_get_soc_bin`, `regulator_get_optional`/`set_voltage`, `devfreq_*`, `dev_pm_opp_*`, `thermal_zone_get_temp`, `clk_set_rate`, `clk_set_parent` |

## Data table 4: `8821cs` parameters with their built-in defaults [G]
Power and regulatory first; the full list (103 parameters, types, defaults, descriptions) is in
`REA\BootImage\modules-v106\8821cs-params.tsv`.
| Parameter | Default | Meaning (driver text where present) |
|---|---|---|
| `rtw_power_mgnt` | 2 | Power save: 2 = maximum |
| `rtw_ips_mode` | 1 | Inactive power save mode |
| `rtw_lps_level` | 1 | Leisure power save level |
| `rtw_smart_ps` | 2 | Smart power save |
| `rtw_low_power` | 0 | – |
| `rtw_lps_chk_by_tp` | 1 | LPS decided by throughput |
| `rtw_channel_plan` | 0xFF | Default channel plan when no country code is set |
| `rtw_country_code` | (unset) | – |
| `rtw_wireless_mode` | 95 | All 2.4/5 GHz modes |
| `rtw_vht_enable` / `rtw_ht_enable` | 1 / 1 | 802.11ac / n on |
| `rtw_bw_mode`, `rtw_tx_bw_mode` | 0x21 | 2.4 GHz 40 MHz, 5 GHz 80 MHz |
| `rtw_btcoex_enable` | 2 | BT coexistence by efuse |
| `rtw_ant_num` | 0 | by efuse |
| `rtw_RFE_type` | 64 | default |
| `rtw_load_phy_file` | 0x44 | PHY file bit map |
| `rtw_adaptivity_en` | 0 | off |
| `rtw_en_napi` / `rtw_en_gro` | 1 / 1 | – |
| `rtw_drv_log_level` | 3 | info |
| `rtw_max_roaming_times` | 2 | – |
| `rtw_pwrtrim_enable` | 1 | – |

## Data table 5: Bluetooth low-power modules [D]
`rtl_btlpm` / `bcm_btlpm`: parameter `assert_level` (int, default −1), GPIOs `bt_wake` and `bt_hostwake` (the stock
DT has `bt_wake` PG17 and `bt_hostwake` PG16 under the BT node), a `/proc/bluetooth/<dir>/lpm` entry. Not loaded by
`rc.local`.

## For mainline
- GPU: mainline Panfrost uses the DT OPP table and a supply; stock never changes the GPU voltage, so stock's 648 MHz
  at "960 mV" depends on DCDC2's boot value (K1 reads it).
- Wi-Fi: mainline `rtw88_8821cs` with `linux-firmware`'s `rtw8821c_fw.bin` (R4); stock's built-in firmware is v20.1.
  Power-save defaults are worth matching for battery life (mainline: `iw dev wlan0 set power_save on`).

## Device checks (optional, read-only on stock)
1. `lsmod`; `cat /sys/module/8821cs/parameters/rtw_power_mgnt` (if exposed); `iw dev wlan0 get power_save`.
2. `cat /sys/kernel/debug/sunxi_gpu/dvfs` or `…/frequency` (if debugfs is mounted).
