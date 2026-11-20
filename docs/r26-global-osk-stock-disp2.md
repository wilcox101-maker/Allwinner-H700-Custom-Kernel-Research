# R26: global on-screen keyboard (OSK) over any app, on the stock kernel (desk only)

> **Update 2026-11-20:** reviewed in [`dr-osk-desk-checks-2026-11-18.md`](dr-osk-desk-checks-2026-11-18.md): the verdict stands; the stock video player uses channel 1 (not channel 0); Menu + X is a RetroArch hotkey, and Redux has since chosen **Menu + Select** with no OSK while RetroArch runs ([`dr-review-2026-11-20.md`](dr-review-2026-11-20.md)).

Date: 2026-11-18. Kernel Research, for the Redux Manager (letter `FROM-REDUX-MANAGER-2026-11-18-a`, pasted in chat;
Dale said yes at 10:38). Manager advice, not a command. Goal: a background OSK daemon that Redux starts at boot. An app,
a Settings switch, a Stock OS Mod APPS entry or a Redux `extras.ini` `app =` entry only turns it on and off. Input comes
from an evdev hotkey chord, with `EVIOCGRAB` while the OSK is open and keys injected through `/dev/uinput`. The OSK is
drawn on its own sunxi disp2 layer (`/dev/disp`), not on fb0. Track: stock kernel (Beta).

**Nothing here has run on a device.** Tags: **[G]** static analysis of a stock binary (kernel `4.9.170 #9` `Image` with
kallsyms, `dmenu.bin`, `portsCtrl.dge`, `ndsCtrl.dge`, RetroArch, DraStic, all from V1.0.6), **[D]** stock DT / config /
strings, **[N]** no public source we know of (Dale, 2026-11-15). **BSP** = Allwinner's public 4.9 disp2 source as
published by Orange Pi (`orangepi-xunlong/linux-orangepi`, branch `orange-pi-4.9-sun50iw9`, `0cd0547ea405`). It is the
same driver family and version string as stock, but stock's source is not published, so a BSP line is an
**inference** unless a [G] line backs it. Stock files were only read, never written or committed. No decompiled code is
reproduced here.

## Answer (5 lines)
1. **Yes, on the desk evidence.** fb0 (and so every Mali-EGL, SDL and fbdev app) sits on **disp0 channel 1, layer 0**.
   A second process can put an ARGB8888 layer with per-pixel alpha on **channel 3 (or 2), layer 0, zorder ≥ 21**, using
   `DISP_LAYER_SET_CONFIG2` (0x49) with an ION dma-buf. That call changes only the layers it lists.
2. **Mali fbdev EGL apps and SDL fbdev apps land on the same layer** (ch1/l0). The stock launcher also draws its own
   frames on that layer through `SET_CONFIG2` (zorder 20) [G][N]. Keep the OSK off ch1, and off ch0 (the only video
   channel) until K24 shows what the video player uses.
3. Hotkeys: Menu + {R1, L1, R2, L2, Y, A, Start, D-pad L/R, Vol±} are taken in games, and Menu + Start also quits DraStic.
   **Menu + Select** (held about 0.5 s) or **Menu + X** look free; Menu-led chords may still open RetroArch's menu (K27).
   No stock binary we scanned uses `EVIOCGRAB`.
4. The main risks are: a layer that **stays up if the daemon dies** (`disp_release` does nothing [G]); a **race between two
   processes using `SET_CONFIG2` at once** (the kernel copies into one global buffer without a lock [BSP]); and wrong
   size and position after an **HDMI switch**. Brightness ioctls do not touch layers. Suspend should keep the layer (K26).
5. On mainline the same design becomes a client of a compositor (layer-shell surface + uinput or virtual-keyboard),
   not a second process taking a DRM plane.

## 1. Can a second process show an alpha-blended layer above the app?

