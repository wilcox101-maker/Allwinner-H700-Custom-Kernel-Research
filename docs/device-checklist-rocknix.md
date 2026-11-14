# Device checklist: ROCKNIX 20261101 on a spare card (one session)

For Dale. **Spare card only. The stock card comes out and stays out.** Nothing is written to the stock
card or to the device's own storage. Purpose: learn what a mainline kernel already does on this exact
unit before Phase 2. Background: [kernel-findings-2026-11-13.md](kernel-findings-2026-11-13.md). Prepared
2026-11-13. Nothing below has been run yet.

## 0. Before: identify the board (on the current stock/Redux system, terminal or SSH)
Write down the output of each:
1. RAM: `grep MemTotal /proc/meminfo`
2. DRAM voltage (DCDC3):
   `for r in /sys/class/regulator/regulator.*; do echo "$(cat $r/name) $(cat $r/microvolts 2>/dev/null)"; done`.
   ROCKNIX's rule: 1100000 = LPDDR4, 1200000 = LPDDR3. The regulator name on stock 4.9 may not be
   `vdd-dram`; look for `dcdc3`.
3. Panel: `dmesg | grep -i -E 'lcd|panel|fog|rg34'`, and the stock firmware version on the card.
4. CPU steps: `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies`
5. Trips: `cat /sys/class/thermal/thermal_zone*/trip_point_*_temp`
6. CPU speed fuse (read-only, root). It is the 16-bit value at physical `0x03006200`, the same cell
   the stock and mainline kernels use. First try
   `for n in /sys/bus/nvmem/devices/*; do echo $n; xxd -l 4 $n/nvmem; done`; if that finds nothing:
   `python3 -c "import mmap,os,struct;f=os.open('/dev/mem',os.O_RDONLY|os.O_SYNC);m=mmap.mmap(f,4096,mmap.MAP_SHARED,mmap.PROT_READ,offset=0x03006000);print(hex(struct.unpack('<I',m[0x200:0x204])[0]))"`
7. CPU voltage at the top step: `cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq` and the
   `dcdc1` (or `vdd-cpu`) line from step 2's loop, read together while a game runs

If step 2 is unclear, stop and send the output first: the image choice depends on it.

## 1. Flash and set the device tree (PC side)
1. Image by DRAM type: LPDDR4 → `ROCKNIX-H700.aarch64-20261101-DDR4.img.gz`, LPDDR3 → `…-DDR3.img.gz`
   (github.com/ROCKNIX/distribution/releases/tag/20261101). Flash to the **spare** card (Etcher/Rufus).
2. On the card's ROCKNIX partition, copy `device_trees/sun50i-h700-anbernic-rg34xx-sp.dtb` to the
   partition root and rename it `dtb.img`.
3. Power off the device, swap in the spare card (TF1), power on.
4. **Screen garbled or blank with sound:** hold power 10 s at once (keep a wrong panel driver's run
   time short). Then put `sun50i-h700-anbernic-rg34xx-sp-v2-panel.dtb` in as `dtb.img` instead.
   Record which one worked.

## 2. Checks (PASS / FAIL + what you saw)
| # | Check | Look for |
|---|---|---|
| 1 | Boot | Reaches EmulationStation; note seconds from power on |
| 2 | Screen | Correct picture, no flicker; brightness setting changes the backlight |
| 3 | Buttons | Every button registers in ROCKNIX's controller setup |
| 4 | Sticks | Both sticks, all four directions each, correct way round (note any inverted axis) |
| 5 | Lid | Close: screen off / sleep. Open: back where you were |
| 6 | Suspend | Power press sleeps; power press wakes into the same game. Battery % before and after 30 min asleep |
| 7 | Wi-Fi | Joins your network |
| 8 | Audio | Speaker, headphones, volume keys |
| 9 | Battery | % shown; charging shows on USB-C |
| 10 | TF2 | A card in the second slot shows up (optional) |

## 3. Logs (ROCKNIX SSH or Samba share; enable in its network settings)
```
cat /proc/device-tree/rocknix-dt-id
cat /sys/power/mem_sleep
cat /storage/.config/sleep.conf.d/sleep.conf
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
cat /sys/class/thermal/thermal_zone*/trip_point_*_temp
for r in /sys/class/regulator/regulator.*; do echo "$(cat $r/name) $(cat $r/microvolts 2>/dev/null)"; done
dmesg > /storage/dmesg-rocknix.txt
```
Copy `dmesg-rocknix.txt` and the outputs off the card. Afterwards: power off, put the stock card back.

Results go to the owner chat as one hw-result note (Dale's words plus the logs).
