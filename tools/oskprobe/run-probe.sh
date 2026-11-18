#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Run sheet driver for the OSK probe session (Redux OSK plan D5, checks K24-K28). KR-1, 2026-11-18.
# Copy oskprobe and this script to /tmp on the device over SSH and run them from /tmp only.
# Writes only to /tmp/oskprobe-logs (RAM). Every exit path runs `oskprobe off` (clears disp0 ch3/l0).
#
# usage: sh /tmp/run-probe.sh STEP [LABEL] [SECONDS]
#   K24 LABEL        layer dump while app LABEL runs (menu, sdl2port, retroarch, video, drastic)
#   K25              device nodes and input devices
#   K26 LABEL [S]    test bar for S seconds (default 60) over app LABEL; do lid, sleep, Menu+Vol, HDMI meanwhile
#   K26-kill         bar in the background, kill -9 after 5 s (bar should stay), then off (bar should go)
#   K27-keys [S]     key codes for S seconds (default 30): Menu+Select, Menu+X, L3, R3, Menu alone
#   K27-type LABEL   types "redux" into app LABEL after 5 s
#   K28 LABEL        grab test while app LABEL runs
#   off              clear the test layer
#   logs             list the saved logs
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
P="$DIR/oskprobe"
LOGS=/tmp/oskprobe-logs

case "$DIR" in
/tmp|/tmp/*) ;;
*) echo "run from /tmp only (found $DIR)"; exit 2 ;;
esac
[ -x "$P" ] || { echo "missing $P (chmod +x?)"; exit 2; }

cleanup() { "$P" off >/dev/null 2>&1; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP

mkdir -p "$LOGS"
step=${1:-}
label=${2:-none}
log="$LOGS/${step}-${label}.txt"

header() {
	echo "== $step label=$label $(date '+%Y-%m-%d %H:%M:%S') =="
	uname -a
	"$P" version
	sha256sum "$P" 2>/dev/null || true
	echo "nds_esckey=$(cat /sys/class/power_supply/axp2202-battery/nds_esckey 2>/dev/null || echo ?)"
}

run() { { header; "$@"; echo "== exit $? =="; } 2>&1 | tee "$log"; echo "saved: $log"; }

case "$step" in
K24) run "$P" layers ;;
K25) log="$LOGS/K25.txt"; run "$P" nodes ;;
K26) run "$P" bar "${3:-60}" ;;
K26-kill)
	log="$LOGS/K26-kill.txt"
	{
		header
		"$P" bar 60 &
		pid=$!
		sleep 5
		echo "kill -9 $pid"
		kill -9 "$pid"
		wait "$pid" 2>/dev/null
		echo "probe killed: is the bar STILL on screen? (expected: yes). Press Enter."
		read -r _
		"$P" off
		echo "after off: is the bar GONE? (expected: yes)"
	} 2>&1 | tee "$log"
	echo "saved: $log" ;;
K27-keys) log="$LOGS/K27-keys.txt"; run "$P" keys "${2:-30}" ;;
K27-type) run "$P" type redux ;;
K28) run "$P" grab ;;
off) "$P" off ;;
logs) ls -l "$LOGS" ;;
*) sed -n '2,20p' "$0"; exit 2 ;;
esac
