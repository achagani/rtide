# 001: Review-first LazyVim startup

- Status: proposed
- Priority rank: 3
- Branch: `issue/001-review-first-lazyvim-startup`
- Worktree: `../rtide-worktrees/001-review-first-lazyvim-startup`

## Problem

Normal startup opens an editing context before the user has reviewed the project and
its Git state.

## Goal

Start with project files and changes visible so the user intentionally selects a file
before editing begins.

## Non-goals

- Replace LazyVim or its plugin manager.
- Ignore explicit file arguments supplied by the user.
- Define a general-purpose file explorer independent of RTIDE startup.

## User-facing behavior

A fresh RTIDE editor pane opens a review-oriented project view with no real file
selected. Explicit file arguments continue to open directly.

## Dedicated worktree

- Branch: `issue/001-review-first-lazyvim-startup`
- Path: `../rtide-worktrees/001-review-first-lazyvim-startup`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- Before implementation, add or update an editor-startup design document if the
  solution changes session restoration or editor lifecycle boundaries.

## Technical spec

- Use the existing LazyVim configuration and Snacks Explorer where practical.
- Keep the initial buffer free of a real project file on a fresh launch.
- Surface Git state for changed files.
- Preserve direct opening for explicit file arguments.
- Define precedence between this behavior and session restoration before coding.

## Implementation plan

1. Reproduce fresh, resumed, and explicit-file startup behavior in disposable repos.
2. Specify session-restoration precedence and configure the review-first entry view.
3. Add headless checks where possible and verify manually in RTIDE.

## Acceptance criteria

- [ ] Fresh launch opens no real file buffer.
- [ ] Changed files show Git state.
- [ ] Selecting a normal file opens it.
- [ ] Tracked changed files open an appropriate review view.
- [ ] Explicit file arguments still work.

## Test plan

- Disposable Git fixtures with clean, modified, staged, and untracked files.
- Headless Neovim startup checks.
- Manual fresh, resumed, and explicit-file RTIDE launches.

## Notes

The prior roadmap selected Snacks Explorer because it is already available. A local
progress record exists but shows all implementation phases pending, so this issue is
not treated as complete.

## Worktree cleanup checklist

- [ ] Integrate and verify the accepted change on `main`.
- [ ] Remove `../rtide-worktrees/001-review-first-lazyvim-startup`.
- [ ] Delete `issue/001-review-first-lazyvim-startup` safely.

## Completion notes

Not completed.
