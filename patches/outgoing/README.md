# Outgoing upstream series (task R22)

Prepared for upstream review; **nothing here has been sent, and nothing in this repo sends mail.**
Whether and when to send is Dale's decision. Details and reasons: `docs/r22-upstream-prep.md`.

| Series | Target tree (base) | Patches | Status |
|---|---|---|---|
| `rg34xx-sp-dts-v1/` | sunxi `sunxi/dt-for-7.5` (`a7f6e476aaed`) | 0/2 cover letter, 1/2 `dt-bindings: arm: sunxi: Add Anbernic RG34XX SP`, 2/2 `arm64: dts: allwinner: h700: Add Anbernic RG34XX SP` | checks pass; **1 TODO** (testing paragraph); recommended to wait for K2 + K5 |
| `opp-turbo-suspend-v1/` | linux-next `next-20261113` (`84abb955b101`); also applies to the sunxi branch | `dt-bindings: opp: sun50i: Allow turbo-mode and opp-suspend` | checks pass; **2 TODOs**; no in-tree user yet, so hold it until a board series uses it |

Re-run every check (fetches the trees, applies, checkpatch --strict, dtbs_check W=1, dt_binding_check,
a before/after control for the OPP patch, drift check against `patches/linux/0006`, maintainers lists):

```sh
WORK=<dir> scripts/upstream-check.sh        # ~10 min on 2 cores after the first fetch
```

## Before sending (Dale)
1. Search lore for an RG34XX SP submission by someone else: <https://lore.kernel.org/all/?q=rg34xx>.
2. Replace every `[TODO …]` (`grep -rn '\[TODO' patches/outgoing`): the testing paragraph must say what
   actually ran on hardware.
3. Put your own name and e-mail in place of `Your Name <you@example.invalid>` and add **your own**
   `Signed-off-by` (the kernel's `coding-assistants.rst`: an AI tool must never add it). For example, in a
   kernel tree at the base commit:
   ```sh
   git am patches/outgoing/rg34xx-sp-dts-v1/000[12]-*.patch
   git rebase --exec 'git commit --amend --no-edit --reset-author -s' a7f6e476aaed
   git format-patch --cover-letter --base=auto -2 -o out/   # then paste the drafted cover letter text
   ```
   (`b4 prep` does the same with a managed cover letter, if you prefer it.)
4. Re-run `scripts/upstream-check.sh` against the then-current `sunxi/dt-for-*` branch and linux-next tag.
5. To/Cc from `get_maintainer.pl` (lists in `docs/r22-upstream-prep.md` §4); plain-text mail, no attachments.
