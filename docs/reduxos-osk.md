# ReduxOS fly-out on-screen keyboard (R32)

**Status:** desk only. Built into the image and checked at build time; **not run on hardware** — the
whole path needs the Mali GLES/KMS stack and the real input devices, which QEMU doesn't provide.

Dale's request: a "fly out" OSK for **keyboard apps** (terminal, file manager, etc.) — **not**
RetroArch, which already has its own built-in OSK and is left untouched.

## Why a compositor is involved
RetroArch runs on bare KMS/GBM (one DRM master). You can't composite a second overlay (a keyboard)
on top of an arbitrary bare-KMS app, which is why the stock OS used hardware `disp2` overlay layers
(KR's `osklib`, R26–R28, is for that stock path). On our mainline stack the clean, supported way to
float a keyboard over an app is a tiny Wayland compositor:

- **cage** — a wlroots single-app kiosk compositor. Runs one app fullscreen on the Mali.
- **wvkbd** (`wvkbd-mobintl`) — a wlroots layer-shell keyboard that **flies out from the bottom edge**
  and types into the focused app via the virtual-keyboard protocol.
- **foot** — a small Wayland terminal (the thing you type *into* for a shell).
- **mc** — Midnight Commander, the file manager.

RetroArch is never started this way, so its own OSK and its bare-KMS path are unchanged.

## Driving it without a touchscreen
The RG34XX-SP has no touch, and wvkbd is pointer/touch-driven. The bridge **`redux-osk-pointer`**
(source `tools/redux-osk-pointer.c`, cross-built by `tools/build-osk-pointer.sh`, injected at image
build like the PS1 core — not committed) reads the analog stick (`adc-joystick` ABS_X/ABS_Y) and face
buttons and emits a relative pointer + clicks through **uinput**, which libinput under cage sees as a
normal mouse:

| Input | Action |
|---|---|
| Left stick | move the cursor |
| A (BTN_SOUTH) | left click (press a key / select) |
| B (BTN_EAST) | right click |

A Bluetooth or USB keyboard/mouse also works and bypasses all of this.

## How a user gets it
| Command | What it does |
|---|---|
| `redux-kbapp <cmd>` | run **any** keyboard app under cage + wvkbd + the pointer bridge |
| `redux-shell` | an OSK terminal (`foot` → bash) — the on-device shell |
| `redux-files` | an OSK file manager (`foot` → `mc`) |

When RetroArch is closed on the console, the player session opens `redux-shell` automatically (if
`/dev/dri/card0` is present), so the device is usable with just the gamepad; it falls back to a plain
console shell if the graphics stack isn't up.

## Build-time checks (`check-hardening.sh`)
Verifies cage, wvkbd and foot are installed, the three launchers exist, and the injected
`redux-osk-pointer` is a real aarch64 binary. These prove the pieces are present; they do **not**
prove the OSK renders or that the stick drives the cursor — that is a **hardware-test item (R35)**.

## Known limits / to validate on hardware (R35)
1. wvkbd flyout render + layer-shell over cage on the Mali (Panfrost GLES) — unverified.
2. `redux-osk-pointer` stick range/centre (assumes 0–4095, centre ~2048 from the DT) and feel
   (deadzone, acceleration) — untuned, untested.
3. Whether to prefer a GUI file manager under cage instead of `mc` in a terminal — ergonomics call
   once it's on a screen.
4. Letting the OSK pointer also be driven by the D-pad, and a button to toggle wvkbd hidden/shown.
