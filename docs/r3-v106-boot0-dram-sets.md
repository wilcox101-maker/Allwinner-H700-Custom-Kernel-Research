# R3: V1.0.6 boot0 DRAM parameter sets and strap selection

Deep Research, 2026-11-13. **Desk only: nothing ran on the device.** Master list task R3.

## Answer in one paragraph
Stock boot0 picks its DRAM settings with Allwinner's **`DRAM.ext`** mechanism. The 2025 boot0 has it switched **off** (mode 0) and always uses its built-in **LPDDR4 @ 672 MHz** block. The V1.0.6 boot0 switches it **on** (mode 1) and reads **four straps, PH6/PH7/PH8/PH10, with pull-ups**, as a 4-bit index. **Index 15 (all four high) selects LPDDR4 @ 672 MHz; index 14 (PH6 low) selects LPDDR3 @ 672 MHz; index 0 (all low) uses the built-in LPDDR3 block.** Indexes 1–13 hold an unedited SDK placeholder (DDR3 @ 792 MHz) that would almost certainly fail on this board. So the original board most likely leaves all four straps open (reads 15 → LPDDR4), and the revised board ties at least PH6 low [inferred from the table; the board straps are unconfirmed]. For our image this confirms the plan: **one u-boot SPL per DRAM type**, LPDDR4 for Dale's unit, chosen at image-build time, as ROCKNIX does. A strap-reading SPL is possible later but isn't needed for v0.x.

## 1. Where the data is (both images, read-only)
- boot0 (`eGON.BT0`) is 64 KiB at 8 KiB of the card; V1.0.6 has an identical backup copy at 256 KiB.
- Files analysed (SHA-256):
  - 2025 `RG34XXSP.img` boot0: `f8ded7fb2363…8aecfe1`
  - V1.0.6 `RG34XXSP-V1.0.6-EN16GB-260526.IMG` boot0: `b0db8859bbdc…8d096562`
- Layout, recovered from the selection routine (Thumb code at load address `0x233c0` in V1.0.6, `0x23388` in 2025; same code in both):

| Offset | Content |
|---|---|
| `0x038`–`0x0b7` | Default DRAM block, 32 words: `dram_clk`, `dram_type`, `dx_odt`, `dx_dri`, `ca_dri`, `odt_en`, `para1`, `para2`, mode registers…, `tpr6` @ `0xa0`, `tpr10`, `tpr11`, `tpr12`, `tpr13` @ `0xb0` |
| `0x348` | Magic `DRAM.ext` (a mismatch prints `extd_head bad magic` and keeps the default) |
| `0x350` | Mode byte: 0 = off, **1 = GPIO straps**, 2/3 = ADC-based variants (not used here) |
| `0x354` | 4 GPIO slots × 8 bytes: `port (1 = PA … 8 = PH)`, `pin`, `func`, `pull`, `drv`, `data` |
| `0x374 + (i−1)·0x80` | 15 parameter sets for index i = 1…15, same 32-word layout as the default block |

## 2. The selection logic (V1.0.6 boot0, desk disassembly)
1. If header word `0x94` is negative, skip selection (prints `dram return write ok`). It is 0 in both images.
2. Check the `DRAM.ext` magic; configure the strap pins; wait 5 ms.
3. **Mode 1:** for slot n = 0…3, read the pin's bit from the PIO data register `0x0300B010 + (port−1)·0x24` and put it in bit n of the index. Slots: **PH6 → bit 0, PH7 → bit 1, PH8 → bit 2, PH10 → bit 3**, each input with pull-up.
4. **Fuse quirk:** if the speed fuse at `0x03006200` reads `0x5000`, SID `+0x228` is non-negative and bit 8 of SID `+0x22c` is clear, boot0 adds 16 to the index (it prints `total dram para:32`). The table has only 15 sets, so such a chip would always fall back to the default block. [Observed in code; whether any RG34XX-SP has that fuse is unknown. Fuse `0x5000` is one of the stock "mask 0x1" CPU bins.]
5. Index 0 → keep the default block. Index i ≥ 1 → if set i's `dram_clk` is non-zero, copy its 128 bytes over the default block; otherwise print `dram para%d invalid use default para`.
6. Print `vaild para:%d  select dram para%d` (count of non-empty sets, chosen index). **This line is in stock's boot0 UART log**, so a UART capture on stock (K3) shows Dale's index directly.

## 3. The sets

| Index | Straps PH10 PH8 PH7 PH6 | 2025 boot0 (mode 0) | V1.0.6 boot0 (mode 1) |
|---|---|---|---|
| 0 | 0 0 0 0 | **LPDDR4 @ 672** (always used) | LPDDR3 @ 672 (default block) |
| 1–13 | — | DDR3 @ 792 placeholder (ignored) | DDR3 @ 792 placeholder (**would be used**: likely boot failure) |
| 14 | 1 1 1 0 | placeholder | **LPDDR3 @ 672** |
| 15 | 1 1 1 1 | placeholder | **LPDDR4 @ 672** |

