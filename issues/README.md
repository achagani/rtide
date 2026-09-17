# Local issues and implementation specs

This directory is RTIDE's canonical source for implementation scope, acceptance
criteria, and completion evidence. The roadmap is a presentation view; when it
disagrees with an issue file, the issue file wins.

## Lifecycle

1. Before implementation, create or update one file in `issues/pending/` from
   `TEMPLATE.md`.
2. Assign the next unused three-digit prefix. Never reuse or renumber it.
3. Record the dedicated branch and worktree before editing implementation files.
4. Read every linked architecture document. Add or update architecture documentation
   when the issue changes durable boundaries, data flow, integration behavior,
   constraints, or design tradeoffs.
5. Start `rtide progress` with `Issue: issues/pending/NNN-short-slug.md` in the
   objective. Progress state is a local handoff aid, not a duplicate specification.
6. Implement and verify every acceptance criterion in the issue worktree.
7. Fill in completion notes and move the unchanged numeric filename to
   `issues/completed/` only after the issue is complete and verified.
8. Integrate the accepted change into `main`, verify it there, remove the worktree,
   and delete the issue branch.

Allowed statuses are `proposed`, `in progress`, `blocked`, and `completed`.

## Naming and isolation

- Issue file: `issues/pending/NNN-short-slug.md`
- Branch: `issue/NNN-short-slug`
- Worktree: `../rtide-worktrees/NNN-short-slug`

```bash
mkdir -p ../rtide-worktrees
git worktree add ../rtide-worktrees/NNN-short-slug \
  -b issue/NNN-short-slug main
```

Confirm the location before editing:

```bash
git status --short --branch
git worktree list
```

After integration:

```bash
git switch main
git pull --ff-only
git worktree remove ../rtide-worktrees/NNN-short-slug
git branch -d issue/NNN-short-slug
```

Use `git branch -D` only when the work was intentionally accepted through a squash
or another integration method that prevents Git from recognizing it as merged.

## Responsibilities

- Issue specs define implementation scope, behavior, acceptance criteria, and tests.
- [`docs/architecture/`](../docs/architecture/README.md) defines durable system
  reasoning, boundaries, decisions, flows, tradeoffs, and constraints.
- `.rtide/progress/` is ignored local execution state. It should reference the issue
  path and contain only concise checkpoint and handoff information.
- [`docs/roadmap.html`](../docs/roadmap.html) is a non-canonical visual index.

Every implementation change requires an issue/spec, including fixes and refactors,
even when the original request did not explicitly ask for one.
