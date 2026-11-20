# Project status (2026-11-20)

One page: where ReduxOS for the RG34XX-SP stands, what used to be unknown and is now defined, and what remains.
Maintained by whoever changes the state; details live in the linked documents. `main` at `baddb17` when written.

## 1. Where we are
- **Everything builds from source and boots in QEMU.** u-boot v2026.10 + TF-A v2.14.0, mainline kernel `97d73c8` (7.4-rc2) with
  our patches as noble `.deb` packages. The current deliverable is the **full-featured ReduxOS beta (R32)**: it boots
  straight into RetroArch (KMS/GLES) as an unprivileged `player` user, with 9 libretro cores, codec audio and volume keys,
  built for both LPDDR4 and LPDDR3. QEMU smoke **16/16** on each; delivered privately to Dale, not published
  ([`reduxos-beta-build-2026-11-20.md`](reduxos-beta-build-2026-11-20.md) §R32, [`reduxos-frontend.md`](reduxos-frontend.md)).
  CI repeats the kernel and image build on every change.
- **Nothing of ours has run on an RG34XX-SP.** Every result is "desk only" unless a document says otherwise. The only
  hardware facts are a few readings Redux took on Dale's unit under **stock** (rows marked **[V]** in the task list: the
  unit has a rumble motor, stock's nine CPU frequency steps, a charge-current reading). The device is blocked until
  Redux v0.5, except K3/K4 on Dale's 2 GB LPDDR4 unit (decision Q11).
- Milestones ([assessment](ubuntu-2404-rg34xxsp-assessment.md)): the desk parts of M0–M5 are done; the hardware
  parts of M0–M4 have not started; M6 (release) is not started.
- Separate track, stock kernel: the global on-screen keyboard (R26–R28, DR-1 to DR-3). Redux has merged its daemon; the
  probe session K24–K28 is pending.

## 2. Previously unknown, now defined
| Element | Definition | Checked on | Record |
|---|---|---|---|
| Boot chain | BROM → SPL at 8 KiB → TF-A BL31 → u-boot; card layout; one SPL per DRAM type | desk + QEMU (real u-boot) | [R1](r1-boot-chain.md), [R24](r24-image-with-uboot.md) |
| DRAM sets | Stock boot0 picks LPDDR3 or LPDDR4 parameters from straps PH6/7/8/10; our u-boot builds for each, capped at 4 GiB | desk | [R3](r3-v106-boot0-dram-sets.md), Q10/Q11 |
| Panel selection | Strap **PE6**: low = original panel, high = newer panel (V1.0.6-era firmware) | desk (stock u-boot and kernel) | [panel detect](rg34xxsp-panel-detect-and-uboot-patch.md) |
| Original panel | NewVision **NV3052C**; entry in the upstream driver; 720×480, 26 MHz | desk; drives the panel in ROCKNIX | [R19](r19-display-layer.md) |
| Newer panel | GalaxyCore **GC9703 family** (from its register sequence); new driver `panel-galaxycore-gc9703`, opt-in tree | desk | [K9 desk](k9-newer-panel-gc9703.md), [R29](r29-gc9703-panel-driver.md) |
| Display path | DE33 mixer → TCON TOP → LCD TCON0 → RGB panel set up over 3-wire SPI (PI8/9/10, reset PI14, power PI15); PWM0 backlight on PD28 | desk | [R19](r19-display-layer.md) |
| CPU speed grades | Stock's fuse → grade decision reproduced (patch 0001); nine stock per-grade tables; where mainline runs faster than stock | desk + host test | [G2](ghidra-g2-cpu-grades.md), [decoder](stock-cpu-bin-decoder-and-dcdc2.md) |
| Thermal and GPU rail | Stock 115 °C CPU critical trip; GPU on the fixed 0.94 V rail, 420–600 MHz | desk | [custom patches](kernel-custom-patches.md) |
| Battery and charger | AXP717 (stock name `axp2202`): gauge and charger registers, DT properties, 128-byte gauge model; undocumented registers named from the BSP | desk | [G4](ghidra-g4-battery-gauge.md), [R30](dr-unknowns-and-rebuild-2026-11-20.md) §2 |
| "Fast Shutdown" | Writes a reserved bit of PMIC register 0x18; no documented effect; nothing to port | desk (Ghidra + datasheet) | [R30](dr-unknowns-and-rebuild-2026-11-20.md) §1 |
| Inputs | Key pins and codes, stick mux (PI0/PI1/PI2), lid switch on PE7 (`gpio-keys`, wake source), rumble PWM2/PH2 | desk; rumble motor confirmed on Dale's unit under stock (K13) | [W3.1](ghidra-w3-1-kernel-inventory.md), [G5/G6](ghidra-g5-g6-audio-rumble.md) |
| PE11 (`adc-en-gpios`) | Read by no stock code; mainline need not drive it | desk | [R30](dr-unknowns-and-rebuild-2026-11-20.md) §1 |
| Audio | Internal codec, speaker amp enable PI5 (100 ms delay in stock, patches 0002/0003), headphone detect PI3 | desk | [G5/G6](ghidra-g5-g6-audio-rumble.md) |
| Wi-Fi / Bluetooth | RTL8821CS on SDIO; in-tree `rtw88`; firmware in noble; BT config file gap | desk | [R4](r4-noble-firmware-audit.md), [W3.2](ghidra-w3-2-stock-modules.md) |
| Second card slot (TF2) | `mmc2`, 4-bit, card detect PE22 (polled), slot power PE4, ALDO1 I/O rail, 50 MHz; node in our `-redux` tree since 2026-11-20 | desk (stock DT; schema-checked) | [W3.3](ghidra-w3-3-dt-diff.md), [R30](dr-unknowns-and-rebuild-2026-11-20.md) §2 |
| HDMI (stock side) | `hdmi@06000000`, HDCP and CEC on, always-on supplies | desk (stock DT) | [R30](dr-unknowns-and-rebuild-2026-11-20.md) §2 |
| Deep suspend | Upstream TF-A has no system suspend for this SoC; only the ROCKNIX patch + SRAM stub route is known | desk | [custom patches](kernel-custom-patches.md) §7 |
| Stock userspace | Boot scripts, launcher, power daemon, 11 emulators' `deeplayer` check; udev rules are all Ubuntu's; `brightCtrl.bin` and `/dev/vsgame` are dead references | desk | [stock RE](stock-re-boot-and-userspace.md), [R30](dr-unknowns-and-rebuild-2026-11-20.md) §1 |
| Stock display interface | `/dev/disp` layers: launcher, SDL apps and the video player on channel 1; channels 2/3 free for an overlay | desk | [R26](r26-global-osk-stock-disp2.md), [DR-2](dr-osk-desk-checks-2026-11-18.md) |
| RetroArch on stock | Menu = hotkey enable; Menu + X = pause/FPS; keyboard hotkeys fire without Menu | desk (stock config + RetroArch 1.20 source) | [DR-3](dr-osk-desk-checks-2026-11-18.md) |
| Userspace base | Minimal noble arm64 rootfs; RAM-tier defaults; Mesa/Panfrost packages; update and rollback design | desk + QEMU | [R5](r5-noble-userspace-prototype.md), [R13](r13-ram-tier-defaults.md), [R6](r6-mesa-panfrost-noble.md), [R8](r8-update-rollback.md) |
| Licences | Per-component licences, source bundle, notices; image name is ReduxOS | desk | [R9](r9-licensing-redistribution.md) |
| Frontend on mainline | 22 stock interfaces mapped; 21 need changes | desk | [R21](r21-redux-on-mainline-map.md) |
| ReduxOS composition | Base, full hardware set (incl. TF2 node, rumble motor, ALDO3 kept on, video engine), security rules, app set | desk + QEMU | [manifest](reduxos-distro-build.md), [beta build](reduxos-beta-build-2026-11-20.md) |

