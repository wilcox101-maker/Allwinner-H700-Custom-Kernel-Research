# ReduxOS games & BIOS framework (R36)

**No ROMs or BIOS are shipped.** This is the folder structure and tooling so a library and BIOS set
drop in with ease. Desk only — the paths and scripts are built and checked, but nothing here has run
on hardware.

## Layout (games root `/roms`)
```
/roms/
  <SYSTEM>/        one folder per system (names match the Anbernic stock layout, so an existing
                   card library transfers 1:1) — FC, SFC, MD, GBA, PS, PSP, DREAMCAST, NEOGEO, ...
  bios/            RetroArch "system" directory — drop BIOS files here (flat, exact filenames)
  saves/  states/  created on demand by RetroArch
```
`/roms` is on the root card by default; mount a dedicated games microSD at `/roms` to use the big
card instead. RetroArch is pre-pointed at it (`rgui_browser_directory=/roms`,
`system_directory=/roms/bios`).

## The two data files (in `/usr/share/reduxos/`)
- **`systems.tsv`** — every system: folder, label, default core/engine, required BIOS filename(s),
  file extensions. 53 systems mirroring the stock set.
- **`bios-reference.tsv`** — **filenames + md5 + size only** (no content) for a known-good BIOS set
  (532 files), so drop-ins can be verified. Add your own rows for anything not listed.

## Tools
| Command | What it does |
|---|---|
| `redux-setup-roms [TARGET]` | build/repair the folder tree (default `/roms`); writes a README into each system folder saying which core and BIOS it needs. Idempotent. Runs once at first boot via `reduxos-roms-setup.service`. |
| `redux-bios-check [BIOSDIR]` | validate `/roms/bios` against the reference: present/OK, present/wrong-md5, and per-system which BIOS is still missing. Read-only. |

## Dropping in BIOS (the easy path)
1. Copy your BIOS files into `/roms/bios/` (over the network as `dale`, or on the card).
2. Run `redux-bios-check`. It tells you, per system, what's present and what's still needed, and flags
   any file whose md5 doesn't match the reference.

## Emulator cores (separate track, R36 build)
`systems.tsv` names the intended core per system. The cores themselves are a separate effort: 10 ship
today (see [`reduxos-frontend.md`](reduxos-frontend.md)); the rest are to be built from source (the
`pcsx_rearmed` pattern, scaled) or added from noble, and **PortMaster** ported. **Proprietary content
is deliberately excluded** (no PICO-8 binary, no BIOS) — those stay user-supplied. Non-commercially
licensed cores keep this a **private** build, never the public release. A53 performance for Saturn,
Dreamcast, PSP, N64 and NAOMI is unproven and will need the device to judge.

**Cores, launcher, PortMaster (R36 part 2):** see [`reduxos-cores-portmaster.md`](reduxos-cores-portmaster.md).
