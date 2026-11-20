# SPDX-License-Identifier: GPL-2.0-only
# ReduxOS player session. Runs only on the physical console (tty1); an SSH or other login just
# gets a shell. RetroArch drives KMS/GBM directly (no desktop). On exit, drop to a shell so the
# device is recoverable rather than looping.
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$RETROARCH_RUNNING" ]; then
    export RETROARCH_RUNNING=1
    # Quiet the console cursor/blanking while the frontend owns the screen.
    setterm -cursor off 2>/dev/null || true
    retroarch --verbose 2>> "$HOME/retroarch-boot.log"
    setterm -cursor on 2>/dev/null || true
fi