### 1.1 Display-engine layout on stock
| Item | Value | Evidence |
|---|---|---|
| Channel config mode | `chn_cfg_mode = <0x1>` in the stock DT `disp@01000000` | [D] `REA\BootImage\dtb.dts` |
| Mode selection | `de_feat_init_config`: mode 0 → `de330_mode0_features`, **1 → `de330_mode1_features`**, 2 → mode2 | [G] `0xffffff8008425c3c` |
| disp0 (screen 0: LCD and, after `DISP_DEVICE_SWITCH`, HDMI) | **4 channels**: ch0 = video (VI), **ch1, ch2, ch3 = UI**; 4 layers each (16 in all) | [G] `de330_mode1_num_chns` = {4, 2}, `num_vi_chns` = {1, 2}, `chn_id_lut` = {0, 6, 7, 8 \| 2, 1}; layer counts from BSP `de331_feat.c` |
| disp1 (screen 1, TV output) | 2 video channels | [G] same tables |
| UI-channel scaling | supported on all 4 disp0 channels | BSP `de331_feat.c` mode1 `is_support_scale` |
| fb0 binding | **channel 1, layer 0** | [G] `display_fb_request` (`0xffffff80083fd60c`) stores 1 and 0 into `layer_hdl[fb][0/1]`; BSP `dev_fb.c` |
| fb0 pan (`FBIOPAN_DISPLAY`) | get, modify crop, set: on **ch1/l0 only**. Zorder and alpha stay as last set | BSP `dev_fb.c` pan path |
| `/dev/disp` release | **does nothing** (returns 0) | [G] `disp_release` `0xffffff80083f4a0c` = `mov w0,#0; ret` |

### 1.2 What `SET_CONFIG2` does
- The ioctl argument is an array of 4 unsigned longs: **{screen, pointer to config2 array, count, 0}**. The kernel copies
  `count × sizeof(config2)` bytes, zeroes `info` for any entry with `enable = 0` and passes the list to the manager
  [BSP `dev_disp.c`]. The stock dispatcher has the 0x49 case [G] (W3.1 table 3).
