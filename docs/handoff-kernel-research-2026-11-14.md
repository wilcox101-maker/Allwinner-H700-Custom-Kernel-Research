# Kernel Research handoff, 2026-11-14

For the next Kernel Research (KR) chat. Written at the end of the chat that started from
`REDUX-KERNEL-RESEARCH-HANDOFF-2026-11-13.md` (and `-2`). **Nothing in this repository has run on an
RG34XX-SP.** Everything is desk, build, schema and QEMU work.

## 1. Where things are
- **Work repo (this one):** `wilcox101-maker/Allwinner-H700-Custom-Kernel-Research`, main at the
  merge of PR #28. No open PRs. Dale granted merge permission: KR branches, opens a PR (REST API;
  GraphQL is blocked) and merges its own PRs.
- **Shared files:** `docs/master-task-list.md` (tasks, K-IDs, decisions) and `docs/research-sync.md`
  (chat-to-chat log) are canonical. The claude.ai Project copies are pointers.
- **Deep Research (DR)** works in the same repo (`deep-research` branch → PRs). Resolve conflicts in the
  two shared docs by keeping both entries.
- **Redux repo** (`Anbernic_RG34XXSP_Redux`): read-only for KR. Deliverables to the Redux Manager go as
  `FROM-REDUX-KERNEL-<date>-<letter>.md` + zip into `redux-work\Claude Files` on Dale's PC, never to
  the owner chat. The last KR package was **k**; device tasks K17–K22 are not in any Redux package yet.
- **The Redux Manager** now also oversees this project and relays Dale's decisions.

## 2. Done in this chat (all desk; PR numbers)
| Task | Result | Doc |
|---|---|---|
| R16 | Upstream-style board patch series `patches/linux/0001-0006` | `kernel-custom-patches.md` §10 |
| R10, R17 | Kernel `.deb` build (`scripts/build-kernel.sh`), reproducible, module allowlist trim | `kernel-build-r10.md`, `kernel-module-trim-r17.md` |
| R18 | Our kernel boots noble in QEMU; no initramfs needed | `r18-kernel-in-qemu.md` |
| R19 (+ Q8 rework, #18, #23) | Display layer by reference (H616 DE/TCON 984067 v2, PWM 1202273 v12); RG34XX-SP panel as an entry in upstream `panel-newvision-nv3052c.c` (`patches/linux-display/0001-0003`); newer PE6-high panel is **not** an NV3052C, no driver | `r19-display-layer.md` |
| R20 (#22) | Trial fragment `config/rg34xxsp-builtin-trim.config` (−5.8 MB Image); `tools/boot_path.py` check in every build | `r20-builtin-trim.md` |
| R11 Nov (#25) | `patches/upstream/base-layer.txt`: H616 CPU cooling map (1202209); watch list | `r11-upstream-check-2026-11.md` |
| Q1/Q2/Q5 (#27) | Stock thermal (115 °C), ROCKNIX H700 CPU table as overrides (`dts/sun50i-h700-redux-cpu-opp.dtsi`, 1512 MHz boost off by default), patch 0007 (OPP schema), 1024 mA | master list §C |
| R1 + R2 (#28) | `scripts/build-uboot.sh`: u-boot **v2026.10** + TF-A v2.14.0 per DRAM type, reproducible, `--sources`; FEL kit | `r1-boot-chain.md`, `r2-fel-test-kit.md` |

Verified on the device: **nothing.**

## 3. Decisions in force (Dale)
Q1 stock 115 °C · Q2 ROCKNIX H700 table, 1512 MHz only via Expert Mode, stress test K22 before use ·
Q3 PE6 high boots `-redux.dtb` (no display) until K9 · Q5 1024 mA until K14 · Q6 mainline + our patches,
display as a pinned layer · Q7 image name ReduxOS · Q8 panel sequences as GPL NV3052C tables ·
Q4: Dale has updated the Project instructions (24.04; LPDDR4 original / LPDDR3 revised).

## 4. Rules carried over
- Link other projects' patches by name and commit; never copy them. Stock-derived data stays out of
  the repo (exception by Q8: the one NV3052C table in patch `linux-display/0003`).
- No kernel, u-boot, panel or Mali binaries in any repo. `boot-2025-p4.img` is private.
- Never write to the stock card or p1. No dd offsets from other projects.
- Every claim names its source and date. Say plainly what has not run on the device.
- AI-assisted patches: no Signed-off-by from a tool; disclosure line in each commit message
  (kernel `Documentation/process/coding-assistants.rst`). `patches/linux/0001-0005` still lack it.
- Device work is blocked until Redux v0.5; then spare cards only.

## 5. Next tasks
1. **Device, in order:**
   - K3: serial console; stock log line `select dram para<N>` gives the DRAM type.
   - K4: FEL kit (`r2-fel-test-kit.md`).
   - First boot from a spare card: image with `UBOOT_BIN` (DR).
   - K17: rollback test.
   - K18 and K19: panel and backlight.
   - K21: CPU thermal under load.
   - K22: CPU table stress test.
   - K20: built-in trim boot test.
2. **Desk:**
   - R11 December check (around 2026-12-14; list in `r11-upstream-check-2026-11.md` §5).
   - Add the disclosure line to patches 0001–0005 before any upstream submission.
   - Package l for Redux: carry K17–K22 to the Redux task note.
3. **Checkpoint before the first card write:** Dale's DRAM type from K3, and the matching
   `u-boot-rg34xxsp-<dram>-2026.10.bin`.

## 6. Rebuilding the work tree (fresh workspace)
```
WORK=/tmp/w scripts/workbench.sh --display --bindings     # Linux tree + all desk checks
WORK=/tmp/w scripts/build-kernel.sh --display --build      # kernel packages (~16 min, 2 jobs)
WORK=/tmp/w2 scripts/build-uboot.sh --sources              # u-boot both DRAM types + sources
```
Python needs `pyelftools` for u-boot (`pip install --break-system-packages pyelftools`); apt: swig,
bison, flex, bc, libssl-dev, libgnutls28-dev. `--stock-dts` needs the Redux repo's
`reference/stock-202505/board.dts`. The NV3052C table generator needs Dale's private
`stock_panel_seqs.json` (in `Claude Files`), only to regenerate.

## 7. Archive name for the finished chat
`Kernel Research 2026-11-13 to 2026-11-14: R1 R2 R10-R20, Q1-Q8 applied, u-boot v2026.10`
