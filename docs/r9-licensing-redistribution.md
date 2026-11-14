# R9: Licensing and redistribution audit

Deep Research, 2026-11-14. Master list task R9. **Not legal advice**: this records what each component's own licence or policy says and what the project should do to stay on the safe side; anything marked *ask* needs a person (Dale, or a lawyer if the image is ever sold or shipped on hardware).

## Answer in one paragraph
Nearly everything we ship is either Ubuntu's own unmodified packages or our own GPL work, so the obligations are routine: **publish the corresponding source for every GPL binary we distribute** (kernel, u-boot, TF-A + stub, and the Ubuntu packages in the image) and keep the firmware licence files. Three things need decisions before a public image: (1) **the "Ubuntu" name**: Canonical's IP policy says modified Ubuntu may only carry its trademarks if Canonical approves it, so the image should not be branded "Ubuntu" (new decision **Q7**); (2) **panel init sequences**: ROCKNIX's panel blobs have no stated licence, so we should not ship them; put the two RG34XX-SP sequences into GPL kernel code the way upstream panel drivers do; (3) **the ROCKNIX TF-A suspend patch** carries no licence statement, so ask its author before carrying it (the stub it loads is GPL-2.0-or-later).

## 1. Component by component
| Component | Licence / terms (evidence) | What we ship | Obligation / action | Status |
|---|---|---|---|---|
| Ubuntu packages in the image (~189, R7 manifest) | Each package's own licence (`/usr/share/doc/*/copyright`, kept in the image by the R7 `path-include`), plus **Canonical's IP Rights Policy** for the aggregate | Unmodified binaries from noble/-updates/-security | GPL'd packages: offer their source. Keep `copyright` files (done). Trademarks: see §2 | **Done (2026-11-14):** `image/release-sources.sh` collects every source package for the image (§3) |
| `linux-firmware-realtek` (rtw88, rtl_bt) | "Redistributable. See LICENCE.rtlwifi_firmware.txt" (upstream WHENCE, R4) | Unmodified Ubuntu package (files under `/lib/firmware`) | Keep the licence file; no source exists | OK. **Never** embed these into the kernel (`EXTRA_FIRMWARE`, which ROCKNIX does); KR's config doesn't |
| Our kernel package | GPL-2.0 (Linux) + our patches (GPL-2.0) | `linux-image-<ver>-rg34xxsp` | Publish complete corresponding source: pinned upstream commit + `patches/linux/` + `config/` + `scripts/build-kernel.sh` (all in this repo); add a source tarball or `deb-src` to the release/repo | Partly: repo has it all; release step to add |
| u-boot (+ our PE6 and R8 bits) | GPL-2.0+ | SPL+u-boot at 8 KiB (future images) | Source: u-boot tag + patches + defconfig/fragment, published with each image | Future (R1) |
| TF-A BL31 | BSD-3-Clause | inside the u-boot binary | Keep BSD notice in the release notes/source bundle | Future |
| ROCKNIX TF-A suspend patch (`001-allwinner-h616-psci-system-suspend.patch`, Kailash R S) | **No licence or SPDX statement in the patch** (header: `From:`/`Subject:` only); ROCKNIX repo has no top-level `LICENSE`/`COPYING` at `4fc79d7` | Not yet (suspend work, KR §7) | **Ask** the author for a licence (BSD-3-Clause to match TF-A is the natural choice) before carrying it; until then reference only | Blocked: ask |
| `h700-suspend-stub` (MagnominusGit) | **GPL-2.0-or-later** (its README; `COPYING` = GPL-2) | Would be embedded in BL31 | GPL source for the stub and its build; the combined `bl31.bin` must come with source (KR's note) | OK if source published |
| Panel init sequences | ROCKNIX `extra-firmware/panels/*.panel`: **no licence found**; content is Anbernic's sequences (our PE6 work proved they are stock-derived) | Not shipped (repo policy since R5) | Don't redistribute ROCKNIX's blobs. Express the two sequences in GPL-2.0 kernel code or DT (as upstream `panel-newvision-nv3052c.c` does for other vendors' NV3052C panels) as part of R19, or extract them on the user's device from the user's own stock image with `tools/extract_rg34xxsp_panels.py` | **Decided (Q8 a, 2026-11-14):** GPL-2.0 tables in the NV3052C driver (R19, KR) |
| Stock hardware facts in docs/DTs (DRAM values, OPP tables, pins) | Facts recorded from stock binaries; no code copied (methodology doc §5) | Yes (docs, DT drafts) | None beyond attribution | OK |
| Stock binaries (boot0 copies, kernels) | Anbernic; GPL kernel source not published by Anbernic | **Not** in the repo (local only) | Keep it that way | OK |
| Mesa / LLVM | MIT / Apache-2.0 with LLVM exception, via Ubuntu | Unmodified Ubuntu packages | As for Ubuntu packages | OK |
| This repository | GPL-2.0-only (LICENSE, SPDX tags); DTs dual GPL-2.0/BSD-2-Clause | — | — | OK |

## 2. The "Ubuntu" name (new decision Q7)
**Decided 2026-11-14 (Dale): option (a), the name is ReduxOS.** Applied: u-boot menu label `ReduxOS RG34XX-SP`, image files `reduxos-rg34xxsp-noble-<date>-…`, an `/etc/reduxos-release` identity file, and the source bundle's README ("built from Ubuntu 24.04 LTS packages; not Ubuntu, not provided by Canonical"). `/etc/os-release`, `/etc/issue` and the login banner stay as Ubuntu's unmodified `base-files` ships them for v0.x (changing them means diverting conffiles of an Ubuntu package); revisit before any wide release. Docs may say *built from Ubuntu 24.04 LTS packages* (factual use).

