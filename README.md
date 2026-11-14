# Allwinner H700 Custom Kernel Research

Research and prototypes for an **Ubuntu 24.04 LTS (noble) arm64** distribution for Allwinner H700
handhelds, starting with the **Anbernic RG34XX-SP**: a mainline kernel with our own patches and
device trees, the boot chain, and a minimal noble userspace.

**Status: research phase, desk work only.** Nothing in this repository has been booted on an H700
device yet. The test device is unavailable until the Redux v0.5 milestone; device-dependent tasks are
tracked as `blocked: device` in [`docs/master-task-list.md`](docs/master-task-list.md).

## Layout
| Path | What |
|---|---|
| [`docs/master-task-list.md`](docs/master-task-list.md) | Master task list: device tasks (K-IDs), desk tasks (R-IDs), decisions for Dale (Q-IDs), hand-offs |
| [`docs/research-sync.md`](docs/research-sync.md) | Running log between the Deep Research and Kernel Research chats |
| `docs/*.md` | Findings, one document per topic (index below) |
| [`patches/linux/`](patches/linux/) | Our Linux patches: a 6-patch `git am` series against torvalds/linux `97d73c8` (compile- and schema-checked, not booted) |
| [`patches/upstream/display-layer.txt`](patches/upstream/display-layer.txt) | Display layer (R19): upstream H616 display, PWM and generic-panel series, pinned by patchwork ID and `git patch-id`; applied by `tools/apply_upstream.py`, never copied here |
| [`patches/linux-display/`](patches/linux-display/) | Our patches on top of the display layer: panel binding, panel-driver fix-up for today's mainline |
| [`patches/u-boot/`](patches/u-boot/) | Our u-boot patches (build-tested, not booted) |
| [`dts/`](dts/) | RG34XX-SP board trees and include files, copied into `arch/arm64/boot/dts/allwinner/` |
| [`tests/`](tests/) | Host test of the CPU speed-bin decoder (patch 0001) |
| [`tools/`](tools/) | Read-only analysis tools for stock images, the stock OPP table generator, `dt_driver_coverage.py` (DT node → driver → Kconfig check) , `gen_trim_config.py` (module allowlist → config fragment) and `boot_path.py` (drivers a node needs before it probes, and whether they are built in) |
| [`scripts/workbench.sh`](scripts/workbench.sh) | Rebuilds the Linux tree with our patches and runs every desk check |
| [`config/rg34xxsp.config`](config/rg34xxsp.config) | Kernel config fragment for the RG34XX-SP on Ubuntu 24.04 (every line says why) |
| [`config/module-keep.txt`](config/module-keep.txt) | Module allowlist: every module not listed (and not a board driver or fragment option) is turned off |
| [`scripts/build-kernel.sh`](scripts/build-kernel.sh) | Builds and checks the config, then the kernel `.deb` packages (R10) |
| [`image/`](image/) | R7: card-image builder, package list, overlay, QEMU test; R9: licence checks and source bundle |
| [`r5/`](r5/) | R5: noble userspace prototype (mmdebstrap + QEMU sizing scripts and results) |
| [`r18/`](r18/) | R18: QEMU boot script for our kernel (virtio over MMIO) and its results |
| [`r20/`](r20/) | R20: kernel-swap helper for the R18 rootfs and the QEMU, config-diff and boot-path results of the built-in trim |

