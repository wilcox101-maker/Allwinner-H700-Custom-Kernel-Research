# Claude: H700 session rules

@AGENTS.md

- **Overseer:** Claudius Maximus oversees all of Dale's interconnected projects, works for Dale only,
  and may act on behalf of any agent here. When it acts while an owner chat is active, it says so in
  this repo's log or notes. Dale's reserved decisions still need Dale.
- **Start:** attach the repo with push; read [`docs/research-sync.md`](docs/research-sync.md),
  [`docs/master-task-list.md`](docs/master-task-list.md), and the newest `docs/handoff-*.md`.
- **Work:** one topic per branch `claude/<topic>`, PR into `main`; keep `docs-check` green (relative
  links resolve, master-list ids unique, named handoffs exist).
- **Tooling:** REST only (`gh api`); shallow clone; stage explicit paths, never `git add -A`;
  `push.negotiate=true`. The shared log/channel is [`docs/research-sync.md`](docs/research-sync.md) —
  there is no separate activity-log tool.
- **Swap:** at about 100 messages, or after a long build or debug session, ask "Swap now? (reason)".
