# Handoff: Deep Research chat, 2026-11-13 (21:40 ET)

For the next Deep Research chat in the "H700 Allwinner Custom Kernel Research" Project. **This chat is advisory**: read-only on the Redux repo, no pushes, no PRs, no edits to `notes/`. Findings for Redux go as files to `Documents\GitHub\redux-work\Claude Files`, then through the Manager chat.

## Start here (HELLO)
1. Read `claude/research-sync.md` (rules + both chats' entries) and `claude/master-task-list.md`.
2. Read this file.
3. Restart R5 as described below. Add a dated DR entry to the sync file at the start and end of each work block.

## State
- **Device:** unavailable for kernel research until Redux **v0.5**. All device tasks are logged as `blocked: device` (K1–K15) in the master list; K16 (BT config) is still to be added.
- **Network:** Dale switched Capabilities to **all websites** (21:30). `ports.ubuntu.com` (HTTPS) is confirmed working. Kernel.org, Launchpad, GitLab and the others should now work too; untested.
- **Dale's PC (via the device bridge):** stock images are in `Anbernic RG34xxSP\RG34XXSP.img` (2025). V1.0.6 is under `.FW`. Read only: never write to images or cards. VM scratch is `$HOME/fx`: unpacked boot images, extracted u-boot/DTB, `fw/` (stock BT firmware dumped read-only). `debugfs` reads the image's p5 rootfs at `?offset=$((92577792*512))`.
- **The cloud workspace does not carry over.** R5 scripts are copied to `Claude Files\h700-ubuntu-research\r5\`.

## Done (desk only; nothing validated on hardware)
- 24.04 assessment (MBR layout), 6.10 notes, CodeAsm lessons, H700 brief, Anbernic build methodology
- Panel ID = **PE6** + u-boot DT-selection patch (build-tested on v2026.01, not run)
- CPU speed-bin decoder + DCDC2 findings. The 0x7c00 conflict is resolved: 2025 = mask 0x2, V1.0.6 = b0/b1.
- Master task list, aligned to Kernel Research's K1–K9
- **R4 noble firmware audit** → `claude/r4-noble-firmware-audit.md`:
  - Use `linux-firmware-realtek` (identical bytes to ROCKNIX's); never the `linux-firmware` metapackage (~470 MB).
  - The kernel needs `FW_LOADER_COMPRESS_ZSTD`; Wi-Fi/BT as modules, no `EXTRA_FIRMWARE`.
  - Stock's BT config has 4 extra entries (`0xd9=0f, 0xe4=08, 0x8d=fa, 0x8f=bf`) → K16 (renumbered: KR took K13–K15).

## R5 in progress (noble userspace prototype)
- `build.sh` (mmdebstrap minbase + NM, wpasupplicant, openssh, zram-generator, `linux-firmware-realtek`, docs/man/locales excluded, user `dale`) + `r5-measure`/`measure.service` (prints mem/services/RSS to the console after 60 s, then powers off) + `boot.sh <MB>`.
- **amd64 proxy, 512 MB, TCG (no KVM), `linux-image-virtual`:**
  - rootfs without kernel: 211 MB, 186 packages; ~45 MB of that is Python, pulled in by NetworkManager → netplan.
  - Idle: **63 MB used, 393 MB available** of 456 MB.
  - Top RSS: NetworkManager 18 MB, systemd 13 MB, journald 9 MB.
  - Running services: dbus, NM, wpa_supplicant, journald, logind, timesyncd, udevd, 2 gettys.
  - **zram failed**: `zram.ko` is not in the `virtual` kernel. Switch to `linux-image-generic` (already edited in `build.sh`). Our own kernel needs `CONFIG_ZRAM`.
  - TCG boot times are not meaningful.
- **Next:**
  1. Install qemu-user-static, register binfmt `qemu-aarch64`, and rebuild with `ARCH=arm64 MIRROR=https://ports.ubuntu.com/ubuntu-ports ./build.sh rootfs-arm64-k.tar` (the two attempts were interrupted, not failed).
  2. Boot it with `qemu-system-aarch64 -M virt -cpu cortex-a53` at 512 MB, 1 GB and 2 GB.
  3. Also measure a variant with iwd + systemd-networkd instead of NM (no Python).
  4. Write the findings to `claude/r5-noble-userspace-prototype.md`.

## Next tasks after R5 (master list)
R3 V1.0.6 boot0 DRAM sets → R13 RAM-tier defaults → R6 Mesa/Panfrost in noble → R7 image tooling → R8 update/rollback → R9 licensing (now including ROCKNIX's `EXTRA_FIRMWARE` blob embedding).

## First chores for the next chat
- Add device task **K16** to `claude/master-task-list.md` (Kernel Research edited it at 21:55: read it first, then merge). Its R4 row may also need marking done.
- Read Kernel Research 21:55 in the sync file: charge voltage capped at 4.10 V, speaker delay patches, R14/R15 done, Q5/H5 added.

## Waiting on Dale
- Decisions Q1–Q5 in the master list: thermal trip, CPU voltages, PE6-high mapping, outdated Project instructions, charge current (Q5, from KR).
- Redux hand-offs H1–H3 (+ KR H5): not yet sent as a DR file; H4 is done (KR package j carries K1–K15).

## Open PRs
None. This chat never opens PRs.

## Archive name
`H700 Deep Research 2026-11-12→2026-11-13: assessment, panel PE6 + u-boot patch, CPU bins, master task list, R4 firmware audit, R5 started`
