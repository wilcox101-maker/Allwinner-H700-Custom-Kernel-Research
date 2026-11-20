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
