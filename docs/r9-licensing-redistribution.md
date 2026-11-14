# R9: Licensing and redistribution audit

Deep Research, 2026-11-14. Master list task R9. **Not legal advice**: this records what each component's own licence or policy says and what the project should do to stay on the safe side; anything marked *ask* needs a person (Dale, or a lawyer if the image is ever sold or shipped on hardware).

## Answer in one paragraph
Nearly everything we ship is either Ubuntu's own unmodified packages or our own GPL work, so the obligations are routine: **publish the corresponding source for every GPL binary we distribute** (kernel, u-boot, TF-A + stub, and the Ubuntu packages in the image) and keep the firmware licence files. Three things need decisions before a public image: (1) **the "Ubuntu" name**: Canonical's IP policy says modified Ubuntu may only carry its trademarks if Canonical approves it, so the image should not be branded "Ubuntu" (new decision **Q7**); (2) **panel init sequences**: ROCKNIX's panel blobs have no stated licence, so we should not ship them; put the two RG34XX-SP sequences into GPL kernel code the way upstream panel drivers do; (3) **the ROCKNIX TF-A suspend patch** carries no licence statement, so ask its author before carrying it (the stub it loads is GPL-2.0-or-later).

## 1. Component by component
| Component | Licence / terms (evidence) | What we ship | Obligation / action | Status |
|---|---|---|---|---|
| Ubuntu packages in the image (~189, R7 manifest) | Each package's own licence (`/usr/share/doc/*/copyright`, kept in the image by the R7 `path-include`), plus **Canonical's IP Rights Policy** for the aggregate | Unmodified binaries from noble/-updates/-security | GPL'd packages: offer their source. Keep `copyright` files (done). Trademarks: see §2 | **To do:** publish a source bundle per release (`apt-get source` for every package in the manifest, or a written offer valid 3 years) |
| `linux-firmware-realtek` (rtw88, rtl_bt) | "Redistributable. See LICENCE.rtlwifi_firmware.txt" (upstream WHENCE, R4) | Unmodified Ubuntu package (files under `/lib/firmware`) | Keep the licence file; no source exists | OK. **Never** embed these into the kernel (`EXTRA_FIRMWARE`, which ROCKNIX does); KR's config doesn't |
| Our kernel package | GPL-2.0 (Linux) + our patches (GPL-2.0) | `linux-image-<ver>-rg34xxsp` | Publish complete corresponding source: pinned upstream commit + `patches/linux/` + `config/` + `scripts/build-kernel.sh` (all in this repo); add a source tarball or `deb-src` to the release/repo | Partly: repo has it all; release step to add |
| u-boot (+ our PE6 and R8 bits) | GPL-2.0+ | SPL+u-boot at 8 KiB (future images) | Source: u-boot tag + patches + defconfig/fragment, published with each image | Future (R1) |
| TF-A BL31 | BSD-3-Clause | inside the u-boot binary | Keep BSD notice in the release notes/source bundle | Future |
| ROCKNIX TF-A suspend patch (`001-allwinner-h616-psci-system-suspend.patch`, Kailash R S) | **No licence or SPDX statement in the patch** (header: `From:`/`Subject:` only); ROCKNIX repo has no top-level `LICENSE`/`COPYING` at `4fc79d7` | Not yet (suspend work, KR §7) | **Ask** the author for a licence (BSD-3-Clause to match TF-A is the natural choice) before carrying it; until then reference only | Blocked: ask |
| `h700-suspend-stub` (MagnominusGit) | **GPL-2.0-or-later** (its README; `COPYING` = GPL-2) | Would be embedded in BL31 | GPL source for the stub and its build; the combined `bl31.bin` must come with source (KR's note) | OK if source published |
| Panel init sequences | ROCKNIX `extra-firmware/panels/*.panel`: **no licence found**; content is Anbernic's sequences (our PE6 work proved they are stock-derived) | Not shipped (repo policy since R5) | Don't redistribute ROCKNIX's blobs. Express the two sequences in GPL-2.0 kernel code or DT (as upstream `panel-newvision-nv3052c.c` does for other vendors' NV3052C panels) as part of R19, or extract them on the user's device from the user's own stock image with `tools/extract_rg34xxsp_panels.py` | **Decision with R19** |
| Stock hardware facts in docs/DTs (DRAM values, OPP tables, pins) | Facts recorded from stock binaries; no code copied (methodology doc §5) | Yes (docs, DT drafts) | None beyond attribution | OK |
| Stock binaries (boot0 copies, kernels) | Anbernic; GPL kernel source not published by Anbernic | **Not** in the repo (local only) | Keep it that way | OK |
| Mesa / LLVM | MIT / Apache-2.0 with LLVM exception, via Ubuntu | Unmodified Ubuntu packages | As for Ubuntu packages | OK |
| This repository | GPL-2.0-only (LICENSE, SPDX tags); DTs dual GPL-2.0/BSD-2-Clause | — | — | OK |

