# R6: Mesa / Panfrost on Ubuntu 24.04 (noble) for the Mali-G31

Deep Research, 2026-11-14. **Desk only: package indexes, Mesa source at the shipped tag, ELF inspection. No GPU was available (QEMU has no Mali), so nothing here ran on a G31.** Master list task R6.

## Answer in one paragraph
noble-updates ships **Mesa 25.2.8**, which has everything the G31 needs for OpenGL: the `panfrost` Gallium driver and the `sun4i-drm` display-to-render glue. Expect **OpenGL ES 3.1** (and desktop GL 3.1) on the G31; that is what emulators use. **Vulkan is effectively absent:** PanVK in 25.2.8 refuses to start on Bifrost v7 unless `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` is set, warns that it is non-conformant, and then reports only Vulkan 1.0; even Mesa 26.3 still keeps v7 behind that switch. The catch is size: Ubuntu builds Mesa against LLVM, so the GL stack costs **~226 MB of disk** (LLVM alone 136 MB) and an estimated **~10 MB of private RAM per GL process**, although Panfrost itself never uses LLVM. Recommendation: **use Ubuntu's Mesa for v0.x** (supported, security-patched by Canonical), install only the GL/EGL/GBM packages (**not** `mesa-vulkan-drivers`, +110 MB for nothing usable), and keep a Panfrost-only, LLVM-free Mesa build as a measured option for the 512 MB tier later.

## 1. What noble ships (ports.ubuntu.com, arm64, read 2026-11-14)
| Package | noble (release) | noble-updates | noble-security |
|---|---|---|---|
| `libgl1-mesa-dri`, `libegl-mesa0`, `libgbm1`, `mesa-vulkan-drivers` | 24.0.5-1ubuntu1 | **25.2.8-0ubuntu0.24.04.4** | 25.2.8-0ubuntu0.24.04.2 |
| `mesa-libgallium` (holds all Gallium drivers) | — | 25.2.8-0ubuntu0.24.04.4 | 25.2.8-0ubuntu0.24.04.2 |
| `libdrm2` | 2.4.120-2build1 | 2.4.125-1ubuntu0.1~24.04.2 | same |
| `libvulkan1` (loader) | 1.3.275.0-1build1 | — | — |

noble-updates carries the newer Mesa as Ubuntu's usual LTS graphics backport (the 25.10 stack). It can move again in a later point release; that is mostly good for us (Panfrost fixes) but means the GPU stack can change under a stable image. Pin or test before each Mesa SRU lands (R8).

Driver files present in 25.2.8 (noble-updates `Contents-arm64`): `dri/panfrost_dri.so` and `dri/sun4i-drm_dri.so` (in `libgl1-mesa-dri`), the PanVK ICD `libvulkan_panfrost.so` + `panfrost_icd.json` (in `mesa-vulkan-drivers`), all backed by `libgallium-25.2.8-0ubuntu0.24.04.4.so` (in `mesa-libgallium`). `sun4i-drm_dri.so` is the "kmsro" link that renders with Panfrost and scans out through the Allwinner display driver; with an H616 DE33 display driver the DRM driver name should still be `sun4i-drm` [inferred; depends on the display series, Q6].

## 2. What the G31 gets from Mesa 25.2.8 (read in the source at tag `mesa-25.2.8`)
| API | Level on Bifrost v7 (G31) | Evidence |
|---|---|---|
| **OpenGL ES** | **3.1** | Mesa's Panfrost page lists GLES 3.1 for G31/G51/G52/G76; the driver reports ESSL 320 shader support for arch ≥ 6 (`pan_screen.c`), but ES 3.2 needs geometry/tessellation, which Panfrost doesn't expose [inferred] |
| Desktop OpenGL | 3.1 (GLSL 1.40); **3.3 with `PAN_MESA_DEBUG=gl3`** | `pan_screen.c`: `glsl_feature_level = is_gl3 ? 330 : 140` |
| OpenCL | Rusticl, needs LLVM | Mesa Panfrost page; not a target here |
| **Vulkan (PanVK)** | **Refuses to load** on v6/v7 unless `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER` is set; then `vk_warn_non_conformant_implementation`, and `apiVersion` = **1.0** (1.1/1.2 features are `PAN_ARCH >= 10`) | `panvk_physical_device.c` lines 271–280, 325–326; `panvk_vX_physical_device.c` `get_api_version()` |

Upstream status since then (same files at newer tags): **26.0.0** and **26.2.7** still gate v7 and report 1.0; **26.3.0** and `main` (`94ad3c5e`) still gate v7 but report **Vulkan 1.3** once enabled. Mesa's documentation table now lists Vulkan 1.3 for the G31 without a footnote; the code still treats v7 as "not well-tested". **So the assessment's "Vulkan 1.3 (PanVK)" for the G31 is wrong for noble and not yet true by default upstream**; corrected in `ubuntu-2404-rg34xxsp-assessment.md`.

What that means: emulator frontends and cores must use **GLES** (RetroArch `gl`/`glcore` over GLES, SDL2 GLES). Don't ship Vulkan-only software. Vulkan on the device is a curiosity for testing (K11), not a feature.

## 3. Cost on disk and in RAM
Computed with apt against the R5 iwd rootfs's package database (noble + noble-updates + noble-security, no Recommends):

