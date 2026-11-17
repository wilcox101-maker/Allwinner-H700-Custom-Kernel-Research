# R2: FEL test kit for our u-boot (device task K4)

Date: 2026-11-14. Task R2 (Kernel Research). **Written on the desk; none of these commands has run
against an RG34XX-SP.** Expected output below is what the code prints, not a captured log. Use after
K3 (serial console) and after Redux v0.5 frees the device.

## What FEL gives us
The H700's boot ROM has a USB recovery mode (FEL). In FEL, the host sends our SPL + u-boot over USB
**straight into RAM** and starts it. **Nothing is written to any card or to the device.** Power-off
returns the unit to normal. It is the safest first run of our boot chain (R1).

## 1. Prerequisites
- **Serial console (K3)** connected at 115200 8N1. FEL itself gives little feedback; the console shows
  SPL, BL31 and u-boot.
- **DRAM type known** (Q10, 2026-11-17): from the hardware version Dale states (v1.0 = 2 GB LPDDR4; Dale's
  unit) or from stock boot0's line `vaild para:… select dram para15` = LPDDR4 (`para14`/`para0` = LPDDR3).
  LPDDR4 → lpddr4 binary, LPDDR3 → lpddr3 binary. **If unknown, stop**: the wrong binary can
  put 1.2 V on 1.1 V memory (R1 §4).
- Binaries from `scripts/build-uboot.sh` (R1): `u-boot-rg34xxsp-lpddr4-2026.10.bin` (or lpddr3) and
  `SHA256SUMS`. Check: `sha256sum -c SHA256SUMS`.
- A host with `sunxi-fel`:
  - **Ubuntu 24.04** (bare metal or live USB, simplest): `sudo apt install sunxi-tools` (1.4.2+git20221128,
    knows the H616; checked on the desk). Add a udev rule or use `sudo`.
  - **Windows (Dale's PC):** either WSL2 with `usbipd-win` to pass the device through (`usbipd list`,
    `usbipd bind --busid <id>`, `usbipd attach --wsl --busid <id>`) and then the Ubuntu steps; or a native
    Windows `sunxi-fel` build with the WinUSB driver installed for "Allwinner FEL" via Zadig. Both untested
    here; the live USB avoids driver work.
- USB-C data cable from the host to the device's USB-C port.

## 2. Enter FEL
1. Device **off**, **both cards out** (so the BROM finds no SPL).
2. Connect USB-C to the host, press power. The screen stays black: that is expected.
3. On the host:
   ```
   sunxi-fel -l
   sunxi-fel version
   ```
   Expected: `-l` lists one device; `version` prints a line starting `AWUSBFEX soc=00001823(H616)`.
   On Linux, `lsusb` shows `1f3a:efe8` (Allwinner FEL).

If nothing appears:
- Check the cable carries data.
- Check the port is the SoC's USB OTG port, not a charge-only path. This is unconfirmed on the RG34XX-SP: K4 is the first check.
- Plan B: a spare card with sunxi-tools' `fel-sdboot.sunxi` written at 8 KiB forces FEL. It's a destructive write to that spare card only, so confirm first.

## 3. Run our u-boot from RAM
```
sunxi-fel -v uboot u-boot-rg34xxsp-lpddr4-2026.10.bin
```
`sunxi-fel` loads the SPL, waits for DRAM init, copies BL31 + u-boot, and starts them.

Expected on the **serial console** (abridged, in order):
```
U-Boot SPL 2026.10-rg34xxsp (Oct 05 2026 - 21:35:33 +0000)
DRAM: 1024 MiB                 <- or the unit's size; a hang here = wrong DRAM binary/values
Trying to boot from FEL
NOTICE:  BL31: v2.14.0(release):v2.14.0
NOTICE:  BL31: Detected Allwinner H616 SoC (1823)
...
U-Boot 2026.10-rg34xxsp (Oct 05 2026 - 21:35:33 +0000) Allwinner Technology
CPU:   Allwinner H616 (SUN50I)
Model: Anbernic RG35XX 2024     <- u-boot's own DT; expected, see R1 §3
DRAM:  1 GiB
...
RG34XX-SP: panel ID PE6=0, fdtfile=allwinner/sun50i-h700-anbernic-rg34xx-sp-redux-panel.dtb
...
Hit any key to stop autoboot:  2
```
With no card, autoboot then finds nothing to boot. Press a key at the prompt, then:
```
=> printenv fdtfile panel_id
=> bdinfo
```
Record:
- the full console log;
- `fdtfile` and `panel_id`: `boe` means PE6 low (the original panel);
- the DRAM size;
- whether the screen stayed dark. u-boot has no display driver here, so a dark screen is expected.

## 4. Pass / fail
| Result | Meaning | Next |
|---|---|---|
| All lines above, `PE6=0`, `boe` | SPL, DRAM, BL31, u-boot and our patch work on this unit | first spare-card boot (R1 §7) |
| `PE6=1` | newer panel (K9 case) | record; image boots without display (Q3) |
| Hang after `U-Boot SPL` / no `DRAM:` | DRAM init failed | power off; recheck K3's DRAM type; do **not** write a card |
| No `BL31` lines, or reset loop | BL31/handoff problem | log and stop |
| Device not in FEL | cable, port or no-card behaviour | try §2 plan B |

## 5. Safety
- FEL runs only in RAM. Power-off undoes it.
- Don't run `sunxi-fel write`, `spiflash-*` or any FEL command not listed here.
- Don't write a card in this test. A card write is the next step, on a spare card only, after this passes.