## 2. The "Ubuntu" name (new decision Q7)
Canonical's IP Rights Policy (15 July 2015) allows redistributing Ubuntu **unmodified**; modified versions may be associated with the Ubuntu trademarks only if Canonical approves, certifies or provides them, otherwise the trademarks must be removed and replaced (the policy also says "recompile", which the community disputes; it adds that it does not reduce rights under the components' own open-source licences). Our image is a modified Ubuntu (own kernel, boot setup, configuration). Today the image uses "Ubuntu" in the u-boot menu label (`U_BOOT_MENU_LABEL="Ubuntu 24.04 RG34XX-SP"`); the file name uses only the codename "noble".

Options for Dale (**Q7**):
- **(a) Own name (recommended):** call the image something else ("Redux OS", "H700 Linux", …), describe it factually as *built from Ubuntu 24.04 LTS packages* in the docs, and change the menu label. Leave `base-files`/`/etc/os-release` as Ubuntu ships them for v0.x (they're unmodified Ubuntu packages); revisit if the image is ever distributed widely.
- (b) Ask Canonical for approval to use the name (their "remix" path); slow and uncertain.
- (c) Personal/private use only: no public images. Then most of this section is moot.

Until Q7 is decided, keep images private (no public downloads).

## 3. Release checklist (to add to the image build, R7)
1. `<image>.manifest.tsv` (done) + `<image>.sources.tar` or a written source offer covering every GPL package in it.
2. Kernel + u-boot + TF-A + stub corresponding source (tags, patches, configs, build scripts) as a tarball next to the image.
3. Firmware licence files present (`/usr/share/doc/linux-firmware-realtek/copyright`; checked by a test in the image build).
4. No ROCKNIX panel blobs, no stock binaries, no Ubuntu trademarks in our own branding (per Q7).
5. Release notes: components, versions, licences, "not affiliated with Anbernic or Canonical".

## 4. Sources
- Canonical IP Rights Policy, 15 July 2015: https://ubuntu.com/legal/intellectual-property-policy (summary: unmodified redistribution allowed; modified versions + trademarks need approval, otherwise remove/replace them; does not reduce rights under component licences). Community discussion of its scope: LWN (2015), Software Freedom Conservancy statement via CIO (2015), ubuntu-devel "remix branding" thread (2025-10).
- R4 audit (`docs/r4-noble-firmware-audit.md`): firmware licence text and the `EXTRA_FIRMWARE` concern.
- ROCKNIX `4fc79d7`: `projects/ROCKNIX/packages/tools/atf/patches/H700/001-allwinner-h616-psci-system-suspend.patch` header; no top-level `LICENSE`/`COPYING` found; `packages/linux-firmware/kernel-firmware/package.mk` (`PKG_LICENSE="other"`).
- `MagnominusGit/h700-suspend-stub`: README ("GPL-2.0-or-later"), `COPYING` (GPL-2).
- GPL-2.0 §3 (source for distributed binaries): `LICENSE` in this repo.
