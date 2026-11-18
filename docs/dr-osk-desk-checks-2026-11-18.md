# DR-1, DR-2, DR-3: desk checks for the global OSK (R26)

Date: 2026-11-18. Deep Research, for the Owner's letter `FROM-REDUX-OWNER-2026-11-18-s` (GO from the Manager for Dale,
12:18 ET). Desk only. **Nothing here has run on a device.** Tags: **[G]** static analysis of a stock binary (V1.0.6),
**[D]** stock config file or strings, **[S]** public source at a pinned commit, **[N]** no public source we know of.
Stock files were only read (copies in the cloud workspace); nothing stock is committed or quoted at length.

## Answer (5 lines)
1. **DR-3: Menu + X is not free in RetroArch.** The stock and MOD `retroarch.cfg` bind `input_pause_toggle_btn = "3"` and
   `input_fps_toggle_btn = "2"`, and 306/307 are buttons 2/3. So Menu + X is pause or FPS (which one depends on the label question below) [D][S]. **Menu + Select is free** in RetroArch and in every stock program scanned. Menu alone does not open the RA menu.
2. **DR-3, extra:** with this config RetroArch's **keyboard** hotkeys work **without Menu**. Typed `h` resets the game, F2/F4 save/load
   state, `p` pauses, `space`/`l` fast-forward, and more (§3.3). Leaving out only Esc and F1 is not enough while a game runs.
3. **DR-2: the stock video player does not use ch0.** `vp.dge` (the file browser) draws on **ch1/l0, zorder 20** through
   `SET_CONFIG2`, like the launcher [G]. Playback runs `FFplay.sh` → `ffplay` (SDL2 → Mali fbdev → fb0 = ch1/l0) [G][D].
   `xplayerdemo2` cannot run on stock: its Cedar libraries are not in the image [D]. ch2/ch3 stay free; ch3 stays the OSK channel.
4. **DR-1: R26 holds up.** BSP checks agree on `SET_CONFIG2` (copy, then per-layer update under the manager lock),
   channel order by lowest zorder, and dma-buf handling. Corrections are items 1–3 above, plus one rule: always commit **one layer per
   call** (KR-1/KR-2 already do).

## 1. DR-2: stock video player layers

