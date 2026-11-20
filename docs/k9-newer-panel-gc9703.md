# K9 (desk part): the newer RG34XX-SP panel is a GalaxyCore GC9703-family controller

Date: 2026-11-20. Deep Research, at Dale's request ("reverse engineer what we have", Ghidra run locally).
**Desk only: not checked on a device.** Tags as in `ghidra-plan.md`: [G] Ghidra/static, [S] public source.
The stock init sequence itself is stock-derived and is not in this repo (rule R9); only its identifying features are.

## Result
- The panel selected by **PE6 high** (stock `lcd_type` 0) is driven by a **GalaxyCore GC9703-family** controller. Confidence: high
  for the family, medium for the exact part. Until now it was "not identified" (R19 §3, K9).
- The stock **kernel** carries the same two sequences as stock u-boot, in one function that branches on `lcd_type` [G].
- Mainline Linux has no GC9703 panel driver that we know of. A driver entry needs multi-byte parameters (up to 44 bytes), which
  the NV3052C driver's `{cmd, val}` table can't hold, so this is a new small panel driver, not another NV3052C entry.

## Evidence
| Feature of the stock PE6-high sequence (V1.0.6) | Public GC9703 init ([S], ArtInChip `panel_dsi_gc9703.c`, Apache-2.0) | GC9702 ([S], Beken `lcd_mipi_gc9702_720x1280.c`) |
|---|---|---|
| Unlock command `D7 61 74 97` | **same** | `D5 61 74 97` (differs) |
| Page select `D0 10`, `D0 11`, `D0 12` | same | `D0 10`, `D0 11` |
| Page 10 opens with `60`–`6F` = `FF` (16 writes) | same | different values |
| Page 10 then `A9 13`, `A8`, `F5`, `FD`, `9D`, `A5 00`, `A6 C0 80`, `7A 25`, `7B 76`, `88 32`, `8A 20`, `AE F1`, `C1 C0`, `B8`, `B7 30`, `92` | same registers in the same order; `A5`–`C1` values identical; `A8`, `F5`, `FD`, `9D`, `B8`, `92` values differ (panel tuning) | different |
| Page 11: `B8`, `B9 FF`, `BA 8F`, `B3` (44 bytes), `B7 07`, `BC`, `A0`… | same registers, same lengths | similar layout |
| Page 12: 12-bit gamma tables in `80`–`9B` | not compared | not compared |

Limits: both public files drive MIPI-DSI panels; ours is initialised over 3-wire SPI and fed parallel RGB, so the interface
registers will differ. No GC9703 datasheet was found. A sibling part (the GC97xx family shares this command set) can't be ruled out
on the desk. K9 on a PE6-high unit (flex marking or ID read) confirms it.

## Stock kernel [G]
Ghidra 12.2 headless, read-only, on Dale's existing project (`REA\BootImage\ghidra-project`, Image V1.0.6, 4.9.170):
- `lcd_panel_fog_fj035fhd05_v1_init` (`0xffffff80084229b0`) prints `lcd_type` and branches on it: `lcd_type == 1` sends 145
  commands starting `FF 30 / FF 52 / FF 01` (NV3052C, original panel); otherwise 100 commands starting `D7 61 74 97`, ending
  `36 09`, `11`, `29`. Command writer `0xffffff8008421f18`, data writer `0xffffff800842247c`, delay `0xffffff800841a2d8`.
- `allen_get_lcd_type` (`0xffffff8008421ecc`) is exported but has no direct caller in the kernel image (no `bl` to it); it is there for modules.
- The driver name `fog_fj035fhd05_v1` is left over from another panel; the DT's `lcd_driver_name` is `rg34xxsp_v1`.
- u-boot (same image, `tools/extract_rg34xxsp_panels.py`): PE6 low 148 commands, PE6 high 101, same openings as the kernel's.

## What this changes
- Q3 (a) stays: PE6-high units boot without display until a driver exists. The fallback (b) is no longer needed as a guess.
- New desk task candidate: a `panel-galaxycore-gc9703` SPI/DPI driver with the sequence generated locally from a stock image,
  the same way as the NV3052C table (Q8 (a) pattern). Needs a PE6-high unit to test. Which panel Dale's unit has is not recorded here (K4 prints the PE6 line).

## Local files (Dale's PC, not in git)
- `REA\ghidra_scripts\DRDecompRange.java`: read-only headless script, decompiles every function in an address range.
- `REA\BootImage\decomp-dr-lcd\`: its output for the stock LCD panel drivers (180 functions). Stock-derived; deletable.

Tools: Ghidra 12.2 and JDK 25, both already in `REA\` (nothing installed on the PC); Python 3 + capstone in the cloud workspace.
