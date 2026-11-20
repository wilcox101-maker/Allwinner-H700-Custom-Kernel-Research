# Handoff — Deep Research (DR), SWAP 2026-11-20 16:45 ET

## State
- `main` = `4f562a8` (PR #73 merged 14:03 ET: R31–R36 framework; root SSH `PermitRootLogin yes`, no root credential shipped).
- **PR #74 open** (`claude/r36-cores`, head `31078e9`): R36 cores + launcher + playlists + PortMaster. Smoke green on
  `bbcbd62` (code); docs-only follow-up re-running. Not merged — Manager/Dale merge. Security note for Dale in the PR body:
  `/dev/uinput` 0660 for `input`.
- Everything desk/QEMU only — **nothing has run on an RG34XX-SP**.

## Done this session
- R36: 22 pinned source-built cores (`config/reduxos-games/cores.tsv`, `tools/build-libretro-cores.sh`), `redux_exec`
  launcher core + `redux-launch` + session loop, `redux-scan-roms` playlists, PortMaster 2026.11.17-0700, `/roms` owned by
  `player` (saves were broken), asset shim (R33 assets part), deeplayer build guard, QEMU `r36-check.py`.
  QEMU 19/19, all 33 cores load on the emulated A53. Doc: [`reduxos-cores-portmaster.md`](reduxos-cores-portmaster.md).
- Images LPDDR4 + LPDDR3, 282 MiB zstd each, delivered to `ReduxOS-builds\2026-11-20\r36-cores\` (checksums verified on the PC).
- Reply to KR's V1.0.6 breakdown: Claude Files `FROM-DR-TO-KR-2026-11-20-breakdown-reply.md` (private).

## Build host facts (fresh container loses all of this)
- Needs: `gcc/g++-aarch64-linux-gnu`, cmake, mmdebstrap, genimage, qemu-user-static, binfmt-support, dpkg-dev, unzip, zstd;
  multiarch arm64 from ports.ubuntu.com for `libgles-dev:arm64 libegl-dev:arm64 zlib1g-dev:arm64` (GLES cores).
- binfmt drops occasionally: re-mount `binfmt_misc`, feed `/usr/lib/binfmt.d/qemu-aarch64.conf`, `arch-test arm64`.
- Kernel+u-boot rebuild: `workbench.sh --display && build-kernel.sh --display --build && build-uboot.sh --dram all` (~70 min, 2 CPUs).
  Cores ~1.5 h total (fbneo 24 min, mame2003_plus 12, ppsspp 11). Image ~35 min each under emulation; QEMU smoke ~25 min.
- **Never edit a script while it runs** (bash reads incrementally) — build from a frozen copy.
- Image env: `CORES_DIR` `PORTMASTER_ZIP` `PCSX_CORE` `OSK_POINTER` (`RA_SLIM=0` keeps assets).

## Pending (priority)
1. Merge #74 (Manager/Dale; uinput decision is Dale's).
2. Remaining cores: hatarib (ATARIST), yabasanshiro (SATURN), easyrpg, onscripter, freej2me (needs a JRE — likely skip).
3. R35 OSK on hardware; R34 sticks→P1 (uinput combiner); R33 llvm part.
4. Device validation of R36 (speed, Mali GLES, PortMaster GUI on KMS) — after K3/K4.

## Next step
Wait for a GO. Read `research-sync.md`, `master-task-list.md`, this handoff.
