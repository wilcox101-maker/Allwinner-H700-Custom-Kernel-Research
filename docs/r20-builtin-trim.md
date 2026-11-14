# R20: built-in (`=y`) code the RG34XX-SP cannot use (trial, desk and QEMU only)

Date: 2026-11-14. Follows R17 (module trim) and R18 (kernel in QEMU), which left built-in code as
the larger share of the kernel. **Nothing here has run on an RG34XX-SP**, and the default build
does not change: the trimmed config is an opt-in trial fragment until device task K3 (serial
console) can show a real boot with it.

## 1. Result
Same tree for both: torvalds `97d73c8` + `patches/linux` + display layer (`build-kernel.sh
--display`), with and without `--fragment config/rg34xxsp-builtin-trim.config`.

| | Without trim | With trim | Change |
|---|---|---|---|
| `Image` (uncompressed, what u-boot loads after gunzip) | 23.7 MB | 18.0 MB | −5.8 MB (−24 %) |
| `vmlinuz` (`Image.gz`, on the card) | 9.7 MB | 7.6 MB | −2.1 MB |
| `.deb` / installed | 13.4 / 27.2 MB | 10.6 / 24.1 MB | −2.8 / −3.1 MB |
| Modules | 165 files, 10.8 MB | 168 files, 10.8 MB | +3 (were built in, now modules: below) |
| QEMU 512 MB: MemTotal | 491 052 kB | 495 800 kB | +4.6 MB |
| QEMU 512 MB: MemAvailable after boot | 433 616 kB | 439 768 kB | +6.0 MB |
| QEMU 512 MB: kernel part of boot (TCG, one run each) | 1.48 s | 1.13 s | −0.35 s |
| QEMU: units started, errors in log | — | identical set; 0 errors in both | — |

QEMU is `virt` + Cortex-A53 under TCG with the R18 noble/iwd rootfs (`r20/swapkernel.sh` puts
each kernel package into the same rootfs). It proves the trimmed kernel still runs a full Ubuntu
userspace without an initramfs; it does **not** exercise any H700 driver. Logs:
`r20/results/boot-{base,trim}-512.log`.

On a 512 MB unit, 6 MB is about 1.4 % of RAM. It is worth having, but it is not the reason to rush
this: the reason is a smaller, simpler kernel with less code that can misbehave.

## 2. What the fragment turns off (232 lines; `config/rg34xxsp-builtin-trim.config`)
Grouped by reason, every line checked to hold after `olddefconfig` (build-kernel step 2a):
- **Firmware/platform features the board lacks:** Xen, EFI (u-boot boots the Image with `booti`
  via extlinux, not as an EFI app), NUMA, memory hotplug, hibernation (suspend-to-RAM stays),
  SCMI/SCPI, SDEI, TEE/OP-TEE, SMMU, ChromeOS EC, the VM clock.
- **Storage it lacks:** ATA/SATA, MTD (NOR/NAND), UFS, SAS. USB sticks still work: SCSI,
  `BLK_DEV_SD` and `USB_STORAGE` stay built in.
- **Network hardware it lacks:** every Ethernet vendor (there is no Ethernet; Wi-Fi is SDIO and
  USB NICs are modules), NFS client and NFS root.
- **USB controllers of other SoCs:** xHCI, DWC3, DWC2, ChipIdea, ISP1760. The H616's own MUSB (OTG)
  and EHCI/OHCI (host) stay built in.
- **PMICs, regulators, clock chips of other boards** (AXP717 and fixed regulators stay), and
  **Allwinner CCU/pinctrl/power-domain drivers of other SoCs** (A64, A100, H6, H3, A523, A733, D1).
- **Leaf drivers with no node in any RG34XX-SP tree** (other MMC hosts, SPI/I2C/GPIO controllers,
  NOR flash, TPM, RTC, battery gauge).

The candidates came from a scan: every `=y` driver symbol whose `of_device_id` compatibles match
no node (enabled or not) in our five trees. Library and core symbols the scan also found
(`GPIO_GENERIC`, `INTERCONNECT`, `RESET_SIMPLE`, `RESET_SUNXI`, GICv3, PSCI cpuidle, …) were
kept on purpose; turning those off saves little and risks a dependency we can't see on the desk.

`r20/results/config-diff.txt` lists all 374 options that stop being `=y` (the fragment's lines
plus what depended on them). Three become modules instead of disappearing:
`DMA_VIRTUAL_CHANNELS`, `DRM_PANEL_ORIENTATION_QUIRKS`, `REGMAP_SPI`. No module was lost (the
module-trim check passes).

## 3. New permanent check: the boot path is built in
`tools/boot_path.py` follows, from given device-tree nodes, every reference a driver waits on
before probing (clocks, resets, pinctrl, supplies, GPIOs, interrupt parents, parent buses, …)
and reports each driver's Kconfig value. `build-kernel.sh` now runs it on every build (step 2a2)
for SD slot 1 (`mmc@4020000`) and the serial console, and also requires `MMC_BLOCK`, `EXT4_FS`,
`MSDOS_PARTITION` and `DEVTMPFS` built in. Result today, with and without the trim: 15 entries on
the path (MMC, UART, CCU, R-CCU, RTC, both pin controllers, GIC, NMI, R-I2C, AXP717, the 5 V fixed
regulator, the 24 MHz oscillator, the SoC bus, and the DMA engine). All are `=y` except the DMA
engine, a module the UART can work without.
`r20/results/boot-path.tsv` has the list.

So **the RG34XX-SP needs no initramfs** to mount root from SD slot 1, on the desk evidence. This
matches what R18 measured in QEMU (initramfs optional), now checked against the real board tree.

## 4. Watchdog
`SUNXI_WATCHDOG` stays a module (`sunxi_wdt.ko`, loaded by udev). It doesn't cover a hang before
udev runs. Deep Research (R8 §3) agrees that is enough for v0.x; built-in is a one-line change if
K17 (rollback on hardware) shows early hangs.

## 5. Plan
1. Now: the fragment is a trial (`--fragment`), not in the default build. The new boot-path check
   *is* in the default build.
2. After **K3** (serial console works): boot the trimmed kernel from a spare card, compare `dmesg`
   with the untrimmed kernel (same driver probe list, no new deferred probes), then run the K4/K5
   checks. If equal: make the fragment default.
3. Afterwards, possible further steps (not done): a scan for `=y` options that are not DT drivers
   (filesystems, network protocols, debug options), measured the same way.

## 6. Risks
- A driver we turned off could be needed by something the desk can't see (firmware tables,
  a node u-boot adds at boot). Mitigation: the K3 comparison above, and the fragment is one
  `--fragment` away from being dropped.
- Without `EFI_STUB` the kernel can't be started as an EFI application. Our boot path (R7/R8:
  u-boot, extlinux, `booti`) doesn't use that; anyone booting with `bootefi` would need it back.
