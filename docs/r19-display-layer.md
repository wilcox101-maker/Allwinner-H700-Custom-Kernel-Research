# R19: display layer for the mainline kernel (desk only)

Date: 2026-11-14. Task R19 (Kernel Research), following decision Q6 (Dale, 2026-11-14): the kernel
base is mainline plus `patches/linux`, and display comes as a **separate, pinned layer**.
Revised the same day for decision **Q8 (a)** (Dale): the panel runs on the upstream NV3052C panel
driver with our entry, instead of an unmerged generic panel driver loading a firmware file (§4).

**Nothing here has run on an RG34XX-SP.** Everything below is build, schema and file-format
checking on a desk. The open device checks are listed at the end.

## 1. What the layer is
Mainline (torvalds `97d73c8`, after v7.4-rc2) already has the H616 DE33 mixer driver
(`sun8i_mixer.c`, `allwinner,sun50i-h616-de33-mixer-0`) and the NV3052C panel driver
(`panel-newvision-nv3052c.c`, used for the RG35XX family). It does not have the H616
display-engine compatible, the LCD TCON, the H616 DT nodes, the H616 PWM controller or an entry
for the RG34XX-SP panel.

Two patch series posted to the kernel lists supply the SoC parts. We carry them **by reference**:
`patches/upstream/display-layer.txt` names each series by patchwork ID, version, date and author
and pins every patch by `git patch-id --stable`. No code from these series is stored here.

