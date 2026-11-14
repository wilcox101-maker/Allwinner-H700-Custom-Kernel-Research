# R11: upstream check, November 2026

Date: 2026-11-14. Recurring task R11 (monthly). Base: torvalds `97d73c8` (2026-11-13, after
v7.4-rc2) + `patches/linux` + display layer. Next check: around 2026-12-14.

**Method.** Kernel patchwork (`patchwork.kernel.org`, projects `linux-arm-kernel` and `dri-devel`),
searched for H616/H700, DE33, TCON, HDMI, NV3052C, Anbernic and the `sun4i`/`sun8i` drivers, posted
since mid-2025. (lore.kernel.org is not reachable from this workspace.) For each relevant series,
every patch was tried against our tree with `git apply --check`, both forwards (still to come) and
in reverse (already in our base). Desk only; nothing here has run on a device.

## 1. Series we carry: still current
| Series | Ours | Newest found | Status |
|---|---|---|---|
| H616 LCD TCON + display engine (Ryan Walklin) | 984067 v2, 2025-07-20 | same | not merged; no newer version |
| H616 PWM (James Hilliard / Richard Genoud) | 1202273 v12, 2026-11-04 | same (v11 was 2026-11-03) | not merged; still in review |

## 2. Already in our base (nothing to do)
| Series | Evidence |
|---|---|
| drm/sun4i layer refactor for DE33, 30 patches (1019579 v2, Jernej Skrabec, 2025-11) | last patch reverse-applies; the others were changed by later work |
| drm/sun4i assorted display fixes, 13 patches (1139528, Jernej Skrabec, 2026-08) | patches 1–12 reverse-apply (incl. TCON TOP and TCON fixes); 13 (VI buffer alignment) is not in yet, reposted alone as 1160136 v2; not relevant to the LCD path |

## 3. Adopted now: H616 CPU cooling map
[1202209](https://patchwork.kernel.org/series/1202209/) (Jernej Skrabec, sunxi co-maintainer,
2026-11-04): adds a `cooling-maps` node to the H616 CPU thermal zone.

**Why it matters here:** in mainline's `sun50i-h616.dtsi`, the CPU zone has passive trips at 60 and
70 °C but no cooling map, so nothing throttles the CPU before the 110 °C critical trip shuts the
board down. Our trees inherit that. With the map, the default `step_wise` governor
(`THERMAL_DEFAULT_GOV_STEP_WISE=y` in our config) lowers the CPU's cpufreq limit from the 70 °C trip.

Now in `patches/upstream/base-layer.txt` (new; applied by `workbench.sh` on every run, with or
without `--display`), pinned by patch-id like the display layer. Result: applies cleanly; all 8 DTBs
`dtbs_check` clean; the RG34XX-SP trees now carry the CPU cooling map. Drop it when it reaches
mainline. Device check **K21**: CPU at full load on our kernel; does it settle near 70 °C
instead of climbing to the critical trip?

## 4. Watch (not adopted)
| Series | What | Why not now / effect on us |
|---|---|---|
| [1092102](https://patchwork.kernel.org/series/1092102/) v2, 2026-05-09, Jernej Skrabec: *drm/sun4i: update DE33 support* | DE33 clock fixes, CSC, a new planes driver and new DT bindings that split the H616 DE33 layer | Not merged after 6 months; 6 of 8 patches apply to our tree, 2 conflict. **When it lands, the DE nodes from 984067 will likely need rework.** Our display layer would have to follow; the patch-id pin will show it |
| [1158750](https://patchwork.kernel.org/series/1158750/), 2026-09-04, Barzin Lotfabadi: *h616: add HDMI device tree nodes* | H616 display engine + HDMI DT nodes, Orange Pi Zero3 HDMI | Patch 1 conflicts with 984067 (both add the DE nodes). Input for the later HDMI task |
| [1209352](https://patchwork.kernel.org/series/1209352/) v3, 2026-11-12, Arun Iyengar: *h616: Orange Pi Zero2 fixes, GPU DVFS and GPU cooling* | (1) codec register range 0x31c → 0x320 (covers the RAMP register); (3) an H616 GPU OPP table, 306–600 MHz at 810–950 mV; (4) a GPU passive trip at 85 °C with a GPU cooling map | Two days old, no review yet. Our GPU OPP dtsi (`sun50i-h700-redux-gpu-opp.dtsi`) runs 420–600 MHz at a fixed 940 mV (DCDC2). Worth taking (4) once reviewed; (3)'s voltage scaling only helps if DCDC2 may be scaled on this board, which is open |
| [1199446](https://patchwork.kernel.org/series/1199446/) v6, 2026-11-02, James Hilliard: *8250_dw: describe the H616 and A523 UART configurations* | UART FIFO/RX-trigger set-up | The console works without it; take it when merged |
| [1206813](https://patchwork.kernel.org/series/1206813/), 2026-11-10: *clk: sunxi-ng: h616: fix EMAC 25 MHz and S/PDIF clocks* | clock fixes | The RG34XX-SP has no Ethernet and doesn't use S/PDIF |

No upstream activity on `panel-newvision-nv3052c.c`, on H700 boards, or on the RG34XX-SP: our
three NV3052C patches and the board patches are the only ones.

## 5. Next check (December)
1. Pinned series 984067 and 1202273: newer versions or merged? If merged, drop from the manifest.
2. 1202209 (CPU cooling) merged? Then drop from the base layer.
3. 1092102 (DE33 update): merged or reposted? Then plan the display-layer rework.
4. 1209352: reviewed? Then consider its GPU cooling map (patch 4).
5. New HDMI work for H616.
