# ReduxOS beta-candidate build, 2026-11-20

Deep Research, at Dale's request ("begin the official ReduxOS distro; start compiling and building", and "leave out nothing
that benefits this device's hardware"). Composition: [`reduxos-distro-build.md`](reduxos-distro-build.md).
**Not booted on an RG34XX-SP.** QEMU is not the handheld; the first hardware step is K4 (FEL, RAM only).

## Result
- Image `reduxos-rg34xxsp-noble-20261120-deb-uboot-lpddr4.img`, 898 MB (zstd 133 MB), 217 packages, for **LPDDR4** units.
- All build checks pass (licences, display, **hardening (new)**, boot layout); **QEMU smoke test 14/14** at 512 MB,
  including the two new checks (firewall active with inbound `policy drop`; sshd refuses root login).
- Delivered privately to Dale's PC: `Downloads\Anbernic RG34xxSP\ReduxOS-builds\2026-11-20\` (image, checksums,
  package and source lists, smoke report, README). Not committed, not published (private beta).

## What changed in this build (vs the R30 rebuild)
| Area | Change | Why |
|---|---|---|
| Second card slot | `&mmc2` node, PE4 slot power, ALDO1 I/O, polled card detect, 50 MHz, no 1.8 V | stock wiring (W3.3, R30); TF2 was missing |
| ALDO3 | `regulator-always-on` | no known consumer; mainline would switch it off |
| Rumble motor | `pwm-vibrator` on PWM2/PH2, 2 kHz; `CONFIG_INPUT_PWM_VIBRA=m`; PWM2 pin added | motor confirmed on Dale's unit (K13); stock drives it this way (G6) |
| Firewall | `CONFIG_NF_TABLES` + `NFT_*` (the kernel had no working packet filter); `nftables` package, `/etc/nftables.conf`, service enabled | manifest §4 |
| SSH | `sshd_config.d/60-reduxos.conf`: no root login, no X11, 3 tries | manifest §4 |
| Hardware userspace | `alsa-utils`, `bluez`, `rfkill`, `iw`, `evtest`, `v4l-utils` | audio mixer, Bluetooth, Wi-Fi and input tools; inspect the video engine |
| Build check | `image/check-hardening.sh` (12 rules) run by `build-image.sh`; two checks added to the smoke test | the manifest is enforced, not just written |

Already present and confirmed in the image: panel drivers for both panels, Cedrus video engine (`sunxi-cedrus`), Wi-Fi and
Bluetooth firmware for the 8821CS, sticks, codec, PWM backlight. Module count 182 (was 167).

## Checks run (cloud workspace, gcc 13.3.0 aarch64)
| Check | Result |
|---|---|
| `scripts/workbench.sh --display --bindings` | pass; all DTBs 0 `dtbs_check` warnings, including the new TF2, ALDO3 and vibrator nodes |
| `scripts/build-kernel.sh --display --build` | pass; every enabled DT node has its driver (`-redux-v2-panel`: 77 nodes); `.deb` 12.9 MB, SHA-256 `309113cf57cec34b…` |
| `image/build-image.sh` (lpddr4 u-boot, SHA-256 `1d0381e1cb846ab2…`) | pass; image SHA-256 `3a5b18ea053abd0e…`; `.zst` SHA-256 `aee4de1a15c4f713…` |
| `image/qemu/smoke-test.sh … 512` | 14 passed, 0 failed |

## Not in this build
HDMI, deep suspend, hardware video decode in players (needs a v4l2-request FFmpeg), the YouTube app (KR), the frontend
(Redux, R21), the LPDDR3 image (built on request). Stock-firmware analysis is Kernel Research's full sweep (2026-11-20).

---

## R32 — full-featured beta (frontend), 2026-11-20

Dale: *"Continue to compile to full featured beta private release."* Added the game frontend on top
of the R31 hardware image and built both DRAM variants. **Still desk/QEMU only — not run on an
RG34XX-SP.** Design and button derivation: [`reduxos-frontend.md`](reduxos-frontend.md).

