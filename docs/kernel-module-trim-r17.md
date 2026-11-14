# R17: kernel module trim, and the gaps it found

Kernel Research chat, 2026-11-14. **Built, not booted.** Base: torvalds/linux `97d73c8` +
`patches/linux/0001-0006`, config from `config/rg34xxsp.config` (see `kernel-build-r10.md`).

## Result
| | R10 package | R17 package | Change |
|---|---|---|---|
| Modules | 924 files, 38.5 MB | **160 files, 10.6 MB** | −83 % files, −72 % size |
| Installed size | 56.4 MB | **26.9 MB** | −52 % |
| `.deb` file | 18.4 MB | 12.7 MB | −31 % |
| `vmlinuz` (gzip) | 9.3 MB | 9.3 MB | built-in code not trimmed yet |
| Clean build, 2 cores | 25 min | 16 min | |

Package: `linux-image-7.4.0-rc2-rg34xxsp_7.4.0~rc2-1_arm64.deb`. All three RG34XX-SP DTBs are in it.

## How it works
`scripts/build-kernel.sh` (default on; `--no-trim` to compare) turns off every option the base
config builds as a module, **unless** it is:
1. set in `config/rg34xxsp.config`, or
2. the driver of an enabled node in one of the three RG34XX-SP device trees
   (`tools/dt_driver_coverage.py --symbols`), so a new board node keeps its driver automatically,
   or
3. on the allowlist `config/module-keep.txt`, where every pattern says why it is kept.

`tools/gen_trim_config.py` writes the "is not set" fragment. Built-in (`=y`) options are untouched.

**Checks before any build** (each stops it):
- every fragment line holds (now 107 lines);
- every enabled node of the three trees has its driver;
- **no kept, user-selectable option was lost.** Turning off a module can silently disable
  another one that *depends on* it; the check compares base and result. Helper libraries with no
  menu entry may go once nothing selects them, and are listed, not failed.

## What it found
1. **iwd would not have worked with the R10 kernel.** iwd 2.14 (noble's version) checks its kernel
   options at start-up (`src/main.c`, `check_crypto()`, tag 2.14, commit `42b4da1`). Four of the
   options it lists were off: `CRYPTO_USER_API_HASH` and `CRYPTO_USER_API_SKCIPHER`, without which
   **iwd exits at start-up**, and `KEY_DH_OPERATIONS` (WPS) and `PKCS8_PRIVATE_KEY_PARSER`
   (WPA-Enterprise/TLS), which only disable those features. R5 recommends iwd. The fragment now
   carries every option iwd lists, built in. *(Wording made precise in the 2026-11-14 audit.)*
2. **Everyday handheld features were missing** (not trimmed: never on in `defconfig`):
   - **exFAT**, the format of SD cards over 32 GB, where games usually live;
   - **`uhid`**: BlueZ 5.72 (noble) handles Bluetooth input, including LE controllers, through
     `/dev/uhid` (`src/shared/uhid.c`, `profiles/input/hog-lib.c`; tag 5.72, commit `770ad56`);
   - **`uinput`**, for emulator frontends and remappers;
   - add-on **controller drivers** (Xbox `xpad`, PlayStation, Sony, Nintendo, Microsoft, Steam) with
     rumble and battery level, and **USB UAS** storage.
3. **The trim's own check caught a real loss:** `HID_PLAYSTATION` depends on
   `LEDS_CLASS_MULTICOLOR` (the light bar). It is on the allowlist now.
4. **Things that kept coming back** were switched off at the source, in the fragment:
   - TV tuners and DVB were pulled in by the media core's sub-driver auto-select. Media is now
     limited to platform devices (the Cedrus video engine) and HDMI-CEC.
   - Broadcom, Qualcomm, Marvell and TI Bluetooth UART protocols are off; the board is Realtek.
   - MIPI DSI is not kept: this panel is RGB with 3-wire SPI set-up.

## What was removed (630 options in the base, by kind)
Infrared-remote support (141 modules, mostly key maps), TV/DVB tuners, cameras and sensors (IIO, hwmon),
touchscreens, CAN, FPGA, CoreSight tracing, NFC, Type-C controllers, Ethernet MACs and PHYs for
other SoCs, other Wi-Fi/BT chips (Atheros, Broadcom, Marvell, TI, Redpine), DRM drivers and
panels for other GPUs and boards, ~70 audio codecs, RTCs and regulators for other boards,
btrfs, UBIFS, 9p, MD/DM, bridges, VLAN, DSA, traffic shaping.

## What is kept besides the board's own drivers
Wi-Fi/BT stacks and RFKILL; Allwinner display and HDMI drivers (ready for the display series);
Panfrost; Cedrus; on-board and USB audio; all crypto (Wi-Fi and iwd choose algorithms at run time);
FUSE and overlayfs; iptables/conntrack for a host firewall; common USB-Ethernet adapters and
USB-serial adapters; USB device mode (network and serial to a PC over USB-C).

## Checked
- `scripts/build-kernel.sh --build` from a clean build directory: all checks passed; 770 modules
  in the base, 162 after the trim (160 `.ko` files packaged).
- 40 named modules confirmed in the package by name, including `rtw88_8821cs`, `hci_uart`,
  `btrtl`, `adc-joystick`, `iio-mux`, `mux-gpio`, `sun20i-gpadc-iio`, the three `axp20x` power
  drivers, `sun4i-codec`, `panfrost`, `sunxi-cedrus`, `zram`, `exfat`, `uhid`, `uinput`, `xpad`,
  `hid-playstation`, `hid-nintendo`, `uas`, `snd-usb-audio`, `usb_f_ncm`.
- **Not checked:** no boot, so no module has been loaded on hardware. Removing a module is
  undone by adding a line to `config/module-keep.txt`.

## Next
- Built-in code is now the bigger share (`vmlinuz` 9.3 MB). A similar pass over `=y` options is
  riskier (boot-critical drivers), so it waits for a serial console (K3) to debug boots.
- R18: the kernel in QEMU with R5's rootfs, for RAM after boot.
