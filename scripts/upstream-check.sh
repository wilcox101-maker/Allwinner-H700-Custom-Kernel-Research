#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Re-run every pre-submission check on the outgoing upstream series (task R22).
# It never sends anything: no git send-email, no b4 send.
#
# For each series in patches/outgoing/ it:
#   1. checks out the maintainer tree the series targets (sunxi/dt-for-<ver> or a linux-next tag)
#      and applies the series with git am (must apply cleanly)
#   2. runs checkpatch --strict on every patch, with a placeholder Signed-off-by added so that
#      the only expected finding (no Signed-off-by: the human submitter adds it) doesn't hide others
#   3. RG34XX SP series: dtbs_check with W=1 on the new DTB; any warning that the RG35XX SP DTB
#      (its base) doesn't also print fails; dt_binding_check on arm/sunxi.yaml
#   4. OPP series: dt_binding_check, then a control: an H616 OPP table using turbo-mode and
#      opp-suspend must fail dtbs_check without the patch and pass with it
#   5. drift check: the outgoing DTS must equal patches/linux/0006's DTS minus the documented
#      upstream differences (no allwinner,pa-delay-ms; "RG34XX SP" spelling)
#   6. writes get_maintainer.pl output per series to $WORK/upstream-check/<series>.maintainers
#   7. lists the [TODO …] placeholders left in each series (must be 0 before sending)
#
# Usage: scripts/upstream-check.sh
#   WORK=<dir>         work directory (default ./.work); Linux clone in $WORK/linux (as workbench.sh)
#   SUNXI_BRANCH=…     default sunxi/dt-for-7.5
#   NEXT_TAG=…         default next-20261113
# Needs what workbench.sh needs (aarch64 gcc, dtc, dtschema, yamllint).

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${WORK:-$REPO/.work}
LINUX=$WORK/linux
OUTDIR=$WORK/upstream-check
SUNXI_URL=https://git.kernel.org/pub/scm/linux/kernel/git/sunxi/linux.git
NEXT_URL=https://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git
SUNXI_BRANCH=${SUNXI_BRANCH:-sunxi/dt-for-7.5}
NEXT_TAG=${NEXT_TAG:-next-20261113}
DTS=arch/arm64/boot/dts/allwinner
FAILS=0

log() { printf '\n== %s\n' "$*"; }
bad() { printf 'FAIL: %s\n' "$*" >&2; FAILS=$((FAILS + 1)); }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$OUTDIR"
if [ ! -d "$LINUX/.git" ]; then
	git init -q "$LINUX"
fi
git -C "$LINUX" remote get-url sunxi >/dev/null 2>&1 || git -C "$LINUX" remote add sunxi "$SUNXI_URL"
git -C "$LINUX" remote get-url next >/dev/null 2>&1 || git -C "$LINUX" remote add next "$NEXT_URL"

log "Fetch $SUNXI_BRANCH and $NEXT_TAG"
git -C "$LINUX" fetch -q --depth 50 sunxi "$SUNXI_BRANCH" || die "fetch $SUNXI_BRANCH"
SUNXI_BASE=$(git -C "$LINUX" rev-parse FETCH_HEAD)
git -C "$LINUX" fetch -q --depth 1 next tag "$NEXT_TAG" || die "fetch $NEXT_TAG"
NEXT_BASE=$(git -C "$LINUX" rev-parse "$NEXT_TAG^{commit}")
echo "  $SUNXI_BRANCH = ${SUNXI_BASE:0:12}, $NEXT_TAG = ${NEXT_BASE:0:12}"

# prepare_tree <name> <base>: a clean worktree at <base>, echoes its path
prepare_tree() {
	local wt=$WORK/upstream-$1
	if [ ! -d "$wt" ]; then
		git -C "$LINUX" worktree add -q -f --detach "$wt" "$2" >/dev/null
	fi
	git -C "$wt" am --abort >/dev/null 2>&1 || true
	git -C "$wt" checkout -q -f --detach "$2"
	git -C "$wt" clean -q -fd
	echo "$wt"
}

