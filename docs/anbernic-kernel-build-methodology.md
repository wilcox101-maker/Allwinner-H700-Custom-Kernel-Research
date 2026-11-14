# How Anbernic builds and patches the RG34XXSP kernel

Research note, 2026-11-13. Method: static analysis of Anbernic's own binaries on Dale's PC (stock 2025 image `RG34XXSP.img` and the V1.0.6 firmware dated 2026-05-26), compared with public Allwinner SDK documentation, Orange Pi's public H616 kernel tree, mainline u-boot, and community projects. **Anbernic has not published its kernel or u-boot source** (Knulli wiki), so everything below about their *process* is reconstructed from the binaries. Each claim carries an evidence level:

- **[C] Confirmed:** read directly from Anbernic's binaries or a primary source.
- **[I] Inferred:** strongly supported by several pieces of evidence, but not stated anywhere.
- **[H] Hypothesis:** plausible; needs more evidence.

Nothing was modified. All analysis was read-only on copies.

---

## 1. Summary

Anbernic doesn't maintain a patch series against an upstream kernel. Each product is built from **its own full copy of Allwinner's H616/H700 BSP SDK (longan)**, kept on engineers' workstations in a shared folder. In practice:

1. Changes are **direct edits inside the vendor kernel tree** (Linux 4.9.170 + Allwinner BSP drivers), following Allwinner's own extension points:
   - new panels appended to the BSP's `panels.c` table;
   - lid sensing added to the PMIC power-key driver;
   - analog sticks added as a modified GPIO-keys driver;
   - boot-time screen and DRAM selection in boot0/u-boot.
2. Everything is built with **the SDK's bundled toolchain** (Linaro GCC 5.3-2016.05) by `build.sh`, then turned into firmware by **the SDK's `pack` step**. The result is converted into the SD card image they ship.
3. Hardware variants are handled **at boot, not with separate kernels**:
   - the first-stage loader (boot0) carries more than one DRAM parameter set and picks one (decoded since: PH6/7/8/10 straps, `docs/r3-v106-boot0-dram-sets.md`);
   - u-boot reads a GPIO strap on port E and passes `lcd_type=` to the kernel (decoded since: PE6, `docs/rg34xxsp-panel-detect-and-uboot-patch.md`);
   - the kernel picks the matching panel driver.
4. The Ubuntu 22.04 root filesystem is a **plain jammy install** (Tsinghua mirror) with the kernel modules **copied straight from the build tree**. No kernel `.deb`: the module `build`/`source` symlinks still point to the engineer's SDK path.

So the "current binaries" come from a vendor SDK plus local edits, rebuilt on demand. They can't be rebuilt or patched by anyone outside Anbernic. Community projects therefore either **reuse the binaries** (Knulli, muOS, StockOS-Mod) or **replace them with mainline** (ROCKNIX, and this project).

---

## 2. Evidence

