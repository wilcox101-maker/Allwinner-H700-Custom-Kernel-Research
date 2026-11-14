# RG34XX-SP panel identification: stock u-boot decoded, and a u-boot patch

Research note, 2026-11-13 (Deep Research chat). Static analysis of the stock bootloader on Dale's PC (read-only copies of `RG34XXSP.img`, 2025, and `RG34XXSP-V1.0.6-EN16GB-260526.IMG`). ROCKNIX `4fc79d7`, u-boot `v2026.01`. **Nothing here has run on the device.** The u-boot patch is build-tested only.

## 1. Results

| Question | Answer | Evidence |
|---|---|---|
| How does stock tell the panels apart? | **One pin: PE6**, read with the internal pull-up on, right after a reset pulse on **PI14** | Disassembly of `lcd_panel_uboot_fj035fhd05_v1_init` (stock u-boot 2018.05, at 0x4a0262e4 in both releases) |
| What does each level mean? | **PE6 low → `lcd_type=boe`**, the original panel. **PE6 high → `lcd_type=old` (2025)**, changed in V1.0.6 to the **v2 panel** sequence | Branch at `cmp r5,#1`; env set to `"boe"` / `"old"`; ` lcd_type=%s` appended to the kernel command line |
| Where did ROCKNIX's panel files come from? | From stock u-boot. `rg34xx-sp-v2-panel.panel` = the V1.0.6 PE6-high sequence, **byte-identical** apart from stock's trailing exit-sleep (`01 11`). `rg34xx-sp-panel.panel` = the PE6-low sequence with **one byte changed** (below) | `tools/extract_rg34xxsp_panels.py` rebuild + `cmp` |
| Which DTB for which level? | ROCKNIX: PE6 low → `sun50i-h700-anbernic-rg34xx-sp.dtb`; PE6 high → `…-v2-panel.dtb`. **Ours (patch defaults since 2026-11-14, Q3 a + Q8 a):** PE6 low → `sun50i-h700-anbernic-rg34xx-sp-redux-panel.dtb` (NV3052C); PE6 high → `sun50i-h700-anbernic-rg34xx-sp-redux.dtb` (no display until K9 identifies that panel's controller) | Mapping above + ROCKNIX DTS panel compatibles; R19 |
| Panel controller | NewVision **NV3052C**-family on the original panel (`FF 30 / FF 52 / FF 01` page select, as in the mainline `panel-newvision-nv3052c.c`) | Init sequence |
| DRAM cross-check | ROCKNIX's `lpddr3` u-boot defconfig = the V1.0.6 boot0 LPDDR3 set (`06060606/0d0d0d0d/1919/9988eeee`, TPR6 `2fb08080`, TPR10 `402f4489`). The `lpddr4` defconfig matches the 2025 boot0 set on clock, drive/ODT and TPR10, **not** on TPR6/TPR11/TPR12 (corrected 2026-11-14, audit). Full table: `docs/r3-v106-boot0-dram-sets.md` | boot0 at 8 KiB |

### Stock routine, decoded (2025 and V1.0.6 identical)
```
PI_CFG1  (0x0300B124) |= 0x11000111   ; PI8, PI9, PI10, PI14, PI15 → outputs (panel SPI: PI8 CS, PI9/PI10 bit-banged; PI14 reset)
PI_DAT   bit14: 1, mdelay(15); 0, mdelay(50); 1, mdelay(100)     ; panel reset pulse
PE_CFG0  (0x0300B090) PE6 = function 6 (EINT/input)
PE_PULL0 (0x0300B0AC) PE6 = 01 (pull-up)
lcd_type = !(PE_DAT (0x0300B0A0) bit 6)
lcd_type == 1 → init sequence A (148 cmds) → env lcd_type="boe"
lcd_type == 0 → init sequence B → env lcd_type="old" (2025) | v2 sequence (V1.0.6)
```

### The one byte that differs: register 0x23
Stock writes `0x23 = 0xA2`; ROCKNIX writes `0x23 = 0x00`. On the NV3052C, 0x23 is "RGB interface control" (DE mode / PCLK polarity per the mainline driver's comment). ROCKNIX's value suits mainline's RGB output timing. **Keep ROCKNIX's value**, and only revisit it if there's tearing or a shifted image on the original panel (device task K10).

### Risk this exposes
On 2025 firmware, **PE6 high meant a third, older panel** (`old`, closest to ROCKNIX's non-SP `rg34xx-panel`, 96.5% similar). V1.0.6 reuses PE6 high for the v2 panel, so Anbernic itself no longer drives the `old` panel. If any RG34XX-SP shipped with the `old` panel, both V1.0.6 and our detection would send it the v2 sequence. **Treat "PE6 high" as v2 only after checking at least one v2 unit** (K9, decision Q3). A safer future step: read the panel ID over SPI (needs the MISO pin, unknown).

## 2. Deliverables
| File | What |
|---|---|
| `patches/u-boot/0001-sunxi-rg34xxsp-dt-selection.patch` | u-boot patch (94 lines, 2 files). Applies cleanly to **plain v2026.01** and on top of ROCKNIX's two H700 u-boot patches |
| `tools/extract_rg34xxsp_panels.py` | Read-only tool: stock image → both init sequences (JSON) → optional PANEL-FIRMWARE rebuild using a template's header and timings |

The decoded stock sequences (JSON) are kept out of this repository until their redistribution terms are settled (R9); run the tool on your own image to produce them.

### The u-boot patch
- New option `CONFIG_ANBERNIC_RG34XXSP_DT_SELECTION` (default **n**; depends on `MACH_SUN50I_H616`), plus two string options for the DTB names.
- In `misc_init_r()`: same PI14 reset pulse, then PE6 input + pull-up. Sets `fdtfile` and `panel_id` (`boe` / `v2`) and prints `RG34XX-SP: panel ID PE6=<n>, fdtfile=<dtb>`. The pull-up is turned off again after the read. Setting env `panel_autodetect=no` skips it (manual override).
- Modelled on upstream's `CONFIG_PINEPHONE_DT_SELECTION` (one GPIO with a pull-up picks the DT).
- With extlinux `FDTDIR /dtbs`, u-boot loads `$fdtfile`, so **one image covers both panels**.
- Build test: v2026.01 + ROCKNIX `0001`/`0002` + `anbernic_rg35xx_h700_lpddr4_defconfig` + the option → `u-boot-sunxi-with-spl.bin` (584,149 bytes) built with aarch64-linux-gnu-gcc 13.3, no warnings; message string present in `u-boot.bin`. (Dummy BL31, so the image isn't bootable as built.)
- `checkpatch`: two warnings (`#ifdef`, same style as the PinePhone code) and a missing `Signed-off-by`. **Dale adds that** (`git commit --amend -s`) if it ever goes upstream.

### Build, test and recovery (illustrative; hardware steps need Dale)
```bash
# build (Linux/WSL2; aarch64 cross gcc; real BL31 from TF-A PLAT=sun50i_h616, or ROCKNIX's TF-A recipe)
git clone -b v2026.01 https://github.com/u-boot/u-boot && cd u-boot
for p in <rocknix>/projects/ROCKNIX/devices/H700/packages/u-boot-DDR4/patches/*.patch; do patch -p1 < "$p"; done
git am <path>/0001-sunxi-rg34xxsp-dt-selection.patch
cp <rocknix>/.../u-boot-DDR4/sources/configs/anbernic_rg35xx_h700_lpddr4_defconfig configs/
echo CONFIG_ANBERNIC_RG34XXSP_DT_SELECTION=y >> configs/anbernic_rg35xx_h700_lpddr4_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- anbernic_rg35xx_h700_lpddr4_defconfig
make CROSS_COMPILE=aarch64-linux-gnu- BL31=<bl31.bin> -j"$(nproc)"
```
**First hardware test = FEL, no card written:** `sunxi-fel uboot u-boot-sunxi-with-spl.bin` with no card in the boot slot. On the serial console, expect `RG34XX-SP: panel ID PE6=0` on an original-panel unit (`printenv fdtfile panel_id`). Nothing is stored, and a power cycle returns to stock. Only after that: write to a **test card** at 8 KiB (`dd bs=1024 seek=8`), never the stock card. ⚠ Writing at 8 KiB replaces that card's boot0.

## 3. Next steps
1. Dale: does the FEL test show PE6=0 on his unit (K4)? That also confirms LPDDR4 u-boot on his board.
2. Find a v2-panel (revised) unit report, to confirm that PE6 reads 1 there (K9).
3. Done since: the V1.0.6 boot0 DRAM-set table is decoded in `docs/r3-v106-boot0-dram-sets.md` (PH6/7/8/10 straps).

## Sources
- Stock binaries (local, read-only): u-boot `2018.05 (Apr 14 2025 - 12:01:32 +0800)` and `(May 26 2026 - 15:48:53 +0800)`, from the boot package at 16,400 KiB.
- ROCKNIX `projects/ROCKNIX/packages/linux-firmware/kernel-firmware/extra-firmware/panels/` and `devices/H700/packages/u-boot-DDR{3,4}` @ `4fc79d7`: https://github.com/ROCKNIX/distribution
- Mainline NV3052C panel driver: https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/panel/panel-newvision-nv3052c.c
- u-boot v2026.01 `board/sunxi/board.c` (PinePhone DT selection precedent): https://github.com/u-boot/u-boot/blob/v2026.01/board/sunxi/board.c
