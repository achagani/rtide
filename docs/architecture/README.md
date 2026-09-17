# RTIDE architecture

This directory records durable system reasoning: boundaries, integration decisions,
data flows, constraints, and tradeoffs that should outlive one implementation issue.
Implementation scope and acceptance criteria belong in [`issues/`](../../issues/README.md).

## Current boundaries

- `bin/rtide` is the single public command and workspace/session orchestrator.
- `libexec/rtide/` contains release-private runtime helpers for agents, providers,
  rendering, memory, forks, progress, and related operations.
- `share/` contains installed templates, static UI, agent convention templates, and
  output assets.
- `.rtide/` is per-workspace runtime state. Only `.rtide/memory/` is intentionally
  eligible for source control.
- `~/.rtide/` holds user-level configuration and global memory.
- `~/.local/lib/rtide/versions/` contains immutable installed releases selected by
  the `current` symlink; the stable launcher remains outside a release payload.
- Tmux owns workspace layout and pane identity. Neovim is the editor surface, TWeb is
  the rich output surface, and the agent pane is the input surface.
- Manual implementation worktrees live outside the primary checkout under
  `../rtide-worktrees/`. RTIDE conversation forks use their separately configured
  global managed root.

## Documentation rules

- Link architecture references from every issue spec, or explicitly state why none
  is needed.
- Read referenced documents before implementation.
- Add or update a document when work changes a durable boundary, flow, integration,
  compatibility contract, constraint, or significant tradeoff.
- Keep task sequencing and acceptance criteria in the issue rather than duplicating
  them here.
- Record a decision in `decisions/` when alternatives and consequences matter beyond
  one issue.

## Decision records

- [0001: Local specification tracking](decisions/0001-local-spec-tracking.md)

## Runtime contracts

- [Runtime settings](runtime-settings.md): desired/effective state, safe persistence,
  apply classes, verified agent transitions, and permission capabilities.
- [Editor startup](editor-startup.md): review-first entry, session precedence, and
  runtime control-socket placement for filesystems that cannot host sockets.