### Result
- Two images, **LPDDR4** and **LPDDR3**, dated `20261120`, 1.8 GiB raw / **381 MiB** zstd each, 429
  packages, our kernel `7.4.0-rc2-rg34xxsp`.
- Boots to RetroArch (KMS/GLES) as an unprivileged **`player`** user on tty1; 9 libretro cores.
- **QEMU smoke 16/16** on each variant, including two new frontend checks (player+retroarch+cores
  present; tty1 autologins player) and the R31 firewall/sshd checks.
- Build-time `check-hardening.sh` extended with 9 frontend/least-privilege rules — all pass.
- Delivered privately to `...\ReduxOS-builds\2026-11-20\frontend-beta\` (both images, per-file
  sha256, manifests, smoke reports, source lists, README). On-device checksums verified. Not
  committed, not published.

### SHA-256
| Artifact | SHA-256 |
|---|---|
| lpddr4 `.img.zst` | `c8c2bdcf61bbba44...980082eb` |
| lpddr3 `.img.zst` | `de591647a2d54bed...e22be8cb` |
| lpddr4 `.img` (raw) | `e017743ab1a7a345...87cae89aa` |
| lpddr3 `.img` (raw) | `ccc69e8282d80669...09fb540342` |
| kernel `.deb` | `309113cf57cec34b...608b4b93` (identical to R31 - same kernel) |
| u-boot lpddr4 | `1d0381e1cb846ab2...173bb8d75` (identical to R1/R24/R31) |
| u-boot lpddr3 | `c0c3de979a2bc127...31d81d249` |

### What the frontend adds (over R31)
| Area | Change |
|---|---|
| Autologin | `getty@tty1` drop-in to `agetty --autologin player`; tty2-6 keep the `dale` login |
| Session | `/home/player/.bash_profile` launches RetroArch on tty1 only, drops to a shell on exit |
| Frontend | `retroarch` + 9 cores, `/etc/retroarch.cfg` (gl/kms, udev, alsa, rgui), gamepad autoconfig |
| Audio | `/etc/asound.conf` (dmix + softvol master) + `reduxos-audio-init.service` (desk-only levels) |
| Volume keys | `triggerhappy` to `reduxos-vol.sh` nudging the softvol master |
| Media | `mpv` (KMS out); `alsa-ucm-conf`, `libasound2-plugins`, `brightnessctl` |
| Least privilege | `player`: locked password, no sudo, groups `video render input audio` only |

### Known gaps (carried, need hardware or a later build)
1. Analog sticks are a separate `adc-joystick` device, not merged into player 1 (buttons + D-pad
   work). A uinput combiner is the fix - deferred.
2. No Genesis or dedicated SNES core (non-free, not in Ubuntu); SNES via bsnes-mercury-performance.
3. PS1 only via `beetle-psx` (heavy on A53). `pcsx_rearmed` (the fast core) isn't packaged, and
   building it from source this session was blocked by a tool-permission check - Dale to decide.
4. Codec mixer levels/routing are desk-only values.
5. Size: `retroarch` pulls `retroarch-assets` then a large font pack, and mesa pulls `libllvm20`.
   Slimming (a stripped retroarch via equivs) is the top follow-up (R33).

### Stock-firmware security (cross-reference)
Kernel Research finished its full Ghidra sweep of the stock firmware on 2026-11-20. Its findings are
**private (Claude Files, not this repo)** per the standing rule. In short, they reinforce the
ReduxOS security defaults already built in R31/R32 (no root login, no default AP, inbound-drop
firewall, no shell-building launcher). Specifics are for Dale and the Manager, not the public repo.

### R32 addendum — PS1 fast core, console shell, fly-out OSK (same day)
After the first R32 images, Dale asked for the PS1 fast core, a usable console shell, and a fly-out
OSK for keyboard apps (terminal, file manager). Added and rebuilt (both variants, QEMU **16/16**):
- **pcsx_rearmed** (GPL-2.0, pinned `7b0e8f8`, arm64 dynarec + NEON) cross-built by
  `tools/build-pcsx-core.sh` and injected at image build (`PCSX_CORE=`); the `.so` is not committed.
  Core count is now 10 (beetle-psx kept for accuracy).
- **Console/shell:** `kbd` + `console-setup` with a legible Terminus 20x10 console font
  (`/etc/vconsole.conf`), a friendly `/etc/profile.d/10-reduxos.sh` (prompt, `redux-help`), `tmux`.
- **Fly-out OSK** ([`reduxos-osk.md`](reduxos-osk.md)): `cage` + `wvkbd` + `foot` + `mc`, launchers
  `redux-kbapp` / `redux-shell` / `redux-files`, and a cross-built gamepad→pointer bridge
  `redux-osk-pointer` (`tools/redux-osk-pointer.c`, injected via `OSK_POINTER=`, not committed).
  RetroArch's own OSK is untouched. The player console opens `redux-shell` on RetroArch exit.
- `check-hardening.sh` gained console + OSK checks. New follow-ups: R33 (slim image), R34 (sticks to
  P1), **R35 (validate/tune the OSK on hardware)**. Final `.zst` ~396 MiB each (zstd -22).

Final SHA-256 (`.img.zst`): lpddr4 `0a597654568c7cef…`, lpddr3 `e878fadc2774988f4…`.

## R36: cores, launcher, PortMaster (DR, 2026-11-20 afternoon; desk/QEMU only)
Details: [`reduxos-cores-portmaster.md`](reduxos-cores-portmaster.md).
- Images `reduxos-rg34xxsp-noble-20261120-deb-uboot-{lpddr4,lpddr3}.img`, 1.6 GiB raw, **282 MiB** zstd -19 each
  (was 1.8 GiB / ~396 MiB before R36, despite adding 23 cores, PortMaster and python3/SDL2: the asset shim removes ~440 MB).
- Build checks: licence, display, hardening (incl. R36 + deeplayer guard), boot layout: **PASS** for both.
- **QEMU smoke 19/19** (LPDDR4, 512 MB, `-cpu cortex-a53`): **all 33 libretro cores load** (`dlopen` + libretro API),
  launcher core end-to-end, playlist scanner, R36 services, `/roms` owned by `player`, `/roms/ports` link, PortMaster
  owned by `player` with hooks, `/dev/uinput` `root:input`. The first run failed on ppsspp (missing `libGLESv2`
  link): fixed, builder check added. LPDDR3 not smoke-booted (same rootfs; QEMU doesn't run the SPL).
- SHA-256 (`.img`): LPDDR4 `84287fed89487d91…`, LPDDR3 `b0131cc6cd11bdd8…` (full sums delivered with the images).
- Delivered privately to Dale's PC (`ReduxOS-builds\2026-11-20\r36-cores\`); on-device checksums verified.
- **Not run on a device**: speed (N64, Dreamcast, PSP, arcade), GLES rendering on the Mali-G31, PortMaster GUI on KMS
  and port controls are all untested.

## R33: lean RetroArch (DR, 2026-11-20 evening; desk/QEMU only)
Details: [`reduxos-r33-slim.md`](reduxos-r33-slim.md).
- `reduxos-retroarch` 1.22.2 (KMS/GLES only) replaces noble's 1.18: rootfs packages 789 → **733 MB** (485 → 469 pkgs,
  Qt5 gone); image zstd 282 → **273 MiB** (1.6 GiB raw).
- Build checks (licence, display, hardening incl. no desktop stacks, boot layout): **PASS** for LPDDR4 and LPDDR3.
- **QEMU smoke 20/20** (LPDDR4, 512 MB, `-cpu cortex-a53`), including `retroarch --features`
  (KMS/EGL/GLES/udev/ALSA) and all 33 cores loading. LPDDR4 `.img` SHA-256 begins `73d6ca00c09733db`.
- Delivered privately to `ReduxOS-builds\2026-11-20\r33-slim\`; checksums verified on the PC.
- **Not run on a device**: RetroArch 1.22 rendering on the Mali-G31 (GLES 3.1 context) is untested.

