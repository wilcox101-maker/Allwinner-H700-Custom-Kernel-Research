# ReduxOS frontend — RetroArch on KMS (R32)

**Status:** desk only. Built and QEMU-smoke-tested; not yet run on hardware. Everything touching the
panel, codec and pads needs a device pass (blocked until Redux v0.5, AGENTS.md §Every session).

The beta boots straight into RetroArch as an unprivileged **`player`** user on tty1. No desktop, no
X, no Wayland — RetroArch drives KMS/GBM directly on the Mali-G31 (Panfrost, GLES).

## Layer map

| Concern | Where | Notes |
|---|---|---|
| Autologin | `getty@tty1.service.d/60-reduxos-autologin.conf` | `agetty --autologin player` on tty1 only; tty2–6 keep the normal `dale` login |
| Session launch | `/etc/skel-player/.bash_profile` → `/home/player/.bash_profile` | Runs RetroArch only on `/dev/tty1`; drops to a shell on exit (recoverable, no loop) |
| Frontend config | `/etc/retroarch.cfg` | `gl` + `kms`, `udev` input, `alsa` audio, `rgui` menu, Debian core/info/asset paths |
| Pad mapping | `/etc/retroarch/autoconfig/ReduxOS_RG34XXSP.cfg` | Matches input name `gpio-keys-gamepad` (no VID/PID) |
| Audio routing | `/etc/asound.conf` | `default` → codec `Codec` via dmix + a software master `PCM` (softvol) |
| Mixer baseline | `reduxos-audio-init.service` → `/usr/local/sbin/reduxos-audio-init.sh` | Sets hardware routing/levels once at boot (desk-only values) |
| Volume keys | triggerhappy `triggers.d/reduxos-volume.conf` → `reduxos-vol.sh` | Nudges the `PCM` softvol at the OS level |

### Why `player` and not `dale`
`dale` is the admin account (sudo group, password `redux` **expired** → must be changed at first
login). An expired password blocks autologin. `player` is a separate account with a **locked**
password (cannot log in over SSH or other VTs) and **no sudo**, in `video render input audio` only —
least privilege for the thing that faces the player. `check-hardening.sh` enforces all three
properties (exists / locked / not-sudo) at build time.

## Button-index derivation (not guessed)

RetroArch's udev joypad driver (`input/drivers_joypad/udev_joypad.c`, v1.18) assigns button indices
by scanning evdev key codes in ascending order over `BTN_MISC..KEY_MAX` (the `KEY_UP..KEY_DOWN`
range it scans first holds only keyboard arrows, absent on this pad). Applying that scan order to the
kernel keycodes the `gpio-keys-gamepad` node emits (upstream RG35XX-2024 DT + our THUMBL/THUMBR):

| idx | keycode | value | pad face |
|----|---------|-------|----------|
| 0 | BTN_SOUTH | 0x130 | B |
| 1 | BTN_EAST | 0x131 | A |
| 2 | BTN_NORTH | 0x133 | X |
| 3 | BTN_WEST | 0x134 | Y |
| 4 | BTN_TL | 0x136 | L1 |
| 5 | BTN_TR | 0x137 | R1 |
| 6 | BTN_TL2 | 0x138 | L2 |
| 7 | BTN_TR2 | 0x139 | R2 |
| 8 | BTN_SELECT | 0x13a | Select |
| 9 | BTN_START | 0x13b | Start |
| 10 | BTN_MODE | 0x13c | Menu (RetroArch menu toggle) |
| 11 | BTN_THUMBL | 0x13d | L3 |
| 12 | BTN_THUMBR | 0x13e | R3 |
| 13 | BTN_DPAD_UP | 0x220 | D-up |
| 14 | BTN_DPAD_DOWN | 0x221 | D-down |
| 15 | BTN_DPAD_LEFT | 0x222 | D-left |
| 16 | BTN_DPAD_RIGHT | 0x223 | D-right |

RetroPad binds are written against these indices in the autoconfig. **Confirm on hardware** — if the
kernel ever reorders keycodes the indices shift.

## Known gaps (for the Manager/Owner to prioritise)

1. **Analog sticks are a separate input device.** The dual sticks are an `adc-joystick` node
   (`ABS_X/Y/RX/RY`), not part of `gpio-keys-gamepad`. RetroArch's udev driver binds one pad per
   device, so the sticks land on pad #2 and are **not** merged into player 1's analog by default.
   D-pad + all buttons work; stick-as-P1-analog needs a userspace combiner (e.g. a small uinput
   merger) — deferred to a later build, not in this beta. Desk-noted, needs hardware to validate the
   chosen fix.
2. **No Genesis/Mega Drive or SNES-dedicated cores.** `genesisplusgx`, `picodrive` and `snes9x` are
   non-commercial-licensed and are **not** in Ubuntu main/universe, so they are not in the image.
   SNES runs on `bsnes-mercury-performance` (DFSG-main). Adding the non-free cores would mean
   building from source and shipping them — a licensing call for Dale, not a desk default.
3. **PS1 is only `beetle-psx`.** That core (Mednafen PSX, 2015 packaged build) is accurate but heavy
   on a Cortex-A53. The fast path is `pcsx_rearmed` (GPL-2.0, from libretro's GitHub), which is **not**
   packaged in noble. Building it from source in this session was **blocked by a tool-permission
   check** (see the results doc); left for Dale to allow or decline. Until then PS1 playability on
   hardware is unverified.
4. **Codec mixer values are desk-only.** `reduxos-audio-init.sh` uses the mainline control names
   (R21) with sensible starting levels, but routing/levels are untuned and the control set must be
   confirmed on the device. The volume keys may also be grabbed by RetroArch while it is in front
   (it would then use its own audio-volume bind) — a hardware-test item.

## Cores shipped (all DFSG-main in noble)

mgba (GB/GBC/GBA), gambatte (GB/GBC), nestopia (NES), bsnes-mercury-performance (SNES),
beetle-pce-fast (PC Engine), beetle-wswan (WonderSwan), beetle-vb (Virtual Boy),
beetle-psx (PS1, slow), desmume (NDS). Core info + XMB assets installed for metadata and an optional
richer menu.
