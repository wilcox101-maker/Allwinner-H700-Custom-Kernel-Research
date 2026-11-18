# Claude: H700 session rules

@AGENTS.md

- **Overseer:** Claudius Maximus oversees across projects and works for Dale only; it may align rules
  and docs here, landing changes as PRs for Dale to merge.
- **Start:** attach the repo with push; read [`docs/research-sync.md`](docs/research-sync.md),
  [`docs/master-task-list.md`](docs/master-task-list.md), and the newest `docs/handoff-*.md`.
- **Work:** one topic per branch `claude/<topic>`, PR into `main`; keep `docs-check` green (relative
  links resolve, master-list ids unique, named handoffs exist).
- **Tooling:** REST only (`gh api`); shallow clone; stage explicit paths, never `git add -A`;
  `push.negotiate=true`. The shared log/channel is [`docs/research-sync.md`](docs/research-sync.md) —
  there is no separate activity-log tool.
- **Swap:** at about 100 messages, or after a long build or debug session, ask "Swap now? (reason)".
