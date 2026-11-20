# Handoff — Deep Research (DR), SWAP 2026-11-20 12:07 ET

## State
- Branch **`claude/reduxos-beta-build`**, **PR #73** open (R31→R36). Head `e712212`. `main` at `5a9a900`.
- CI last seen: `docs` + `uboot-dram-cap` green, `smoke` in progress, PR **mergeable (unstable only
  while smoke runs)**. `build`/`osklib` are path-filtered (don't run for image-only changes). Not merged.
- Everything is **desk/QEMU only — nothing has run on an RG34XX-SP.** Device blocked until Redux v0.5
  except K3/K4 on Dale's 2 GB LPDDR4 unit (Q11).

## Done today (all in PR #73)
- **R32 beta**: boots to RetroArch (KMS/GLES) as unprivileged `player` on tty1 (locked pw, no sudo);
  LPDDR4 + LPDDR3; QEMU smoke 16/16. `reduxos-frontend.md`.
- **R32 addendum**: PS1 fast core **pcsx_rearmed** (GPL-2.0, pinned `7b0e8f8`, arm64 dynarec+NEON) via
  `tools/build-pcsx-core.sh`, injected not committed → 10 cores. Console shell (Terminus font, kbd,
  console-setup, tmux). **Fly-out OSK** for non-RetroArch apps: cage+wvkbd+foot+mc, launchers
  `redux-kbapp`/`redux-shell`/`redux-files`, cross-built gamepad→pointer bridge `redux-osk-pointer`
  (`tools/redux-osk-pointer.c`, injected not committed). `reduxos-osk.md`.
- **R36 framework (no proprietary content)**: 53-system folder tree mirroring the stock card, BIOS
  **reference** (filenames+md5+size only, from Dale's own known-good set — no BIOS content),
  `redux-setup-roms` (first-boot `reduxos-roms-setup.service`) + `redux-bios-check`. RetroArch pointed at
  `/roms` + `/roms/bios`. `reduxos-games-and-bios.md`.

## Delivered to Dale's PC (`…\Downloads\Anbernic RG34xxSP\ReduxOS-builds\2026-11-20\`)
- `frontend-beta\` — both `.img.zst` (~396 MiB, zstd -22), per-file sha256, manifests, smoke reports,
  sources, README. On-device checksums verified. (R31 base image is in the parent folder.)
- `games-kit\reduxos-games-kit.zip` — the 53-folder tree + scripts + BIOS reference. Verified checksums.
- Private (Claude Files, NOT the repo): KR's stock-firmware security sweep (complete 2026-11-20).

## Build harness facts (for R36)
- Cross toolchain `aarch64-linux-gnu-gcc` (13.3) in the container; **no g++** (pure-C cores fine).
- Image build: `KERNEL_DEB=… UBOOT_BIN=u-boot-rg34xxsp-<dram>-2026.10.bin SOURCE_DATE_EPOCH=1795132800
  OUT=… [PCSX_CORE=…] [OSK_POINTER=…] bash image/build-image.sh`. binfmt must be registered first
  (re-mount `binfmt_misc`, feed `/usr/lib/binfmt.d/qemu-aarch64.conf`). Kernel `.deb` + both u-boot bins
  are in `/home/claude/work`. Each image ~10 min under emulation; compress `zstd --ultra -22` (<400 MB
  per-file delivery limit). Big files reach the PC via SendUserFile → fileUuid → device_commit_files.
- **Injected-binary pattern** (no binaries in the repo): build with a `tools/build-*.sh`, inject via an
  env-var customize-hook, `.gitignore` the output. Reuse this for the R36 cores.
- zstd gotcha: never run two `zstd -o SAME` concurrently; and `nm -D | grep -q` under `pipefail`
  SIGPIPEs the producer — use `grep -c` + count.

## Pending (priority order)
1. **R36 cores + PortMaster** — the big one. ~25 unpackaged systems need source-built libretro cores
   (genesis_plus_gx, picodrive, fbneo, mame2003_plus, mupen64plus_next, ppsspp, flycast, snes9x, vice,
   handy, race, pokemini, vecx, bluemsx, melonds, onscripter, easyrpg, …) + noble standalones
   (scummvm, dosbox, mame, fs-uae, openmsx, hatari, stella, fuse, yabause) + **PortMaster** port
   (gptokeyb/oga_controls/SDL-kmsdrm runtime). `systems.tsv` already names the intended core per system.
   Non-commercial cores keep this a **private** build; proprietary (PICO-8, BIOS) stays user-supplied.
   Marathon — do it fresh. All A53 performance (Saturn/DC/PSP/N64/NAOMI) is unproven → hardware.
2. **R35** — validate/tune the fly-out OSK on hardware (cage+wvkbd render on Mali; stick-pointer feel).
3. **R34** — merge the adc-joystick sticks into RetroArch player 1 (uinput combiner).
4. **R33** — slim the image (retroarch forces a 334 MB font pack via retroarch-assets; mesa pulls
   libllvm20) — stripped retroarch via equivs.

## Standing constraints
Desk only. Security findings stay private (Claude Files, not the repo) — the docs-check/classifier
correctly blocks stock secrets in committed files. No binaries committed; inject at build. Stage explicit
paths, never `git add -A`. `main` protected. Brevity (result first, ≤5 lines). Private beta is never
published. DR works only on the H700 project; KR owns stock-firmware analysis + OSK-on-stock (osklib) —
the ReduxOS KMS OSK (cage/wvkbd) is separate, flagged in research-sync. Dale accepts DR recommendations
automatically except his reserved decisions.

## Next step
Wait for a GO. Most likely first task: start **R36** (core-build marathon + PortMaster) in the fresh
session. Read `research-sync.md`, `master-task-list.md`, and this handoff first.
