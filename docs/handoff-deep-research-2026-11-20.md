# Handoff: Deep Research chat, 2026-11-20 (08:00 ET)

For the next DR chat. Rules: `AGENTS.md`, `CLAUDE.md`, README ground rules. DR works only on the H700 project.

## State
- `main` at `baddb17` plus this status-refresh PR; no other open PRs. Current state on one page: [`STATUS.md`](STATUS.md).
- Done since the 11-17 handoff: DR-1/2/3 ([`dr-osk-desk-checks-2026-11-18.md`](dr-osk-desk-checks-2026-11-18.md)); K9 desk part
  ([`k9-newer-panel-gc9703.md`](k9-newer-panel-gc9703.md)); R29 driver ([`r29-gc9703-panel-driver.md`](r29-gc9703-panel-driver.md));
  review ([`dr-review-2026-11-20.md`](dr-review-2026-11-20.md)); R30 unknowns and rebuild
  ([`dr-unknowns-and-rebuild-2026-11-20.md`](dr-unknowns-and-rebuild-2026-11-20.md)).
- Dale's standing choice since 2026-11-18: act on DR's recommended option without asking, his reserved decisions excepted.

## Open
- Device: K3/K4 first (allowed on Dale's 2 GB unit), then the K-tasks; K24–K28 for the stock OSK; K9/K29 need a newer-panel unit.
- Desk candidates, no owner: TF2 device-tree node; HDMI once the upstream series settles; osklib default chord (mapping
  question for KR, in `research-sync.md`); the older third panel (needs a 2025 stock image).
- u-boot binman SPDX patch: drafted, not sent (Dale sends). Follow-up PR after it is on the list: update
  `tools/bootloader_notices.py` KNOWN_FLAGS and `docs/upstream-drafts/u-boot-binman-spdx.md`.
- Private, not in git: `Claude Files\FROM-REDUX-DEEP-2026-11-15-security.md` and `-2026-11-18-security.md`.

## Local files on Dale's PC (not in git, deletable)
`REA\ghidra_scripts\DRDecompRange.java`, `DRDecompRegex.java`; `REA\BootImage\decomp-dr-*`; `Downloads\Anbernic RG34xxSP\.FW\re-extracts\`.
Ghidra 12.2 + JDK 25 are in `REA\`; headless runs are read-only on `REA\BootImage\ghidra-project`.

## Next step
Wait for a GO. The most useful next piece is the step list for K3/K4 on Dale's unit ([`r2-fel-test-kit.md`](r2-fel-test-kit.md)).
