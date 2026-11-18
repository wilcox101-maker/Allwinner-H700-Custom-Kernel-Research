# OSK probe session: run sheet (K24–K28)

KR-1, 2026-11-18, for the Redux OSK plan D5 (`notes/2026-11-18-claude-question-global-osk-plan.md`) and the Owner's
letter `FROM-REDUX-OWNER-2026-11-18-s`. Background: H700 `docs/r26-global-osk-stock-disp2.md` (PR #61).
**Nothing here has run on a device yet.** The aarch64 binary is built and host-checked on the desk only.

## Safety
- The tools run **only from `/tmp`** (RAM, gone at reboot). The script refuses to run anywhere else.
- They write **nothing to any card or partition**. Logs go to `/tmp/oskprobe-logs/`.
- The only display change is one test layer on **disp0 channel 3, layer 0**. Channels 0 and 1 are refused. Every exit
  of `run-probe.sh` runs `oskprobe off`. If a bar is ever left on screen, run `sh /tmp/run-probe.sh off`, or reboot.
- `K27-type` sends only the letters `r e d u x` (the tool accepts only a–z). It never sends Esc, F1 or Enter.
- `K28` grabs the pad and releases it at once.
- A known harmless effect: while the Redux/stock menu is on screen, a layer commit can clash with the menu's own
  per-frame commit (R26 §4) and give one odd frame. Nothing is stored.

## 0. Copy to the device (once per session)
From the PC, in the folder with the unzipped kit (`[DEVICE_IP]` = the handheld's Wi-Fi address; user and password as
for your usual SSH session):
```
scp oskprobe run-probe.sh root@[DEVICE_IP]:/tmp/
ssh root@[DEVICE_IP] 'chmod +x /tmp/oskprobe /tmp/run-probe.sh && /tmp/oskprobe version && sha256sum /tmp/oskprobe'
```
Expect `oskprobe <sha> (KR-1), disp_layer_config2 224 bytes`. The SHA-256 should match `build.log`.
In every step below, start the app on the handheld first, then run the command in the SSH window.

## K24: who uses which layer
For each app: start it, wait until its picture is on screen, then run
`sh /tmp/run-probe.sh K24 <label>`.

| # | App on screen | Label |
|---|---|---|
| 1 | Redux/stock menu | `menu` |
| 2 | an SDL2 port (PortMaster) | `sdl2port` |
| 3 | RetroArch, a game running | `retroarch` |
| 4 | the stock video player, a video playing | `video` |
| 5 | DraStic, a game running | `drastic` |

Looks: **PASS** = the `sys` dump lists the enabled layers with channel/layer/zorder, and nothing is enabled on ch3
(and ideally not on ch2). Note what the video player uses. Desk (DR-2): the stock player is `vp.dge` + `ffplay`; expect
**ch1/l0 only** (ch0, ch2, ch3 empty); a layer on ch0 means a non-stock player. **FAIL** = something is on ch3 (then K26 runs
with `--ch 2`: ask KR for the one-line change), or the `sys` file is missing (paste the attr list).

## K25: device nodes
`sh /tmp/run-probe.sh K25`
Looks: **PASS** = `/dev/uinput`, `/dev/ion` and `/dev/disp` exist with `open-rw: ok`, and an `ANBERNIC-keys` line is in
the input list. **FAIL** = `/dev/uinput` missing or `Permission denied`.

## K26: test bar over apps, sleep, brightness, HDMI
For each app, `sh /tmp/run-probe.sh K26 <label> 90`. While the bar is up (90 s):

| # | App | During the bar |
|---|---|---|
| 1 | SDL2 port (`sdl2port`) | Menu + Vol± (brightness); the bar should stay on top and the app keep running |
| 2 | RetroArch (`retroarch`) | lid close, wait 5 s, lid open; the bar may come back after resume (note what you see) |
| 3 | DraStic (`drastic`) | short power press (sleep), wake |
| 4 | any app (`hdmi`) | plug in HDMI, wait, unplug; the log marks `<- changed` lines |
| 5 | a terminal (`terminal`) | nothing; check it is readable |

Then `sh /tmp/run-probe.sh K26-kill`: the bar should **stay** after `kill -9`; press Enter; the bar should **go**.

Looks: **PASS** = an 8-colour half-transparent bar with a white border at the bottom, the app visible through it and
running normally, brightness working, the bar gone when the step ends, and the kill test behaving as described.
**FAIL** = no bar (paste the log: `SET_CONFIG2` / ION lines), a frozen or garbled app, sleep/wake or HDMI misbehaving, or
the bar not going on `off`.

## K27: keys and injected typing
1. `sh /tmp/run-probe.sh K27-keys 40`, then, slowly and in this order: Menu alone; Menu + Select; Menu + X; Menu + A;
   L3; R3; Select; Start. Write down the order you used.
2. In RetroArch (a game running): press **Menu alone** once. Does the RetroArch menu open on press, on release, or
   not at all? (Answer on the sheet; nothing to run.) Desk (DR-3): by RetroArch 1.20 logic it does **not** open; **Start
   held 2 s** does. Then press **Menu + X**: expect pause (or the FPS counter); note which, it settles which code the printed X
   sends.
3. Typing: for each app, start it, put the cursor in a text field (or a terminal prompt), run
   `sh /tmp/run-probe.sh K27-type <label>`, then within 5 s give the app focus: `sdl2port`, `retroarch` (in RetroArch's own
   menu, e.g. its search field, **not** with a game running: there `r`, `e` and `u` are live hotkeys, DR-3), `terminal` (Redux Terminal), `sdl12` (an SDL 1.2 app such as a `.dge` emulator menu).

Looks: **PASS** = every key shows a `type 1` line with a code (Menu is expected to be `BTN_TL2` 312, unverified);
`redux` appears in the app. **FAIL** = a key shows nothing, or nothing gets typed (note which app).

## K28: does any app grab the pad
For each K24 app (and any port or terminal you use often): start it, then `sh /tmp/run-probe.sh K28 <label>`.
Looks: **PASS** = `grab ...: OK (no other program holds a grab); released`. **EBUSY** = that app holds a grab (note it:
the OSK chord can't work over it).

## After the session
`sh /tmp/run-probe.sh logs`, then copy them to the PC:
`scp -r root@[DEVICE_IP]:/tmp/oskprobe-logs .` and give the folder to the Owner for the hw-result note.
DR-2 (video player layer) and DR-3 (RetroArch Menu key) answers are in the K24/K27 steps above
(`docs/dr-osk-desk-checks-2026-11-18.md`).
