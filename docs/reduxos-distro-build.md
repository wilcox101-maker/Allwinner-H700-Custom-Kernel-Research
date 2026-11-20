# ReduxOS: distro build composition (RG34XX-SP)

The build manifest for **ReduxOS**, the mainline-Linux distribution for the Anbernic RG34XX-SP: base, kernel, boot, RAM
tier, hardware set, app set, security rules and update mechanics. Started by Claudius Maximus on 2026-11-20
(`REDUXOS-DISTRO-BUILD.md`, Claude Files) and moved here by Deep Research the same day, at Dale's request to begin the
official distro. **Nothing here has run on an RG34XX-SP**; the gate is K3/K4 on Dale's 2 GB LPDDR4 unit (Q11).
Current build results: [`reduxos-beta-build-2026-11-20.md`](reduxos-beta-build-2026-11-20.md). Project state: [`STATUS.md`](STATUS.md).

Rule for this file (Dale, 2026-11-20): it states **what ReduxOS does**. Weaknesses found in Anbernic's stock firmware stay
in the private report in Claude Files and are never described here.

## 1. Base
| Layer | Choice | Where |
|---|---|---|
| Userland | Ubuntu 24.04 (noble) arm64 packages, branded **ReduxOS** (`/etc/reduxos-release`; Q7) | [`image/packages.txt`](../image/packages.txt), [R7](r7-image-tooling.md) |
| Kernel | Mainline `97d73c8` (7.4-rc2) + our patches + the display layer, as noble `.deb` packages | [R10](kernel-build-r10.md), [R19](r19-display-layer.md) |
| Boot | u-boot v2026.10 + TF-A v2.14.0, one SPL per DRAM type, reproducible | [R1](r1-boot-chain.md), [R24](r24-image-with-uboot.md) |
| Panels | `panel-newvision-nv3052c` (PE6 low, selected by u-boot) and `panel-galaxycore-gc9703` (PE6 high, opt-in tree only) | Q8, [R29](r29-gc9703-panel-driver.md) |
| RAM tier | 2 GB LPDDR4 first (Dale's unit, Q10/Q11); zram + tier defaults | [R13](r13-ram-tier-defaults.md) |

## 2. Hardware set: everything on the board that mainline can drive
Dale (2026-11-20): leave out nothing that benefits this device's hardware. Status per block, all **desk only**:

| Block | Kernel (driver, DT) | Userspace in the image | State |
|---|---|---|---|
| CPU, DVFS, thermal | `sun50i-cpufreq-nvmem`, Q2 OPPs, stock 115 °C trip (Q1), H616 cooling map | — | built |
| GPU (Mali-G31) | Panfrost | Mesa GL/GLES (no Vulkan, R6) | built |
| Display, backlight | DE33 → TCON → RGB panel, PWM0 backlight (display layer) | — | built (both panels) |
| **Video engine** | **Cedrus** (`sunxi-cedrus`, H616 node enabled upstream): hardware decode of MPEG-2, H.264, H.265 (8/10-bit) and VP8 through V4L2 stateless | `v4l-utils` (inspect `/dev/video*`) | kernel built; noble's FFmpeg/mpv have no v4l2-request path, so players decode in software until a v4l2-request build is added |
| Audio | `sun4i-codec`, 100 ms speaker-amp delay (patches 0002/0003), headphone detect | `alsa-utils` (mixer, `speaker-test`, state restore) | built; mixer defaults wait for K15 |
| Wi-Fi | `rtw88` 8821CS on SDIO | `iwd`, `iw`, `wireless-regdb`, `linux-firmware-realtek` | built |
| Bluetooth | `hci_uart` + `btrtl` on UART1 | `bluez`, `rfkill` | built; config-file gap tracked as K16 |
| Buttons, lid | `gpio-keys` (buttons; lid on PE7, a wake source) | `evtest` | built |
| Sticks | `adc-joystick` behind the GPADC mux | `evtest` | built; axes to confirm (K5) |
| **Rumble motor** | **`pwm-vibrator` on PWM2/PH2, 2 kHz** (new 2026-11-20; motor confirmed on Dale's unit, K13) | force feedback through the input device | built (display layer) |
| Battery, charger | `axp20x_battery`, `axp20x_usb_power`, 1024 mA (Q5) | sysfs | built |
| RTC | PCF8563 on R_I2C | `systemd-timesyncd` | built |
| SD slot 1 | `mmc0` | first-boot growth, exFAT tools | built |
| **SD slot 2 (TF2)** | **`mmc2`, 4-bit, polled card detect, power PE4, I/O ALDO1** (new 2026-11-20, from the stock wiring) | exFAT tools | built |
| **ALDO3** | **kept on** (no known consumer; stock keeps it on) (new 2026-11-20) | — | built |
| LEDs | `gpio-leds` PI11/PI12 | sysfs | built |
| HDMI | not in our base (no H616 HDMI nodes upstream yet) | — | missing |
| Deep suspend | TF-A v2.14.0 has no H616 system suspend | — | missing (suspend-to-idle only) |
| USB-C host mode | peripheral only | — | later (Type-C handling) |

## 3. App set
### 3.1 Left out
| Item | Why |
|---|---|
| `wiliwili` (Bilibili client from stock) | Dale, 2026-11-20: replaced by the planned YouTube app. ReduxOS is built from Ubuntu packages, so no stock app is ever in it; `image/check-hardening.sh` fails the build if one appears |
| Developer tools not needed on a handheld (snapd, qemu-user, OpenMPI, game-streaming clients) | Not in `packages.txt`; the check refuses them |

### 3.2 Planned: YouTube app (Kernel Research; not in the image yet)
Design brief in Claude Files (`REDUXOS-YOUTUBE-APP-BRIEF-2026-11-20.md`). Summary: native `mpv` + `yt-dlp` (no served ads);
SponsorBlock as an mpv script; an optional device-wide DNS blocklist; logged out by default; an opt-in, checksum-verified
`yt-dlp` updater; shipped as its own updatable component. Correction to the brief: Panfrost does not decode video; hardware
decode would come from Cedrus (§2) through a v4l2-request FFmpeg build. Front-end choice after an on-device mpv benchmark.

### 3.3 Core tools (from the Redux CFW decisions)
Mixer (`alsamixer`), Bluetooth (`bluetoothctl`), input test (`evtest`), speaker test (`speaker-test`) are in the image now.
Network setup is `iwctl` (iwd), not `nmtui`: the image uses iwd + systemd-networkd (R5).

## 4. Security rules (enforced by `image/check-hardening.sh` and the QEMU smoke test)
| Rule | How |
|---|---|
| No shared secrets in the image | SSH host keys and machine-id are made on first boot (`h700-firstboot`); none ship |
| No root credential shipped | `PermitRootLogin yes` (Dale, 2026-11-20: root SSH is not blocked), but the image sets **no root password** (locked, `!` in `/etc/shadow`, Ubuntu default) and ships **no root `authorized_keys`**, so remote root is unusable until the owner sets their own password or key. No backdoor, no default login. Checked by `check-hardening.sh` and the QEMU smoke test |
| User password must be changed | the default user's password is expired in the image |
| SSH | on for the beta (only remote access before the frontend exists); password login for the user account until a key is added; `X11Forwarding no`, `MaxAuthTries 3`. Opt-in SSH is a later choice for Dale |
| Firewall on | nftables, `policy drop` on input: loopback, replies, ICMP, DHCP client, SSH only; forward dropped |
| No phone-home | `motd-news.timer` off; no telemetry added; outbound traffic only when the user starts it |
| No DHCP/DNS server or hotspot at boot | not installed; a hotspot, if added, starts them only while it runs, with a per-unit key |
| Logs kept | journald `Storage=persistent`, bounded (R13) |

## 5. Build and update
- Build: `scripts/build-uboot.sh --dram all`, `scripts/workbench.sh --display`, `scripts/build-kernel.sh --display --build`,
  then `image/build-image.sh` with the kernel `.deb` and the u-boot for the unit's DRAM type. Output:
  `reduxos-rg34xxsp-noble-<date>-deb-uboot-<dram>.img`, checked for licences, display, hardening and boot layout.
- Test: `image/qemu/smoke-test.sh <img> 512` (also in CI, R23).
- Distribution: **private beta** (Dale, 2026-11-20): images go to Dale and chosen testers by private link, never as a
  GitHub release. No image or binary is committed.
- First use of our u-boot is by FEL (RAM only, R2/K4), never by writing a card that holds stock.
- Updates: reflash for the beta; apt channels and kernel rollback are designed (R8) but not yet served.

## 6. Open decisions (beta checklist in Claude Files, `REDUXOS-V1-BETA-QUESTIONS.md`)
Scope (LPDDR4 unit only first), beta blockers vs known gaps, delivery (FEL + card), SSH default, ad-block scope, update
model, "beta done" bar. The biggest unblocker is K3/K4.