# checkpatch_series <tree> <patch>…
checkpatch_series() {
	local wt=$1; shift
	local p tmp out
	tmp=$(mktemp)
	for p in "$@"; do
		case "$(basename "$p")" in 0000-cover-letter.patch) continue ;; esac
		python3 -I - "$p" "$tmp" <<-'EOF'
		import sys
		s = open(sys.argv[1]).read()
		author = [l[6:] for l in s.splitlines() if l.startswith('From: ')][0]
		s = s.replace('\n---\n', '\nSigned-off-by: %s\n---\n' % author, 1)
		open(sys.argv[2], 'w').write(s)
		EOF
		out=$("$wt/scripts/checkpatch.pl" --strict "$tmp" 2>&1 || true)
		# A new DTS file always draws "does MAINTAINERS need updating?"; the sunxi entry covers it (N: pattern)
		if printf '%s\n' "$out" | grep -E '^(ERROR|WARNING|CHECK)' |
			grep -v 'does MAINTAINERS need updating' | grep -q .; then
			printf '%s\n' "$out"
			bad "checkpatch: $(basename "$p")"
		else
			echo "  ok  checkpatch --strict $(basename "$p")"
		fi
	done
	rm -f "$tmp"
}

kmake() { make -s -C "$1" O="$2" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" "${@:3}"; }

todos() {
	local n
	n=$(grep -c '\[TODO' "$@" | awk -F: '{s += $NF} END {print s + 0}')
	echo "  [TODO …] placeholders left: $n (must be 0 before sending)"
}

# ---------------------------------------------------------------------------------------------
S=rg34xx-sp-dts-v1
log "Series $S on $SUNXI_BRANCH"
mapfile -t P < <(printf '%s\n' "$REPO/patches/outgoing/$S"/*.patch)
WT=$(prepare_tree sunxi "$SUNXI_BASE")
O=$WORK/upstream-out-sunxi
mapfile -t PP < <(printf '%s\n' "${P[@]}" | grep -v 0000-cover-letter)
git -C "$WT" -c user.name=check -c user.email=check@invalid am -q "${PP[@]}" ||
	die "$S does not apply to $SUNXI_BRANCH"
echo "  ok  applies"
checkpatch_series "$WT" "${P[@]}"
kmake "$WT" "$O" defconfig >/dev/null
for b in rg35xx-sp rg34xx-sp; do
	kmake "$WT" "$O" W=1 CHECK_DTBS=y "allwinner/sun50i-h700-anbernic-$b.dtb" 2>&1 |
		grep -v jobserver | sed "s/anbernic-$b/anbernic-BOARD/g" | sort -u >"$OUTDIR/$b.dtbs" || true
done
if new=$(comm -13 "$OUTDIR/rg35xx-sp.dtbs" "$OUTDIR/rg34xx-sp.dtbs") && [ -n "$new" ]; then
	printf '%s\n' "$new"
	bad "dtbs_check W=1: new warnings in the RG34XX SP DTB"
else
	echo "  ok  dtbs_check W=1: no warning beyond the RG35XX SP base ($(wc -l <"$OUTDIR/rg35xx-sp.dtbs") shared)"
fi
if kmake "$WT" "$O" dt_binding_check DT_SCHEMA_FILES=arm/sunxi.yaml >"$OUTDIR/$S.dbc" 2>&1; then
	echo "  ok  dt_binding_check arm/sunxi.yaml"
else
	cat "$OUTDIR/$S.dbc"; bad "dt_binding_check arm/sunxi.yaml"
fi
# drift check against our working patch 0006
python3 -I - "$REPO/patches/linux/0006-arm64-dts-allwinner-h700-add-Anbernic-RG34XX-SP.patch" \
	"$WT/$DTS/sun50i-h700-anbernic-rg34xx-sp.dts" <<-'EOF' || bad "outgoing DTS drifted from patches/linux/0006"
	import sys
	src = open(sys.argv[1]).read().split('+++ b/arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg34xx-sp.dts\n', 1)[1]
	src = src.split('\n-- \n', 1)[0]
	ours = ''.join(l[1:] + '\n' for l in src.splitlines()[1:] if l.startswith('+'))
	ours = ours.replace('&codec {\n\tallwinner,pa-delay-ms = <100>;\n};\n\n', '')
	ours = ours.replace('RG34XX-SP', 'RG34XX SP').replace('RG35XX-SP', 'RG35XX SP')
	out = open(sys.argv[2]).read()
	if ours != out:
	    import difflib
	    sys.stdout.writelines(difflib.unified_diff(ours.splitlines(1), out.splitlines(1), 'patches/linux/0006', 'outgoing'))
	    sys.exit(1)
	print('  ok  outgoing DTS = patches/linux/0006 minus the documented upstream differences')
	EOF
"$WT/scripts/get_maintainer.pl" --nogit "${P[@]}" >"$OUTDIR/$S.maintainers" 2>/dev/null
echo "  maintainers: $OUTDIR/$S.maintainers ($(wc -l <"$OUTDIR/$S.maintainers") lines)"
todos "${P[@]}"

# ---------------------------------------------------------------------------------------------
S=opp-turbo-suspend-v1
log "Series $S on $NEXT_TAG"
mapfile -t P < <(printf '%s\n' "$REPO/patches/outgoing/$S"/*.patch)
WT=$(prepare_tree next "$NEXT_BASE")
O=$WORK/upstream-out-next
Y=Documentation/devicetree/bindings/opp/allwinner,sun50i-h6-operating-points.yaml
git -C "$WT" -c user.name=check -c user.email=check@invalid am -q "${P[@]}" ||
	die "$S does not apply to $NEXT_TAG"
echo "  ok  applies"
checkpatch_series "$WT" "${P[@]}"
kmake "$WT" "$O" defconfig >/dev/null
if kmake "$WT" "$O" dt_binding_check DT_SCHEMA_FILES=opp/allwinner,sun50i-h6-operating-points.yaml \
	>"$OUTDIR/$S.dbc" 2>&1; then
	echo "  ok  dt_binding_check $Y"
else
	cat "$OUTDIR/$S.dbc"; bad "dt_binding_check $Y"
fi
# control: an H616 table with turbo-mode + opp-suspend
python3 -I - "$WT/$DTS/sun50i-h616-cpu-opp.dtsi" <<-'EOF'
	import sys
	p = sys.argv[1]; s = open(p).read()
	for opp, prop in (('opp-1512000000 {', 'turbo-mode;'), ('opp-480000000 {', 'opp-suspend;')):
	    assert s.count(opp) == 1, opp
	    s = s.replace(opp, opp + '\n\t\t\t' + prop)
	open(p, 'w').write(s)
	EOF
B=allwinner/sun50i-h618-orangepi-zero3.dtb
after=$(kmake "$WT" "$O" CHECK_DTBS=y "$B" 2>&1 | grep -c 'turbo-mode\|opp-suspend' || true)
git -C "$WT" checkout -q HEAD~1 -- "$Y"
before=$(kmake "$WT" "$O" CHECK_DTBS=y "$B" 2>&1 | grep -c 'turbo-mode\|opp-suspend' || true)
git -C "$WT" checkout -q -f HEAD -- "$Y" "$DTS/sun50i-h616-cpu-opp.dtsi"
if [ "$before" -gt 0 ] && [ "$after" -eq 0 ]; then
	echo "  ok  control: $B with turbo-mode/opp-suspend: $before warnings without the patch, 0 with it"
else
	bad "control: before=$before after=$after (expected >0 and 0)"
fi
"$WT/scripts/get_maintainer.pl" --nogit "${P[@]}" >"$OUTDIR/$S.maintainers" 2>/dev/null
echo "  maintainers: $OUTDIR/$S.maintainers ($(wc -l <"$OUTDIR/$S.maintainers") lines)"
todos "${P[@]}"

log "Summary"
if [ "$FAILS" -ne 0 ]; then
	echo "$FAILS check(s) failed."
	exit 1
fi
echo "All upstream checks passed. Nothing was sent; sending is Dale's decision (patches/outgoing/README.md)."