Canonical's IP Rights Policy (15 July 2015) allows redistributing Ubuntu **unmodified**; modified versions may be associated with the Ubuntu trademarks only if Canonical approves, certifies or provides them, otherwise the trademarks must be removed and replaced (the policy also says "recompile", which the community disputes; it adds that it does not reduce rights under the components' own open-source licences). Our image is a modified Ubuntu (own kernel, boot setup, configuration). Today the image uses "Ubuntu" in the u-boot menu label (`U_BOOT_MENU_LABEL="Ubuntu 24.04 RG34XX-SP"`); the file name uses only the codename "noble".

Options for Dale (**Q7**):
- **(a) Own name (recommended):** call the image something else ("Redux OS", "H700 Linux", …), describe it factually as *built from Ubuntu 24.04 LTS packages* in the docs, and change the menu label. Leave `base-files`/`/etc/os-release` as Ubuntu ships them for v0.x (they're unmodified Ubuntu packages); revisit if the image is ever distributed widely.
- (b) Ask Canonical for approval to use the name (their "remix" path); slow and uncertain.
- (c) Personal/private use only: no public images. Then most of this section is moot.

Until Q7 is decided, keep images private (no public downloads).

## 3. Release checklist (in the image build since 2026-11-14)
Items 1 and 3 and the blob/stock-file part of 4 are now automated; 2 is automated for the kernel and takes a u-boot tarball once R1 builds one; 5 is written by hand per release.

- `image/build-image.sh` writes `<image>.sources.tsv` (source package + version, from the image's dpkg database) and runs `image/check-licences.sh` on the rootfs; a failure stops the build. The check: every installed package keeps its `copyright` file; every file under `/usr/lib/firmware` belongs to a package (no hand-dropped blobs); no `*.panel` files; no stock boot0/`boot_package`/`.fex` files in `/boot` or the firmware tree. Tested both ways on the R8 image: passes (192 packages, 156 firmware files); a copy with a missing copyright file, a stray blob, a `.panel` file and a `boot0_sdcard.bin` fails on all four.
- `image/release-sources.sh <image>.sources.tsv` writes `<image>.sources/`: `ubuntu/` (`.dsc` + tarballs for every source package, exact versions; from the archive, or from Launchpad's librarian when the archive has superseded the version, checked against the `.dsc` SHA-256 sums), `ours/` (this repo at HEAD as a tarball, pristine Linux at `LINUX_SHA`, the u-boot tarball when the image carries u-boot; it refuses a dirty repo), `SOURCES.tsv`, `README.txt` (rebuild steps, "not affiliated" line) and `SHA256SUMS`. It exits non-zero if any package is missing, so a release can't go out without its source.
- Measured on the R8 image (our kernel, 192 binary packages from **123** Ubuntu source packages): all 123 fetched from ports.ubuntu.com in 7.5 min; bundle **809 MB** (Ubuntu 648 MB, of which LLVM is 217 MB and GCC 93 MB; Linux tarball 161 MB; repo 0.2 MB). Launchpad fallback checked with two superseded versions (`base-files 13ubuntu10.1`, `llvm-toolchain-20 1:20.1.2-0ubuntu1~24.04.2`: the URL path keeps the epoch, the file names drop it); an unknown package is reported MISSING and fails the run. `dpkg-source -x` unpacks the fetched packages.
- **Private images (R19 option b / Q8 b):** `PANEL_FW=<dir>` makes `build-image.sh` copy the builder's own `panels/*.panel` (from `tools/gen_panel_firmware.py`) into `/usr/lib/firmware/panels`, names the image `…-private`, and runs the check with `PRIVATE=1`, which turns those files (and only those) into warnings. `release-sources.sh` refuses `-private` images, so a stock-derived image can't be bundled for release by mistake. Tested: same panel file fails without `PRIVATE`, warns with it; a `.panel` outside `panels/` still fails; a `-private` name is refused. If Dale picks Q8 (a), the panel data moves into GPL kernel code and this mode is no longer needed for the display.
- Publishing the bundle next to the image (same release page) meets GPL-2.0 §3(a) without a written offer. If a release ever ships without it, a written offer valid three years is the fallback.

The checklist:
1. `<image>.manifest.tsv` (done) + `<image>.sources.tar` or a written source offer covering every GPL package in it.
2. Kernel + u-boot + TF-A + stub corresponding source (tags, patches, configs, build scripts) as a tarball next to the image.
3. Firmware licence files present (`/usr/share/doc/linux-firmware-realtek/copyright`; checked by a test in the image build).
4. No ROCKNIX panel blobs, no stock binaries, no Ubuntu trademarks in our own branding (Q7: ReduxOS).
5. Release notes: components, versions, licences, "not affiliated with Anbernic or Canonical".

## 4. Sources
- Canonical IP Rights Policy, 15 July 2015: https://ubuntu.com/legal/intellectual-property-policy (summary: unmodified redistribution allowed; modified versions + trademarks need approval, otherwise remove/replace them; does not reduce rights under component licences). Community discussion of its scope: LWN (2015), Software Freedom Conservancy statement via CIO (2015), ubuntu-devel "remix branding" thread (2025-10).
- R4 audit (`docs/r4-noble-firmware-audit.md`): firmware licence text and the `EXTRA_FIRMWARE` concern.
- ROCKNIX `4fc79d7`: `projects/ROCKNIX/packages/tools/atf/patches/H700/001-allwinner-h616-psci-system-suspend.patch` header; no top-level `LICENSE`/`COPYING` found; `packages/linux-firmware/kernel-firmware/package.mk` (`PKG_LICENSE="other"`).
- `MagnominusGit/h700-suspend-stub`: README ("GPL-2.0-or-later"), `COPYING` (GPL-2).
- GPL-2.0 §3 (source for distributed binaries): `LICENSE` in this repo.
