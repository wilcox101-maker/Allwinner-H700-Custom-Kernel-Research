# RG35XX H bring-up notes (CodeAsm): lessons for the RG34XXSP

Research note, 2026-11-13. Source: https://codeasm.com/hardware/anbernic-RG35XXH (Nico Vijlbrief, dated 2024-10-28), cross-checked against linux-sunxi and Chris Morgan's RG35XXSP notes. Nothing here has been tested on the RG34XXSP.

## 1. What the page is
- A personal notebook about the **RG35XX H**, not the RG34XXSP. The author calls it a mess and recommends a custom OS instead.
- It records a 2024 attempt to boot mainline u-boot on the H700, which never got to a working boot. Its value to us is the method and the mistakes, not a working recipe.

## 2. Findings that carry over (with confidence)

| Finding | Source | Applies to RG34XXSP? |
|---|---|---|
| H700 identifies over FEL as `soc=00001823(H616)`. Stock kernel 4.9.170, `mali_kbase`, `8821cs`, `rtl_btlpm` modules | CodeAsm | Same SoC and the same stock kernel family. Expected to match (verify with `sunxi-fel version`) |
| **FEL mode** is reached by connecting USB-C OTG with **no SD card**. `sunxi-fel` can then load SPL + u-boot (and kernel/DTB/initramfs) **into RAM** | CodeAsm; linux-sunxi RG35XX H page | **Likely; must verify.** Which slot the BROM boots from, and whether TF2 matters, is unconfirmed on this board |
| Stock boot image (p4) is Android boot v2: kernel base `0x40078000`, page size 2048 | CodeAsm (`unpackbootimg`) | Matches the Redux repo's `bootimg.py` finding |
| RG35XX H UART: header between the left SD slot and left speaker, pins GND, TX, RX, GND | linux-sunxi | Different board. Location doesn't carry over |
| RG35XX SP UART: 4 pinholes, bottom-right of the board. Pin 1 = GND, pins 2/3 = TX/RX at ~3.2 V, pin 4 also reads 0 Ω to ground. 115200 baud | Chris Morgan, 2024-05-20 | **Closest sibling to the RG34XXSP (also a clamshell).** Best lead for the UART pads (K3). Expect a 3.3 V UART |
| Vendor DTB extraction: `dd` p4 → `binwalk` → `dd skip/count` → `dtc` | Chris Morgan | Already done for our unit (Redux `reference/stock-202505/board.dts`) |

## 3. Why the CodeAsm boot attempt failed (our analysis, not the author's)
These explain the failure well, but they're inferences, not something the author confirmed:

1. **Wrong SD offset.** The page writes u-boot with `dd … bs=512 seek=64`, which is **32 KiB**. On sunxi the BROM looks for the SPL header at **8 KiB** (`bs=1024 seek=8`). H616/H618 also check an alternate location at **256 KiB**. 32 KiB is neither, so the BROM never sees the SPL. That offset appears to come from the Rockchip RGxx3 u-boot docs the author was following.
2. **Wrong BL31.** The build passed `BL31=../rkbin/rk35/rk3588_bl32_v1.15.bin`, a Rockchip RK3588 binary. The H700 needs **TF-A built for `PLAT=sun50i_h616`**. With the wrong BL31, u-boot can start in SPL but the handoff to EL3 can't work.
3. **Wrong DT for SD.** The SPL reported `allwinner/sun50i-h700-anbernic-rg35xx-2024` (the defconfig default). Since 2024, mainline u-boot has added board detection and DRAM options (`anbernic_rg35xx_h700_lpddr4/lpddr3` defconfigs, as used by ROCKNIX). The plain 2024 defconfig is not a fair test.

## 4. What changes in our plan

**A safer M2: boot over FEL before writing any card.** FEL lets us test our own SPL + u-boot + kernel + DTB + initramfs **entirely in RAM**. No boot0 is overwritten, no card is touched, and a power cycle returns the device to stock. Proposed order:

1. `sunxi-fel version` with no card inserted. Confirms FEL entry and the SoC ID. Read-only.
2. `sunxi-fel uboot u-boot-sunxi-with-spl.bin` (our LPDDR4 build). Watch for the u-boot prompt on serial (needs the UART) or for any sign of life.
3. Load kernel/DTB/initramfs to RAM over FEL and boot to a BusyBox shell on the console.
4. Only then write a **test card** at 8 KiB. Never the stock card.

**UART first (M0):** open the device and look for a 4-pad group like the RG35XX SP's. Find ground with a meter (0 Ω to a known ground) and confirm the ~3.3 V level before connecting a **3.3 V** USB-serial adapter at 115200 8N1. Don't connect a 5 V adapter.

**Safety notes**
- FEL loads into RAM only, so it can't brick the device. But a wrong DRAM setting just fails to train, and a wrong panel init could still stress the panel once a kernel drives it. Keep the panel driver out of the FEL test kernel until M1 confirms the panel variant.
- Opening the case voids the warranty (linux-sunxi). Soldering to the ground pad is hard: the ground plane soaks up heat (Chris Morgan suggests more flux).

## 5. Other references from the page
- Alpine Linux for H700 (`mporrato/alpine-h700`, Unlicense): reuses the **stock kernel and bootloader** from the factory image, tested on the RG35XX Plus. It's an example of the "stock kernel + new userspace" route (option A in our assessment), not mainline. It has a login on `/dev/ttyS0`.
- RG35XX-SP SSH/Samba helpers: `xgbox/rg35xxsp-ssh-samba`. Not needed: the Redux repo already covers SSH.

## Sources
- CodeAsm, Anbernic RG35XX H: https://codeasm.com/hardware/anbernic-RG35XXH
- linux-sunxi, Anbernic RG35XX H: https://linux-sunxi.org/Anbernic_RG35XX_H
- linux-sunxi, Bootable SD card: https://linux-sunxi.org/Bootable_SD_card
- Chris Morgan, Development Information for Anbernic RG35XXSP: https://macromorgan.blogspot.com/2024/05/anbernic35xxspinfoextract.html
- alpine-h700: https://github.com/mporrato/alpine-h700