| Program | Role | Display path | Channel / layer / zorder | Evidence |
|---|---|---|---|---|
| `vp.dge` (`/mnt/vendor/bin/video`, 32-bit, SDL 1.2) | Video file browser; started by `dmenu_ln` when `/tmp/vpRun.ini` exists | Its own ION frames through `DISP_LAYER_SET_CONFIG2`, between `DISP_SHADOW_PROTECT` on/off; 5 buffers in rotation | **ch1/l0, zorder 20**, alpha mode 0, alpha value 0xff, `enable = 1`; colour space 0x101/0x104 by width | [G] commit builder `0x12fe4` → helper `0x16524` (Thumb) |
| `vp.dge` HDMI switch | `DISP_DEVICE_SWITCH` (0x0F), then 20 ms later `SET_CONFIG2` with `enable = 0` | **ch1/l0 off** | [G] `0x132be`–`0x13300` (4 such sites) |
| `vp.dge` → playback | Writes `/tmp/.next` = `cd /mnt/vendor/bin/video` + `./FFplay.sh "<file>"` (with ` hdmi` when HDMI is on) and exits; the launcher shell runs it | — | — | [G] `0x15dd4`, call at `0x17072`; [D] `dmenu_ln` |
| `FFplay.sh` → `ffplay` (FFmpeg `N-114784-g8339a45400`, 32-bit, Anbernic build) | Player: `-fs -autoexit -vf scale=640:-2` | SDL2 (`/usr/lib32/libSDL2-2.0.so.0.12.0`, the stock Mali fbdev build) → fb0 | **ch1/l0** (fb0's layer; zorder as last set) | [D] script, `NEEDED`, stock `/usr/lib32`; R26 §2 for SDL2 → fb0 |
| `ffplay`: other `/dev/disp` use | Only brightness get/set (strings `get_brightness_ioctl`, `set_brightness_ioctl`); no layer ioctls | — | — | [D] strings |
| `xplayerdemo2` (Tina CedarX demo, `LayerCreate_DE`) | Listed in the launcher's app table as an alternative to `./vp.dge` | Would use the libcdx DE sink | **not used**: none of its `libcdx_*`, `libxplayer`, `libvdecoder`, `libVE`, `libcdc_base` are in rootfs (`/usr/lib32`, `/usr/lib`, `/lib`) or appfs `/lib` | [D] `debugfs` listings |

- **K24 row "video":** expect ch1/l0 only, with ch0, ch2 and ch3 empty, both in the browser and during playback. A layer on ch0
  would mean a different player (for example from a MOD or a port), not the stock one.
- `ffplay` has its own keypad/power-key thread on `ANBERNIC-keys` and `event0` (strings `read_adc2key_thread`, `read keypad error`,
  `up ready sleep`), much like `portsCtrl`. The thread's Thumb code has no `EVIOCGRAB` constant (`0x40044590`) [G]. ARM-mode code
  was not scanned, so K28 should still include `video`.

## 2. DR-3: RetroArch Menu key and the OSK chord

### 2.1 How RetroArch numbers the SP's buttons
RetroArch 1.20 `udev_joypad.c` numbers buttons by walking the device's key codes from `BTN_MISC` upward, then the codes below it
[S] (`v1.20.0` = `ab3b1758`, lines 227–241). `ANBERNIC-keys` carries 304–316 [D] (W3.1 table 5). Result, matched against the
stock autoconfig `/deep/retro/ANBERNIC-keys.cfg` (identical in V1.0.6 and MOD v3.9.9) [D]:

| RA button | Code | Autoconfig name | Stock hotkey on this button (Menu held) |
|---|---|---|---|
| 0 | 304 | A | — |
| 1 | 305 | B | screenshot |
| 2 | 306 | Y | **FPS toggle** |
| 3 | 307 | X | **pause toggle** |
| 4 / 5 | 308 / 309 | L1 / R1 | load / save state |
| 6 | 310 | Select | — |
| 7 | 311 | Start | **quit** (`exit_emulator_btn`) |
| **8** | **312** | (none) | **hotkey enable** (`input_enable_hotkey_btn = "8"`): this is **Menu** |
| 9 / 12 | 313 / 316 | L3 / R3 | — |
| 10 / 11 | 314 / 315 | L2 / R2 | slow motion / fast-forward toggle |
| hat | ABS_HAT0 | D-pad | Left/Right = state slot |

`input_volume_up_btn = "16"` / `down_btn = "15"` point at buttons this device does not seem to have (Vol keys 114/115 should be 13/14).
That doesn't matter for the OSK. Same config in `/.config/retroarch/retroarch.cfg`, `/deep/retro/retroarch.cfg` and `retroarch-1.20.cfg`, V1.0.6
and MOD v3.9.9 [D]. Not checked: per-core or per-game overrides under `/deep/retro/config`, and any RetroArch config Redux ships.

### 2.2 Does Menu alone open the RetroArch menu?
**No, by upstream logic.** `input_menu_toggle_btn = "nul"`; Menu is only the hotkey enable. Holding it blocks game input after
`input_hotkey_block_delay` = 5 frames [S] (`input_driver.c` 5536–5558). The menu opens with keyboard F1, or with
`input_menu_toggle_gamepad_combo = "7"` = `INPUT_COMBO_HOLD_START` (`input_defines.h` 210–221). That means **Start held 2 s**
(`HOLD_BTN_DELAY_SEC`), and it ignores a press while the hotkey enable is held and Start is not [S] (`input_driver.c` 581–645).
The stock manual's "Menu = quick menu" is not what this code does. Anbernic could have patched their binary [N], so K27 step 2 still asks.

### 2.3 Chord verdict
| Chord | RetroArch | Launcher / `portsCtrl` / `ndsCtrl` / DraStic (R26 §3.1) | Verdict |
|---|---|---|---|
| **Menu + X** | **pause toggle** (if X = 307) or **FPS toggle** (if X = 306) | free | **conflict in RetroArch** |
| **Menu + Select** | free; game input already blocked while Menu is held | free (Start + Select is the launcher's, not Menu + Select) | **use this** |
| Menu + A | free | free; but A reaches non-RA apps as a game button | second choice |
| Menu + L3 / R3 | free | free; L3/R3 report on stock (Redux 11-17) | third choice (awkward on the SP) |

Dale's decision (11:23) was "**chord Menu + X (if K27 shows no conflict)**". The desk now shows a conflict, so this goes back to the
Owner. KR-3 already takes the chord as a setting (`osk_in` `km.chord`, test `BTN_C`), so Menu + Select is a one-line default
change (`BTN_TL` 310). KR-3 also notes that the chord's second press reaches the app. With Select that press is harmless in RetroArch and in the stock programs above.

### 2.3a Keyboard hotkeys (affects the KR-3 RetroArch flag)
RetroArch treats each device type separately [S] (`input_driver.c` 5520–5786). Here the hotkey enable is set for the gamepad (8)
but not the keyboard (`input_enable_hotkey = "nul"`), and `input_hotkey_device_merge = "false"`. With that config **a keyboard
hotkey fires on its own key, without Menu**. `input_auto_game_focus = "0"`, so game focus is off. Stock keyboard hotkeys [D]:

| Key | Action | Risk |
|---|---|---|
| Esc / F1 | quit / menu | already left off (Dale) |
| **h** | **reset the core** | loses unsaved progress |
| **F2 / F4** | **save / load state** | overwrites or replaces a save |
| p, k | pause, frame advance | |
| space, l, e | fast-forward toggle/hold, slow motion | |
| r | rewind | |
| f, F11 | fullscreen, mouse grab | |
| m, n, comma | shader next/prev/toggle | |
| t, y, u | cheat index −/+, cheat toggle | |
| i, tilde | netplay watch, netplay chat | |
| F3, F6, F7, F8, F9 | FPS, state slot −/+, screenshot, mute | |
| add, subtract (keypad + / −) | volume | |
| scroll_lock | game focus toggle | |

Options for the Owner (KR-3 implements whichever is picked):
- **(a)** While RetroArch runs a game, type only into RetroArch's own menu and text fields: open the OSK only when the RA menu is up.
  This can't be detected from outside without a RetroArch network command.
- **(b)** Send `scroll_lock` once on open and once on close, so typing goes to the core with game focus on. Game focus blocks
  keyboard hotkeys [S] (`INP_FLAG_KB_MAPPING_BLOCKED`). The risk is that focus state gets out of step if the user also toggles it.
- **(c)** Widen the RetroArch flag to drop every key in the table above (most letters stay usable, but not h, p, k, r, l, e, f, m, n, t, y, u, i).
- **(d)** Ship Redux's own `retroarch.cfg` with `input_enable_hotkey = "nul"` changed to a key the OSK never sends, so keyboard
  hotkeys need it. Cleanest, but it changes stock RetroArch behaviour for real keyboards. That is the Owner's call.

## 3. DR-1: independent review of R26

| R26 claim | Check | Result |
|---|---|---|
| §1.2 `SET_CONFIG2` arg = {screen, ptr, count, 0}; copy; zero `info` when `enable = 0`; per-screen global array | BSP `dev_disp.c` 3581–3613 (`lyr_cfg2[16]` / `lyr_cfg2_1[16]`, lines 56–57) | **agree** |
| §1.2 manager updates only listed layers, under a lock | `disp_manager.c` 1875 ff.: `mutex_lock(&mgr_mlock)` after the copy; per-layer `save_and_dirty_check2`; fd dma-mapped on every commit | **agree**; the lock covers the manager, not the ioctl's copy (R26 §4 race stands) |
| §1.2 channels stacked by lowest zorder | `de_rtmx.c` 1412–1440 (`de_rtmx_chn_zorder`) and the pipe-routing loop 1378–1408: lowest `min_zorder` first; ties go to the lower channel number | **agree**; z 30 on ch3 is above z 20 on ch1 |
| §1.2 `count` | `disp_mgr_set_layer_config2` rejects `count > num_layers`, but only after the copy. Its dma-map loop also steps through `lyr_cfg_using[0]` assuming the listed layers are contiguous | **new rule:** always one layer per call (`count = 1`). KR-1 `oskprobe.c` and KR-2 `osk_disp.c` already do. Detail in a private DR note |
| §1.3 struct 224 bytes | not recomputed; KR-1/KR-2 carry `_Static_assert`s that build in CI | **accepted** |
| §2 video player "most likely ch0" | §1 above | **corrected**: ch1/l0, no ch0 use |
| §2 SDL2 2.0.12 32-bit uses Mali fbdev | stock `/usr/lib32/libSDL2-2.0.so.0.12.0` present; `ffplay` links it | **agree** (now also the video path) |
| §3.1 Menu + X "looks free" | §2.3 above | **corrected**: RetroArch pause / FPS |
| §3.1 "Menu = RetroArch quick menu" (manual) | §2.2 above | **not supported** by RA 1.20 logic with the stock config; menu = Start held 2 s or F1 |
| §3.3 RetroArch has no `EVIOCGRAB` | RA `v1.20.0` `input/`: no `EVIOCGRAB` | **agree** |
| §3.4 RetroArch sees a new uinput keyboard | RA `udev_input.c` takes hotplug from `udev_monitor` (3328–3527); stock has `systemd-udevd` [D] | **plausible**; K27 confirms. Create the uinput device at daemon start (before RetroArch), so RetroArch's first device scan already finds it |
| §3.4 danger keys Esc, F1 | §2.3a | **incomplete**: many more keyboard hotkeys are live |
| §4 layer survives daemon death | each commit takes a dma-buf reference (`disp_dma_map`); `disp_release` is a no-op [G] | **agree** |

R26's GO verdict stands. The two chord/keyboard corrections change the input defaults, not the display design.

## 4. Lines for the run sheet (K24 / K27), for KR to fold into `tools/oskprobe/RUNSHEET.md` (PR #62)
- **K24 #4 `video`:** "Desk (DR-2): stock player = `vp.dge` browser + `ffplay` (SDL2); expect **ch1/l0 only**, ch0/ch2/ch3 empty.
  A layer on ch0 means a non-stock player."
- **K27 step 1:** add **Menu + A**. Expect Menu = 312, Select = 310, X = 307 or 306 (the label question), A = 304.
- **K27 step 2:** "Desk (DR-3): by upstream logic Menu alone does **not** open the menu; **Start held 2 s** does. Also try
  **Menu + X**: expect pause (or the FPS counter). Note which one, since it settles which code the printed X sends."
- **K27 step 3 (`retroarch`):** type only in RetroArch's own menu (for example the search field), never with a game running.
  With a game running, three of the letters in `redux` are live hotkeys: **r** (rewind), **e** (slow motion) and **u** (cheat toggle).

## 5. Sources
- Stock (Dale's PC, read-only; copies in the cloud workspace, not committed): `.FW\re-extracts\gaps\bin\d_video\video\{vp.dge,
  xplayerdemo2,ffplay,FFplay.sh}`, `appfs\bin\dmenu.bin`, `appfs\ctrl\dmenu_ln`; `RG34XXSP-V1.0.6-EN16GB-260526\{4.rootfs.img,
  5.appfs.img}` and `RG34XXSP-V1.0.6-BASE-20260526-mod-v3.9.9.img` (partitions 5/6), read with `debugfs`:
  `/.config/retroarch/retroarch.cfg`, `/deep/retro/{retroarch.cfg,retroarch-1.20.cfg,ANBERNIC-keys.cfg}`.
- RetroArch [`v1.20.0`](https://github.com/libretro/RetroArch/tree/v1.20.0) (`ab3b175848fa`): `input/drivers_joypad/udev_joypad.c`,
  `input/input_driver.c`, `input/input_defines.h`, `input/drivers/udev_input.c`, `runloop.c` 5486–5492.
- BSP [orangepi-xunlong/linux-orangepi `orange-pi-4.9-sun50iw9`](https://github.com/orangepi-xunlong/linux-orangepi/tree/orange-pi-4.9-sun50iw9/drivers/video/fbdev/sunxi/disp2/disp)
  `0cd0547ea405`: `dev_disp.c`, `de/disp_manager.c`, `de/lowlevel_v33x/de330/de_rtmx.c`.
- This repo: [`r26-global-osk-stock-disp2.md`](r26-global-osk-stock-disp2.md), [`ghidra-w3-1-kernel-inventory.md`](ghidra-w3-1-kernel-inventory.md) table 5.

Tools: `llvm-objdump` (Thumb-2 and ARM), `readelf`, `strings`, `debugfs` 1.46.5, Python 3. All were already in the workspaces;
nothing was installed on Dale's PC or the device.
