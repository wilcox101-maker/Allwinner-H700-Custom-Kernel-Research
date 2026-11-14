# R22: upstream preparation for patches 0006 (RG34XX SP DTS) and 0007 (OPP schema)

Deep Research, 2026-11-14. Assigned by the Manager chat, approved by Dale (GO). **Desk only. Nothing was sent
upstream**; sending is Dale's decision. Outgoing files: `patches/outgoing/`; checks: `scripts/upstream-check.sh`.

## 1. Result
| | RG34XX SP series (0005 + 0006) | OPP schema (0007) |
|---|---|---|
| Target tree | sunxi `sunxi/dt-for-7.5` @ `a7f6e476aaed` (2026-11-10) | linux-next `next-20261113` @ `84abb955b101`; also applies to the sunxi branch |
| Applies cleanly | yes (also on `next-20261113`) | yes |
| `checkpatch.pl --strict` | 0 errors / 0 warnings / 0 checks, apart from the expected missing `Signed-off-by` and, for the new DTS, "does MAINTAINERS need updating?" (the file is covered by the sunXi entry's `N:` pattern; `get_maintainer.pl` lists the sunXi maintainers) | 0/0/0 apart from the missing `Signed-off-by` |
| `dtbs_check` (`CHECK_DTBS=y W=1`) | no warnings of its own; the one W=1 line (`/soc` unit address in `sun50i-h616.dtsi`) is printed for the RG35XX SP DTB too | control: an H616 OPP table with `turbo-mode` + `opp-suspend` gives 2 schema warnings without the patch, 0 with it |
| `dt_binding_check` | `arm/sunxi.yaml` passes | `opp/allwinner,sun50i-h6-operating-points.yaml` passes |
| Negative control of the script | a stray property in the outgoing DTS fails both the dtbs gate and the drift check | — |
| Open before sending | 1 `[TODO]`: testing paragraph in the cover letter | 2 `[TODO]`s: user of the binding, hardware test |
| Recommendation | **wait for K2 (mainline boot) and K5 (stick axes, stick clicks)**, then fill in the testing paragraph | **hold** until a board series uses the properties (see §3) |

Nothing here was booted. The pinned workbench (`scripts/workbench.sh --bindings`, Linux `97d73c8`) also passed
in full on 2026-11-14 13:50 ET with the unchanged `patches/linux/` series.

## 2. What changed between `patches/linux/` and the outgoing series
Our working series (`patches/linux/0001–0007`) stays as it is; the image keeps using it. The outgoing copies differ:

- **Binding (from 0005):** the `sunxi.yaml` entry moved from after "RG35XX SP" to before "RG35XX (2024)", where it sorts
  alphabetically; description "Anbernic RG34XX SP" (the file's spelling for the RG35XX SP); real commit message
  instead of "Draft for the Redux project".
- **DTS (from 0006):** the `&codec { allwinner,pa-delay-ms = <100>; }` block is **dropped**. That property is
  defined only by our patches 0002/0003 (ASoC binding + driver), which are not in this series; with it, the DTS
  would fail `dtbs_check` on any upstream tree. Upstream boards then keep the driver's 700 ms speaker start-up
  delay until 0002/0003 are sent and merged (a follow-up DTS patch can add the property). Model and comment say
  "RG34XX SP" like the RG35XX trees ("Anbernic RG35XX SP"). The compatible stays `anbernic,rg34xx-sp`.
  `scripts/upstream-check.sh` checks that these are the only differences from 0006.
- **Subjects** capitalised as in the sunxi tree's recent commits ("Add …"); subject prefixes as used there.
- **Author** is the placeholder `Your Name <you@example.invalid>` (the repo's patches use `redux@invalid`); no
  `Signed-off-by`. Each commit message keeps a line saying an AI assistant drafted it and how it was checked
  (`Documentation/process/generated-content.rst`); the kernel has no `Assisted-by` tag in either tree checked.
- **0007** message rewritten to say what the binding rejects today and why both properties are generic; the
  missing in-tree user is stated below the `---` cut for reviewers.

## 3. Points Dale should weigh before sending
1. **Untested hardware description.** sunxi maintainers merge board trees from people who have booted them; the
   cover letter's testing paragraph is a `[TODO]` on purpose. K2 (ROCKNIX/mainline boot) and K5 (`evtest`
   axes and both stick clicks) answer it. The right-stick reversal is copied from the RG35XX H and is unconfirmed.
2. **0007 has no user upstream.** No Allwinner DTS in `next-20261113` uses `turbo-mode` or `opp-suspend` (they
   are used elsewhere, e.g. Renesas), and the outgoing RG34XX SP DTS inherits the upstream H616 OPP table
   unchanged, so it doesn't use them either. DT maintainers often refuse binding changes with no user. Options:
   (a) hold 0007 until a board patch marks an OPP `turbo-mode` (for us: after K22, if Dale wants our Q2 boost
   setup upstream); (b) send it with that board patch as one series; (c) send it alone as RFC. Recommended: (a)/(b).
3. **Timing.** `sunxi/dt-for-7.5` is the branch for the next merge window; once it is sent on to the SoC tree,
   new boards go to the following release's branch. Re-run the check against whichever `dt-for-*` exists then.
4. **Duplicates.** A web search found no RG34XX SP submission on lore (2026-11-14); the lore search itself could not
   be opened from here, so check <https://lore.kernel.org/all/?q=rg34xx> before sending.
5. **Credits.** The stick nodes follow the RG35XX H tree (© Ryan Walklin, Chris Morgan) and the file includes
   the RG35XX SP tree. Cc'ing both authors is a courtesy, not required by `get_maintainer.pl`.

## 4. Recipients (`scripts/get_maintainer.pl --nogit`, on the trees above)
**RG34XX SP series** — To: Chen-Yu Tsai <wens@kernel.org>, Jernej Skrabec <jernej.skrabec@gmail.com>,
Samuel Holland <samuel@sholland.org> (sunXi); Rob Herring <robh@kernel.org>, Krzysztof Kozlowski
<krzk+dt@kernel.org>, Conor Dooley <conor+dt@kernel.org> (DT bindings). Cc: devicetree@vger.kernel.org,
linux-arm-kernel@lists.infradead.org, linux-sunxi@lists.linux.dev, linux-kernel@vger.kernel.org; Maxime Ripard
<mripard@kernel.org> ("in file"). Optional courtesy Cc: Ryan Walklin, Chris Morgan, Andre Przywara (active H616/H700 reviewer).

**OPP schema** — To: Viresh Kumar <vireshk@kernel.org>, Nishanth Menon <nm@ti.com>, Stephen Boyd <sboyd@kernel.org>
(OPP); Yangtao Li <tiny.windzz@gmail.com> (Allwinner cpufreq); Rob Herring, Krzysztof Kozlowski, Conor Dooley (DT);
Chen-Yu Tsai, Jernej Skrabec, Samuel Holland (sunXi). Cc: linux-pm@vger.kernel.org, devicetree@vger.kernel.org,
linux-arm-kernel@lists.infradead.org, linux-sunxi@lists.linux.dev, linux-kernel@vger.kernel.org; Maxime Ripard.

The script regenerates both lists into `$WORK/upstream-check/*.maintainers`; use the fresh lists when sending.

## 5. Sources
- sunxi tree `git.kernel.org/pub/scm/linux/kernel/git/sunxi/linux.git`, branch `sunxi/dt-for-7.5` @ `a7f6e476aaed`.
- linux-next tag `next-20261113` @ `84abb955b101`.
- Linux `97d73c8` (`Documentation/process/coding-assistants.rst`, `generated-content.rst`); the same files in
  `next-20261113` have no `Assisted-by` tag.
- `Documentation/devicetree/bindings/dts-coding-style.rst` (node/property order; the DTS already follows it).
