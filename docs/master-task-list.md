# Master task list: H700 Ubuntu 24.04 project

Created 2026-11-13 21:25 ET by the Deep Research chat, at Dale's request. **The test device is unavailable for kernel research until Redux reaches v0.5**, so every task that needs the device is **pending (blocked: device)**. Desk tasks continue.

How to use it:
- One row per task.
- Status values: `pending` · `blocked: device` · `blocked: decision` · `claimed: DR|KR` · `done`.
- Owners: **DR** = Deep Research chat, **KR** = Kernel Research chat, **Dale**.
- Either chat may change a row's status or add rows. When claiming or finishing a task, add a line to `docs/research-sync.md` too. Done tasks move to the bottom.

## A. Device tasks: pending until v0.5 (blocked: device)
IDs **K1–K9** match the Redux task note `notes/2026-11-13-claude-message-kernel-research-device-pending.md` (Kernel Research package g). **K10–K12** are Deep Research additions, proposed to Redux in hand-off package DR-a. **K13–K15** are Kernel Research additions (KR package j carries K1–K15 to Redux). **K16** is a Deep Research addition (from R4), not yet in any Redux package. **Nothing writes to the stock card or internal storage**; writes go to a spare card only.

| ID | Task | Why / what it unblocks | Source | Status |
|---|---|---|---|---|
| K1 | **Read-only readings on stock:**<br>- `MemTotal`<br>- DCDC1/2/3 µV<br>- `dmesg \| grep 'vf versions'`<br>- CPU speed fuse @ 0x03006200<br>- thermal trips<br>- panel lines in `dmesg` | Dale's CPU bin; DCDC2 (GPU 648 MHz); DRAM type cross-check | checklist §0; `stock-cpu-bin-decoder-and-dcdc2.md` §4 | blocked: device |
| K2 | ROCKNIX 20261101 DDR4 on a spare card: 10 checks + logs | M1 baseline: what mainline does on this unit, panel variant | `kernel-research-device-checklist-rocknix.md` | blocked: device |
| K3 | UART pads (case open, meter, 3.3 V adapter, 115200 8N1). First capture: stock boot log; note boot0's `vaild para:… select dram para<N>` line (N = 15 → LPDDR4, all DRAM straps open) | Serial console for every later boot test (M0); confirms the DRAM strap index (R3) | `rg35xxh-codeasm-lessons.md` | blocked: device |
| K4 | FEL boot, no card: `sunxi-fel version`, then our u-boot (LPDDR4 + PE6 patch); expect `RG34XX-SP: panel ID PE6=0` | First run of our boot chain; confirms PE6 and LPDDR4 | `rg34xxsp-panel-detect-and-uboot-patch.md` | blocked: device (needs K3) |
| K5 | Sticks on mainline: `evtest` axis order/sign; also press both stick clicks (L3 PE8 / R3 PE9) | Final `abs-range` in board DT; confirms the stick-click buttons exist | `kernel-custom-patches.md` §3, §10 | blocked: device |
| K6 | Deep-suspend ladder (custom-patches §7; needs UART) | Real suspend-to-RAM in our image | custom-patches §7 | blocked: device |
| K7 | Stick polling cost at 16 ms (CPU %) | Polling interval | custom-patches §3 | blocked: device |
| K8 | Chip revision: stock SRAM-controller value vs mainline SMCCC SOC_ID | Trust the b0/b1 and c0/c1/c2 bins | custom-patches §2a | blocked: device |
| K9 | Revised (v2-panel) unit reads PE6 = 1 | What PE6-high maps to (Q3) | panel doc §1 | blocked: needs a second unit / community report |
| K10 *(proposed)* | Original panel with ROCKNIX's reg `0x23 = 0x00` (stock 0xA2): look for tearing/shift. Part of K2 | Confirms the panel file we ship | panel doc §1 | blocked: device |
| K11 *(proposed)* | Panfrost vs stock Mali: frame rate on 3–4 reference games/cores, same settings; plus R6 §6 checks (`eglinfo -B` = GLES 3.1, `glmark2-es2-drm`, per-process GL memory from `smaps_rollup`, PanVK with the override flag). The GPU half can run headless on `renderD128` before the display works | Validates the GPU choice; user expectations | assessment §7 | blocked: device |
| K12 *(proposed)* | Noble image on hardware: MemTotal/MemAvailable/Slab, PSS sum, boot time per stage, service list vs the QEMU numbers from R5 (`r5/r5-measure` prints them all) | Confirms RAM-tier defaults (R13) | R5 | blocked: device (needs our image) |
| K13 | Rumble motor: does the RG34XX-SP have one (stock DT names PH2, but it is a family-wide DT)? Look inside, or try stock rumble in a game | Whether to add a vibrator node | custom-patches §8 | blocked: device |
| K14 | Charging temperature at stock's 1500 mA (draft: 1024 mA, 4.10 V cap) | Charge current in the board DT | custom-patches §8 | blocked: device |
| K15 | Speaker start-up: UI sounds with the 100 ms amp delay (patches 0002/0003) vs mainline's fixed 700 ms | Keep 100 ms or adjust | custom-patches §8 | blocked: device |
| K16 *(proposed)* | Bluetooth config check: on mainline with upstream `rtl_bt/rtl8821cs_config.bin` (lacks stock's 4 extra entries `0xd9=0f, 0xe4=08, 0x8d=fa, 0x8f=bf`), pair a controller + headset; check range, audio dropouts, `btmon` errors. If bad, retry with stock's config on a spare card | Whether we ship upstream's BT config or need a board-specific one (licensing → R9) | `r4-noble-firmware-audit.md` | blocked: device |
| — | Full release test matrix (M6): tiers, both SD slots, display, input, audio, Wi-Fi, BT, HDMI, charging, battery, suspend, recovery | Release 0.1 | assessment §5–6 | blocked: device, later |

## B. Desk tasks (no device needed)
| ID | Task | Owner | Status |
|---|---|---|---|
| R1 | Boot-chain card layout for our images (MBR, SPL @ 8 KiB, FAT `/boot` + extlinux `FDTDIR`, per-DRAM SPL) | KR | claimed: KR (after the model checkpoint Dale was asked about) |
| R2 | FEL test kit: exact `sunxi-fel` commands + expected u-boot output (incl. the PE6 line) | KR | claimed: KR |
| R8 | Update/rollback design: kernel/board apt repo, extlinux fallback entry, A/B or recovery partition, versioning | DR | pending |
| R9 | Licensing/redistribution audit: ROCKNIX panel blobs, ROCKNIX TF-A suspend stub, rtw88/rtl_bt firmware (incl. ROCKNIX's `EXTRA_FIRMWARE` embedding), our u-boot patch (GPL-2.0+) | DR | pending |
| R19 | Display layer for the mainline base (Q6): carry the upstream H616/H700 display series (DE33 mixer, LCD/TCON DT, PWM, panel) pinned by name, version and date on top of `patches/linux`, with the RG34XX-SP panel nodes behind the PE6 panel ID; build- and schema-checked, then K-tasks for the device | KR | claimed: KR (2026-11-14) |
| R11 | Upstream tracking: DE33 / H616 LCD-TCON / PWM v12 / HDMI series; review monthly | KR | accepted: KR |

## C. Decisions for Dale (blocked: decision)
| ID | Decision | Options / recommendation | Status |
|---|---|---|---|
| Q1 | CPU thermal critical trip | Upstream 110 °C (default in draft) vs stock 115 °C (option a, `…-stock-thermal.dtsi`). Redux rule: "critical trip never changed" | blocked: decision |
| Q2 | CPU voltages | Conservative bin-agnostic table (480/1008/1200) vs per-chip stock tables via the custom xlate (after K8) | blocked: decision (recommend: conservative for v0.x) |
| Q3 | Mapping for PE6-high in our u-boot | `-v2-panel` DTB (Anbernic V1.0.6 behaviour) vs a no-panel DTB until K9 | blocked: decision (recommend: no-panel until K9) |
| Q4 | Project instructions still say "Ubuntu 22.04" and "LPDDR4" for every tier | Update to 24.04 target and LPDDR4 (original) / LPDDR3 (revised). Only Dale can edit the instructions | blocked: decision |
| Q5 | Battery charge current on mainline | Upstream 1024 mA (draft) vs stock 1500 mA after K14. Charge voltage is already capped at stock's 4.10 V (upstream tree: 4.20 V) | blocked: decision (recommend: 1024 mA until K14) |

## D. Hand-offs to the Redux Manager chat (files via `redux-work\Claude Files`)
| ID | Item | Status |
|---|---|---|
| H1 | `hardware-map.md` typo: stock `amux-en` is **PI0**, not PI8 (KR finding) | pending |
| H2 | Ubuntu 22.04 end of standard support: **May 2027** (not April) | pending |
| H3 | `STATUS.md` says Dale's local clone is at `0afecd9`; it was at `d0de8e0` on 2026-11-13 | pending |
| H4 | Proposed device tasks K10–K12 for the Redux kernel-research note | done: in KR package j's note (K1–K15) |
| H5 | `hardware-map.md` header says the SP lacks the analog-stick mux; the same file confirms two sticks (KR finding) | pending (KR package i) |

H1–H3 go out together as `FROM-REDUX-DEEP-RESEARCH-2026-11-13-a.md` in `redux-work\\Claude Files` (Deep Research package DR-a). K16 should ride along in that package.

## E. Done (most recent first)
- 2026-11-14 02:40: R7 image tooling: mmdebstrap + genimage + u-boot-menu; `image/build-image.sh` builds an MBR card image (u-boot slot at 8 KiB, FAT32 /boot with extlinux + synced DTBs, ext4 root grown on first boot); with our kernel it boots in QEMU at 512 MB without initramfs, firstboot/apt/network OK, 189 pkgs / 440 MB, no Python. Card layout still provisional on R1 (DR, `r7-image-tooling.md`).
- 2026-11-14 02:27: **Q6 decided by Dale: mainline + our patches** is the kernel base; display comes as a separate, pinned layer (new task R19, KR). The assessment's ROCKNIX-7.2 plan needs updating (DR).
- 2026-11-14 02:40: KR audit of the kernel work: fresh-clone reproduction passed; kernel builds made bit-reproducible (244/245 package files identical across two build dirs); fixes for wording (iwd), compiler version, broken link and Project paths (DR audit D3), test-copy drift check (D4), SPDX tags. Kernel base decision (DR audit D1, **Q6**): KR recommendation added (KR, sync 02:40).
- 2026-11-14 01:45: R6 Mesa/Panfrost in noble: Mesa 25.2.8 (noble-updates) → GLES 3.1 on G31; PanVK gated off on v7 (Vulkan 1.0 with an override); GL stack 226 MB disk (LLVM 136 MB), est. 8–10 MB RAM per GL process; recommend Ubuntu Mesa for v0.x, no `mesa-vulkan-drivers`; side finding: R5 rootfs lacks `apt` (DR, `r6-mesa-panfrost-noble.md`).
- 2026-11-14 00:30: Audit of all work to date (`audit-2026-11-14.md`): re-checks pass; DR errors E1–E8 fixed; D1 (kernel base: mainline vs ROCKNIX 7.2) needs Dale (DR).
- 2026-11-14 00:30: R13 RAM-tier defaults: one self-scaling config (zram `min(ram,1024)` zstd, swappiness 100, page-cluster 0, earlyoom, journald 32M); QEMU OOM stress: kernel/earlyoom/oomd all recover, userspace killers 25–70 s sooner (DR, `r13-ram-tier-defaults.md`, `config/rootfs/`, `r13/`).
- 2026-11-14 00:30: R18 our kernel under R5's iwd rootfs in QEMU at 512 MB/1 GB/2 GB: boots without an initramfs, all services up, zram works; **+26 MB MemTotal, +31–37 MB MemAvailable** vs Ubuntu 6.8; rootfs 423 → 209 MB. QEMU only (KR, `r18-kernel-in-qemu.md`).
- 2026-11-14 00:15: R17 module trim by allowlist (`config/module-keep.txt`): 924 → 160 modules, 38.5 → 10.6 MB; package 56.4 → 26.9 MB installed. Found and fixed: iwd's 4 missing kernel options (R10 package would not run iwd), exFAT/uhid/uinput/controller drivers missing, PlayStation pad lost to a dependency. Built, not booted (KR, `kernel-module-trim-r17.md`).
- 2026-11-13 23:00: R10 kernel config + cross-build + `bindeb-pkg` for noble on mainline `97d73c8` + our series (not ROCKNIX 7.2; reasons in the doc). Config checks: fragment holds, every DT node has a driver. Package `linux-image-7.4.0-rc2-rg34xxsp_7.4.0~rc2-1`: 56.4 MB installed, vmlinuz 9.3 MB, 924 modules / 38.5 MB. Built, not booted (KR, `kernel-build-r10.md`).
- 2026-11-13 22:45: R5 noble arm64 userspace prototype in QEMU: base idles at ~11 MB anon / 33–38 MB PSS at 512 MB–2 GB; iwd+networkd stack = −73 MB disk, −53 packages, no Python, ~5 MB less RAM than NM; zram works (DR, `r5-noble-userspace-prototype.md`, `r5/`).
- 2026-11-13 22:30: R16 upstream-style `sun50i-h700-anbernic-rg34xx-sp.dts` as patch 0006 (sticks, stick clicks PE8/PE9, battery, speaker delay); `dtbs_check` 0 warnings, checkpatch clean; held for submission until K5. Stick clicks also added to the Redux tree. `scripts/workbench.sh` reruns every desk check (KR, `kernel-custom-patches.md` §10).
- 2026-11-13 22:00: R3 stock boot0 `DRAM.ext` decoded: V1.0.6 reads PH6/PH7/PH8/PH10 (pull-ups); idx 15 = LPDDR4, 14 = LPDDR3, 0 = default LPDDR3, 1–13 = SDK DDR3 placeholders; 2025 boot0 has selection off (DR, `r3-v106-boot0-dram-sets.md`).
- 2026-11-13 22:00: R4 noble firmware audit: `linux-firmware-realtek` carries the exact rtw88/rtl_bt bytes; kernel needs `FW_LOADER_COMPRESS_ZSTD`; BT config gap → K16 (DR, `r4-noble-firmware-audit.md`).
- 2026-11-13 21:50: R15 board DT for audio, battery/charger, Wi-Fi/BT: stock vs upstream table; charge cap 4.10 V; speaker-amp delay patches 0002/0003 (KR, custom-patches §8).
- 2026-11-13 21:50: R14 compile-check: five patches (cpufreq xlate, codec delay + binding, OPP and board bindings), checkpatch 0/0; board DT `dtbs_check` 0 warnings in both variants (KR, custom-patches §9).
- 2026-11-13: R12 custom cpufreq xlate (stock bins → bits 0–8) + generated OPP dtsi; compile-tested, 28-case host test (KR, design §2a); hardware check = K8.
- 2026-11-13: CPU speed-bin decoder recovered (DR + KR); `0x7c00` differs between 2025 and V1.0.6 (KR found it, DR confirmed).
- 2026-11-13: DCDC2/GPU regulator desk findings (DR).
- 2026-11-13: Panel ID = PE6; ROCKNIX panel files traced to stock; u-boot DT-selection patch build-tested (DR).
- 2026-11-13: GPT vs SPL @ 8 KiB resolved → MBR (KR raised, DR agreed).
- 2026-11-13: Anbernic build methodology; boot0 DRAM = LPDDR4 @ 672 MHz on the 2025 image (DR).
- 2026-11-13: 24.04 assessment, 6.10 notes, CodeAsm lessons, H700 brief (DR); custom-patch designs, ROCKNIX checklist (KR).
