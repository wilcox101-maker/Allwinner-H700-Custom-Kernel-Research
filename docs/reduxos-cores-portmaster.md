# ReduxOS R36: source-built cores, launcher, PortMaster (desk/QEMU only)

Dale, 2026-11-20: match the Stock OS Mod's systems, with no proprietary content. This adds the
emulator **cores** and a **PortMaster** port on top of the games/BIOS framework
([`reduxos-games-and-bios.md`](reduxos-games-and-bios.md)). **Nothing here has run on an RG34XX-SP.**
Loading a core in QEMU is not playing a game: speed (N64, Dreamcast, PSP, arcade) needs the device.

## 1. Cores
- `config/reduxos-games/cores.tsv`: 22 cores, each **pinned to an upstream commit** (resolved
  2026-11-20), with build kind/args and licence. `tools/build-libretro-cores.sh` cross-builds them
  (gcc/g++ 13.3 `aarch64-linux-gnu`, Ubuntu 24.04 host; the GLES cores also need multiarch
  `libgles-dev:arm64 libegl-dev:arm64`), checks each is an aarch64 `.so` exporting the libretro API,
  strips it, and copies its licence files and source pin. Resumable; one failure doesn't stop the rest.
- No binary is committed. The image injects them with `CORES_DIR=<out> image/build-image.sh`, with
  licences in `/usr/share/doc/reduxos-cores/`.
- Licences: most are GPL/LGPL/zlib/MIT. **Non-commercial:** fbneo, mame2003_plus, picodrive, bluemsx.
  That's fine for Dale's private build; never ship them in a public or commercial release (R9).

| Systems | Core | Size (stripped) |
|---|---|---|
| A2600 / A5200 / A7800 / A800 | stella2014, a5200, prosystem, atari800 | 0.2–3.1 MB |
| AMIGA | puae | 21 MB |
| C64 / VIC20 | vice_x64, vice_xvic | 3.6 / 2.9 MB |
| MD, MDCD, SMS, GG, 32X | picodrive (ARM64 DRC) | 1.9 MB |
| FBNEO, CPS1-3, NEOGEO | fbneo | 84 MB |
| MAME | mame2003_plus | 45 MB |
| DREAMCAST, NAOMI | flycast (GLES) | 34 MB |
| N64 | mupen64plus_next (GLES3, aarch64 dynarec) | 4.2 MB |
| PSP | ppsspp (GLES) | 20 MB |
| DOS | dosbox_pure | 3.0 MB |
| GW, LYNX, NGP, POKE, VARCADE, MSX, NEOCD | gw, handy, race, pokemini, vecx, bluemsx, neocd | 0.2–1.7 MB |
| PICO | fake08 (open re-implementation; carts are user-supplied, no PICO-8 binary) | 0.9 MB |

The packaged noble cores (nestopia, gambatte, mgba, bsnes-mercury, beetle-pce/vb/wswan/psx, desmume)
and the injected pcsx_rearmed are unchanged.

**Not built yet:** ATARIST (`todo:hatarib`; libretro/hatari no longer carries the core),
SATURN (`todo:yabasanshiro`; beetle-saturn is far too heavy for an A53), EASYRPG, ONS, JAVA
(freej2me needs a JRE). PGM2 is `unsupported` (needs current MAME). OPENBOR and SCUMMVM are
`via:portmaster`.

## 2. One playlist per system
`redux-scan-roms` writes a RetroArch playlist for each system folder that has games and an installed
core, with the core already set, so a game opens straight away. It runs at every boot
(`reduxos-playlists.service`, as `player`), and again after PortMaster closes. APPS has a
"Rescan Games" entry for running it by hand.

## 3. Ports and apps from RetroArch: the launcher core
RetroArch can't run shell scripts. `redux_exec` (`tools/redux-exec-core.c`, built by
`tools/build-redux-exec-core.sh`) is a tiny libretro core that takes a `.sh` as content and works
like this:
1. It writes the script's path to a 0600 request file in `$XDG_RUNTIME_DIR` (write-then-rename,
   no symlink follow).
