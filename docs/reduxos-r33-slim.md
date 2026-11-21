# ReduxOS R33: slimming the image (desk/QEMU only)

Goal (master list R33): a leaner image without losing anything ReduxOS uses. **Nothing here has run on
an RG34XX-SP.** Measured on the R36 LPDDR4 rootfs (2026-11-20): 485 packages, 789 MB installed.

## 1. Where the space goes (largest packages)
| Package | MB | Pulled in by | Needed? |
|---|---|---|---|
| libllvm20 | 133 | mesa-libgallium (`NEEDED libLLVM.so.20.1`) | Panfrost: no. See §2 |
| mesa-libgallium | 45 | libgl/egl/gbm | yes (Panfrost) |
| libicu74 | 35 | libqt5core, libxml2 | partly (libxml2 stays) |
| libflite1 | 27 | libavfilter9 ← **mpv** | only for mpv |
| retroarch | 25 | — | yes |
| Qt5 (core/gui/widgets/network/dbus) | ~32 | **retroarch** (noble build) | no: ReduxOS uses rgui on KMS |
| libcodec2, libavcodec | 16, 14 | ffmpeg ← retroarch, mpv | yes |

Modelled from the dpkg dependency graph (`tools/model-pkg-closure.py`):
- **noble retroarch → upstream build for KMS/GLES only: −32 MB** (15 packages: Qt5 and its X11/xcb helpers).
- dropping mpv: −70 MB (46 packages: avfilter, flite, placebo, lapack/fftw, openal…). **Not done:** mpv is
  the planned engine of the YouTube app (`reduxos-distro-build.md` §3 and the design brief in Claude Files).

## 2. LLVM: Panfrost doesn't need it, but forking mesa isn't worth it now
- Panfrost (Mali-G31, Bifrost) compiles shaders with Mesa's own Bifrost compiler. LLVM is only used by
  llvmpipe/lavapipe and other drivers. Ubuntu builds every gallium driver into one `libgallium-25.2.8.so`,
  which hard-links `libLLVM.so.20.1`. It can't be dropped without rebuilding mesa.
- Cost measured on the binary: `libLLVM.so.20.1` has **377,863 dynamic relocations** and a **7.5 MB RW
  segment** (6.6 MB RELRO). Every GL process (RetroArch; cage/wvkbd/foot for the OSK) dirties about 7.5 MB
  of private RAM and does those relocations at start-up. On disk it's 133 MB, roughly 40 MB of the
  compressed image.
- **Recommendation: keep Ubuntu's mesa.** A ReduxOS mesa (`-Dllvm=disabled`, panfrost+kmsro+softpipe) would
  save 133 MB of disk and ~7.5 MB per GL process. In exchange we'd have to track every noble mesa security
  update ourselves for the most security-exposed userspace library on the device. With 2 GB of RAM and a
  282 MiB image, that doesn't pay yet.
- **Revisit when:** a 512 MB/1 GB variant is supported, or device measurements show the start-up cost
  matters. Device test (needs hardware): RetroArch RSS and time-to-menu, then the same with an
  LLVM-less mesa built as a test package.

## 3. Done in this PR: RetroArch built from upstream (`tools/build-retroarch.sh`)
- Pinned to upstream **v1.22.2** (`69a4f0e`), cross-built with KMS/EGL/GLES 3.1, udev, ALSA, FFmpeg (built-in
  media player), FreeType, zlib and networking. Configured without Qt, X11, Wayland, PulseAudio, JACK, SDL,
  Vulkan (Panfrost on Bifrost v7 isn't conformant yet) or buildbot core downloads (ReduxOS ships its own
  pinned cores). The script refuses a binary that links any desktop stack.
- Packaged as `reduxos-retroarch_1.22.2-1reduxos1_arm64.deb`. Its `Depends` come from the binary's `NEEDED`,
  and it `Provides: retroarch, libretro-frontend`, so noble's `libretro-*` core packages still install.
  Not committed; injected with `RETROARCH_DEB=`. Without it (CI), the build falls back to noble's retroarch
  plus the R36 asset shim.
- Also newer: noble ships 1.18.0, from universe, which gets no security fixes.
- Checks: `check-hardening.sh` rejects desktop libraries in a `reduxos-retroarch` image. The QEMU check runs
  `retroarch --features` on the emulated A53 and reports KMS/EGL/GLES/udev/ALSA/FFmpeg.

## 4. Results
See §R33 in [`reduxos-beta-build-2026-11-20.md`](reduxos-beta-build-2026-11-20.md).
