# Allwinner H700 Custom Kernel Research

Research and prototypes for an **Ubuntu 24.04 LTS (noble) arm64** distribution for Allwinner H700
handhelds, starting with the **Anbernic RG34XX-SP**.

**Status: research phase, desk work only.** Nothing in this repository has been booted on an H700
device yet. The test device is unavailable until the Redux v0.5 milestone; device-dependent tasks are
tracked as `blocked: device` in [`docs/master-task-list.md`](docs/master-task-list.md).

## Layout
| Path | What |
|---|---|
| [`docs/master-task-list.md`](docs/master-task-list.md) | Master task list: device tasks (K-IDs), desk tasks (R-IDs), decisions for Dale (Q-IDs), hand-offs |
| [`docs/research-sync.md`](docs/research-sync.md) | Running log between the Deep Research and Kernel Research chats |
| `docs/*.md` | Findings, one document per topic (index below) |
| [`r5/`](r5/) | R5: noble userspace prototype (mmdebstrap + QEMU sizing scripts and results) |
| [`tools/`](tools/) | Read-only analysis tools for stock images |
| [`patches/u-boot/`](patches/u-boot/) | Our u-boot patches (build-tested, not booted) |

## Findings index
| Doc | Topic |
|---|---|
| `docs/r5-noble-userspace-prototype.md` (in progress) | R5: minimal noble arm64 rootfs, QEMU at 512 MB / 1 GB / 2 GB, NM vs iwd+networkd |
| [`docs/r4-noble-firmware-audit.md`](docs/r4-noble-firmware-audit.md) | R4: Wi-Fi/BT firmware in noble, kernel config needs, BT config gap |
| [`docs/handoff-deep-research-2026-11-13.md`](docs/handoff-deep-research-2026-11-13.md) | Deep Research handoff, 2026-11-13 |

More findings documents from the Claude Project are being moved here.

## Ground rules
- **Never write to stock images or to any card.** Tools here only read images.
- Stock-derived data (panel init sequences, vendor config blobs) is **not** committed: its
  redistribution terms are unknown (task R9). Use `tools/extract_rg34xxsp_panels.py` on your own image.
- Every claim says whether it was checked on hardware. "Desk only" means it was not.

## Licence
GPL-3.0 for this repository's own content (see `LICENSE`). Patches against u-boot and Linux carry
those projects' licences (GPL-2.0+ / GPL-2.0).