- The manager updates **only the layers in the list**. Every other enabled layer keeps its configuration. A dma-buf is
  unmapped only when no enabled layer still uses its address [BSP `disp_manager.c`, `disp_mgr_set_layer_config2`,
  `disp_mgr_is_address_using`]. So the OSK's buffer survives the app's (or the launcher's) commits.
- Blending order: the mixer sorts **channels** by the lowest zorder among their enabled layers and stacks them from
  lowest to highest [BSP `de_rtmx.c` `de_rtmx_chn_zorder` and pipe routing]. A channel whose layer has a higher zorder
  than ch1/l0 is drawn above it.
- The header documents zorder as "0 to max layer number" (16 here). The stock launcher sets **20** on ch1/l0 and it
  works [G], and the code only compares u8 values [BSP]. The OSK must be above 20. **Proposed: 30** (checked on the
  device in K26).
- The layer buffer is a **dma-buf fd** (`fb.fd`), not a physical address. Stock gets one from ION: the launcher allocates
  with **heap mask 1** (heap id 0 = `sys_user`, `ion_system`), flags 3, 4 KiB alignment, then `ION_IOC_SHARE` [G]
  (`dmenu.bin` 0x137ec → 0x19928; stock DT `ion` node [D]; ION ioctl numbers in `stock-re-boot-and-userspace.md` §6).
  disp0 sits behind the IOMMU (`iommus` in the DT [D]), so a system-heap buffer works the way the launcher uses it.

### 1.3 The stock launcher's own call (template) [G][N]
`dmenu.bin` 0x13844 builds one config2 per frame and commits it between `DISP_SHADOW_PROTECT` on/off (0x0D), rotating
over 5 ION buffers. Field values (offsets are the same in 32-bit and 64-bit builds; see below):

| Field (offset) | Launcher value | OSK proposal |
|---|---|---|
| `info.mode` (0x00) | 0 = `LAYER_MODE_BUFFER` | 0 |
| `info.zorder` (0x04, u8) | **20** | **30** |
| `info.alpha_mode` (0x05) | 0 = pixel alpha | 0 (per-pixel), or 2 (pixel × global) to fade the whole OSK |
| `info.alpha_value` (0x06) | 0xff | 0xff (used with modes 1 and 2) |
| `info.screen_win` (0x08: x, y, w, h) | 0, 0, `DISP_GET_SCN_WIDTH` (0x07), `…_HEIGHT` (0x08) | OSK rectangle, e.g. bottom 720 × 200, worked out from 0x07/0x08 |
| `info.fb.fd` (0x20) | ION dma-buf fd | own ION dma-buf fd |
| `info.fb.size[0]` (0x24) | buffer w × h | OSK buffer w × h |
| `info.fb.format` (0x48) | from the buffer record | **0 = `DISP_FORMAT_ARGB_8888`** (`DISP_FORMAT_RGBA_8888` = 2 also exists) |
| `info.fb.color_space` (0x4C) | 0x101 if width ≥ 720 else 0x104 | as the launcher (does nothing for RGB) |
| `info.fb.pre_multiply` (0x54) | 0 | 1 if the renderer writes premultiplied ARGB (sets the pipe's premultiply control [BSP]) |
| `info.fb.crop` (0x58, 4 × s64, 32.32 fixed point) | 0, 0, w << 32, h << 32 | the same |
| `enable` (0xD0) | 1 | 1 to show; 0 to hide |
| `channel` (0xD4) | **1** | **3** (2 is the fallback) |
| `layer_id` (0xD8) | 0 | 0 |

- **Size:** `struct disp_layer_config2` is **224 bytes** (`info` 208), the same for `aarch64-linux-gnu` and
  `armv7a-linux-gnueabihf`. Checked with `_Static_assert` against the BSP header using clang `-ffreestanding`. It also
  matches the launcher's 32-bit offsets. The daemon should carry the same assertions, and its header must state where
  it comes from (BSP `include/video/sunxi_display2.h`, GPL-2.0). Build the daemon as aarch64 to stay off the 32-bit
  compat path.
- **Hide:** the same call with `enable = 0` on ch3/l0. **Don't touch ch1**: it belongs to fb0 and to the launcher.
- The launcher also **turns ch1/l0 off** (`enable = 0`, ch1, l0) about 20 ms after each `DISP_DEVICE_SWITCH` (0x0F),
  LCD ↔ HDMI (screen 0, type 4 mode 5 = 720p60, or type 1) [G][N] (`dmenu.bin` 0x13a94, 0x136c0).
- Updating the OSK image: one buffer is enough if the daemon redraws only between commits. To avoid tearing, use two
  buffers and swap `fb.fd`. Commit only when the OSK changes, never every frame (see §4, race).

## 2. Do Mali EGL apps and SDL fbdev apps use the same channel? Is any layer reserved?
| Stack (stock V1.0.6) | Output path | Evidence |
|---|---|---|
| `libmali.so.0.20.0` (64-bit `/usr/lib`, 32-bit `/usr/lib32`) | fbdev window system only: `mali_egl_winsys_fbdev.c`, `/dev/fb`, `/dev/ion`; no `/dev/disp` string | [D] strings |
| SDL2 2.0.12 (64- and 32-bit) and SDL2 2.28.5 (`/usr/lib/aarch64-linux-gnu`) | `MALI_*` video driver, `/dev/fb0`; evdev input (`SDL_EVDEV_*`) | [D] strings |
| SDL 1.2.11.4 (appfs, used by the launcher and the `.dge` emulators) | `fbcon` driver, `/dev/fb0`, `SDL_FBDEV`; keyboard from `/dev/tty*`; joystick `/dev/input/event%d` | [D] strings |
| RetroArch (stock `retroarch.cfg`) | `video_driver = "gl"` (Mali fbdev EGL), `input_driver = "udev"`, `input_joypad_driver = "udev"` | [D] `/.config/retroarch/retroarch.cfg` |
| Launcher `dmenu.bin` | its own ION frames on **ch1/l0** through `SET_CONFIG2` (§1.3), and `/dev/fb0` cleared at start | [G][N] |

So **every fbdev, Mali-EGL and SDL app ends up on ch1/l0**, and the launcher replaces that layer with its own buffers
while it runs. Reserved or likely in use:
- **ch1/l0**: fb0 and the launcher.
- **ch0**: the only video channel. The stock video player (`xplayerdemo2`, `vp.dge` via Allwinner's libcdx/Cedar) most
  likely puts YUV video there. *Not confirmed* (K24).
- **disp1**: the TV screen; not used on the SP's LCD.
- **ch2 and ch3**: nothing in the stock binaries we examined puts a layer there. Proposed OSK channel: **ch3**.

An app that calls `/dev/disp` itself (the video player, or a port that copies the launcher's method) could still pick
ch2 or ch3. K24 records every enabled layer, per app, from the stock debug dump.

## 3. Hotkey conflicts
### 3.1 Combinations already in use
| Where | Combination → action | Source |
|---|---|---|
| Launcher | Vol± = volume; **Menu + Vol±** = brightness; Menu tap = a UI page; power ≥ 100 ms = sleep; power hold 2 s = power off; Start + Select = leave settings pages | [G] `stock-re-boot-and-userspace.md` §1.3 |
| In game (`portsCtrl` / `ndsCtrl`) | Vol± = volume; Menu + Vol± = brightness; power > 2 s = power off; DraStic: **Menu + Start** = quit | [G] §1.3 |
| In game (Stock / MOD defaults) | Menu = RetroArch quick menu; Menu + **R1** save state, **L1** load, **R2** fast-forward, **L2** slow motion, **Y** FPS, **A** screenshot, **Start** quit, **D-pad L/R** state slot, **Vol±** brightness | [D] Dale's `Anbernic_StockOS_and_MOD_Manual.docx` (not device-checked) |
| RetroArch `retroarch.cfg` | hotkey-enable button 8, exit button 7, `input_menu_toggle_gamepad_combo = "7"`, keyboard **F1** = menu, **Esc** = quit the emulator | [D] stock cfg (button numbers map to keys through `ANBERNIC-keys.cfg`, not read here) |
| PortMaster `gptokeyb` | kill mode (`-k` / `-sudokill`) with a hotkey (`HOTKEY` env or `-hotkey`) | source `PortsMaster/gptokeyb` `5b1284e1`, `src/gptokeyb.cpp` (exact kill combo not traced) |
| SP layout | Select and Start sit on top of each other: Select + Start is easy to hit by accident | [D] manual |

**Free candidates, best first:** (1) **Menu + Select, held ~500 ms**; (2) **Menu + X**; (3) Menu + B; (4) L3 + R3, if the
SP reports them (Redux 11-17 data mentions an L3/R3 report; check in K27). Treat Menu-led chords as "maybe": RetroArch
uses Menu to enable hotkeys and may open its menu as soon as Menu goes down. The daemon should act on the **second**
key while Menu is held, and K27 checks what RetroArch does.

### 3.2 `nds_esckey` gating
The launcher writes `nds_esckey` (0 in the launcher, 1 for ports / case-29 apps, 3 for the video player), and
`portsCtrl`/`ndsCtrl` run only while it is 1 [G]. They read the keypad **without** a grab. So they also see the OSK chord
keys, but neither of them uses Menu + Select or Menu + X. **The daemon must not write `nds_esckey`**: it can read it to
know the app class. While the OSK holds its grab, these daemons see no keypad events, so Menu + Vol brightness and
volume stop working until the OSK closes. The power key (event0, `axp2202-pek`, a separate device) is not grabbed and
keeps working.

### 3.3 Who grabs the pad
| Program | `EVIOCGRAB` (0x40044590)? | Evidence |
|---|---|---|
| `dmenu.bin` | no | [G] W3.5 §6; constant scan here: 0 |
| `portsCtrl.dge`, `ndsCtrl.dge` | no | [G] constant scan (Thumb `movw #0x4590`): 0 |
| RetroArch 1.20 (stock `retroarch64`, `retroarch`) | no | [G] constant scan: 64-bit `movz #0x4590` = 0, while the positive control `evtest` (which has `--grab`) = 3; the 32-bit scan has no positive control. RetroArch `6b94b824` `udev_input.c`, `udev_joypad.c`, `linuxraw_*`: none |
| DraStic (stock 32-bit) | no | [G] constant scan, no positive control |
| SDL2 (`SDL_evdev.c`, `SDL_sysjoystick.c`, `SDL2` branch `fe30456e`) | no | source |
| `gptokeyb` (`src/gptokeyb.cpp` `5b1284e1`) | no | source; it creates its own uinput device, so it can run beside the OSK |

Kernel behaviour (upstream evdev): a second `EVIOCGRAB` fails with `EBUSY`, and while one client holds the grab, no
other client receives events. So: (a) while the OSK is open its grab hides the pad from the app, which is what we want;
(b) if an app ever holds a grab, the daemon's (non-grabbing) chord reader sees nothing. The fallback is the Settings or
app switch. The chord reader must never grab while the OSK is closed.

### 3.4 Injected keys
- `CONFIG_INPUT_UINPUT=y` [D] (`kernel.config:1725`). `/dev/uinput` is in the stock misc list ([G] W3.1). Its node and
  permissions on the device are checked in K25.
- SDL2 apps (evdev keyboard via udev hotplug) and RetroArch (`udev` keyboard) should see a new uinput keyboard (K27).
  **Danger keys for RetroArch:** Esc quits the emulator and F1 opens the menu (stock cfg). Mark them on the OSK, or leave
  them off while RetroArch runs.
- SDL 1.2 `fbcon` apps read the keyboard from the **tty**. uinput keys reach them only through the kernel console
  keyboard on the active virtual terminal (K27).
- Redux's `frontend/term/osk.c` (Redux `a67262c`) outputs **byte strings for a pty**: control bytes, escape sequences. A
  global OSK needs **key codes + Shift/Ctrl** for uinput instead, so add a byte → (keycode, modifiers) table for a US
  layout. The layout, movement and Shift/Ctrl latch logic can be reused as they are.

## 4. Risks to sleep/lid, brightness and HDMI switch
| Area | Finding | Mitigation |
|---|---|---|
| Daemon death | `disp_release` does nothing [G], so a configured layer **stays on screen** after the process exits or crashes | Hide on SIGTERM/SIGINT/exit; the Redux service manager runs a one-shot "ch3/l0 off" when the daemon stops; the off switch also sends `enable = 0` |
| **Concurrent `SET_CONFIG2`** | The ioctl copies the user array into a **global** `lyr_cfg2[16]` (per screen) **before** taking the manager lock; there is no lock in the ioctl entry [BSP `dev_disp.c`]. W3.1 lists no mutex for 0x49 in stock [G]. The launcher commits every frame [G], so an OSK commit at the same moment can be mixed with the launcher's | No OSK over the launcher (the launcher has its own UI), or accept a rare one-frame glitch; commit only on change; retry on error |
| Forced-layer backup | Each `SET_CONFIG2` also saves its list as the backup that `force_set_layer_config_exit` restores [BSP]; stock has both functions [G kallsyms]. No caller found in the disp sources | Low risk; note for K26 |
| Sleep / lid | Sleep is `pwr_new.sh` → `mem` [G]. On resume the BSP turns the LCD device back on; the manager keeps its layer list, so the OSK should come back as it was | Close the OSK on lid close or power-key sleep (the daemon can read event0 without grabbing); K26 checks resume |
| Launcher idle timer | The launcher's idle sleep (1–10 min) is driven by keypad input [G §2.1]; while the OSK grabs the pad, the launcher sees no input | Another reason not to open the OSK over the launcher |
| Brightness | 0x102/0x103 reach `disp_lcd_set_bright` (backlight only) [G W3.1]; no layer effect. `DISP_BLANK` (0x0C) blanks the whole screen, OSK included | none |
| HDMI switch | `DISP_DEVICE_SWITCH` on screen 0 to HDMI 720p60 and back [G]; screen size changes (720 × 480 ↔ 1280 × 720); the launcher turns ch1/l0 off after each switch [G][N] and runs `rtcwake -m mem -s 1` after HDMI → LCD [G]. The OSK rectangle stays in old coordinates | Watch `/sys/class/extcon/hdmi/state` (or `/sys/class/switch/hdmi/state`): hide on change, read 0x07/0x08 again, recompute the rectangle (the UI channel can scale a fixed buffer), show again |
| Memory traffic | A 720 × 200 ARGB layer is about 0.58 MB per frame (≈ 35 MB/s at 60 Hz); full screen ≈ 83 MB/s | Only enabled while the OSK is open |
| Licence | The daemon's ioctl structs come from a GPL-2.0 BSP header | Keep the notice; the daemon's licence must allow it (Manager/owner) |

## 5. Mainline (Phase 2): the same idea on DRM
On mainline the H616 DE33 mixer0 offers **1 VI + 3 UI planes** with `alpha` and `zpos` properties (torvalds
`20eef29b7c84`, `sun8i_mixer.c` `sun50i_h616_mixer0_cfg`, `sun8i_ui_layer.c`), so the hardware has room for the OSK.
But only the DRM master may commit planes. An app that drives KMS itself (SDL `kmsdrm`, RetroArch `kms`) owns the
display, and a second process cannot add a plane next to it. The only exception is a DRM lease from that master, which
these apps don't offer. So Phase 2 should run apps under a small compositor (cage, sway or labwc: owner's choice) and make
the OSK a **layer-shell** client (`wlr-layer-shell`, overlay layer) that sends keys through
`virtual-keyboard-unstable-v1` or uinput (uinput works the same on mainline). The compositor maps the OSK to an overlay
plane or composites it. Input stays the same: the evdev chord reader plus `EVIOCGRAB`, or the compositor's own key
bindings. The stock-only ioctls (`/dev/disp`, ION) do not exist on mainline, so Phase 2 replaces the drawing layer and
keeps the OSK logic.

## 6. Proposed device checks (stock, Beta track; numbering for the Manager)
Every row is read-only on the card. A test binary, if used, is copied over SSH into a RAM-only directory; that is the
Manager's call.

| ID | Check | Answers |
|---|---|---|
| K24 *(proposed)* | With the stock debug sysfs: `cat /sys/class/disp/disp/attr/sys` (layer list) while (a) the launcher, (b) an SDL2/Mali port, (c) RetroArch (`gl`), (d) the video player and (e) DraStic each run; record channel, layer, zorder, format and size for every enabled layer. Also list `ls /sys/class/disp/disp/attr/` (closes the open "disp attr folders" item) | §2: is ch2/ch3 free, does the video player use ch0, ch1 zorder per app |
| K25 *(proposed)* | `ls -l /dev/uinput /dev/ion /dev/disp`; `cat /sys/class/misc/uinput/dev` | §3.4: uinput present, who can open it |
| K26 *(proposed)* | Overlay probe (desk-built aarch64 static test): ARGB8888 ch3/l0, zorder 30, half-transparent bar over (a) an SDL2/Mali port, (b) RetroArch, (c) DraStic, (d) a terminal app; then: lid close/open, power-key sleep/resume, Menu + Vol brightness, HDMI plug in/out; then kill the probe with `kill -9` and see whether the bar stays | §1, §4 |
| K27 *(proposed)* | `evtest` on `ANBERNIC-keys`: codes for Menu + Select, Menu + X, L3, R3; in RetroArch, whether pressing Menu alone opens the menu; a uinput test keyboard seen by an SDL2 port, RetroArch, SimpleTerminal/muTerm and an SDL 1.2 app | §3.1, §3.4 |
| K28 *(proposed)* | With each app from K24 running, a test tool tries `EVIOCGRAB` on `ANBERNIC-keys` (and releases it at once): `EBUSY` means the app holds a grab | §3.3 for programs we could not scan (ports, PPSSPP, terminals) |

## 7. Sources
- Stock (Dale's PC, read-only): `REA\BootImage\Image`, `kallsyms\kallsyms-v106.tsv`, `dtb.dts`, `kernel.config`;
  `.FW\re-extracts\appfs\bin\{dmenu.bin,portsCtrl.dge,ndsCtrl.dge}`; from `RG34XXSP-V1.0.6-EN16GB-260526\4.rootfs.img`
  and `5.appfs.img` (read with `debugfs -R dump`): `libmali.so.0.20.0` ×2, `libSDL2-2.0.so.0.12.0` ×2,
  `libSDL2-2.0.so.0.2800.5`, `libSDL-1.2.so.0.11.4`, `/.config/retroarch/retroarch.cfg`, `/deep/retro/retroarch{,64}`,
  `/deep/drastic/drastic`, `/usr/bin/evtest`; `Anbernic_StockOS_and_MOD_Manual.docx`.
- BSP: [orangepi-xunlong/linux-orangepi `orange-pi-4.9-sun50iw9`](https://github.com/orangepi-xunlong/linux-orangepi/tree/orange-pi-4.9-sun50iw9/drivers/video/fbdev/sunxi/disp2/disp)
  `0cd0547ea405`: `dev_disp.c`, `dev_fb.c`, `de/disp_manager.c`, `de/lowlevel_v33x/de330/de331_feat.c`,
  `de/lowlevel_v33x/de330/de_feat.c`, `de/lowlevel_v33x/de330/de_rtmx.c`, `include/video/sunxi_display2.h`.
- Mainline: torvalds/linux `20eef29b7c84`, `drivers/gpu/drm/sun4i/sun8i_mixer.c`, `sun8i_ui_layer.c`.
- RetroArch `6b94b82410be`; SDL `SDL2` `fe30456e94e8`; PortsMaster/gptokeyb `5b1284e15025`; Redux `a67262c`
  (`frontend/term/osk.c`, `frontend/src/ui.c`).
- Earlier KR/DR work: [`stock-re-boot-and-userspace.md`](stock-re-boot-and-userspace.md) §1–§6,
  [`ghidra-w3-1-kernel-inventory.md`](ghidra-w3-1-kernel-inventory.md) table 3.

Tools (user-scope, official sources): Python venv `/home/claude/venv-re` in the KR cloud workspace with
`capstone 5.0.3` and `pyelftools 0.31` from PyPI (nothing installed on Dale's PC or the device).

## 8. Verdict on the Manager's tests (Dale's addendum, 10:50)
| Test | Desk result | Settled only on the device |
|---|---|---|
| (1) No kernel change | **Pass.** Everything needed is already in the stock kernel: `CONFIG_INPUT_UINPUT=y` [D], `/dev/disp` `SET_CONFIG2` with 3 free UI-channel slots (ch2/ch3) [G], ION system heap [D][G], evdev `EVIOCGRAB` (upstream). The work is userspace only: one daemon plus a switch | K25 (`/dev/uinput` node and permissions) |
| (2) No effect on sleep/lid, brightness, HDMI | **Pass, with two rules for the daemon.** Brightness ioctls touch only the backlight [G]. The OSK layer does not take part in the sleep/lid path or the HDMI switch, and the power key/lid device is never grabbed. Rules: close the OSK on lid/power sleep; on HDMI change, hide it and recompute its rectangle | K26 (resume with the layer configured, HDMI in/out, Menu + Vol with the OSK closed and open) |
| (3) No noticeable cost while hidden | **Pass.** Hidden = layer disabled (no display-engine traffic), no grab, no `/dev/disp` commits (so none of the §4 race), and the daemon blocks in `poll()` on the keypad, event0 and the HDMI state: no CPU work between key presses | K26/K27: `top` and an app's FPS counter with the daemon running hidden vs not running |

**Verdict: GO** (desk). The plan rests on [G]/[D] evidence plus BSP inferences, and none of it has run on the device.
The K25–K27 checks above (plus K24 for picking the channel and K28 for unscanned apps) are what can still overturn it.
If K24 shows a stock app using ch3, move the OSK to ch2. If K26 shows the layer misbehaving across resume or HDMI,
the fallback is to hide the OSK before those events, which the rules above already do.