## 3. What remains
### 3a. Only the device can answer (tasks in [`master-task-list.md`](master-task-list.md) §A)
| Unknown | Task |
|---|---|
| Does our u-boot + TF-A boot; UART pads; Dale's unit's DRAM set and panel strap | K3, K4 |
| What mainline does on this unit (ROCKNIX from a spare card) | K2 |
| Original panel and backlight on our kernel | K18, K19 |
| Newer panel: the exact part, then its driver | K9, K29 |
| CPU fuse value and chip revision of the unit; Q2 table under load | K8, K22, K21 |
| Sticks, speaker start-up, Bluetooth config, charging, deep suspend | K5/K7, K15, K16, K14, K6 |
| GPU speed against stock; memory and boot time; kernel rollback on hardware | K11, K12, K17 |
| What ALDO3 feeds (its voltage) | K1 follow-up |
| Stock OSK assumptions (layers, permissions, chord, key injection, grabs) | K24–K28 |

### 3b. Desk work not done yet
| Item | Note |
|---|---|
| HDMI on mainline | no H616 HDMI nodes in our base; upstream series watched in R11 |
| Deep suspend | port or rewrite the TF-A suspend path (licence question on the ROCKNIX patch) |
| Older third panel (2025 firmware, PE6 high) | needs a 2025 stock image to trace |
| osklib default chord | still Menu + X here; Redux uses Menu + Select, and Select is osklib's Shift key ([review](dr-review-2026-11-20.md) §2) |
| Video decode in players | Cedrus (kernel) is built; noble's FFmpeg/mpv lack v4l2-request ([manifest](reduxos-distro-build.md) §2) |
| Signed apt repository; release test matrix; recovery instructions tested | M5/M6 |
| Frontend port to mainline | R21 map, Redux's work |
| 512 MB and 1 GB tiers | deferred by the Project instructions |

### 3c. Decisions and paperwork
- All of Q1–Q11 are decided (Q7: the name is ReduxOS; Q9: ship the Unicode licence text in the notices). No Q-item is open.
- **Q8**: both panel tables are now in GPL kernel patches (the newer one in a new driver, merged with #69).
- **u-boot mapping for PE6 high**: unchanged (no display) until K9/K29; a new decision after that.
- u-boot binman SPDX patch: drafted, not sent. Hand-offs H1–H3 and H5: pending.

## 4. Outside references reviewed (nothing copied)
ROCKNIX (patch set and panel files), the fotlim LineageOS device tree for the RG34XX-SP, omega-zero / BaseOS:
see [`dr-unknowns-and-rebuild-2026-11-20.md`](dr-unknowns-and-rebuild-2026-11-20.md) §4.
