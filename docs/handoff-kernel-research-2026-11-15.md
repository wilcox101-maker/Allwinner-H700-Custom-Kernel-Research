# Kernel Research handoff, 2026-11-15 (04:10 ET)

For the next Kernel Research (KR) chat. Replaces `handoff-kernel-research-2026-11-14.md` for current state; its
rules still hold. Coordination: the Redux Manager (Dale, 2026-11-15); send questions (swap, merges, decisions,
installs) to it via `redux-work\Claude Files`, not to Dale.

## State
- Ghidra plan ([`ghidra-plan.md`](ghidra-plan.md)): every KR item done: G0.1–G0.4, G1, G2, G4, G5, G6, W3.1, W3.2,
  W3.3. DR has G3 and W3.4–W3.6. Findings with no known public source are tagged [N]; list at the top of the plan.
- PRs #42–#51 (+ this one) are stacked; the Manager merges in number order as CI goes green.
- Redux packages sent: m (Waves 0–1) and n (Waves 2–3, replaces m's zip), plus o (asks to the Manager).
- Dale's PC: `REA\BootImage\kallsyms` (symbol list, ELF from vmlinux-to-elf, Ghidra script `ReduxApplyKallsyms`,
  sysfs and module-parameter TSVs, a deletable project snapshot) and `REA\BootImage\modules-v106` (stock modules,
  `rc.local`, 8821cs parameters). Nothing stock is in any repo.

## Open items (Dale 03:00: keep going until complete): gap-closing on finished items, desk only
1. Redux map (package n's `stock-kernel-ghidra.md`): add [N] tags, matching the plan's list, next time it is sent.
2. W3.1: write limits of `disp_sys_store` and `key_info_store` (didn't decompile); who reads `openbor_volume`,
   `nds_esckey`, `nds_pwrkey` (stock userspace: coordinate with DR W3.5); where `display_id` comes from; check
   the `/dev/disp` command names against strings instead of the BSP header; the `disp`/`hdmi` `attr` folders.
3. G5: source of the jack invert flag (which level = plugged); ALSA jack name; codec defaults when a DT property
   is missing.
4. G4: confirm the driver-default pairing in table 3; meaning of registers 0x70, 0xB0/0xB2 (AXP717 datasheet).
5. G1: default value of `os_sleep`; whether the Wi-Fi wake is armed in suspend.
6. W3.3: re-read the upstream trees at our pin `97d73c8` (the doc used master of 2026-11-15).
Device checks for all items are listed in the docs and in packages m and n (Owner adds them to the queue).

## Tools (the new chat's container starts empty)
- Repo: `tools/kallsyms_49.py` (stdlib symbol reader, test `tests/test_kallsyms_49.py`).
- This chat used, in its own container: Ghidra 12.2 (GitHub release `Ghidra_12.2_build`, SHA-256 2c2cd776…be67, same
  as Dale's zip), OpenJDK 25 (apt), and a copy of Dale's project from the snapshot tar with the kallsyms names applied
  headless (`ReduxApplyKallsyms.java`; set `OWNER` in `project.prp` to the container user). **Installing these again is
  an install: ask the Manager first.** Without them, `kallsyms_49.py`, the relocation table (R_AARCH64_RELATIVE
  entries give every data pointer, since the Image is relocatable) and `readelf`/`strings` cover most lookups.
- The stock rootfs is read with `debugfs -c` on Dale's PC (`.FW\RG34XXSP-V1.0.6-EN16GB-260526\4.rootfs.img`),
  never mounted or written.

## Next step
Item 2 first (largest), then 3–6; one PR per item or two related items, stacked; report to the Manager when done.
