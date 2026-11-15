# Decision (Dale, 2026-11-14 21:07 ET): Unicode-DFS-2016 notice for u-boot's capitalization table

Relayed by the Redux Manager. Recorded by Deep Research, 2026-11-15. Master list: **Q9**.

## Question
u-boot's `include/capitalization.h` is compiled into our bootloader (through `CONFIG_EFI_UNICODE_CAPITALIZATION=y`, a
default of `anbernic_rg35xx_h700_defconfig`). It is tagged `SPDX-License-Identifier: Unicode-DFS-2016`, a licence that
requires its copyright and permission notice to appear with copies or in associated documentation, and u-boot ships
no copy of the text. Found by `tools/bootloader_notices.py` (R9, PR #37).

Options put to Dale: **(A)** add the licence text to the bootloader notices, no binary change; (B) have KR turn the
option off, which drops the table but changes the R1 binary and needs a new FEL check (K4).

## Decision
**A.** Ship the Unicode-DFS-2016 text in the bootloader notices; keep `CONFIG_EFI_UNICODE_CAPITALIZATION` as it is;
no binary change.

## Applied (this PR)
- `tools/licences/Unicode-DFS-2016.txt`: the text as published in SPDX license-list-data (byte-identical at tag
  `v3.29.0` and `main` `31846481de7e`; CC0-1.0 data). Provenance in `tools/licences/README.md`.
- `tools/bootloader_notices.py` appends it under "Licence texts" whenever a compiled file carries that id; it no
  longer warns about it. Checked: the full text appears verbatim, once; output is deterministic and the same under
  `LC_ALL=C`.
- The notices go into every u-boot image as `/usr/share/doc/reduxos-bootloader/NOTICES.txt` and into the release
  source bundle (R9 §3a). `scripts/build-uboot.sh` adds `tools/licences/` to its inputs tarball.
- u-boot binaries unchanged (`1d0381e1…` LPDDR4, `c0c3de97…` LPDDR3).

## Related, not decided here
`lib/binman.c` + `include/binman.h` (tag `Intel`, no text) stay flagged. The generator now names the review in its
warning; an upstream report is drafted for Dale: `docs/upstream-drafts/u-boot-binman-spdx.md` (not sent).
