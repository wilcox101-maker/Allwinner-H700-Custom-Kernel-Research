# Allwinner H700 Custom Kernel Research

Kernel, device-tree and boot-chain research for running a maintained, mainline-based Ubuntu on
Allwinner H700 handhelds, starting with the **Anbernic RG34XX-SP**.

> **Desk research only.** Nothing in this repository has been booted or run on a device yet.
> The test unit is unavailable for kernel work until the Redux v0.5 milestone; every
> hardware-dependent item is logged as a pending device task (K-numbers, below). Every claim
> here names its source and date, and anything not yet run on hardware says so.

## Status (2026-11-13)

| Area | State |
|---|---|
| Kernel base | torvalds/linux `97d73c8` (2026-11-13, after v7.4-rc2) |
| Patches | 6, all apply cleanly; `checkpatch` clean (see below) |
| Device trees | 3 RG34XX-SP variants, all `dtbs_check` 0 warnings |
| CPU speed bins | Stock decoder recovered from the vendor kernels; kernel xlate + 28-case host test |
| Display | **None yet.** Mainline has no H616/H700 display or PWM support; no panel is ever guessed |
| Hardware validation | **None.** Pending device tasks K1–K16 |

## Layout

```
mainline/
  patches/linux/   0001-0006, a git-am series against torvalds/linux 97d73c8
  dts/             board trees and include files (copied into arch/arm64/boot/dts/allwinner/)
  design/          custom-patches.md: the design, decisions and verification record
  tests/           xlate_test.c: host test of the speed-bin decoder (patch 0001)
  tools/           gen_cpu_opp_stock.py (stock DTS -> OPP dtsi), findconst.py (binary search aid)
docs/
  findings-2026-11-13.md        answers to the first six research questions, with sources
  device-checklist-rocknix.md   one-page ROCKNIX spare-card checklist (device task K2)
scripts/
  workbench.sh     rebuilds the kernel tree and runs every desk check
```

### Patches (`mainline/patches/linux/`)

| # | Subject | Why |
|---|---|---|
| 0001 | cpufreq: sun50i: add Anbernic RG34XX-SP speed-bin decode | Reproduces the vendor kernel's fuse → speed-bin decision, so each chip can get its stock voltages |
| 0002 | ASoC: dt-bindings: sun4i-a10-codec: add `allwinner,pa-delay-ms` | Binding for 0003 |
| 0003 | ASoC: sun4i-codec: make the speaker amplifier delay configurable | Mainline waits a fixed 700 ms on every speaker power-up; stock waits 100 ms |
| 0004 | dt-bindings: opp: sun50i: add Anbernic RG34XX-SP operating points | Binding for 0001's compatible and extra nvmem cells |
| 0005 | dt-bindings: arm: sunxi: add Anbernic RG34XX-SP | Board compatible |
| 0006 | arm64: dts: allwinner: h700: add Anbernic RG34XX-SP | Upstream-style board tree: sticks, stick clicks, battery, speaker delay |

### Device trees (`mainline/dts/`)

| File | Purpose |
|---|---|
| `sun50i-h700-anbernic-rg34xx-sp.dts` | Upstream-style tree (patch 0006). Inherits upstream OPPs and thermal unchanged: **for upstream review, not for our image** |
| `sun50i-h700-anbernic-rg34xx-sp-redux.dts` | The tree for our image: adds a never-undervolt CPU table (480/1008/1200 MHz at the highest stock voltage) and GPU OPPs on the fixed 0.94 V rail |
| `sun50i-h700-redux-cpu-opp-stock.dtsi` | Generated: all nine stock per-bin CPU tables; needs patch 0001. Do not edit by hand |
| `sun50i-h700-redux-gpu-opp.dtsi` | GPU 420–600 MHz at 0.94 V (648 MHz waits on a stock DCDC2 reading) |
| `sun50i-h700-redux-stock-thermal.dtsi` | Option: stock's 115 °C CPU critical trip, no GPU/VE/DDR trips (decision Q1) |

The workbench also builds `…-reduxstock.dtb` = the redux tree + stock CPU tables + stock thermal.

Comments inside the generated and redux files still say `phase2-mainline/`, the path these files
had in the Redux package; here that directory is `mainline/`.

## Running the checks

```sh
# Ubuntu 24.04 host
sudo apt install gcc-aarch64-linux-gnu device-tree-compiler bc flex bison libssl-dev
pip install dtschema yamllint ply gitpython

scripts/workbench.sh                 # fetch Linux, apply patches, dtbs_check, checkpatch, host test
scripts/workbench.sh --bindings      # also dt_binding_check for the three touched schemas
scripts/workbench.sh --stock-dts <Redux>/reference/stock-202505/board.dts   # + generator round trip
```

It works in `./.work/` (git-ignored; override with `WORK=`), never touches a device, card or
image, and stops at the first failure.

**Last full run:** 2026-11-13 22:20 ET, from an empty work directory, with `--bindings` and
`--stock-dts`: all steps passed (3 DTBs 0 warnings, 6 patches checkpatch-clean, 28/28 host test,
generator byte-identical, 3 binding schemas clean). Negative controls: a wrong DT property and a
wrong schema value each produced output, so both checks are live.

## Rules for this repository

- **Text only.** No kernel, u-boot, firmware, panel or Mali binaries, no stock images, and no
  dumps of vendor firmware. Hardware facts (pins, voltages, frequencies) are recorded as numbers
  with their source.
- **No copied patches** from other projects (ROCKNIX, Knulli and others): link them by name and
  commit instead. Everything here is our own text and code.
- **Never drive an unidentified panel**, never undervolt relative to stock, and never write to a
  device's boot area or another project's `dd` offsets. Device tests are run by Dale, on a spare
  card only.
- **Kernel submission rules:** a tool never adds `Signed-off-by`; the human submitter reviews and
  adds it, and the changelog says how a tool helped (`Documentation/process/coding-assistants.rst`).
  Patch 0006 carries that note; 0001–0005 still need it before any submission.

## Related

- Redux firmware (stock-based CFW; source of the stock device tree used here):
  [wilcox101-maker/Anbernic_RG34XXSP_Redux](https://github.com/wilcox101-maker/Anbernic_RG34XXSP_Redux)
- The shared task list (device tasks K1–K16, desk tasks R1–R16, Dale's decisions Q1–Q5) and the
  research notebook live in the claude.ai Project "H700 Allwinner Custom Kernel Research"
  (`claude/master-task-list.md`, `claude/research-sync.md`).

## Licence

There is no repository-wide licence file. Kernel patches are GPL-2.0, as the files they change.
The device trees carry `GPL-2.0-only OR BSD-2-Clause`, as upstream's do. The helper files
(`xlate_test.c`, `findconst.py`, `gen_cpu_opp_stock.py`, `workbench.sh`) have no licence line
yet; that is the repository owner's choice.
