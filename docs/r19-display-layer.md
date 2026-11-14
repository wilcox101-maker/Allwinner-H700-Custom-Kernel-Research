# R19: display layer for the mainline kernel (desk only)

Date: 2026-11-14. Task R19 (Kernel Research), following decision Q6 (Dale, 2026-11-14): the kernel
base is mainline plus `patches/linux`, and display comes as a **separate, pinned layer**.

**Nothing here has run on an RG34XX-SP.** Everything below is build, schema and file-format
checking on a desk. The open device checks are listed at the end.

## 1. What the layer is
Mainline (torvalds `97d73c8`, after v7.4-rc2) already has the H616 DE33 mixer driver
(`sun8i_mixer.c`, `allwinner,sun50i-h616-de33-mixer-0`). It does not have the H616 display-engine
compatible, the LCD TCON, the H616 DT nodes, the H616 PWM controller or a driver that can run the
RG34XX-SP panel. Three patch series posted to the kernel lists supply those. We carry them **by
reference**: `patches/upstream/display-layer.txt` names each series by patchwork ID, version,
date and author and pins every patch by `git patch-id --stable`. No code from these series is
stored in this repository.

| Series (patchwork) | Version, date, author | Patches used | Gives |
|---|---|---|---|
| [984067](https://patchwork.kernel.org/series/984067/) | v2, 2025-07-20, Ryan Walklin | 1–5, 7–11 (skip 6: already upstream; skip 12: RG35XX panel) | H616 DE and TCON TOP compatibles, R40/H616 LCD TCON support, DE33 bus binding, DE/mixer/TCON/LCD-pin DT nodes in `sun50i-h616.dtsi` |
| [1202273](https://patchwork.kernel.org/series/1202273/) | v12, 2026-11-04, James Hilliard (patches by Richard Genoud) | 1–5 | H616 PWM support in `pwm-sun8i`, its binding and DT node (backlight on PWM0 / PD28) |
| [937983](https://patchwork.kernel.org/series/937983/) | v2, 2025-02-26, Hironori KIKUCHI | 1–3 | Generic MIPI DPI+SPI panel driver (`panel-mipi.c`) that reads the panel's init sequence and timing from a firmware file |

Our own patches on top (`patches/linux-display/`, checkpatch clean):
- `0001` adds `anbernic,rg34xx-sp-panel` and `anbernic,rg34xx-sp-v2-panel` to the
  `panel-mipi.yaml` binding, and `spi-3wire` (the RG34XX-SP panel is driven over 3-wire SPI).
  `dt_binding_check` is clean.
- `0002` makes the generic panel driver build on today's mainline: `drm_panel_init()` is gone,
  so the driver now allocates with `devm_drm_panel_alloc()`; it also rejects DSI pixel formats it
  has no bus format for (`MIPI_DSI_FMT_RGB101010` is new since the series). It is a fix-up for an
  unmerged series, to be folded into its next version rather than sent alone. Found by the first
  full package build of the layer (2026-11-14): the patch applied cleanly but did not compile.

### Why these three
- 984067 is the newest version of the H616 LCD series found on patchwork. ROCKNIX runs an LCD
  pipeline of this kind on the RG34XX-SP on mainline (tag 20261101); we have not compared its
  patches line by line with this version, and have not run either on our board.
- 1202273 v12 (2026-11-04) is the newest posting of the H616 PWM series.
- 937983 keeps the stock-derived panel init sequence **out of the kernel and out of this
  repository**: the driver loads `panels/<compatible>.panel` from the firmware directory at
  probe time. That fits rule R9 (stock data is not redistributed until its terms are known).
  It is not merged upstream; if a panel-specific driver (NV3052C) is preferred upstream later,
  only the panel node and one config option change.

## 2. Adapting to today's mainline
The series were posted against older trees. `tools/apply_upstream.py` applies them with small,
recorded fixes; each fix is a literal edit stated in the manifest, never a hand edit in a tree.

| Patch | Drift | Fix in the manifest |
|---|---|---|
| 984067/2 | `allwinner,sun50i-a64-de2.yaml` child-node pattern was simplified upstream | `replace` the old pattern line with the current one |
| 984067/9 | the DE33 SRAM section it adds now exists upstream as `sram_c` | `drop-hunk` the SRAM node, `replace` the reference with `&sram_c` |
| 937983/3 | Kconfig/Makefile context has moved | `reanchor`: the pure-addition hunks are inserted before their (unique) trailing context line |

The tool checks the patch-id of every downloaded patch **before** the fixes, so a re-posted or
altered patch stops the run instead of applying silently. Each patch is committed with its
original author, date and message, so `git log` in the work tree shows who wrote what.

Result, 2026-11-14: all 18 patches apply on `97d73c8` + `patches/linux/0001-0006`.

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

Two board trees include the display file and set the panel compatible:

| DTB | Panel | Selected by |
|---|---|---|
| `sun50i-h700-anbernic-rg34xx-sp-redux-panel.dtb` | v1 (`anbernic,rg34xx-sp-panel`) | u-boot, PE6 low |
| `sun50i-h700-anbernic-rg34xx-sp-redux-v2-panel.dtb` | v2 (`anbernic,rg34xx-sp-v2-panel`) | u-boot, PE6 high **and** V1.0.6-era board (see Q3/K9) |

The plain `-redux.dtb` keeps no display nodes, so an unidentified panel is never driven.

## 4. Panel firmware (`tools/gen_panel_firmware.py`)
Writes `panels/<compatible>.panel` (PANEL-FIRMWARE format v1 of the generic driver) from the
user's **own** stock image, via `stock_panel_seqs.json` from `tools/extract_rg34xxsp_panels.py`.
Timing, flags, size and delays are hardware facts set in the tool (720×480, h 47/4/42, v 33/4/16,
26 MHz; v1 also offers 52 MHz; 71×48 mm); the init commands come only from the image.

Check (2026-11-13/14, desk): from the stock 2025 image and the V1.0.6 image, the tool's v1 output
is byte-identical to ROCKNIX 20261101's working v1 file; from V1.0.6 its v2 output is
byte-identical to ROCKNIX's v2 file. The 2025 image's PE6-high sequence belongs to an older third
panel, and the tool refuses it. Outputs are checked against recorded SHA-256 values and anything
else is refused unless `--allow-unknown` is given.

The `.panel` files are never committed; at image build time they are generated from an image the
builder owns (R9 still open).

## 5. Build integration
- `scripts/workbench.sh --display`: after our 6 patches, applies the layer and
  `patches/linux-display/`, builds and `dtbs_check`s 9 DTBs (our 5 + the 4 upstream RG35XX trees
  that share the H616 include, to catch breakage the layer causes elsewhere), builds every C file
  that any patch touches with `W=1` (any warning fails; added after the `drm_panel_init()` break
  above, which only a full build had caught), checkpatches our display patches and, with
  `--bindings`, runs `dt_binding_check` on 6 more schemas.
- `scripts/build-kernel.sh --display`: merges `config/rg34xxsp-display.config` (PWM_SUN8I,
  BACKLIGHT_PWM, SPI_GPIO, DRM_PANEL_MIPI, all modules) after the base fragment, keeps them through
  the module trim, checks every fragment line holds and every enabled DT node of the panel trees
  has a driver.

## 6. Results (desk, 2026-11-14)
| Check | Result |
|---|---|
| Layer applies on `97d73c8` + 0001–0006 | 18/18 upstream patches (patch-ids verified) + our 2 |
| `dtbs_check`, 9 DTBs | 0 warnings each |
| `dt_binding_check`, 9 schemas | clean |
| `W=1` build of the 6 touched C files (cpufreq, codec, sun4i DRM ×2, PWM, panel) | 0 warnings |
| checkpatch, our 8 patches | clean (`--no-signoff`) |
| Config: fragment lines held | 111/111 |
| DT node → driver coverage, panel DTBs | 75 enabled nodes, 0 without a driver |
| Package build (`build-kernel.sh --display --build`, 2 jobs, 16 min) | builds; 12.8 MB `.deb`, 27.2 MB installed, 165 module files / 10.8 MB, vmlinuz 9.3 MB (R17 without the layer: 26.9 MB installed, 160 files / 10.6 MB) |
| Display modules in the package | `sun4i-drm`, `sun4i-tcon`, `sun8i-mixer`, `pwm-sun8i`, `pwm_bl`, `spi-gpio`, `panel-mipi`; both panel DTBs |

## 7. Open device checks
These need the device (after Redux v0.5) and are added to the master list as K-tasks:
1. Does the panel come up with the v1 file on a PE6-low unit (image, no flicker, right colours)?
   Try 26 MHz first; 52 MHz is the second mode in the file.
2. Backlight: polarity and 25 kHz vs stock 50 kHz (audible whine, flicker at low levels); the
   lowest level that is still visible.
3. v2 panel (K9/Q3): confirm a PE6-high V1.0.6-era unit and its file.
4. HDMI is not in this layer (separate later task).

## 8. Risks
- Three out-of-tree series: each rebase may need new manifest fixes. The patch-id pin makes drift
  loud, not silent.
- 937983 has not been merged in 20 months; carrying it is a maintenance cost. Fallback: an
  NV3052C panel-driver entry, which would put the init sequence in kernel source (R9 decides).
- No hardware result yet. Do not ship a display DTB before item 1 above passes.
