# R18: our kernel under the R5 noble userspace, in QEMU

Kernel Research chat, 2026-11-14. **QEMU only (`virt`, Cortex-A53, TCG on a 2-core x86-64 host).**
Nothing here ran on an H700. QEMU has none of the board's devices, so this measures the kernel's
own memory and disk cost and that Ubuntu's userspace runs on it, not that any board driver works.

## Setup
- **Kernel:** the R17 package `linux-image-7.4.0-rc2-rg34xxsp_7.4.0~rc2-1_arm64.deb`
  (`scripts/build-kernel.sh --build`).
- **Rootfs:** R5's iwd variant, built by `r5/build.sh` exactly as in R5, except no Ubuntu kernel
  (`KVER=`) and our package installed (`EXTRA_DEBS=`, new in this task):
  `ARCH=arm64 NET=iwd KVER= EXTRA_DEBS=<our .deb> r5/build.sh iwd-rg.tar`, then
  `r5/mkimg.sh iwd-rg.tar iwd-rg`.
- **Boot:** `r18/boot.sh iwd-rg <MB> [4] [initrd]`. It is R5's `boot.sh` with two changes: virtio over
  MMIO (our kernel has no PCI), and no initramfs unless asked (ext4 and virtio-blk are built in).
  Same 4 vCPUs and the same measurement hook (`r5/r5-measure`, 60 s after boot).
- **Comparison:** R5's iwd runs, same userspace, with Ubuntu's `6.8.0-149-generic`
  (`docs/r5-noble-userspace-prototype.md`).

## Results
**Memory** (`/proc/meminfo` 60 s after boot; R5 figures from its doc):

| RAM | Kernel | MemTotal | MemAvailable | Slab | AnonPages | PSS, all processes |
|---|---|---|---|---|---|---|
| 512 MB | Ubuntu 6.8 (R5) | 454 MB | 386 MB | 32 MB | 11 MB | 33 MB |
| 512 MB | **ours** | **480 MB** | **423 MB** | **19.5 MB** | 11.4 MB | 32.8 MB |
| 1 GB | Ubuntu 6.8 (R5) | 956 MB | 822 MB | 32 MB | 11 MB | 33 MB |
| 1 GB | **ours** | **982 MB** | **853 MB** | 19.5 MB | 11.4 MB | 32.4 MB |
| 2 GB | Ubuntu 6.8 (R5) | 1959 MB | 1818 MB | 32 MB | 11 MB | 33 MB |
| 2 GB | **ours** | **1985 MB** | **1852 MB** | 19.9 MB | 11.3 MB | 35.6 MB |
| 512 MB + initramfs | ours | 480 MB | 422 MB | 19.9 MB | 11.7 MB | 33.1 MB |

- **+26 MB MemTotal and +31 to +37 MB MemAvailable at every size.** The userspace columns
  (AnonPages, PSS) match R5, so the gain is the kernel's: less memory reserved for the kernel image
  and less slab (19.5 vs 32 MB).
- **zram works with our kernel**: `/dev/zram0`, zstd, 239.5 MB at 512 MB (R5's `ram / 2` setting).
- **All 10 services R5 saw are running**, iwd among them, and no console line contains "error" or
  "fail" in any of the four boots. iwd started with no missing-option message; its required kernel
  options were added in R17.

**Disk** (`r5/mkimg.sh`; its "kernel_MB" line is our kernel here, not a distro one):

| | R5 iwd (Ubuntu 6.8) | R18 (ours) |
|---|---|---|
| Rootfs total | 423 MB | **209 MB** |
| Kernel: `/boot` + modules + firmware | 247 MB | **33 MB** |
| Userspace | 176 MB | 176 MB |
| Packages | 146 | 144 (no Ubuntu kernel packages; ours added) |

**Boot time** under TCG emulation (only meaningful as a comparison between our own runs):
kernel 1.3–1.7 s without an initramfs, **7.6 s with one** (its 7.2 MB gzip archive unpacked under
emulation); userspace 21–26 s either way.

## Findings for other tasks
- **R1 (card layout): the initramfs isn't needed by the kernel.** Root on ext4 mounts directly,
  and the SD controller driver is built in (`MMC_SUNXI=y`). Without one, the boot is shorter and
  ~1.5 MB more memory stays free. What an initramfs would still give: an early fsck of the root
  file system, and a rescue shell. That trade-off belongs in R1; here it is only evidence.
- **R13 (RAM tiers):** for the 512 MB tier, plan on about **423 MB available** after boot with our
  kernel and the iwd stack, not R5's 386 MB.
- **Built-in trim (later):** `update-initramfs` warned about missing firmware for two **built-in**
  Ethernet PHY drivers (Microsemi, Realtek). The board has no Ethernet; this is the kind of `=y`
  code a later built-in trim would remove.
- `update-initramfs` used gzip because the minimal rootfs has no `zstd` tool; if R1 keeps an
  initramfs, adding `zstd` makes it smaller.

## Changes to Deep Research's R5 scripts (small, backward compatible)
- `r5/build.sh`: optional `EXTRA_DEBS` installs local `.deb` files at the end.
- `r5/mkimg.sh`: a kernel without its own `/usr/lib/firmware/<version>` directory made `du` fail
  under `set -e`. The sum now tolerates the unmatched glob. Behaviour with Ubuntu's kernel is
  unchanged.

## Files
`r18/boot.sh`; `r18/results/`: the four console logs, `iwd-rg.sizes`, `iwd-rg-packages.txt`.