### 2.1 Build identity, from the kernel binaries [C]
| Image | Kernel build string |
|---|---|
| Stock 2025 (`RG34XXSP.img`, p4) | `Linux version 4.9.170 (flower@flower-B85M-D2V) (gcc version 5.3.1 20160412 (Linaro GCC 5.3-2016.05) ) #19 SMP PREEMPT Sat Apr 12 16:50:28 CST 2025` |
| V1.0.6 (2026-05-26) | `… (flower@flower-B85M-D2V) (… Linaro GCC 5.3-2016.05) #9 SMP PREEMPT Tue May 26 15:49:58 CST 2026` |
| RG35XX SP (2024, Chris Morgan's log) | `4.9.170 (cc@cc-H81M-S1) (… Linaro GCC 5.3-2016.05) #241 … Apr 11 12:49:34 CST 2024` |
| RG35XX H (2024, CodeAsm) | `#276 SMP PREEMPT Thu Apr 11 12:12:08 CST 2024` |
| RG40XX V (Dec 2025, swetoast guide) | `#14 SMP PREEMPT Thu Dec 25 12:29:54 CST 2025`, U-Boot 2018.05 |

What this shows:
- [C] **Several engineers, each with their own workstation** (`flower`, `cc`), all in China Standard Time.
- [C] **The same 2016 Linaro toolchain** across all products.
- [I] The build counter went back from #19 (2025) to #9 (2026). The kernel was built from a **fresh or different tree copy** for V1.0.6, not by continuing in the old one. That matches the path change below.

### 2.2 SDK location, from module paths [C]
`mali_kbase.ko`, and the module symlinks `/lib/modules/4.9.170/{build,source}` in the V1.0.6 rootfs, point to:
```
/home/flower/cc_share/allwinner/h700/rg34xxsp/sdk/dynamic_standby/kernel/linux-4.9
```
CodeAsm found the same pattern for the RG35XX H:
```
/home/flower/cc_share/allwinner/h700/rg35xxh/sdk/rg35xxh/kernel/linux-4.9
```
- [C] The layout `<sdk>/kernel/linux-4.9` matches Allwinner's **longan** SDK, which has `brandy/` (boot0 + u-boot), `build/` (incl. `pack` and `toolchain`), `device/config/chips/...` and `kernel/linux-4.9`.
- [I] There's **one SDK copy per product** (`rg35xxh`, `rg34xxsp`), and sometimes per feature line. `dynamic_standby` suggests the V1.0.6 kernel came from a tree set up for suspend/standby work. They're kept in a shared folder (`cc_share`).
- [C] The stock firmware unpacked in Knulli's guide is named `h700_linux_tv_uart0_20231108.img`. That's the longan `pack` naming (`<chip>_<platform>_<board>_<uart>.img`; Allwinner's example is `t509_linux_demo_uart0.img`). [I] Anbernic started from Allwinner's **H700 "tv" reference board** configuration (the H700 is a TV-box SoC variant).

### 2.3 What's in the tree: Allwinner BSP plus Anbernic edits
**Base.** Orange Pi's public H616 kernel (`orangepi-xunlong/linux-orangepi`, branch `orange-pi-4.9-sun50iw9`) is also **4.9.170** [C]. It has the same BSP layout: `modules/gpu/mali-bifrost/driver/...`, `drivers/regulator/axp2101-regulator.c`, `drivers/input/misc/axp2101-pek.c`, and `drivers/video/fbdev/sunxi/disp2/disp/lcd/panels.c` [C]. Anbernic's kernel also contains `sound/soc/sunxi_v2/*` (Audio Hub) and `drivers/power/supply/axp2202_*.c`, which **aren't** in Orange Pi's tree [C]. [I] Anbernic got a **newer Allwinner H616/H700 BSP drop** than the one Orange Pi published, on the same 4.9.170 base.

**Anbernic's own changes, found as strings in the kernel [C]:**

| Feature | Evidence | How it was done |
|---|---|---|
| Panel drivers | Panel table strings end `… fx070 \| FX070_DHM18BOEL2_1024X600 \| bp101wx1 \| rg34xxsp_v1`. Also `lcd_panel_fog_fj035fhd05_v1_init` | Orange Pi's `panels.c` lists Allwinner's stock panels **ending at `bp101wx1_panel`**. Anbernic **appended their panels to the vendor table** (BSP `disp2/lcd` driver model) |
| Runtime panel selection | `lcd_type=` boot parameter (`__setup`), `allen_get_lcd_type`, `===%s:L%d,lcd_type= %d`, `allen_boe_lcd=%d, str=%s` | Kernel reads `lcd_type` from the command line and picks the panel |
| Panel detection in u-boot | u-boot strings `--allen--PE_pull[31:0] = 0x%x`, `--allen--PE_data[31:0] = 0x%x`, `===%s:L%d,lcd_type = %d` (in **both** the 2025 and V1.0.6 bootloaders) | u-boot reads the **PE6 strap** (decoded later) to identify the panel, then passes `lcd_type=` |
| Analog sticks | `drivers/input/keyboard/gpio_keys_gpadc.c`, `amux-en-gpios`, `adc_cal`, `joypad_store_adc_cal`, device name `dierct-keys-polled` (sic) | A **modified copy of `gpio-keys-polled`** that also reads sticks through the GPADC + analog mux. Not in Orange Pi's tree |
| Lid sensor | `hall_switch_isr`, `hall_press_work_func`, `hall_key`, `get_hallkey_state`, inside the `axp20x_pek` power-key code | Hall sensor **added to the PMIC power-key driver** (0 "hall" matches in Orange Pi's `axp2101-pek.c`). That's why the lid is a power-key event rather than `SW_LID` |
| Device check | `deeplay_encrypt_init`, `allen: deeplay devic fail`, `## deeplay device errr !!!`, chardev `deeplayer`, near I²C setup code | [H] An **I²C-based device check** (anti-clone or licensing chip), exposed to userspace as a character device. The hostname on CodeAsm's unit was `deeplay` |
| Debug tags | `[allen]`, `--allen--` throughout the kernel and u-boot | [I] One engineer ("allen") owns board-level changes in both u-boot and kernel |

**What changed between 2025 and V1.0.6 [C].** Comparing the strings of the two kernels:
- **one new panel driver, `rg34xxsp_v1`**;
- **SD card re-detect/retry logic** (`retry sd attach`, `Unable to re-detect card`, `mmc_sd_init_card()` debug);
- the source-file lists in the two kernels are **identical** (1,100 paths each).
- (Found later: the CPU speed-bin decoder also differs for one fuse value, `0x7c00`; see `docs/stock-cpu-bin-decoder-and-dcdc2.md`.)

[I] A board revision is handled with a **small, targeted edit set** in the per-product tree. The SD retry logic fits the V1.0.6 change to a non-removable TF1 noted in the Redux repo.

### 2.4 Bootloader and DRAM handling [C]
- The boot0 header at 8 KiB (`eGON.BT0`) holds the DRAM parameters. The boot0 strings define the type codes: `DRAM Type =%d (3:DDR3,4:DDR4,7:LPDDR3,8:LPDDR4)`.
- **2025 boot0:** type **8 (LPDDR4)** at **672 MHz**, `DX_ODT 0x08080808`, `DX_DRI 0x0e0e0e0e`, `CA_DRI 0x0e0e`, `ODT_EN 0x7887bbbb`, `TPR10 0x402f6633`.
- **V1.0.6 boot0:** default set is type **7 (LPDDR3)** at 672 MHz (`06060606 / 0d0d0d0d / 1919 / 9988eeee`), with the `DRAM.ext` strap table switched on. Fully decoded in `docs/r3-v106-boot0-dram-sets.md`: PH6/7/8/10 straps; index 15 → LPDDR4, 14 → LPDDR3.
- The `dram_type = 3` / `dram_clk = 792` values in the stock kernel DTB are **template values**: boot0 ignores them.
- **Mainline link [C]:** mainline u-boot's `anbernic_rg35xx_h700_defconfig` uses the 2025 boot0 drive/ODT values (`DRAM_CLK=672`, `DX_ODT=0x08080808`, `DX_DRI=0x0e0e0e0e`, `CA_DRI=0x0e0e`, `ODT_EN=0x7887bbbb`, `TPR10=0x402f6633`, LPDDR4). Mainline's numbers were taken from Anbernic's boot0, which is how the community made mainline DRAM init possible. **Dale's 2025 board uses the same LPDDR4 parameters**, pending a boot test.
- Boot0 sits at 8 KiB, the u-boot "boot package" (u-boot, ATF, SCP, DTB in Allwinner's TOC format) at 16,400 KiB, and the first partition at 36 MiB (Knulli guide + our GPT read) [C]. The u-boot environment selects `setargs_mmc` and `boot_normal=sunxi_flash read 45000000 boot;bootm 45000000` [C].

### 2.5 Root filesystem and module install [C]
- `/etc/apt/sources.list`: Ubuntu **jammy** ports from `mirrors.tuna.tsinghua.edu.cn`. Hostname `ANBERNIC`. 1,284 dpkg packages. **No `linux-image` package**, no Armbian release files.
- `/lib/modules/4.9.170` holds 16 modules: `8821cs.ko` (Realtek vendor driver), `rtl_btlpm.ko`, camera sensors from Allwinner's `sunxi-vin` (left over from the reference board) and others. They have `vermagic=4.9.170 SMP preempt mod_unload modversions aarch64`. `mali_kbase.ko` (`r20p0-01rel0`) sits directly in `/lib/modules/`.
- Module files are dated the same morning as the kernel build. The `build`/`source` symlinks point into the SDK tree. [I] Modules come from `make modules_install` (or a copy) **straight into the rootfs image**. The kernel goes into `boot.img` through the SDK's pack step. Neither is versioned through apt.

---

## 3. Anbernic's pipeline, reconstructed [I]

```
Allwinner H616/H700 longan SDK drop (BSP 4.9.170, brandy u-boot 2018.05, boot0, pack tools,
Linaro GCC 5.3 toolchain), board config started from the H700 "tv" reference board
        │  copy per product (and per feature line) into ~/cc_share/allwinner/h700/<product>/sdk/<line>/
        ▼
Direct edits in the tree (no upstream patch series):
  kernel/linux-4.9:  panels appended in disp2/lcd/panels.c (+ panel .c files), lcd_type= cmdline,
                     gpio_keys_gpadc.c (sticks), hall sensor in axp20x/axp2101 pek, deeplay check,
                     MMC tweaks; board DTS (sys_config-style `board.dts`) under device/config/...
  brandy:            boot0 DRAM parameter set(s) for the board's memory; u-boot reads PE straps → lcd_type
        ▼
./build.sh config  →  ./build.sh  →  ./build.sh pack      (Allwinner's documented 3-step flow)
        ▼
h700_linux_tv_uart0_<date>.img  (longan firmware: boot0, boot_package, boot-resource, env, boot …)
        ▼
Converted to an SD image (GPT): boot0 @ 8 KiB, boot package @ 16,400 KiB, partitions from 36 MiB
  + ext4 rootfs = Ubuntu 22.04 jammy (apt) + /lib/modules copied from the build tree
  + appfs launcher + exFAT Roms
```

How a hardware revision gets supported (the V1.0.6 case):
1. Add the new panel driver to the BSP panel table (`rg34xxsp_v1`).
2. Extend u-boot strap detection so it reports the new `lcd_type`.
3. Add the new DRAM set to boot0, selected at boot.
4. Make any driver fixes the board needs (SD re-detect).
5. Rebuild and repack.

There's **one image for both boards**, which is why stock firmware can boot old and new units while CFWs built on old binaries can't.

---

## 4. How the community made current binaries possible

| Approach | Who | How it works | Limits |
|---|---|---|---|
| Reuse stock binaries | Knulli, muOS, StockOS-Mod, alpine-h700 | Copy boot0, boot package and `boot.img` from stock (OpenixCard / `dd`). Build extra modules against **vanilla 4.9.170** with the stock config (`/proc/config.gz`, `CONFIG_IKCONFIG_PROC=y`) and the Knulli toolchain | `CONFIG_MODVERSIONS=y`: only modules for subsystems Anbernic didn't touch load reliably. No kernel fixes possible. New boards need new stock binaries (Knulli "Scarab" 2026-05 added revised H700 support this way) |
| Replace with mainline | ROCKNIX, upstream (Walklin, Morgan, Przywara, Škrabec), this project | DRAM parameters lifted from boot0 headers into u-boot defconfigs. Board DTs written from the vendor DTB (`dtc` of `boot.img`) and serial logs. Panel init sequences captured into per-panel blobs for `panel-mipi-dpi-spi` | Out-of-tree display stack still required. Every panel and DRAM variant has to be characterised by hand |

## 5. What this means for the Ubuntu 24.04 project

1. **Confirms the mainline route.** Anbernic's kernel can't be rebuilt from public sources. It's a private 4.9.170 BSP fork built with a 2016 compiler, and the modules aren't packaged. A 24.04 distro on it couldn't take kernel fixes.
2. **Reuse Anbernic's hardware knowledge, not their code:**
   - DRAM: 2025-board boot0 = mainline `lpddr4` defconfig values. For revised boards, the V1.0.6 boot0 LPDDR3 set = ROCKNIX's `lpddr3` defconfig drive/ODT values.
   - Panel identification: reproduced in our u-boot patch (PE6).
   - Lid: stock routes the hall sensor through the power key. Mainline's `gpio-keys` `SW_LID` on PE7 is the cleaner design and is already in the upstream RG35XX SP DT.
3. **The `deeplay` device check** is irrelevant to a mainline kernel. Stock *userspace* may still look for its `deeplayer` character device. Not our concern, since we don't ship Anbernic's launcher.
4. **Licensing:** the stock kernel is GPL-2.0 code, and the source hasn't been published. We take **no code** from the stock binaries, only hardware facts (register values, timings), and document where each came from. *Not legal advice.*

## 6. Follow-ups
- Done: stock u-boot panel-detect routine (PE6) and the V1.0.6 boot0 `DRAM.ext` table.
- Confirm on hardware: our 2025 board boots with mainline `lpddr4` u-boot (K2 via the ROCKNIX DDR4 image, or the FEL test K4).

## Sources
Local, read-only (Dale's PC):
- `RG34XXSP.img` (2025): GPT, boot0 @ 8 KiB, p4 `boot.img`
- `.FW/RG34XXSP-V1.0.6-EN16GB-260526/{2.env,3.boot,4.rootfs}.img` and the `.IMG` raw head

Public:
- Knulli, RG35XX H (Anbernic hasn't published kernel/u-boot source): https://knulli.org/devices/anbernic/rg35xx-h/
- Knulli, H700 firmware extraction: https://knulli.org/guides/h700-firmware-extract/
- Allwinner, Longan Linux development guide (SDK layout, `build.sh config / build.sh / build.sh pack`): https://server7.whycan.com/files/allwinner/f133mx-hxx/Software软件类文档/SDK模块开发指南/Longan_Linux_开发指南.pdf
- Orange Pi H616 BSP kernel 4.9.170: https://github.com/orangepi-xunlong/linux-orangepi/tree/orange-pi-4.9-sun50iw9
- Mainline u-boot `anbernic_rg35xx_h700_defconfig`: https://github.com/u-boot/u-boot/blob/master/configs/anbernic_rg35xx_h700_defconfig
- CodeAsm, RG35XX H (SDK path): https://codeasm.com/hardware/anbernic-RG35XXH
- Chris Morgan, RG35XX SP boot log (`cc@cc-H81M-S1`): https://gist.github.com/macromorgan/ea39d090ef75281194bb2f0a307bb0c7
- swetoast, Anbernic firmware development guide (RG40XX V build identifiers): https://github.com/swetoast/Anbernic-Firmware-Application-Development-Guide
- Building modules against vanilla 4.9.170 with Knulli's config: https://gist.github.com/mnml/12f75bbf16eac4def15ba72cf1b11926
- Knulli Scarab release (revised H700 support): https://github.com/knulli-cfw/knulli-linux/releases
