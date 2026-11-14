#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# R9 §3: collect the corresponding source for one image built by image/build-image.sh, so the image
# can be published together with its source (GPL-2.0 §3(a), and the equivalent terms of the other
# copyleft licences in the image). See docs/r9-licensing-redistribution.md.
#
# usage: image/release-sources.sh <OUT>/<NAME>.sources.tsv
#   The .sources.tsv (source package, version) is written by build-image.sh next to the image.
#   LINUX_GIT=<git tree that has LINUX_SHA>  default: $REPO/.work/linux (scripts/workbench.sh)
#   UBOOT_SRC=<u-boot source tarball>        required when the image carries u-boot (NAME has -uboot)
#   MIRROR=…                                 default https://ports.ubuntu.com/ubuntu-ports
#   ALLOW_DIRTY=1                            accept uncommitted changes in this repo (test builds only)
#
# Writes <OUT>/<NAME>.sources/:
#   ubuntu/        .dsc + tarballs of every Ubuntu source package the image's binaries come from
#   ours/          this repo at HEAD (patches, kernel config, DTs, image builder, overlays);
#                  pristine Linux at the pinned commit; u-boot source if the image has u-boot
#   SOURCES.tsv    source, version, where each was fetched from
#   README.txt     what this is and how to rebuild
#   SHA256SUMS
# Fetches from the Ubuntu archive first; a version the archive has already superseded is fetched
# from Launchpad's librarian, which keeps every published version. Read-only on the image; needs
# apt-get, curl, git, xz. Runs as a normal user.
set -euo pipefail
TSV=$(readlink -f "${1:?usage: $0 <OUT>/<NAME>.sources.tsv}")
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
OUTDIR=$(dirname "$TSV"); NAME=$(basename "$TSV" .sources.tsv)
DEST=$OUTDIR/$NAME.sources
MIRROR=${MIRROR:-https://ports.ubuntu.com/ubuntu-ports}; SUITE=noble
LINUX_GIT=${LINUX_GIT:-$REPO/.work/linux}
LINUX_SHA=$(sed -n 's/^LINUX_SHA=\([0-9a-f]\{40\}\).*/\1/p' "$REPO/scripts/workbench.sh")
OWN_SOURCES=" linux-upstream "      # built by us from this repo (scripts/build-kernel.sh): see ours/
log() { printf '== %s\n' "$*"; }
die() { printf 'ERROR %s\n' "$*" >&2; exit 1; }

[ -f "$TSV" ] || die "no $TSV (run image/build-image.sh first)"
[ -n "$LINUX_SHA" ] || die "could not read LINUX_SHA from scripts/workbench.sh"
if [ -n "$(git -C "$REPO" status --porcelain --untracked-files=no)" ] && [ "${ALLOW_DIRTY:-0}" != 1 ]; then
	die "repo has uncommitted changes; the bundle must match what the image was built from (ALLOW_DIRTY=1 for tests)"
fi
case $NAME in *-private*) die "$NAME is a private image (stock-derived panel firmware, build-image.sh PANEL_FW): it must not be published" ;; esac
case $NAME in *-uboot*) [ -f "${UBOOT_SRC:-}" ] || die "image carries u-boot: set UBOOT_SRC=<u-boot source tarball>" ;; esac

mkdir -p "$DEST/ubuntu" "$DEST/ours"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
: > "$DEST/SOURCES.tsv"

log "1. Ubuntu source packages ($(wc -l < "$TSV") in $(basename "$TSV"))"
A=$WORK/apt; mkdir -p "$A/lists/partial" "$A/cache/archives/partial"
for s in $SUITE $SUITE-updates $SUITE-security; do echo "deb-src $MIRROR $s main universe"; done > "$A/sources.list"
APT=(-o Dir::Etc::SourceList="$A/sources.list" -o Dir::Etc::SourceParts=/nonexistent
     -o Dir::State::Lists="$A/lists" -o Dir::Cache="$A/cache" -o Dir::State::status=/dev/null
     -o Debug::NoLocking=1 -o APT::Sandbox::User="$(id -un)" -qq)
apt-get "${APT[@]}" update

