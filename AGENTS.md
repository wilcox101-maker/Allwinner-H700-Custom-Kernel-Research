# Rules for AI collaborators — H700 kernel research

Dale owns the project. The authoritative rules live in [`README.md`](README.md) (`## Ground rules`,
the brevity block, protected `main`); this file gathers the collaboration rules and the project's
place in the wider org. Where they differ, README wins.

## Place in the org
- **Dale** — owner.
- **Claudius Maximus** — general overseer of all of Dale's interconnected projects; works for Dale
  only. It may act on behalf of any agent here (owner, manager, engineers, helpers): read, branch,
  push, comment, and open or merge PRs within this file's rules. What is reserved for Dale stays Dale's.
- **Redux Manager** — coordinates this repo together with the Redux CFW. Findings for Redux go to
  Dale as files, then through the Manager chat.
- This repo is **H700 Research** (ReduxOS: mainline kernel, boot chain, noble userspace), running
  parallel to **Redux CFW**
  ([wilcox101-maker/Anbernic_RG34XXSP_Redux](https://github.com/wilcox101-maker/Anbernic_RG34XXSP_Redux)),
  whose stock device tree this work consumes.
- **Custom Hardware Design** — a shared support project, available to all projects for general support.

## Agents here
- **Deep Research (DR)** and **Kernel Research (KR)** chats. Neither can message the other; their only
  channel is [`docs/research-sync.md`](docs/research-sync.md) — both read it at the start of a work
  block and add to it at the end. Dale carries anything urgent by hand.
- Both chats are **read-only on the Redux repo**; Redux-bound findings go to Dale, then via the Manager.

## Every session
1. Read [`docs/research-sync.md`](docs/research-sync.md),
   [`docs/master-task-list.md`](docs/master-task-list.md), and the newest `docs/handoff-*.md`.
2. Device testing is open (Dale, 2026-11-21, Q12: no longer blocked until Redux v0.5); the goal is the new
   firmware, ReduxOS, led by the Redux CFW Owner. Device sessions are Dale's, run from kits and run sheets;
   tools still never write a card. One topic per branch, PR into `main`; `docs-check` must stay green.
3. Claiming or finishing a task updates its row in `docs/master-task-list.md` and adds a line to
   `docs/research-sync.md`.

## Hard rules (summary — README is authoritative)
- Never write to stock images or to any card; tools here only read images.
- No binaries; no patches copied from other projects — link them by name.
- Never drive an unidentified panel; never undervolt relative to stock; never change the thermal
  critical trip.
- Stock-derived data (panel init sequences, vendor blobs) is not committed (task R9).
- Kernel submission: a tool never adds `Signed-off-by`; the human submitter reviews and signs.
- Every claim says whether it was checked on hardware; "desk only" means it was not.
- `main` is protected: no force-push, no deleting; fix with a new commit or a revert PR.
- Brevity: result first, at most 5 lines; messages between chats at most 3 sentences, detail in a
  linked file.

## Dale decides
Anything irreversible, and the rule files (`AGENTS.md`, `CLAUDE.md`) — merged only with Dale's say-so.
