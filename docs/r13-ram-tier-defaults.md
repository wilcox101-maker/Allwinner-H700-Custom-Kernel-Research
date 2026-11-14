# R13: RAM-tier defaults (512 MB / 1 GB / 2 GB)

Deep Research, 2026-11-13. **Desk + QEMU only (Ubuntu's generic kernel, `virt`, Cortex-A53, TCG); nothing ran on an H700.** Master list task R13. Inputs: R5 (`docs/r5-noble-userspace-prototype.md`). Config files: [`config/rootfs/`](../config/rootfs/). QEMU check: [`r13/`](../r13/).

## Answer in one paragraph
**One image, one set of defaults, self-scaling by RAM.** The base system costs only ~33 MB of process memory at every tier (R5), so the tiers differ in how much headroom the frontend and emulators get, not in which system services run. Defaults: a **zram swap sized `min(ram, 1024)` MiB with zstd**, `vm.swappiness=100` and `vm.page-cluster=0`, **no swap on the SD card**, journald capped at 32 MB on disk, memory accounting on, and **earlyoom as the userspace OOM killer on every tier**. In the QEMU stress test (§5) all three OOM setups (kernel only, earlyoom, systemd-oomd) recovered the 512 MB guest; earlyoom and oomd ended the runaway process 25–70 s sooner than the kernel alone and earlyoom does it with SIGTERM first, which is why it is the default. The evidence for that choice is modest (one emulated run each). Everything here is a starting point to re-check on hardware (K12), with our kernel.

## 1. Tiers and what we know about them
| Tier | Boards (as reported; to confirm with K1 `MemTotal`) | DRAM (R3) | Free at idle, base system (R5, QEMU, generic kernel) |
|---|---|---|---|
| **T512** | revised board | LPDDR3 | ~386 MB of 454 MB |
| **T1G** | revised board | LPDDR3 | ~820 MB of 956 MB |
| **T2G** | original board (Dale's unit) | LPDDR4 | ~1820 MB of 1959 MB |

- The tier is simply **MemTotal at boot**; nothing else needs detecting. Where a setting must differ per tier, it uses systemd's `ConditionMemory=` (compares physical RAM; operators `<`, `<=`, `>=` …), so one image serves all three without a first-boot script.
- Budget guidance for the UI work (a **design target, not a measurement**): on T512, the frontend plus a running emulator core should stay under about **250 MB resident** so that zram is a buffer rather than a crutch. T1G/T2G have no practical constraint for 2D/retro emulation.

## 2. The defaults (same on every tier unless stated)

| Area | Default | Why |
|---|---|---|
| zram | `zram-size = min(ram, 1024)`, `compression-algorithm = zstd`, `swap-priority = 100` (`config/rootfs/etc/systemd/zram-generator.conf`) → 453 MiB / ~950 MiB / 1 GiB | zram only uses RAM for what it stores. Full-RAM sizing on T512/T1G gives the most headroom; the 1 GiB cap keeps T2G from storing more than it can ever need. noble's `systemd-zram-generator` 1.1.2 accepts **one** algorithm (no recompression) |
| Algorithm | **zstd** | Best ratio, which matters most on T512. LZ4 is the fallback if K12 shows stutter from (de)compression on the A53 while an emulator runs |
| Disk swap | **none** | SD card writes are slow and wear the card |
| sysctl | `vm.swappiness = 100`, `vm.page-cluster = 0` (`etc/sysctl.d/60-h700-zram.conf`) | Swap to zram before evicting file cache (ROM/game data); no readahead from a seek-free device. Starting values for K12 |
| OOM | **earlyoom** enabled (defaults: act when available RAM **and** free swap both fall below 10 %) | §5: ended both stress loads sooner than the kernel alone (258 s vs 330 s, 304 s vs 329 s, emulated). Small C daemon, no PSI or cgroup requirements, SIGTERM before SIGKILL, "kill the biggest" behaviour that suits one fullscreen app |
| OOM option | systemd-oomd (in noble `main`), **installed only when wanted**, with `ManagedOOMSwap=kill` on `-.slice` and a memory-pressure rule on `user@.service` (`etc/systemd/system/user@.service.d/60-h700-oomd.conf`) | Cgroup-aware and more precise, but needs `CONFIG_PSI`, and kills whole units; decide after K12 (§5) |
| Memory accounting | `DefaultMemoryAccounting=yes` (`etc/systemd/system.conf.d/60-h700-accounting.conf`) | Per-unit memory in `systemd-cgtop`; required if oomd is ever used |
| Journal | `Storage=persistent`, `SystemMaxUse=32M`, `RuntimeMaxUse=16M`, `MaxRetentionSec=1month` (`etc/systemd/journald.conf.d/60-h700.conf`) | Logs survive reboots for hardware debugging; bounded SD writes and RAM |
| Network | iwd + systemd-networkd + systemd-resolved (R5) | ~5 MB less RAM and 73 MB less disk than NetworkManager |
| SSH | socket-activated (`ssh.socket`, noble's default): costs nothing until used | — |
| Timers | **disable** `motd-news.timer` (network fetch for a login banner nobody sees) and `e2scrub_all.timer` / `e2scrub_reap.service` (LVM-only checks, no-ops here); keep `fstrim.timer`, `dpkg-db-backup.timer`, `systemd-tmpfiles-clean.timer` | Fewer wake-ups during play |
| Bluetooth | `bluez` not started until the user turns BT on | Not running at idle on any tier; matters most on T512 |
| /tmp | on disk (noble default) | A tmpfs /tmp would compete with games for RAM on T512 |

**Per-tier differences: none needed for v0.x.** The zram expression scales by itself, and the base system already fits T512 with room to spare. If K12 shows T512 needs more, the first lever is a `ConditionMemory=<640M` drop-in (for example, starting optional services only on T1G/T2G), not a separate image.

## 3. Kernel requirements (for R10; added to the master list)
- `CONFIG_ZRAM` (=m is fine) with `CONFIG_ZRAM_BACKEND_ZSTD` (and `_LZ4` for the fallback). Since Linux 6.12 zram uses its own compression back-ends, not the crypto API. **Already in R10's `config/rg34xxsp.config`**, as are `CONFIG_PSI=y` and the cgroup options.
- `CONFIG_PSI=y`, not disabled by default, so systemd-oomd stays an option (its unit has `ConditionPathExists=/proc/pressure/memory`).
- `CONFIG_MEMCG=y` and the unified cgroup hierarchy (noble default) for accounting.
- Do not set `CONFIG_ZSWAP_DEFAULT_ON`: zswap in front of zram is double work.

## 4. What is still unknown (device task K12, expanded)
1. Our kernel's own footprint (MemTotal reservations, slab). The generic kernel's numbers don't transfer.
2. zstd vs LZ4 cost on the A53 while an emulator runs: frame-time spikes during swap-in.
3. The real compression ratio of frontend/emulator memory (the QEMU test used base64 text, ~1.35:1; real heaps are usually better).
4. earlyoom thresholds on the device: does it fire before the UI stutters, and only at the biggest process?

## 5. QEMU check (512 MB, generic kernel, TCG)
`r13/mkimg-r13.sh` overlays `config/rootfs/` on the R5 iwd rootfs and replaces the R5 hook with `r13/r13-check`, which:
1. confirms the config is applied (zram size and algorithm, sysctls, journald, accounting);
2. **test A:** grows a transient unit's memory to 1.25 × RAM with compressible data (base64 of random bytes);
3. **test B:** grows one to 1.5 × RAM with incompressible random data;
4. records how long each hog lived, what zram held, and who killed it.

**Config applied (all runs):** zram0 453 MiB zstd, swap priority 100; `swappiness=100`, `page-cluster=0`; journald `Storage=persistent`, 32M/16M; `DefaultMemoryAccounting=yes`.

| OOM setup (512 MB, one run each) | Test A: base64 to 1.25 × RAM | Test B: random to 1.5 × RAM | Killed by | System after |
|---|---|---|---|---|
| Kernel OOM killer only | hog gone after **330 s** | **329 s** | kernel (2 kills) | running |
| **earlyoom** 1.7 (defaults) | **258 s** | **304 s** | earlyoom SIGTERM (2) | running |
| systemd-oomd 255 (`ManagedOOMSwap=kill` on `-.slice`, 90 %) | **268 s** (two runs: 268, 268) | **303 s** | oomd, whole `r13-hog*.service` | running |

What zram held just before each kill:
- **Compressible (test A):** up to 394–406 MB of data in 290–301 MB of RAM, a ratio of **~1.35:1** for base64 text. Real program heaps usually compress better [expected]; device numbers are K12.
- **Incompressible (test B):** zram barely engaged until RAM was nearly gone, then held 284–330 MB in 249–293 MB (~1.13:1). zram cannot help with random data, as expected.

Reading it:
- **All three recover.** The userspace killers act earlier, while there is still a little headroom, so the thrashing phase is shorter. Under emulation the times are stretched; on the device the gap will be seconds, but it is the stutter the player sees.
- **earlyoom vs oomd:** the same timing here. oomd kills a whole unit (good when the frontend launches each emulator as its own unit/scope; bad if everything runs in one service), needs PSI and accounting, and its 90 % swap threshold is system-wide. earlyoom is process-level and simpler. Default: earlyoom; revisit when the frontend's process layout is known (R7/UI).
- **Retracted:** an earlier run with a first version of the harness (the hog ran inside the reporting service itself, log `r13/results/boot-r13-512-v1harness-kernelonly.log`) showed the kernel-only guest printing nothing for over 10 minutes after the first OOM kill; I first reported that as a hang. With the hogs in their own transient units it didn't happen again, so it is **not** evidence about the kernel OOM killer; the cause wasn't traced.
- Single emulated runs on Ubuntu's generic kernel: indicative only.

## 6. Files
| Path | Purpose |
|---|---|
| `config/rootfs/etc/systemd/zram-generator.conf` | zram size and algorithm |
| `config/rootfs/etc/sysctl.d/60-h700-zram.conf` | swappiness, page-cluster |
| `config/rootfs/etc/systemd/journald.conf.d/60-h700.conf` | journal limits |
| `config/rootfs/etc/systemd/system.conf.d/60-h700-accounting.conf` | memory accounting |
| `config/rootfs/etc/systemd/system/user@.service.d/60-h700-oomd.conf` | oomd rule, used only if oomd is installed |
| `r13/r13-check`, `r13/r13-check.service`, `r13/mkimg-r13.sh` | QEMU check; `OOM=none|earlyoom|oomd` |
| `r13/results/` | raw console logs (`OOM=none|earlyoom|oomd`, plus the retracted v1-harness run) |

R7 (image tooling) installs `earlyoom`, copies `config/rootfs/`, and disables the timers listed in §2.

## 7. Sources
- zram-generator.conf(5), noble 1.1.2 (single `compression-algorithm`, default size `min(ram / 2, 4096)`, swap priority 100): https://manpages.ubuntu.com/manpages/noble/man5/zram-generator.conf.5.html
- systemd-oomd(8): requires cgroup v2, memory accounting, PSI (Linux 4.20+), and recommends swap: https://www.man7.org/linux/man-pages/man8/systemd-oomd.8.html ; unit condition on `/proc/pressure/memory`: systemd `units/systemd-oomd.service.in`
- systemd `ConditionMemory=` (compare operators, physical memory): systemd `src/shared/condition.c`
- Arch Wiki, zram (zstd commonly reaches about 3:1 on real data): https://wiki.archlinux.org/title/ZRAM
- noble ports indexes, 2026-11-13: `earlyoom` 1.7-2 (universe), `systemd-oomd` 255.4-1ubuntu8.18 (main), `systemd-zram-generator` 1.1.2-3 (universe)
