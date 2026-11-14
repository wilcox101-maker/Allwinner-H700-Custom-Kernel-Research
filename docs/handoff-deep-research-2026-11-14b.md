# Handoff: Deep Research chat, 2026-11-14 (17:00 ET, second swap of the day)

For the next Deep Research (DR) chat in the "H700 Allwinner Custom Kernel Research" Project. Replaces
`handoff-deep-research-2026-11-14.md` (09:50 ET); its ground rules, decisions table (Q1–Q8), "what DR has built"
list and local-environment notes **still hold** — read it first, then this file for what changed.

## Changes to the ground rules
- **Merging:** this chat's own `gh api -X PUT …/pulls/N/merge` was refused by the session's permission check
  (not by Dale). The next chat may try once; if refused, leave the PR open and ask Dale to merge.
- **Branches:** one PR per task. While a PR from `deep-research` is unmerged, put the next task on a stacked
  branch (`deep-research-<task>`) and say "merge #N first" in its PR. Don't force-push `deep-research`
  (refused); bring `main` in with a merge commit instead.
- Ask Dale **"Swap now?"** at about 100 messages.

## Open PRs (both green, mergeable, not merged; merge #32 first)
| PR | Branch | Task | Contents |
|---|---|---|---|
| #32 | `deep-research` | R22 | `patches/outgoing/` (RG34XX SP binding + DTS with cover letter on sunxi `dt-for-7.5`; OPP schema patch on `next-20261113`), `scripts/upstream-check.sh`, `docs/r22-upstream-prep.md`; R22/R23 rows in the master list |
| #33 | `deep-research-r23` (stacked on #32) | R23 | `.github/workflows/image-smoke.yml`, `image/qemu/smoke-test.sh`, `docs/r23-ci-qemu-smoke.md` |

## R22 status (nothing sent; sending is Dale's decision)
- All checks pass (checkpatch --strict, dtbs_check W=1, dt_binding_check, OPP before/after control, drift check
  against `patches/linux/0006`). Recipients in `docs/r22-upstream-prep.md` §4.
- Outgoing DTS drops `allwinner,pa-delay-ms` (only our 0002/0003 define it).
- Before sending: K2 + K5 results into the cover letter's testing `[TODO]`; Dale's name + his own Signed-off-by;
  lore duplicate check (<https://lore.kernel.org/all/?q=rg34xx> — needs approval from this environment); re-run
  `scripts/upstream-check.sh` against the then-current `sunxi/dt-for-*` branch. Hold 0007 until a board uses
  `turbo-mode`/`opp-suspend` (after K22).

## R23 status
- CI builds the kernel (cached by input hash), the image, boots it in QEMU at 512 MB; 12 checks. Green on GitHub:
  cold cache 20 min, warm 8 min. A failing step posts its last lines as `::error` annotations: read them with
  `gh api repos/…/check-runs/<id>/annotations` (the Actions log API is blocked through this proxy).
- Triggers: PRs/pushes to `main` touching `image/ config/ patches/ dts/ tools/` or the kernel scripts; weekly;
  by hand.
- Told KR (sync entry): `tools/apply_upstream.py`'s `git am` needs a committer identity on a fresh machine.

## Next (DR desk work; unchanged from the 09:50 handoff, none started)
1. Image with the real bootloader (`build-uboot.sh --dram all --sources`, `UBOOT_BIN=…`; check SPL at 8 KiB, no
   overlap with the FAT at 16 MiB, eGON checksum). **Never write a card.**
2. R9 source bundle: `release-sources.sh` to accept KR's three u-boot/TF-A tarballs; TF-A BSD notice.
3. R8 `mmc 0:1` check vs `docs/r8-update-rollback.md`.
4. R13 CPU notes (ROCKNIX table, 1024 mA, Expert Mode boost, R11 cooling map).
5. Optional follow-up to R23: a second CI job for `image/qemu/rollback-test.sh` (u-boot bootcount path).

## Local environment additions
- Extra packages used this block: `gcc-aarch64-linux-gnu device-tree-compiler bc flex bison libssl-dev fakeroot
  kmod cpio debhelper libdw-dev libelf-dev build-essential fdisk arch-test`, `pip install dtschema yamllint
  actionlint-py`. The workflow's install step is the authoritative list.
- `build-kernel.sh` leaves a `-dbg` package next to `linux-image-…rg34xxsp_…deb`; use only the latter.
