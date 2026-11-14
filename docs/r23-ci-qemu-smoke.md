# R23: QEMU boot smoke test of the image in CI

Deep Research, 2026-11-14. Assigned by the Manager chat, approved by Dale (GO). **QEMU only**: this proves that
the userspace, our kernel package, first boot and the card layout work together. It says nothing about the
RG34XX-SP's own hardware (display, input, Wi-Fi, PMIC, suspend); those stay device tasks (K-IDs).

## 1. What runs
`.github/workflows/image-smoke.yml`, on GitHub's `ubuntu-24.04` runner:

1. **Kernel package**: `scripts/workbench.sh --display` (all desk checks) then `scripts/build-kernel.sh --display --build`.
   Cached with `actions/cache`, keyed on the hash of `patches/`, `dts/`, `config/*.config`, `config/module-keep.txt`,
   `tools/` and the two scripts, so it is rebuilt only when one of them changes. Only `linux-image-…rg34xxsp_…deb`
   is kept (not the `-dbg` package).
2. **Image**: `image/build-image.sh` with that package (its licence and display checks run as part of it).
3. **Boot**: `image/qemu/smoke-test.sh <image> 512` boots a copy in QEMU `virt`, Cortex-A53, 4 vCPUs, **512 MB**
   (the smallest RAM tier), TCG, via `qemu-test.sh` (kernel and command line from the image's FAT partition,
   `r7-check` injected into the copy). Then it checks the console log:

| Check | Fails when |
|---|---|
| boot reached multi-user and the check ran | `R7BEGIN`/`R7END` missing (hang, panic, root not found) |
| systemd state | anything but `running` (e.g. `degraded` = a failed unit) |
| first boot grew root | no `h700-firstboot: root grown` line |
| root ≥ 2 GiB after growth | the copy is 3 GiB; root must have grown into it |
| SSH host keys, machine-id | first-boot setup didn't run |
| apt present | the minbase/apt regression from R6 |
| networkd, iwd, earlyoom, resolved, zram, ssh.socket | any not `active` |
| wired network | QEMU's NIC not `routable configured` |
| kernel is ours | `uname -r` doesn't end in `-rg34xxsp` |
| extlinux uses `fdtdir` | u-boot-menu didn't write the DTB directory (R7/R8 boot path) |
| no panic/Oops/BUG/segfault | any of these anywhere in the console log |

   DNS (through QEMU user networking) and free memory are reported, not failed, since they depend on the host.
4. **Artifacts** (14 days): the QEMU console log, the smoke report, the image manifest and checksum, build logs. The
   image itself is not uploaded.

Triggers: pull requests and pushes to `main` that touch `image/`, `config/`, `patches/`, `dts/`, `tools/`, the two
kernel scripts or the workflow; weekly (Monday 06:23 UTC) to catch noble-updates changes; and by hand
(`workflow_dispatch`). Actions are pinned by commit (checkout v7.0.1, cache v6.1.0, upload-artifact v7.0.2).
The workflow has read-only repository permissions.

## 2. Local run (2026-11-14, this chat; same commands as the workflow)
- Kernel from `main` (`workbench.sh --display` passed, `build-kernel.sh --display --build`), about 1 h on 2 cores.
- Image `reduxos-rg34xxsp-noble-20261114-deb.img`, 867 MB; licence and display checks PASS; mmdebstrap 443 s.
- Smoke test at 512 MB: **12 passed, 0 failed** in 1 min 31 s (root 595 MiB → 2.7 GiB; 417 MB available).
- **Negative controls:** the parser fails a log with `degraded` + no root growth (2 FAIL), one with no `R7END` and a
  panic line (2 FAIL), and an empty log (11 FAIL). A real broken image (ext4 superblock of the root partition zeroed
  in a copy) boots to `VFS: Unable to mount root fs`, QEMU exits through `panic=10`, and the test reports
  **0 passed, 12 failed**, exit 1.
- Two fixes found by running it: the build leaves a `-dbg` kernel package next to the real one (the workflow now copies
  only the real one and refuses more than one), and `sfdisk` comes from the `fdisk` package (now installed).

## 3. Use by hand
```sh
sudo image/qemu/smoke-test.sh out/reduxos-rg34xxsp-noble-<date>-deb.img 512   # boot + check, exit 0 = pass
image/qemu/smoke-test.sh --check-log out/<image>.qemu-512.log                   # re-check a saved log
```

## 4. Limits and next steps
- No u-boot in the loop: QEMU loads the kernel directly, as R7 did. `image/qemu/rollback-test.sh` (R8) covers
  u-boot's extlinux/bootcount path with the `qemu_arm64` u-boot; it could become a second CI job later.
- The `-uboot` image variant (real SPL at 8 KiB) can't boot in QEMU `virt`; its layout checks stay in the
  handoff's "image with the real bootloader" task.
- First CI run time on GitHub's 4-vCPU runner: see the PR's check; expected ~40–70 min with a cold kernel
  cache, ~15 min after.
