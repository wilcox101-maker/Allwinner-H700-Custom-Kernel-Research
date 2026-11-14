# R4: Noble firmware audit for the RG34XX-SP (Wi-Fi/BT, GPU, others)

Deep Research, 2026-11-13. **Desk only; nothing ran on the device.** Master list task R4.

## Answer in one paragraph
Ubuntu 24.04 (noble-updates) already carries the exact Wi-Fi and Bluetooth firmware that ROCKNIX ships for H700, in the small split package **`linux-firmware-realtek`** (6.2 MB download, 6.0 MB installed). Our image should install that package and **not** the `linux-firmware` metapackage, which pulls in about 470 MB of firmware for hardware this device doesn't have. The noble files are zstd-compressed, so our kernel needs `CONFIG_FW_LOADER_COMPRESS_ZSTD=y`. No other firmware is needed for the confirmed hardware: Panfrost on Mali-G31 needs none. One open item: stock Bluetooth uses a vendor config with four extra parameters that upstream's config lacks (§3). That needs a device check (proposed K16).

## 1. What the device needs (evidence)
| Function | Stock (2025 image, read-only) | Mainline/ROCKNIX | Firmware files |
|---|---|---|---|
| Wi-Fi | vendor out-of-tree `8821cs.ko` (`kernel/drivers/net/wireless/rtl8821cs/`); firmware built into the module | `rtw88` SDIO: `CONFIG_RTW88_SDIO`, `CONFIG_RTW88_8821C` (ROCKNIX `devices/H700/linux/linux.aarch64.conf`) | `rtw88/rtw8821c_fw.bin` |
| Bluetooth | `rtl_btlpm.ko` + vendor files `/lib/firmware/rtlbt/rtl8821c_fw` (54,892 B) and `rtl8821c_config` (41 B), i.e. the Realtek `rtk_hciattach` route | `hci_uart` (H5) + `btrtl` (`CONFIG_BT_HCIUART_RTL=y`, `CONFIG_BT_RTL=m`) | `rtl_bt/rtl8821cs_fw.bin`, `rtl_bt/rtl8821cs_config.bin` |
| GPU (Mali-G31) | `mali_kbase.ko` r20p0 | Panfrost | none (Bifrost Panfrost needs no firmware) |

ROCKNIX's H700 firmware list (`devices/H700/config/kernel-firmware.dat`, ROCKNIX `4fc79d7`) is those three Realtek files plus panel init files. The chip is the RTL8821CS (SDIO Wi-Fi + UART BT). That is inferred from both the stock module name and ROCKNIX's choice; device check: K2.

## 2. Noble package facts (archive.ubuntu.com, read 2026-11-13)
- `noble` release: `linux-firmware 20240318.git3b128b60-0ubuntu2` is one 475 MB package.
- `noble-updates`: `linux-firmware 20240318.git3b128b60.0ubuntu3.1` is now a **metapackage** (1.8 KB) that depends on 18 split packages. One of them is `linux-firmware-realtek 20240318.git3b128b60-0ubuntu3.1`, `Architecture: all`. Deb SHA-256 `93b11d4f7d086727f6d0fa980c4ee8439dbad50305e8958ca3f71be272f64833`.
- The package contents we need (after zstd decompression):

| File (noble path, `.zst`) | Size | SHA-256 (first 12) | Version |
|---|---|---|---|
| `/lib/firmware/rtw88/rtw8821c_fw.bin` | 139,472 | `2ef409bc4185` | rtw88 header v24.11 |
| `/lib/firmware/rtl_bt/rtl8821cs_fw.bin` | 56,648 | `3baa2eeaa43c` | Realtek patch fw 0x75b8f098, 2 patches |
| `/lib/firmware/rtl_bt/rtl8821cs_config.bin` → symlink to `rtl8761b_config.bin` | 25 | `6ddeb15f2358` | — |