Values (hex), with mainline/ROCKNIX for comparison:

| Field | 2025 default (LPDDR4) | V1.0.6 idx 15 (LPDDR4) | mainline `anbernic_rg35xx_h700` = ROCKNIX `lpddr4` | V1.0.6 default (LPDDR3) | V1.0.6 idx 14 (LPDDR3) | ROCKNIX `lpddr3` |
|---|---|---|---|---|---|---|
| dx_odt / dx_dri | 08080808 / 0e0e0e0e | same | same | 06060606 / 0d0d0d0d | same | same |
| ca_dri / odt_en | 0e0e / 7887bbbb | same | same | 1919 / 9988eeee | same | same |
| para1 | 30fa | **310a** | — | 30ea | 30fa | — |
| para2 | 08001000 | **00000000** | — | 04001000 | 00001000 | — |
| tpr6 | **42808080** | 40808080 | 40808080 | 2fb08080 | same | 2fb08080 |
| tpr10 | 402f6633 | same | same | 402f4489 | same | 402f4489 |
| tpr11 | 23272724 | **00000000** | 1b1f1e1c | 0d0f0c10 | 0e0e0f0e | 10121013 |
| tpr12 | 05050407 | **00000000** | 06060606 | 0e0e0d0e | 0f10110f | 0d0e0d0e |
| tpr13 | 02008c60 | 02008c60 | — | 00008c60 | 00008c60 | — |

Observations:
- **The drive/ODT values agree everywhere**, which is what the SPL choice depends on. Our LPDDR4 SPL (mainline defconfig values) matches stock on every field mainline exposes **except TPR11/TPR12**, and stock itself uses three different TPR11/12 pairs (2025: trained-looking values; V1.0.6 idx 15: zero). These look like per-batch delay tuning [hypothesis]. Mainline's/ROCKNIX's `1b1f1e1c / 06060606` is a third pair, and ROCKNIX boots on these units, so it is our default. **K4/K2 confirm it.**
- **TPR6 `0x42808080` (2025) vs `0x40808080`** (the open item from 20:10): V1.0.6's own LPDDR4 set went back to `0x40808080`, the mainline value. Nothing to change on our side.
- **para2**: 2025 `0x0800_1000`, V1.0.6 default `0x0400_1000`, set 14 `0x0000_1000`, set 15 `0`. The high half looks like a size hint in MB (2048 / 1024 / 0 = auto) [hypothesis, unverified]. Mainline u-boot detects size itself, so this doesn't affect us; it does suggest that the V1.0.6 default block came from a 1 GB LPDDR3 unit.

## 4. What this means for our image
1. **Build one SPL per DRAM type** (as ROCKNIX does) and choose by image or by a first-boot tool. Dale's original unit: LPDDR4. Unchanged from R1's plan.
2. **Optional later: a strap-reading SPL.** Mainline SPL could read PH6/7/8/10 (pull-ups, 5 ms) and pick between two compiled-in H616 DRAM configs. That needs both LPDDR3 and LPDDR4 init in one SPL, which mainline's H616 driver doesn't support at once (`SUNXI_DRAM_H616_LPDDR3` vs `_LPDDR4` is a build choice). Not worth it for v0.x; logged as an idea, not a task.
3. **Wrong-SPL risk** (KR 19:40 item 4): with the LPDDR3 SPL, an LPDDR4 board also gets the DDR3 image's 1.2 V `vdd-dram`. The straps are the only on-board identifier we know of; a recovery card should therefore carry the SPL that matches the board, and the image name must say which DRAM type it is for.
4. **Device checks (no new K-ID needed):** K3/K4. On stock, a UART capture shows `vaild para:… select dram para<N>`: N = 15 confirms LPDDR4 and "all straps open" on Dale's unit. Added to K3 in the master list (the first stock UART capture).

## 5. Tool
`tools/boot0_dram_ext.py BOOT0.bin` prints the mode, strap pins and every set, and a field table of the non-placeholder sets. Read-only. Extract boot0 first with `dd if=<image> of=boot0.bin bs=1024 skip=8 count=64` (reads only).

## 6. Sources
- Dale's stock images, read-only, in `Downloads\Anbernic RG34xxSP` (2025 card dump and V1.0.6 factory `.IMG`); boot0 copies were taken with `dd` reads only.
- Capstone Thumb disassembly of both boot0s around the `DRAM.ext` string references (literal pool at `0x23564` in V1.0.6).
- Mainline u-boot `master` `6487c50` (2026-11-13): `configs/anbernic_rg35xx_h700_defconfig`.
- ROCKNIX `distribution` `next` `4fc79d7`: `projects/ROCKNIX/devices/H700/packages/u-boot-DDR{3,4}/sources/configs/anbernic_rg35xx_h700_lpddr{3,4}_defconfig`.
