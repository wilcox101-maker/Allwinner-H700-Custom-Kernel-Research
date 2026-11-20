# osklib: display layer (KR-2) and input + keyboard (KR-3) for the Redux global OSK

> **Update 2026-11-20:** Redux now uses **Menu + Select** and opens no OSK while RetroArch runs (Owner's letter `-v`, 2026-11-18). The defaults below still say Menu + X; Select is also the default Shift key here, so the default needs a mapping decision first ([`docs/dr-review-2026-11-20.md`](../../docs/dr-review-2026-11-20.md) §2).

For the Redux Owner's letter `FROM-REDUX-OWNER-2026-11-18-s`. Evidence: [`docs/r26-global-osk-stock-disp2.md`](../../docs/r26-global-osk-stock-disp2.md).
**Nothing here has run on the device.** The host unit tests pass (gcc, clang, ASan/UBSan) and the code cross-compiles
for aarch64 (musl and glibc). K24–K28 ([`tools/oskprobe/RUNSHEET.md`](../oskprobe/RUNSHEET.md)) check the assumptions it rests on.

C99, `-Wall -Wextra -Werror -pedantic`, libc and Linux uapi headers only. GPL-2.0-only. `src/sunxi_disp2_abi.h` keeps
the layout of Allwinner's GPL-2.0 BSP header (origin named in the file) and asserts it at compile time.

## Files
| File | What |
|---|---|
| `src/osk_disp.{h,c}` | KR-2: ION buffers, `SET_CONFIG2` on disp0 ch3/l0 (ch2 allowed), zorder 30, commit only on change, one-shot off |
| `src/osk_in.{h,c}` | KR-3: `ANBERNIC-keys` reader, Menu + X chord, grab applied only when no key is held, OSK events |
| `src/osk_kbd.{h,c}` | KR-3: uinput keyboard `redux-osk`, Redux layout bytes → US key codes, Shift/Ctrl, RetroArch Esc/F1 rule |
| `src/osk_sys.{h,c}` | system-call table (real calls; tests swap in fakes) |
| `tests/` | host tests + `fake_sys` (no device access); `tests/redux/osk.{c,h}` = Redux `frontend/term/osk.{c,h}` at `dd65506`, unchanged (SHA-256 of osk.c `1e37455f…`), used only to test against the real layout |

Build and test on Linux: `cmake -S tools/osklib -B build && cmake --build build && ctest --test-dir build`.
Redux builds the four `src/*.c` files with its own layout copy (`-DOSK_LAYOUT_DIR=…` or its own makefile rule).

## Interfaces (Owner's names kept; additions marked +)
| Call | Notes |
|---|---|
| `osk_disp_open(&d, opts)` | `opts` NULL = ch3, zorder 30. Refuses ch0/ch1 and zorder ≤ 20 |
| `osk_disp_screen_size(d, &w, &h)` | `DISP_GET_SCN_WIDTH/HEIGHT`; call again after an HDMI change |
| + `osk_disp_buf_new(d, w, h, &buf)` / `osk_disp_buf_free` | ION system heap (mask 1, uncached), mapped; `buf.px` = ARGB8888, not premultiplied. Added because a buffer needs an owner; use two for double buffering |
| `osk_disp_show(d, rect, &buf)` | returns 1 if committed, 0 if nothing changed (no commit) |
| `osk_disp_hide(d)` / `osk_disp_close(d)` | hide commits only when shown; close hides first |
| + `osk_disp_off_once(opts)` | for `redux-osk --off` (plan D1): always one `enable = 0` commit |
| + `osk_disp_rect_bottom(sw, sh, w, h)` | bottom band, centred (HDMI 1280 × 720 keeps a 720-wide band) |
| `osk_in_open(&in, NULL, km, NULL)` | `ANBERNIC-keys`; `km` NULL = defaults (Menu `BTN_TL2`, X `BTN_NORTH`, A `BTN_SOUTH`, B `BTN_EAST`, Select `BTN_TL`, all from the stock key table, **to be confirmed by K27**) |
| `osk_in_poll_fd(in)`, `osk_in_next_event(in, &ev)` | poll the fd; drain events until 0. Events: `TOGGLE`, `UP/DOWN/LEFT/RIGHT` (+`repeat`), `PRESS`, `CLOSE`, `SHIFT` |
| `osk_in_grab(in, on)` | records the wish; the grab follows as soon as no key is held (returns 1 if applied now) |
| + `osk_kbd_open(&k, NULL)` / `osk_kbd_close(k)` | creates/destroys the uinput device |
| `osk_kbd_type(k, key, mods)` | `key` = an `osk_key_t` of the layout; `mods` = `OSK_MOD_SHIFT`/`OSK_MOD_CTRL` from the latches; Ctrl is a real `KEY_LEFTCTRL`. Key held 30 ms (`osk_kbd_set_hold_ms`) |
| + `osk_kbd_set_retroarch(k, on)`, `osk_key_hidden(key, ra)` | Dale 11:23: Esc and F1 left off while RetroArch runs (type refuses them; drawer skips them) |

## How the daemon uses it (sketch for Redux; Redux owns start/stop, pid file and menu flag: KR-4)
```
osk_disp_off_once(NULL);                       /* at start: clear a layer left by a crash */
osk_disp_open(&d, NULL); osk_in_open(&in, NULL, NULL, NULL); osk_kbd_open(&k, NULL);
osk_disp_buf_new(d, 720, 200, &buf[0]); osk_disp_buf_new(d, 720, 200, &buf[1]);
loop: poll(osk_in_poll_fd(in), lid/power event0 fd, HDMI state fd)
  while (osk_in_next_event(in, &ev) == 1)
    TOGGLE  -> open: osk_in_grab(in,1); draw(buf[back]); osk_disp_show(d, rect, &buf[back]); swap
               close: osk_disp_hide(d); osk_in_grab(in,0)
    UP..    -> osk_move(&osk, ...); redraw + show (commits only because the buffer changed)
    PRESS   -> key = osk_key(osk.row, osk.col); if key->mode: osk_press(&osk, ...) flips the latch
               else osk_kbd_type(k, key, (osk.shift?OSK_MOD_SHIFT:0)|(osk.ctrl?OSK_MOD_CTRL:0)); osk.ctrl = 0
    SHIFT   -> osk.shift = !osk.shift
    CLOSE   -> as TOGGLE close
  lid/power/HDMI change -> close; after HDMI re-read osk_disp_screen_size and recompute rect
  never open while /tmp/redux-menu.up exists (R26 section 4: race with the menu's commits)
exit/signal: osk_disp_close(d) (hides), osk_in_close(in) (ungrabs), osk_kbd_close(k)
```

## Known limits (desk)
- The chord's X press also reaches the app (the grab can only start after Menu and X are released). K27 shows
  whether that matters in any app.
- If another program holds `EVIOCGRAB`, the grab fails (`osk_in_is_grabbed` stays 0); the daemon should then close
  the OSK again. K28 lists such programs.
- The D-pad repeats only if the kernel sends auto-repeat (value 2); stock `gpio-keys-polled` may not. If K27 shows
  none, the daemon can repeat on a timer.
- US layout only.