## Findings index
| Doc | Topic |
|---|---|
| [`docs/kernel-custom-patches.md`](docs/kernel-custom-patches.md) | Kernel design record: panel selection, never-undervolt CPU OPPs, stock speed-bin decoder, sticks, thermal, GPU rail, deep suspend, audio/battery, verification, R16 board DT |
| [`docs/r19-display-layer.md`](docs/r19-display-layer.md) | R19: display layer for the mainline base: pinned upstream series, RG34XX-SP panel wiring and DT, panel firmware generator, desk results, open device checks |
| [`docs/r20-builtin-trim.md`](docs/r20-builtin-trim.md) | R20: trial fragment that turns off built-in code the board can't use (−5.8 MB Image, +6 MB free RAM in QEMU); boot path check |
| [`docs/r18-kernel-in-qemu.md`](docs/r18-kernel-in-qemu.md) | R18: our kernel under the R5 noble rootfs in QEMU: memory and disk vs Ubuntu's kernel, initramfs optional |
| [`docs/kernel-module-trim-r17.md`](docs/kernel-module-trim-r17.md) | R17: module allowlist, what it removed and kept, before/after sizes, the iwd and controller gaps it found |
| [`docs/kernel-build-r10.md`](docs/kernel-build-r10.md) | R10: kernel config, cross-build and `.deb` packages for noble; why mainline and not ROCKNIX 7.2; sizes |
| [`docs/kernel-findings-2026-11-13.md`](docs/kernel-findings-2026-11-13.md) | Open questions 1–6: upstream SP tree, display/PWM status, ROCKNIX panel choice and suspend, OPPs/thermal vs stock, sticks |
| [`docs/device-checklist-rocknix.md`](docs/device-checklist-rocknix.md) | One-page ROCKNIX 20261101 spare-card checklist (device task K2) |
| [`docs/r5-noble-userspace-prototype.md`](docs/r5-noble-userspace-prototype.md) | R5: minimal noble arm64 rootfs, QEMU at 512 MB / 1 GB / 2 GB, NM vs iwd+networkd |
| [`docs/audit-2026-11-14.md`](docs/audit-2026-11-14.md) | Audit of all research and work to 2026-11-14: re-checks, errors fixed, open issues |
| [`docs/r6-mesa-panfrost-noble.md`](docs/r6-mesa-panfrost-noble.md) | R6: Mesa 25.2.8 in noble for the Mali-G31: GLES 3.1, PanVK gated off, LLVM cost, package list |
| [`docs/r7-image-tooling.md`](docs/r7-image-tooling.md) | R7: image tooling (mmdebstrap + genimage + u-boot-menu); prototype `image/build-image.sh`, QEMU-booted with our kernel |
| [`docs/r8-update-rollback.md`](docs/r8-update-rollback.md) | R8: apt channels, u-boot boot-counter kernel rollback (tested in QEMU with real u-boot), recovery ladder |
| [`docs/r9-licensing-redistribution.md`](docs/r9-licensing-redistribution.md) | R9: licences per component, source obligations, "Ubuntu" trademark (Q7), release checklist (automated by `image/check-licences.sh` and `image/release-sources.sh`) |
| [`docs/r13-ram-tier-defaults.md`](docs/r13-ram-tier-defaults.md) | R13: RAM-tier defaults (zram, swappiness, earlyoom, journald) + QEMU OOM stress test |
| [`docs/r3-v106-boot0-dram-sets.md`](docs/r3-v106-boot0-dram-sets.md) | R3: stock boot0 DRAM.ext table, PH6/7/8/10 straps → LPDDR3/LPDDR4 sets |
| [`docs/r4-noble-firmware-audit.md`](docs/r4-noble-firmware-audit.md) | R4: Wi-Fi/BT firmware in noble, kernel config needs, BT config gap |
| [`docs/ubuntu-2404-rg34xxsp-assessment.md`](docs/ubuntu-2404-rg34xxsp-assessment.md) | 24.04 compatibility assessment; option B (mainline + noble); milestones M0–M6 |
| [`docs/anbernic-kernel-build-methodology.md`](docs/anbernic-kernel-build-methodology.md) | How Anbernic builds its kernel (binary forensics); boot0 DRAM; panel straps |
| [`docs/rg34xxsp-panel-detect-and-uboot-patch.md`](docs/rg34xxsp-panel-detect-and-uboot-patch.md) | Panel ID = PE6; ROCKNIX panel files traced to stock; u-boot DT-selection patch |
| [`docs/stock-cpu-bin-decoder-and-dcdc2.md`](docs/stock-cpu-bin-decoder-and-dcdc2.md) | Stock CPU speed-bin decoder, per-bin OPP tables, DCDC2/GPU rail |
| [`docs/linux-6.10-h700-notes.md`](docs/linux-6.10-h700-notes.md) | Linux 6.10 and the H700 timeline to 6.16 |
| [`docs/rg35xxh-codeasm-lessons.md`](docs/rg35xxh-codeasm-lessons.md) | CodeAsm RG35XX H notes; FEL-first bring-up; RG35XX SP UART lead |
| [`docs/h700-brief-and-mainline-boot-2024.md`](docs/h700-brief-and-mainline-boot-2024.md) | H700 product brief; 2024 mainline boot (rg35xx-cfw #205) |
| [`docs/handoff-deep-research-2026-11-13.md`](docs/handoff-deep-research-2026-11-13.md) | Deep Research handoff, 2026-11-13 |

All Deep Research documents from the Claude Project are here. The Kernel Research chat's documents (custom kernel patches, device checklist, open-question findings) are to be added by that chat.

## Kernel work at a glance
| # | Patch (`patches/linux/`) | Why |
|---|---|---|
| 0001 | cpufreq: sun50i: add Anbernic RG34XX-SP speed-bin decode | Reproduces the vendor kernel's fuse → speed-bin decision, so each chip can get its stock voltages |
| 0002 | ASoC: dt-bindings: sun4i-a10-codec: add `allwinner,pa-delay-ms` | Binding for 0003 |
| 0003 | ASoC: sun4i-codec: make the speaker amplifier delay configurable | Mainline waits a fixed 700 ms on every speaker power-up; stock waits 100 ms |
| 0004 | dt-bindings: opp: sun50i: add Anbernic RG34XX-SP operating points | Binding for 0001's compatible and extra nvmem cells |
| 0005 | dt-bindings: arm: sunxi: add Anbernic RG34XX-SP | Board compatible |
| 0006 | arm64: dts: allwinner: h700: add Anbernic RG34XX-SP | Upstream-style board tree: sticks, stick clicks, battery, speaker delay |

| Tree (`dts/`) | Purpose |
|---|---|
| `sun50i-h700-anbernic-rg34xx-sp.dts` | Upstream-style (patch 0006). Inherits upstream OPPs and thermal unchanged: **for upstream review, not for our image** |
| `sun50i-h700-anbernic-rg34xx-sp-redux.dts` | For our image: never-undervolt CPU table (480/1008/1200 MHz at the highest stock voltage), GPU on the fixed 0.94 V rail |
| `sun50i-h700-redux-cpu-opp-stock.dtsi` | Generated by `tools/gen_cpu_opp_stock.py`: all nine stock per-bin CPU tables; needs patch 0001. Do not edit by hand |
| `sun50i-h700-redux-gpu-opp.dtsi` | GPU 420–600 MHz at 0.94 V (648 MHz waits on a stock DCDC2 reading) |
| `sun50i-h700-redux-stock-thermal.dtsi` | Option: stock's 115 °C CPU critical trip (decision Q1) |
| `sun50i-h700-redux-display.dtsi` | Display (R19, needs the display layer): DE → TCON → RGB panel over 3-wire SPI, PWM backlight |
| `sun50i-h700-anbernic-rg34xx-sp-redux-panel.dts`, `-redux-v2-panel.dts` | `-redux` + display for panel v1 / v2; u-boot picks one from the PE6 strap |

Display needs the separate display layer (`--display` below; mainline alone has no H616 LCD TCON
or PWM support). No tree ever guesses a panel: the plain `-redux` tree has no display nodes.
The panel's init sequence is a firmware file generated from your own stock image
(`tools/gen_panel_firmware.py`), never stored here.
Comments inside some `dts/` files still say `phase2-mainline/`, their path in the Redux package.

### Running the kernel checks
```sh
# Ubuntu 24.04 host
sudo apt install gcc-aarch64-linux-gnu device-tree-compiler bc flex bison libssl-dev
pip install dtschema yamllint ply gitpython

scripts/workbench.sh                 # fetch Linux, apply patches, dtbs_check, checkpatch, host test
scripts/workbench.sh --bindings      # also dt_binding_check for the three touched schemas
scripts/workbench.sh --stock-dts <Redux>/reference/stock-202505/board.dts   # + generator round trip
scripts/workbench.sh --display       # + display layer (R19): panel DTBs, W=1 build, more schemas

# then, on the same work directory (extra host packages are listed in the script):
scripts/build-kernel.sh              # config checks only: fragment holds, every DT node has a driver
scripts/build-kernel.sh --build      # + make bindeb-pkg and size report
scripts/build-kernel.sh --no-trim    # same, without the module allowlist (for comparison)
scripts/build-kernel.sh --display --build   # with the display layer (after workbench.sh --display)
scripts/build-kernel.sh --fragment config/rg34xxsp-builtin-trim.config --build   # R20 trial
```
It works in `./.work/` (git-ignored; override with `WORK=`), never touches a device, card or image,
and stops at the first failure. Last full run: see the newest Kernel Research entry in
[`docs/research-sync.md`](docs/research-sync.md).

## Ground rules
- **Never write to stock images or to any card.** Tools here only read images.
- Stock-derived data (panel init sequences, vendor config blobs) is **not** committed: its
  redistribution terms are unknown (task R9). Use `tools/extract_rg34xxsp_panels.py` on your own image.
  Hardware facts (pins, voltages, frequencies) are recorded as numbers with their source.
- **No binaries, and no patches copied from other projects** (ROCKNIX, Knulli and others): link
  them by name and commit.
- **Never drive an unidentified panel**, and never undervolt relative to stock.
- **Kernel submission rules:** a tool never adds `Signed-off-by`; the human submitter reviews the
  patch and adds it, and the changelog says how a tool helped
  (`Documentation/process/coding-assistants.rst`). Patch 0006 carries that note; 0001–0005 still
  need it before any submission.
- Every claim says whether it was checked on hardware. "Desk only" means it was not.

## Related
- Redux firmware (stock-based CFW; source of the stock device tree used here):
  [wilcox101-maker/Anbernic_RG34XXSP_Redux](https://github.com/wilcox101-maker/Anbernic_RG34XXSP_Redux)

## Licence
**GPL-2.0** (see `LICENSE`), matching the Linux kernel and u-boot that this work targets. Scripts and
docs are GPL-2.0-only unless a file says otherwise; patches against u-boot and Linux carry those
projects' own licence terms (u-boot GPL-2.0+, Linux GPL-2.0). The repository was created with
GPL-3.0 on 2026-11-13 and switched to GPL-2.0 the same day, before any outside contributions.
