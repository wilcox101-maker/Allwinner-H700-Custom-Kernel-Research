# R29: kernel driver for the newer RG34XX-SP panel (GC9703 family)

Date: 2026-11-20. Deep Research, at Dale's request ("write a kernel driver for my panel").
**Desk only: compiled and schema-checked, never run on a panel.** The original panel (PE6 low) already has its driver entry
(`patches/linux-display/0003`, NV3052C); this is the other one.

## Result
- New driver `drivers/gpu/drm/panel/panel-galaxycore-gc9703.c` (`CONFIG_DRM_PANEL_GALAXYCORE_GC9703`), compatible
  `anbernic,rg34xx-sp-v2-panel`, with its binding: `patches/linux-display/0004` and `0005`.
- Opt-in tree `dts/sun50i-h700-anbernic-rg34xx-sp-redux-v2-panel.dts`. **Our u-boot does not select it**: PE6 high still boots
  the plain `-redux` tree without display (decision Q3 unchanged).
- All desk checks pass (§4). First hardware test is K29, on a unit known to carry this panel.

## 1. Why the u-boot mapping is unchanged
PE6 high does not prove this panel. The 2025 stock firmware used PE6 high for an older, third panel
(`tools/gen_panel_firmware.py` note); only V1.0.6-era firmware pairs PE6 high with this sequence. Sending a GC9703 sequence
to a different controller breaks the rule "never drive an unidentified panel". So the tree is selected by hand, per unit,
after K9. Changing the mapping is a decision for Dale (a new Q-item once K29 passes).

## 2. The driver
| Item | Value | Source |
|---|---|---|
| Bus | 3-wire SPI, 9-bit words (`mipi_dbi_spi_init` without a D/C line), as the NV3052C driver on the same pins | stock bit-bangs the same framing |
| Power-on | supply on; reset low 10 ms; wait 50 ms; init table; exit-sleep; 120 ms | ROCKNIX 20261101's working v2 panel file (delays 10/50/120/120) |
| Enable | display-on; 120 ms; then the DRM core turns the backlight on | same file |
| Power-off | display-off; enter-sleep; 120 ms; reset low; supply off | stock panel-exit order (0x28, 0x10) [G] |
| Mode | 720×480, 26 MHz, 60 Hz, h 47/4/42, v 33/4/16, sync active low; RGB888, DE high, data on falling edge | same as the original panel's entry and ROCKNIX's v2 file |
| Size | 71 × 48 mm | as the original panel |
| Init table | 98 commands, 730 bytes, parameters up to 44 bytes; format per command: count, command, parameters | stock V1.0.6 u-boot, PE6-high branch |

Structure follows `panel-newvision-nv3052c.c` (same probe, supply name `power`, reset GPIO, backlight hook), so the shared
`sun50i-h700-redux-display.dtsi` wiring serves both panels; the v2 tree only overrides `compatible`.
A malformed table is refused at run time (bounds check per entry).

## 3. The table (`tools/gen_gc9703_table.py`)
Same method as `gen_nv3052c_table.py`: reads `stock_panel_seqs.json` (from `tools/extract_rg34xxsp_panels.py` on a V1.0.6
image), prepares the commands as `gen_panel_firmware.py` does for v2, and prints only if the result has the known-good SHA-256
of ROCKNIX 20261101's working v2 file. Trailing exit-sleep and display-on are dropped; the driver sends them.
Decision Q8 (a) allows the board's two panel sequences into GPL kernel source as C tables. It was written when both were
expected to be NV3052C entries; this one lands in a new GPL driver instead. **If Dale reads Q8 more narrowly, say so and
patch 0005 is regenerated locally instead of committed.**

Check (2026-11-20): the table inside patch 0005 is byte-identical to the generator's output from the V1.0.6 image, and
walking it gives exactly 98 commands with no bytes left over.

## 4. Desk results (2026-11-20, cloud workspace, gcc 13.3.0 aarch64, Linux `97d73c8`)
| Check | Result |
|---|---|
| `scripts/workbench.sh --display --bindings` | pass: 0004/0005 apply from the patch files; `-redux-v2-panel.dtb` builds with 0 `dtbs_check` messages; W=1 build of `panel-galaxycore-gc9703.c` clean; checkpatch clean; `dt_binding_check` of the new schema clean; all earlier checks still pass |
| `scripts/build-kernel.sh --display` (config checks) | pass: fragment line holds; the v2 tree has 74 enabled nodes, 0 without a driver |
| Baseline before the change | same workbench run passed |

Not done: `--build` of the `.deb` packages with the new module; QEMU has no SPI panel, so nothing more can be shown on the desk.

## 5. Device check (K29)
Only on a unit known to have this panel (K9: flex marking, or stock V1.0.6 serial log `lcd_type = 0`).
On a spare card with our image, point extlinux at `sun50i-h700-anbernic-rg34xx-sp-redux-v2-panel.dtb` by hand.
Expect: `gc9703` probes, picture upright with correct colours, no shift or flicker, backlight after about a quarter second,
sleep and wake restore the picture. A blank or wrong picture: power off, go back to the plain tree, and report `dmesg`.

## 6. Risks and limits
- Controller identity rests on the init sequence (K9 desk doc), not a datasheet. The driver only replays the vendor
  sequence, so it works on the panel that sequence was written for whatever the chip is finally called; the name could change.
- Mode and delays come from ROCKNIX's working setup, not from our own test.
- Upstreaming would need a real maintainer, hardware test and a person's sign-off (repo rule: a tool never signs off).

Tools: `gcc-aarch64-linux-gnu`, `device-tree-compiler`, `flex`, `dtschema` in the cloud workspace only; nothing installed on Dale's PC.