2. It closes RetroArch.
3. The player session (`~/.bash_profile`) runs it through `redux-launch`, then starts RetroArch again.

`redux-launch` only accepts scripts under `/roms/PORTS`, `/roms/APPS` or `/opt/tools/PortMaster`. It
runs as the unprivileged `player`, so nothing is elevated. `redux-setup-roms` creates
`PORTS/PortMaster.sh` and `APPS/{Terminal, File Manager, Rescan Games}.sh`.

## 4. PortMaster
- Pinned release `2026.11.17-0700` (PortsMaster/PortMaster-GUI, MIT), checked by SHA-256 in
  `tools/fetch-portmaster.sh`. It's injected with `PORTMASTER_ZIP=` into `/opt/tools/PortMaster`,
  which is owned by `player` because PortMaster writes its log and updates itself there.
- `config/portmaster/launch_hooks.txt` is selected by `PortMaster.sh reduxos`. It sets SDL2 to the
  multiarch path, KMS, ports in `/roms/ports`, and a playlist refresh on exit.
- Ports expect lowercase `/roms/ports`, so `redux-setup-roms` links `ports` to `PORTS`. On a FAT or
  exFAT games card that link isn't possible: format the card as ext4, or mount with `uid=player`.
- PortMaster runs without sudo. Its `gptokeyb` (pad to keys) needs `/dev/uinput`: a udev rule gives
  the `input` group 0660 access, and `uinput` loads at boot. This also fixes the OSK pointer bridge.
  The trade-off is that `player`, already able to read every pad, can now create virtual input.
- New image packages: python3, SDL2 with ttf/image/mixer, unzip.

## 5. Fixes found on the desk
- **`/roms` belonged to root**, so `player` (RetroArch) couldn't write saves or states. Now
  `redux-setup-roms` creates `saves/` and `states/` and gives the tree to `player`.
- **Image size (R33, assets part):** `retroarch` hard-depends on `retroarch-assets`, which pulls about
  440 MB of fonts. A generated shim package (`reduxos-retroarch-slim`, no binary in the repo) provides
  that dependency. rgui needs no assets. Build with `RA_SLIM=0` to keep them for xmb/ozone. The llvm
  part of R33 is still open.

- **ppsspp would not have loaded** (found by the QEMU check, §6): its `.so` left 82 `gl*` symbols undefined
  with no GL library in `NEEDED`, so `dlopen` failed. Now linked to `libGLESv2` (`cores.tsv`), and the core
  builder rejects any core with undefined `gl*` symbols and no GL library.
- **Deeplayer guard** (from KR's private V1.0.6 breakdown §8A: stock cores and emulators reboot the device
  without the vendor driver): `check-hardening.sh` fails the image if any file under `/usr`, `/opt` or `/etc`
  mentions `deeplayer` or `debug2_reg2`. The LPDDR4 rootfs had 0 hits; a synthetic file trips it.

## 6. Checks
- `check-hardening.sh` (R36 section): launcher core and its info file, every core aarch64, launch
  allow-list, scanner and service enabled, uinput 0660 for `input`, PortMaster not owned by root, no
  deeplayer-checked binary.
- CI (`image-smoke`) builds the launcher core and injects it; the big emulator cores are a local, private
  build, so CI only covers the packaged cores.
- QEMU (`-cpu cortex-a53`): `image/qemu/r36-check.py` loads **every** core with ctypes (all libraries
  resolve, `retro_api_version`, system info), drives the launcher core end to end, runs the scanner on
  a throwaway tree, and checks services, the ports link, `/roms` ownership and uinput.
  `smoke-test.sh` reports three R36 lines.

## 7. Results
See §R36 in [`reduxos-beta-build-2026-11-20.md`](reduxos-beta-build-2026-11-20.md) (filled in after the
image builds).