| Install | New packages | Installed size | Largest pieces |
|---|---|---|---|
| **GL stack:** `libgl1-mesa-dri libegl1 libgles2 libgbm1` | 32 | **226 MB** | `libllvm20` 136 MB, `mesa-libgallium` 46 MB, `libicu74` 36 MB (via `libxml2`, via LLVM) |
| Vulkan: `mesa-vulkan-drivers libvulkan1` | 24 | 286 MB (110 MB on top of the GL stack) | every vendor's ICD: Intel 20 MB, nouveau 16 MB, radeon 15 MB, **panfrost 12.6 MB**, … |
| `apt` itself (see §5) | 14 | 17 MB | `apt`, `libapt-pkg`, GnuTLS |

- **LLVM is a hard dependency:** `libgallium-25.2.8….so` has `NEEDED libLLVM.so.20.1` (and `libdrm_amdgpu.so.1`), so every program that opens GL/EGL maps it, Panfrost or not. `libvulkan_panfrost.so` does **not** link LLVM.
- **RAM estimate (not measured):** loading libLLVM writes its relocations into private pages: `.data.rel.ro` 6.5 MB + `.got`/`.data` 0.3 MB, plus 0.7 MB `.bss`. libgallium adds `.data.rel.ro` 1.6 MB + `.data` 0.2 MB (+1.8 MB `.bss`, touched as used). **≈ 8–10 MB of private memory per GL process**, of which ~7 MB is LLVM that Panfrost never calls. On the 512 MB tier, a frontend plus an emulator (two GL processes) would spend ~15–20 MB on this. Measure on the device (K11/K12: `smaps_rollup` of a running emulator).

## 4. Options
| | A. Ubuntu Mesa 25.2.8 (noble-updates) | B. Our own Mesa: Panfrost + kmsro only, `-Dllvm=disabled` | C. Third-party PPAs (kisak, oibaf) |
|---|---|---|---|
| G31 features | GLES 3.1, GL 3.1/3.3 | same | newer Mesa, same v7 Vulkan gate |
| Disk | ~226 MB | ~25–35 MB [estimate: libgallium without LLVM/other drivers, plus EGL/GBM] | ~as A |
| RAM per GL process | ~8–10 MB private (est.) | ~2–3 MB (est.) | as A |
| Security updates | Canonical (main) | **ours**: rebuild on every Mesa security fix | third party; not for a product |
| Work | none | a Debian source package + CI, tracking Ubuntu's patches | none |

**Recommendation: A for v0.x.** The SD card has room, and owning Mesa's security updates is real work. Revisit **B** only if K12 shows the 512 MB tier is short of memory with a running emulator; the saving there is ~7 MB per GL process and ~190 MB of disk. Never C.

Package list for R7 (GL only): `libegl1 libgles2 libgbm1 libgl1-mesa-dri` (pulls `libegl-mesa0`, `mesa-libgallium`, `libllvm20`). **Not** `mesa-vulkan-drivers`. Test tools (`mesa-utils`, `kmscube`, `glmark2-es2-drm`, `vulkan-tools`, all in noble `universe`) go in a separate "debug" package set, not in the default image.

## 5. Side finding: the R5 rootfs has no `apt`
`mmdebstrap --variant=minbase` on noble installs only Priority `required` packages; Ubuntu's `apt` is `important`, so the R5 rootfs (both variants) has **no apt** (`root/r5-packages.txt` has `dpkg` but not `apt`). R7 must add `apt` explicitly (+17 MB, 14 packages, mostly shared with what the GL stack pulls in). R5's doc is corrected.

## 6. Device checks (adds to K11; all read-only, run on our image)
```sh
dmesg | grep -i panfrost                       # probe, GPU model/revision, no MMU faults
ls -l /dev/dri/                                # card0 (display) + renderD128 (Panfrost)
eglinfo -B                                     # mesa-utils: vendor "Mesa", renderer "Mali-G31 (Panfrost)", GLES 3.1
kmscube                                        # needs the display (Q6); spinning cube on the panel
glmark2-es2-drm                                # score; compare with stock Mali in K11
PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 vulkaninfo --summary   # expect apiVersion 1.0, non-conformant warning
grep -E '^(Rss|Pss|Private_Dirty)' /proc/$(pidof retroarch)/smaps_rollup   # per-process GL cost (§3)
```
Without a display driver (Q6, mainline base), Panfrost can still be tested headless through `renderD128` (`eglinfo`, an EGL surfaceless/GBM test), so K11's GPU half doesn't have to wait for the panel.

## 7. Sources
- Ubuntu ports indexes, 2026-11-14: `dists/{noble,noble-updates,noble-security}/main/binary-arm64/Packages.gz`, `dists/noble-updates/Contents-arm64.gz`, `dists/noble/Contents-arm64.gz`; debs `mesa-libgallium`, `mesa-vulkan-drivers`, `libgl1-mesa-dri`, `libegl-mesa0`, `libllvm20` 25.2.8-0ubuntu0.24.04.4 / 20.x, inspected with `aarch64-linux-gnu-readelf`.
- Mesa source, gitlab.freedesktop.org/mesa/mesa: tags `mesa-25.2.8`, `mesa-26.0.0`, `mesa-26.2.7`, `mesa-26.3.0`, `main` `94ad3c5e`: `src/panfrost/vulkan/panvk_physical_device.c`, `src/panfrost/vulkan/panvk_vX_physical_device.c`, `src/gallium/drivers/panfrost/pan_screen.c`, `src/panfrost/lib/pan_props.c`.
- Mesa Panfrost documentation: https://docs.mesa3d.org/drivers/panfrost.html
- Kernel side (already in the R10/R17 config): `DRM_PANFROST` kept; `sun50i-h616.dtsi` GPU node `allwinner,sun50i-h616-mali` with the PRCM PPU power domain, enabled with `mali-supply = <&reg_dcdc2>` in the RG35XX 2024 base (torvalds/linux `97d73c8`).
