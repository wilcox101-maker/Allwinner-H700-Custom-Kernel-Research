# Handoff: Deep Research chat, 2026-11-14 (09:50 ET)

For the next Deep Research (DR) chat in the "H700 Allwinner Custom Kernel Research" Project. Replaces
`handoff-deep-research-2026-11-13.md` (kept for history).

## Ground rules (from Dale, still in force)
- **Work repo:** https://github.com/wilcox101-maker/Allwinner-H700-Custom-Kernel-Research. DR works on branch
  `deep-research`, opens PRs to `main` and **merges them itself** (Dale granted merge permission). `gh` GraphQL is
  blocked here: use REST (`gh api repos/…/pulls -f …`, `gh api -X PUT …/pulls/N/merge`). Licence: GPL-2.0.
- **Redux repo (Anbernic_RG34XXSP_Redux): advisory only.** Read it; never push, open PRs or edit `notes/`.
  Anything for Redux goes as files to `Documents\GitHub\redux-work\Claude Files` (Dale's PC, via the device
  bridge); Dale passes them through the Manager chat.
- **Never write to the stock images or to any card.** Never commit stock-derived binaries (boot0, kernels,
  ROCKNIX `.panel` files, `stock_panel_seqs.json`). Exception since Q8 (a): the two panel init sequences as GPL C
  tables in KR's NV3052C kernel patch.
- **Device:** unavailable until Redux v0.5. All device tasks stay `blocked: device`. Work at the desk.
- **Network:** all websites allowed; `ports.ubuntu.com` works.
- Add a dated DR entry to `docs/research-sync.md` at the start and end of each work block.
- `docs/master-task-list.md` and `docs/research-sync.md` in the repo are canonical; the Project copies are pointers.

## Start here
1. Read `docs/research-sync.md` (newest entries at the bottom, before "Open conflicts") and
   `docs/master-task-list.md`.
2. Read this file, then `docs/handoff-kernel-research-2026-11-14.md` (KR's state).
3. Start with the "Next" list below.

## Decisions (all of Dale's open questions are now decided)
| Q | Decision |
|---|---|
| Q1 | Stock 115 °C critical trip |
| Q2 | ROCKNIX's H700 CPU table; 1512 MHz boost only via Expert Mode (`/sys/devices/system/cpu/cpufreq/boost`), stress test first (K22) |
| Q3 | (a) PE6 high → plain `…-redux.dtb` (no display) until K9 identifies that panel's controller |
| Q4 | Done (Dale updated the Project instructions: LPDDR4 or LPDDR3 per unit, confirmed by K3) |
| Q5 | 1024 mA charge limit until K14 |
| Q6 | Mainline `97d73c8` + `patches/linux`; display as a separate layer (R19) |
| Q7 | Image name **ReduxOS** (not "Ubuntu"); `/etc/os-release` stays Ubuntu's base-files for v0.x |
| Q8 | (a) Original panel on the upstream NV3052C driver (GPL tables); no `.panel` files anywhere |

## What DR has built (all merged; desk + QEMU only, nothing on hardware)
- **Research docs:** R3 (V1.0.6 boot0 DRAM sets), R4 (firmware), R5 (noble userspace), R6 (Mesa/Panfrost),
  R7 (image tooling), R8 (update/rollback), R9 (licensing), R13 (RAM-tier defaults), audit 2026-11-14.
- **`image/build-image.sh`:** mmdebstrap + u-boot-menu + genimage → `reduxos-rg34xxsp-noble-<date>-<kmode>[-uboot].img`
  (MBR sig `0x48373030`, u-boot raw at 8 KiB, FAT32 `BOOT` 256 MiB at 16 MiB, ext4 root grown on first boot),
  plus `.sha256`, `.manifest.tsv`, `.sources.tsv`. Runs `image/check-licences.sh` and `image/check-display.sh`;
  either failing stops the build. No initramfs with our kernel.
- **`image/release-sources.sh`:** source bundle for a release (exact-version Ubuntu sources via archive/Launchpad,
  repo + pristine Linux tarballs, SHA256SUMS, README). Refuses a dirty repo; fails on any missing package.
- **R8 rollback:** `h700-kernel-fallback` (postinst/postrm), `h700-boot-ok`, u-boot BOOTCOUNT_ENV + `altbootcmd`;
  full loop tested in QEMU with a real u-boot (`image/qemu/rollback-test.sh`).
- **`patches/u-boot/0001`** (PE6 panel ID → `fdtfile`): defaults PE6 low → `…-redux-panel.dtb`,
  PE6 high → `…-redux.dtb` (D2 done). KR's `build-uboot.sh` applies it to v2026.10.
- **`config/rootfs/`:** zram (`min(ram,1024)`, zstd), swappiness 100, journald limits, accounting (R13).
- Last QEMU result (2026-11-14, KR's R19 kernel from main before #25): checks pass, 512 MB boot clean,
  root grown to 2.7 GiB, apt + network OK, 417 MB available.

## Next (DR desk work unblocked by KR's R1, 09:40)
1. **Image with the real bootloader:** run `scripts/build-uboot.sh --dram all --sources`, then
   `UBOOT_BIN=<out>/u-boot-rg34xxsp-lpddr4-2026.10.bin image/build-image.sh` (and an LPDDR3 one). Check with
   `sfdisk -d`/`dd` that SPL+u-boot sits at 8 KiB and doesn't overlap the FAT at 16 MiB; check the eGON header
   checksum. **Do not write any card.** Dale's card gets the variant K3 confirms.
2. **R9 source bundle for u-boot:** `release-sources.sh` takes one `UBOOT_SRC` tarball; KR's `--sources` writes
   three (`u-boot-2026.10.tar.xz`, `trusted-firmware-a-2.14.0.tar.xz`, `rg34xxsp-u-boot-inputs-2026.10.tar.xz`).
   Change it to accept a directory (or several files), include TF-A's BSD notice, and test with an `-uboot` image.
3. **R8 check:** KR notes `altbootcmd` uses `mmc 0:1` (SD slot 1 = mmc 0 when booted from it). Confirm the
   `rg34xxsp.config` fragment matches `docs/r8-update-rollback.md` and update the doc's env location note.
4. **Docs:** record ROCKNIX's CPU table, the 1024 mA limit and Expert Mode boost in R13 where RAM/perf tiers
   mention CPU behaviour; note KR's R11 cooling map (sustained load now throttles).
5. After that: nothing open at the desk. Device tasks (K1–K22) wait for v0.5.

## Local environment (cloud workspace does NOT carry over)
- Rebuild from scratch: clone the repo; `apt-get install mmdebstrap genimage dosfstools mtools e2fsprogs
  qemu-user-static qemu-system-arm rsync shellcheck dpkg-dev`; re-register binfmt if mmdebstrap says
  `arm64 can neither be executed…`:
  `mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc; cat /usr/lib/binfmt.d/qemu-aarch64.conf > /proc/sys/fs/binfmt_misc/register`
  (it disappears from this container from time to time).
- Our kernel: `WORK=<dir> scripts/workbench.sh --display && WORK=<dir> scripts/build-kernel.sh --display --build`
  (~1 h on 2 cores). QEMU u-boot for the R8 test: build `qemu_arm64_defconfig` + `image/qemu/u-boot-qemu-rollback.config`.
- Image builds take ~7 min; a source bundle ~7.5 min and ~810 MB; keep an eye on disk (~17 GB free here).
- Stock boot0 copies for R3 are in Dale's `Claude Files\h700-ubuntu-research\r3-raw` (local only).