| Series (patchwork) | Version, date, author | Patches used | Gives |
|---|---|---|---|
| [984067](https://patchwork.kernel.org/series/984067/) | v2, 2025-07-20, Ryan Walklin | 1–5, 7–11 (skip 6: already upstream; skip 12: RG35XX panel) | H616 DE and TCON TOP compatibles, R40/H616 LCD TCON support, DE33 bus binding, DE/mixer/TCON/LCD-pin DT nodes in `sun50i-h616.dtsi` |
| [1202273](https://patchwork.kernel.org/series/1202273/) | v12, 2026-11-04, James Hilliard (patches by Richard Genoud) | 1–5 | H616 PWM support in `pwm-sun8i`, its binding and DT node (backlight on PWM0 / PD28) |

Our own patches on top (`patches/linux-display/`, checkpatch clean apart from the usual
"does MAINTAINERS need updating?" for the new binding file):
- `0001` drm/panel: nv3052c: two per-panel fields, `skip_common_regs` (the panel's table is its
  vendor's complete sequence, so the driver's common registers are not sent after it) and
  `exit_sleep_delay_ms`. Existing panels leave both at zero and behave as before.
- `0002` dt-bindings: `anbernic,rg34xx-sp-panel.yaml`, modelled on the RG35XX panel binding
  (3-wire SPI, reset, power, port). Its maintainer line is a placeholder until a person takes it.
- `0003` drm/panel: nv3052c: the RG34XX-SP entry: the init table (§4), one 60 Hz mode
  (26 MHz, 720×480, h 47/4/42, v 33/4/16, syncs active low), 71×48 mm, RGB888, data-enable
  high, pixel data on the falling edge, common registers skipped, 120 ms after exit-sleep.

### Why skip the common registers
The driver sends `common_init_regs` (gamma, source timing, page 0 set-up written for the RG35XX
and other panels) **after** each panel's own table. Simulated on the desk (page-aware), that
would change 72 of the 132 registers the stock sequence sets, including the gamma values and the
page 0 address-mode register `0x36` (stock `0x09`, common `0x0a`), and set 47 more that stock
leaves at their defaults. So the RG34XX-SP entry sends its own
complete sequence only, as stock u-boot and ROCKNIX's working setup do.

### History: the generic panel driver (dropped)
The first version of this layer (merged earlier on 2026-11-14) carried a third series,
[937983](https://patchwork.kernel.org/series/937983/) v2 (Hironori KIKUCHI): a generic MIPI
DPI+SPI panel driver that loads the init sequence from `panels/<compatible>.panel`, so no
stock-derived data entered kernel or repo. It is unmerged since 2025-02 and needed our fix-up to
build on mainline. Q8 (a) replaced it with the NV3052C entry; the series, its fix-up and the
panel-mipi binding patch are gone from the layer.

## 2. Adapting to today's mainline
The series were posted against older trees. `tools/apply_upstream.py` applies them with small,
recorded fixes; each fix is a literal edit stated in the manifest, never a hand edit in a tree.

| Patch | Drift | Fix in the manifest |
|---|---|---|
| 984067/2 | `allwinner,sun50i-a64-de2.yaml` child-node pattern was simplified upstream | `replace` the old pattern line with the current one |
| 984067/9 | the DE33 SRAM section it adds now exists upstream as `sram_c` | `drop-hunk` the SRAM node, `replace` the reference with `&sram_c` |

The tool checks the patch-id of every downloaded patch **before** the fixes, so a re-posted or
altered patch stops the run instead of applying silently. Each patch is committed with its
original author, date and message, so `git log` in the work tree shows who wrote what.

Result, 2026-11-14: all 15 upstream patches and our 3 apply on `97d73c8` + `patches/linux/0001-0006`.

## 3. RG34XX-SP wiring (`dts/sun50i-h700-redux-display.dtsi`)
Pipeline: mixer0 → TCON TOP → LCD TCON0 → 24-bit parallel RGB panel (NV3052C controller).

| Signal | Pin | Source |
|---|---|---|
| Panel SPI CS / SCK / MOSI (bit-banged, 3-wire) | PI8 / PI9 / PI10 | stock DT `lcd_gpio_0..4`; same as upstream RG35XX family |
| Panel reset (active low) | PI14 | stock DT |
| Panel power (3.3 V switch) | PI15 | stock DT |
| Backlight | PWM0 on PD28 | stock DT `pwm0` pins |
| Panel identity | PE6 strap, read by u-boot | `docs/rg34xxsp-panel-detect-and-uboot-patch.md` |

Backlight: 25 kHz (`pwms = <&pwm 0 40000 0>`), normal polarity, 256 levels, default 50. 25 kHz is
what ROCKNIX runs on this board on mainline (tag 20261101); stock uses 50 kHz. Not checked by us.

| DTB | Panel | Selected by |
|---|---|---|
| `sun50i-h700-anbernic-rg34xx-sp-redux-panel.dtb` | original (`anbernic,rg34xx-sp-panel`) | u-boot, PE6 low |
| `sun50i-h700-anbernic-rg34xx-sp-redux.dtb` | none (no display nodes) | PE6 high, or detection off |

**The newer panel (PE6 high) has no driver.** Its stock sequence (V1.0.6) is not an NV3052C
sequence: no `0xff 0x30 0x52` page selects, and many multi-byte commands (up to 44 parameter
bytes) that the NV3052C driver's `{ cmd, val }` table can't express. Its controller is not
identified (no match in mainline's panel drivers for its opening command `0xd7 0x61 0x74 0x97`).
**Update 2026-11-20 (desk):** the sequence matches the GalaxyCore **GC9703** family; see
[`k9-newer-panel-gc9703.md`](k9-newer-panel-gc9703.md). Not confirmed on hardware.
Until it is, PE6-high units boot without display, which is what Q3's recommendation already was
("no-panel until K9"). The earlier `-redux-v2-panel` tree is removed.

## 4. The panel's init table (`tools/gen_nv3052c_table.py`)
Q8 (a) allows exactly this sequence into GPL kernel source. Origin: the stock Anbernic u-boot
(U-Boot 2018.05, a GPL-2.0+ program) sends it on the PE6-low path; `tools/extract_rg34xxsp_panels.py`
reads it from a stock image into `stock_panel_seqs.json` (private, never committed).

`tools/gen_nv3052c_table.py` turns that JSON into the C table in patch `0003`:
1. prepares the commands exactly as `tools/gen_panel_firmware.py` does for v1 (register `0x23`
   on page 1 set to `0x00`, matching the active-low sync timing; stock's `0xa2` goes with its
   active-high syncs and longer frame);
2. refuses to print unless the result, encoded as a panel file, has the known-good SHA-256 of
   ROCKNIX 20261101's working v1 file: proof that the table holds the same commands that run this
   panel on mainline today;
3. drops the trailing exit-sleep (the driver sends it) and prints `{ cmd, val }` pairs with the
   page selects commented.

Check (2026-11-14, desk): the table comes out byte-identical from the stock 2025 image and the
V1.0.6 image (144 commands), and patch `0003` contains it unchanged.

`tools/gen_panel_firmware.py` stays as the reference for step 1–2; its `.panel` output has no
consumer in our kernel any more.

## 5. Build integration
- `scripts/workbench.sh --display`: after our 6 patches, applies the layer and
  `patches/linux-display/`, builds and `dtbs_check`s 8 DTBs (our 4 + the 4 upstream RG35XX trees
  that share the H616 include, to catch breakage the layer causes elsewhere), builds every C file
  that any patch touches with `W=1` (any warning fails), checkpatches our display patches and, with
  `--bindings`, runs `dt_binding_check` on 6 more schemas.
- `scripts/build-kernel.sh --display`: merges `config/rg34xxsp-display.config` (PWM_SUN8I,
  BACKLIGHT_PWM, SPI_GPIO, DRM_PANEL_NEWVISION_NV3052C, all modules) after the base fragment, keeps
  them through the module trim, checks every fragment line holds and every enabled DT node of the
  panel tree has a driver.

## 6. Results (desk, 2026-11-14, after the Q8 rework)
| Check | Result |
|---|---|
| Layer applies on `97d73c8` + 0001–0006 | 15/15 upstream patches (patch-ids verified) + our 3 |
| `dtbs_check`, 8 DTBs | 0 warnings each |
| `dt_binding_check`, 9 schemas | clean |
| `W=1` build of the 6 touched C files (cpufreq, codec, sun4i DRM ×2, PWM, NV3052C panel) | 0 warnings |
| checkpatch, our 9 patches | clean (`--no-signoff`; the MAINTAINERS note on the new binding aside) |
| Package build (`build-kernel.sh --display --build`) | builds; 12.8 MB `.deb`, 27.2 MB installed, 165 module files / 10.7 MB, vmlinuz 9.3 MB |
| Display modules in the package | `sun4i-drm`, `sun4i-tcon`, `sun8i-mixer`, `pwm-sun8i`, `pwm_bl`, `spi-gpio`, `panel-newvision-nv3052c` (no `panel-mipi`); the panel DTB |
| Boot path (step 2a2), DT coverage of the panel tree | all built in; 75 enabled nodes, 0 without a driver |

Caught on the way: the first package of the rework still contained the removed `-v2-panel` DTB.
Cause: an early copy of patch `0001` had picked up the workbench's local Makefile lines for our
`-redux` trees. Fixed (the patch touches only the driver now), and `workbench.sh` now fails if any
patch names a `-redux` tree. After the fix, the kernel's DTB list has the 4 intended RG34XX-SP trees.

## 7. Open device checks
These need the device (after Redux v0.5) and are in the master list:
1. **K18:** does the original panel come up on a PE6-low unit (image, no flicker, right colours,
   right orientation)? `dmesg` for nv3052c / sun4i errors.
2. **K19:** backlight polarity and 25 kHz vs stock 50 kHz (audible whine, flicker at low levels);
   the lowest level that is still visible.
3. **K9:** confirm what PE6-high units are; with a unit in hand, identify the newer panel's
   controller (marking on the flex cable, or the controller's ID registers read over SPI).
4. A 52 MHz (120 Hz) mode is used elsewhere for this panel; only 60 Hz is offered until K18 passes.
5. HDMI is not in this layer (separate later task).

## 8. Risks
- Two out-of-tree series: each rebase may need new manifest fixes. The patch-id pin makes drift
  loud, not silent.
- Our NV3052C patches touch an upstream driver; until they are merged upstream they are ours to
  rebase. They are small (two fields, one table, one binding).
- No hardware result yet. Do not ship a display DTB before K18 passes.
