# Handoff — Deep Research (DR), SWAP 2026-11-20 evening

For the next DR chat. Rules: `AGENTS.md`, `CLAUDE.md`, README ground rules. DR works only on the H700 project.
Start: attach `wilcox101-maker/Allwinner-H700-Custom-Kernel-Research` **with push**; read
[`research-sync.md`](research-sync.md), [`master-task-list.md`](master-task-list.md) and this handoff; then confirm to the
Manager that DR has resumed **OSK ownership** (below).

## State
- `main` = `946ff66` (#73 R31–R36 framework, #74 R36 cores/PortMaster merged; Dale OK'd the `/dev/uinput` grant).
- **PR #75 open** (`claude/r33-slim`): R33. Manager merges on green.
- Everything desk/QEMU only — **nothing has run on an RG34XX-SP**. Device blocked until Redux v0.5 (exception Q11: K3/K4).

## OSK engine ownership (DR)
DR owns the **ReduxOS KMS on-screen keyboard**: the fly-out OSK for non-RetroArch apps — `cage` + `wvkbd` + `foot`/`mc`,
launchers `redux-kbapp` / `redux-shell` / `redux-files`, the gamepad→pointer bridge `tools/redux-osk-pointer.c`
(injected via `OSK_POINTER`, built in CI) — doc [`reduxos-osk.md`](reduxos-osk.md). `/dev/uinput` is 0660 for `input` (R36).
KR owns the **stock-firmware** OSK (`tools/osklib`, `tools/oskprobe`, K24–K28); separate engine, don't merge them.
Open OSK work is **R35** (tune on hardware: cage+wvkbd render on Mali, stick-pointer feel) — device-blocked.

## R33 result (PR #75) — [`reduxos-r33-slim.md`](reduxos-r33-slim.md)
- Upstream RetroArch **v1.22.2** (pinned `69a4f0e`) built KMS/EGL/GLES 3.1 + udev + ALSA + FFmpeg only, packaged as a
  generated `reduxos-retroarch` .deb (`tools/build-retroarch.sh`, injected with `RETROARCH_DEB`); CI keeps noble's 1.18.
- Rootfs packages 789 → **733 MB** (469 pkgs, Qt5 gone); image zstd 282 → **273 MiB**. QEMU smoke **20/20** incl. the new
  `retroarch --features` check on the emulated A53.
- **LLVM kept** (133 MB): Panfrost doesn't need it, but Ubuntu's mesa links it; measured 377,863 relocations / 7.5 MB RW
  per GL process; a mesa fork would need us to track mesa security updates. Revisit for 512 MB/1 GB units.
- **mpv kept** (its avfilter chain is 70 MB) — planned YouTube app engine.

## Device-blocked until Redux v0.5
- **R34** sticks → RetroArch player 1 (uinput combiner of the adc-joystick sticks).
- **R35** OSK tuning (above). Also device-validate R33/R36: RetroArch 1.22 on Mali (GLES 3.1), core speeds, PortMaster GUI.

## Open threads (desk)
- Remaining R36 cores: hatarib (ATARIST), yabasanshiro (SATURN), easyrpg, onscripter; freej2me needs a JRE (likely skip).
- KR letter answered: Claude Files `FROM-DR-TO-KR-2026-11-20-breakdown-reply.md` (private). KR may reply.
- Images delivered privately: `ReduxOS-builds\2026-11-20\r36-cores\` and `...\r33-slim\`.

## Build host facts (fresh container loses all of this)
See [`handoff-deep-research-2026-11-20c.md`](handoff-deep-research-2026-11-20c.md) §Build host. Added: RetroArch needs
multiarch `libdrm/gbm/udev/asound2/freetype/avcodec/avformat/avutil/swscale/swresample/lzma -dev:arm64`; ~10 min build.
Watch the container quota (~43 GB usable): delete finished image dirs (each ~4.5 GB) before the next build.

## Next step
Wait for a GO. Without device access, the most useful desk item is the remaining R36 cores.