# Launchpad keeps every version ever published; files are listed in the .dsc.
from_launchpad() {   # <src> <version>
	local src=$1 v=${2#*:} base dsc f
	base=https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/$src/$2   # path keeps the epoch, file names drop it
	dsc=${src}_$v.dsc
	curl -fsSL -o "$dsc" "$base/$dsc" || return 1
	awk '/^Checksums-Sha256:/ {on=1; next} /^[^ ]/ {on=0} on && NF == 3 {print $1 "  " $3}' "$dsc" > "$WORK/sums"
	[ -s "$WORK/sums" ] || return 1
	while read -r _ f; do curl -fsSL -o "$f" "$base/$f" || return 1; done < "$WORK/sums"
	sha256sum --quiet -c "$WORK/sums"
}

missing=0; n=0
cd "$DEST/ubuntu"
while IFS=$'\t' read -r src ver; do
	[ -n "$src" ] || continue
	case $OWN_SOURCES in *" $src "*) printf '%s\t%s\tours/ (built from this repo)\n' "$src" "$ver" >> "$DEST/SOURCES.tsv"; continue ;; esac
	n=$((n + 1))
	if apt-get "${APT[@]}" source --download-only "$src=$ver" >/dev/null 2>&1; then where=archive
	elif from_launchpad "$src" "$ver"; then where=launchpad
	else where=MISSING; missing=$((missing + 1)); echo "   could not fetch $src $ver" >&2; fi
	printf '%s\t%s\t%s\n' "$src" "$ver" "$where" >> "$DEST/SOURCES.tsv"
done < "$TSV"
cd - >/dev/null
log "   $n packages: $(grep -c $'\tarchive$' "$DEST/SOURCES.tsv" || true) from the archive, $(grep -c $'\tlaunchpad$' "$DEST/SOURCES.tsv" || true) from Launchpad, $missing missing"

log "2. our sources"
HEAD=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" archive --format=tar --prefix="h700-research-${HEAD:0:12}/" HEAD | xz -T0 -6 > "$DEST/ours/h700-research-${HEAD:0:12}.tar.xz"
printf 'h700-research\t%s\tours/ (this repo, git HEAD)\n' "$HEAD" >> "$DEST/SOURCES.tsv"
if git -C "$LINUX_GIT" cat-file -e "$LINUX_SHA^{commit}" 2>/dev/null; then
	git -C "$LINUX_GIT" archive --format=tar --prefix="linux-${LINUX_SHA:0:12}/" "$LINUX_SHA" | xz -T0 -6 > "$DEST/ours/linux-${LINUX_SHA:0:12}.tar.xz"
	printf 'linux\t%s\tours/ (pristine upstream; patches/linux + config in the repo tarball)\n' "$LINUX_SHA" >> "$DEST/SOURCES.tsv"
else
	die "LINUX_GIT=$LINUX_GIT does not contain $LINUX_SHA (run scripts/workbench.sh)"
fi
if [ -n "${UBOOT_SRC:-}" ]; then
	cp "$UBOOT_SRC" "$DEST/ours/"
	printf 'u-boot\t%s\tours/\n' "$(basename "$UBOOT_SRC")" >> "$DEST/SOURCES.tsv"
fi

log "3. README and checksums"
cat > "$DEST/README.txt" <<EOF
Source for $NAME.img

This directory holds the complete corresponding source for the binaries in the image.

ubuntu/  Unmodified Ubuntu 24.04 (noble) source packages, exactly the versions installed in the
         image. Unpack one with: dpkg-source -x <package>_<version>.dsc
ours/    h700-research-${HEAD:0:12}.tar.xz: the build repository at commit $HEAD
           (kernel patches and config, device trees, image builder, overlays; GPL-2.0-only)
         linux-${LINUX_SHA:0:12}.tar.xz: Linux at commit $LINUX_SHA, before our patches.
           Rebuild the kernel package: unpack both, then in the repo run
           WORK=<dir> scripts/workbench.sh and scripts/build-kernel.sh --build
           (workbench.sh fetches the same commit; this tarball is the offline copy).
$( [ -n "${UBOOT_SRC:-}" ] && echo "         $(basename "$UBOOT_SRC"): u-boot source (with our patches) used for the bootloader.")
SOURCES.tsv  every source package, its version, and where it was fetched from.

Firmware under /usr/lib/firmware comes from Ubuntu's linux-firmware packages; it is distributed
under its own licences (see /usr/share/doc/<package>/copyright in the image) and has no source.

This image is an unofficial build. It is not affiliated with or endorsed by Anbernic or Canonical.
EOF
(cd "$DEST" && find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' sha256sum > SHA256SUMS)
log "done: $DEST ($(du -sh "$DEST" | cut -f1))"
[ "$missing" = 0 ] || die "$missing source packages could not be fetched (see SOURCES.tsv); do not publish the image"