- **Same bytes in 26.04:** `resolute`'s `linux-firmware-realtek 20260319.git217ca6e4-0ubuntu1` has identical hashes for all three. That release sits 10 days after ROCKNIX's pinned upstream `linux-firmware-20260309`, so ROCKNIX very probably ships the same bytes [inferred; not hashed from ROCKNIX's tarball]. Note: 26.04 moves firmware to `/usr/lib/firmware`; the kernel looks in both places.
- Licence (package `README`, which is upstream WHENCE): rtw88 and rtl_bt files are "Redistributable. See LICENCE.rtlwifi_firmware.txt". Ubuntu already redistributes them, so installing the package from the archive raises no new question. Shipping them inside a kernel image is a different matter (§4).

## 3. Bluetooth config: stock vs upstream (open item)
Both are Realtek config files: magic `55 ab 23 87`, then entries of `offset(le16) len(u8) data`.

| Entry | Stock `rtlbt/rtl8821c_config` | Upstream `rtl8821cs_config.bin` (= `rtl8761b_config.bin`) |
|---|---|---|
| `0x000c` (16 B, UART settings) | `02 80 92 04 50 c5 ea 19 e1 1b fd af 5f 01 a4 0b` | **identical** |
| `0x00d9` | `0f` | absent (upstream's non-S `rtl8821c_config.bin` has `d9 = 0f`) |
| `0x00e4` | `08` | absent |
| `0x008d` | `fa` | absent |
| `0x008f` | `bf` | absent |

- The UART block is the same, so the link setup (baud and flow control) should match. Its first word `0x04928002` is, I believe, Realtek's code for 1.5 Mbaud [unverified].
- The meaning of the four extra entries isn't public. They are probably board tuning (RF or power) [hypothesis].
- The firmware itself differs as well: stock's vendor build is 0x0bc6d607; upstream's is 0x75b8f098.
- **Proposed K16 (device, after v0.5):** BT on ROCKNIX or our image with the upstream config: pairing, a gamepad, A2DP audio, range at 3 m and 8 m. If it falls short, the fallback is a local override at `/lib/firmware/updates/rtl_bt/rtl8821cs_config.bin` that adds the four stock entries. That fallback is a parameter file derived from Anbernic's, so it needs Dale's call on licensing first (R9).

## 4. Recommendations for our image and kernel
1. **Packages:** install `linux-firmware-realtek` and `wireless-regdb`. Never install the `linux-firmware` metapackage, and keep it out of the seed: it would add about 470 MB.
   - Optional trim: a `dpkg` `path-exclude` file keeps only `rtw88/rtw8821c*` and `rtl_bt/rtl8821c*` (about 6 MB → 0.2 MB). This is only worth doing if the root filesystem size matters. The SD card isn't tight, so it's a low priority.
2. **Kernel config (for KR, R10/R14):**
   - `CONFIG_FW_LOADER_COMPRESS=y`
   - `CONFIG_FW_LOADER_COMPRESS_ZSTD=y` (required: noble ships `.zst`)
   - `RTW88_SDIO` and `RTW88_8821CS`, and `BT_HCIUART` with `BT_HCIUART_RTL` + `BT_RTL`, all **as modules**
   - **No `CONFIG_EXTRA_FIRMWARE`**
   ROCKNIX builds rtw88 into the kernel (`=y`) and embeds the three blobs with `CONFIG_EXTRA_FIRMWARE`. That puts redistributable-but-not-GPL blobs inside the GPL kernel image. Modules loaded after the root filesystem mounts avoid this and need no initramfs firmware (logged under R9).
3. **Board DT (for KR, R15):**
   - Wi-Fi: rtw88 SDIO binds by SDIO vendor/device ID, so no compatible string is needed; the mmc node only needs the power sequence (`mmc-pwrseq-simple` with the reset GPIO) and the power rails.
   - BT: `serdev` child `compatible = "realtek,rtl8821cs-bt"` with `enable-gpios`, `device-wake-gpios` and `host-wake-gpios` from stock `board.dts`.
   - Check against ROCKNIX's RG35XX-family DTs.
4. **Nothing else needed:** Allwinner H616/H700 needs no SCP firmware for our stack (no ARISC; suspend lives in TF-A, see sync KR 20:45). The AXP717, the audio codec and HDMI need none.

## 5. Sources
- Ubuntu archive indexes: `dists/{noble,noble-updates,resolute}/main/binary-amd64/Packages.gz`; debs `linux-firmware-realtek_20240318.git3b128b60-0ubuntu3.1_all.deb` and `…_20260319.git217ca6e4-0ubuntu1_all.deb`, unpacked and hashed in the cloud workspace.
- ROCKNIX `4fc79d7`: `projects/ROCKNIX/devices/H700/config/kernel-firmware.dat`, `devices/H700/linux/linux.aarch64.conf` (lines ~1840–1856, 1639–1652, 2725–2737), `packages/linux-firmware/kernel-firmware/package.mk` (`PKG_VERSION="20260309"`).
- Stock `RG34XXSP.img` (2025) rootfs, partition 5, read with `debugfs` (read-only) at offset: `/lib/firmware/{rtl_bt,rtlbt,rtlwifi}`; V1.0.6 module tree `kernel/drivers/net/wireless/rtl8821cs/8821cs.ko`, `kernel/drivers/bluetooth/rtl_btlpm.ko`.
