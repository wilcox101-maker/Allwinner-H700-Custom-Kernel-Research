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
