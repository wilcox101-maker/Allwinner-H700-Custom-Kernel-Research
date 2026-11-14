# R8: Updates and rollback for the RG34XX-SP noble image

Deep Research, 2026-11-14. **Design + a QEMU test with a real u-boot (qemu_arm64 build); nothing ran on an H700, and the sunxi u-boot config below is not built or booted.** Master list task R8. Code: `image/overlay/` (hooks), `image/qemu/rollback-test.sh`.

## Answer in one paragraph
Everything updates through **apt**: Ubuntu's archive for the userspace, and **our own signed apt repository** for the board-specific packages (kernel, board configuration, later the display layer and the frontend). Kernel updates are made safe by **u-boot's boot counter**: when a new kernel is installed, a hook writes a second boot menu (`extlinux-fallback.conf`) whose default is the previous kernel and sets `upgrade_available=1` in u-boot's environment (a file on the FAT `/boot`); u-boot counts each boot attempt, and after **3** failed attempts it boots the fallback menu instead. A boot that reaches `multi-user.target` clears the counter. No A/B root filesystem for v0.x: recovery beyond that is the rescue menu entry or rewriting the card. **u-boot itself is never updated by apt** in v0.x. Security updates install themselves only on mains power.

## 1. Channels
| Layer | Source | Who signs/supports | How it updates |
|---|---|---|---|
| Ubuntu userspace (systemd, Mesa, iwd, libc, …) | noble, noble-updates, noble-security (ports.ubuntu.com) | Canonical (`main`) / community (`universe`, e.g. iwd, zram-generator, earlyoom) | apt; `unattended-upgrades` for `-security` only, with `Unattended-Upgrade::OnlyOnACPower "true"` |
| Our kernel `linux-image-<ver>-rg34xxsp` | **our apt repo** (`deb [signed-by=/usr/share/keyrings/rg34xxsp.gpg] https://… noble main`) | us; built reproducibly by `scripts/build-kernel.sh` (KR) | apt; each version is a separate package name, so the old one stays installed |
| Board package (`rg34xxsp-board`: today's `config/rootfs/` + `image/overlay/`) | our apt repo | us | apt (conffiles: local edits are kept) |
| Display layer (R19), frontend, emulator configs | our apt repo | us | apt |
| u-boot (SPL + u-boot at 8 KiB) | **image only** | us | not by apt in v0.x (§4) |

Repository tooling: `reprepro` 5.3.1 or `aptly` 1.5.0 (both in noble `universe`) generate a static repo; host it as static files (e.g. GitHub Pages or release assets) with a dedicated signing key kept offline. Mesa comes from Ubuntu, so an Ubuntu Mesa update can change the GPU stack (R6); if one regresses Panfrost, pin it with an apt preferences file shipped in the board package until fixed.

## 2. Kernel updates and automatic rollback
**What happens on `apt install linux-image-<new>-rg34xxsp`** (all of it already in the R7 image):
1. The kernel package installs `/boot/vmlinuz-<new>` (FAT) and its DTBs under `/usr/lib/linux-image-<new>/`.
2. `/etc/kernel/postinst.d/zz-u-boot-menu` (u-boot-menu) copies the DTBs to `/boot/dtb-<new>/` and rewrites `extlinux.conf`: newest kernel first (`l0`), the previous one as `l1`, each with a rescue entry.
3. `/etc/kernel/postinst.d/zzz-h700-fallback` → `h700-kernel-fallback` writes `extlinux-fallback.conf` (same entries, `default l1`) and runs `fw_setenv upgrade_available 1; fw_setenv bootcount 0` (libubootenv-tool, `main`; `/etc/fw_env.config` → `/boot/uboot.env 0x0000 0x10000`).
4. On the next boots u-boot (`CONFIG_BOOTCOUNT_LIMIT` + `CONFIG_BOOTCOUNT_ENV`) increments `bootcount` and saves the environment, **only while `upgrade_available=1`** (so there are no environment writes on normal boots). When `bootcount` exceeds `bootlimit` (3), u-boot runs `altbootcmd` instead of `bootcmd`: it clears the trial, sets `fallback_used=1`, saves, and runs `sysboot mmc 0:1 fat ${scriptaddr} /extlinux/extlinux-fallback.conf`, i.e. boots the previous kernel.
5. `h700-boot-ok.service` (after `multi-user.target`) clears `upgrade_available` and `bootcount` once a boot gets that far. If `fallback_used=1`, it also **makes the fallback menu the normal one** (copies `extlinux-fallback.conf` over `extlinux.conf`), records the failed kernel in `/var/lib/h700/failed-kernels` and clears the flag; otherwise every later reboot would try the failed kernel again without counting. The next kernel install regenerates both menus and starts a new trial. Later the frontend's own "ready" signal should replace `multi-user.target` as the health criterion, and the frontend should show `failed-kernels` to the user.

What counts as a failed attempt: any boot that doesn't reach the health check, e.g. a kernel panic (the command line now carries `panic=10`, so a panic resets the board), a hang that the user ends by holding power, or a watchdog reset (to add: `RuntimeWatchdogSec=` once the sunxi watchdog is confirmed in our kernel).

**u-boot side (for R1; config fragment, not yet built for sunxi):**
```
CONFIG_BOOTCOUNT_LIMIT=y
CONFIG_BOOTCOUNT_ENV=y
CONFIG_ENV_IS_IN_FAT=y            # already the sunxi default (env/Kconfig: default y if ARCH_SUNXI && MMC)
CONFIG_ENV_FAT_FILE="uboot.env"   # sunxi default; CONFIG_ENV_SIZE=0x10000
CONFIG_USE_PREBOOT=y
CONFIG_PREBOOT="setenv bootlimit 3; setenv altbootcmd 'setenv upgrade_available 0; setenv bootcount 0; setenv fallback_used 1; saveenv; sysboot mmc 0:1 fat ${scriptaddr} /extlinux/extlinux-fallback.conf'; if env exists upgrade_available; then; else setenv upgrade_available 0; setenv bootcount 0; saveenv; fi"
```
`preboot` runs before u-boot evaluates the counter (`common/main.c`: `run_preboot_environment_command()` before `bootdelay_process()`), so `bootlimit`/`altbootcmd` don't have to live in the saved environment. The first boot saves a full environment once, which is what `fw_setenv` then edits. Caveat: a saved environment pins u-boot's defaults at that version; after a u-boot change the image (or a script) must reset it (`env default -a`).

## 3. QEMU test (real u-boot, our kernel, the R7/R8 image)
`image/qemu/rollback-test.sh` boots a copy of the R7 image (our kernel, the hooks above) under **u-boot 2026.01 built for `qemu_arm64` with the same bootcount/env-on-FAT settings** (`image/qemu/u-boot-qemu-rollback.config`; `ENV_SIZE` set to sunxi's 0x10000 so `fw_env.config` is identical). Between runs it simulates a kernel update exactly as the hook would leave it: a new default entry `l0` whose kernel panics (`init=/bin/false`, with `panic=10`), the good kernel as `l1`, `extlinux-fallback.conf` defaulting to `l1`, and `upgrade_available=1`, `bootcount=0`. Logs: `image/qemu/results/rollback-run{1,2,3}.log`.

| Run | What happened (from the console log) | u-boot starts | Kernel panics | Env saves | Result |
|---|---|---|---|---|---|
| 1. first boot | u-boot found no `uboot.env`, preboot saved one; normal extlinux boot | 1 | 0 | 1 | good kernel; `upgrade_available=0 bootcount=0` readable by `fw_printenv` |
| 2. after the simulated bad update | 3 × (u-boot → new entry → panic → reset), then **"R8: boot limit reached, booting fallback"**, `extlinux-fallback.conf`, good kernel | 4 | 3 | 5 (4 counter increments, 1 in `altbootcmd`) | `h700-boot-ok`: counter cleared, **fallback made default**, `failed-kernels` written |
| 3. plain reboot | normal boot straight into the good kernel (`default l1`) | 1 | 0 | **0** | no flash writes on a normal boot |

So the full loop works with real u-boot code: counting only during a trial, the switch to `altbootcmd` after `bootlimit`, the fallback menu, the userspace clear, and no repeat of the failed kernel afterwards. Limits of the test: the simulated "new" kernel is the same build with a broken command line (so the log line reads "fell back from 7.4.0-rc2-rg34xxsp to 7.4.0-rc2-rg34xxsp"); the hook's real path (`apt install` of a second kernel version) and the **sunxi** u-boot build are not exercised; QEMU has no watchdog, so hangs weren't tested.

## 4. What is deliberately not updated in place
- **u-boot / SPL** (raw at 8 KiB): a bad write makes the card unbootable, and the DRAM type must match the board (R3). v0.x: new u-boot = new card image. A later `h700-update-bootloader` would need: DRAM-type check, checksum, write to a spare card first, and a recovery path (FEL, K4).
- **A/B root filesystems:** not for v0.x. apt isn't transactional, but its failure modes (interrupted dpkg) are recoverable with `dpkg --configure -a` from the rescue entry; A/B would double the card space and needs an image-based updater. Revisit if field reports show broken updates.
- **Power:** updates run only on mains power (`OnlyOnACPower`); manual `apt upgrade` on battery is the user's call. Battery level gating can be added to the frontend's update UI.

## 5. Versioning and recovery
- **Image name:** `rg34xxsp-noble-<YYYYMMDD>-<kernel>-<lpddr4|lpddr3>.img` + `.sha256` + `.manifest.tsv` (R7 already writes the first part, the manifest and the checksum; the DRAM suffix comes with `UBOOT_BIN`).
- **Kernel retention:** apt's built-in protection (`APT::VersionedKernelPackages` includes `linux-.*` in `/etc/apt/apt.conf.d/01autoremove`) keeps the running and newest kernels out of `autoremove`; check with two of our kernels installed before relying on it (QEMU, same test harness).
- **/boot space:** 256 MiB FAT; each of our kernels needs ~9.3 MB `vmlinuz` + its DTBs (~1–2 MB for 67 Allwinner DTBs) ≈ 12 MB, so many kernels fit.
- **Recovery ladder:** (1) automatic fallback (§2); (2) rescue entry (`single`) from the u-boot menu over serial; (3) rewrite the card from the release image; user data on a separate games card is unaffected.

## 6. Sources
- u-boot v2026.01 source (`common/autoboot.c` `bootcount_error()` → `altbootcmd`; `common/main.c` preboot order; `drivers/bootcount/Kconfig` and `bootcount_env.c` `upgrade_available` semantics; `env/Kconfig` FAT default for sunxi; `cmd/sysboot.c`).
- noble indexes, 2026-11-14: `libubootenv-tool` 0.3.5-0.1build1 (main), `u-boot-menu` 4.2.3ubuntu1 (main), `unattended-upgrades` 2.9.1+nmu4ubuntu1 (main), `reprepro` 5.3.1-5build4 and `aptly` 1.5.0+ds1-2 (universe).
- `/etc/apt/apt.conf.d/01autoremove` in the built image (VersionedKernelPackages).
