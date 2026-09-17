# 007: Rank pending features

- Status: completed
- Priority rank: operational
- Branch: `issue/007-rank-pending-features`
- Worktree: `../rtide-worktrees/007-rank-pending-features`

## Problem

Pending feature specs have stable IDs but no explicit execution order, so the roadmap
does not communicate which feature should be addressed first.

## Goal

Assign each pending product feature a unique numeric priority rank and present the
roadmap in that order without changing any issue identity.

## Non-goals

- Implement any pending product feature.
- Renumber issue IDs when priorities change.
- Rank process-only or housekeeping issues in the product backlog.

## User-facing behavior

Each pending feature shows a priority rank, with rank 1 as the next recommended job,
and the roadmap lists features in that same order.

## Dedicated worktree

- Branch: `issue/007-rank-pending-features`
- Path: `../rtide-worktrees/007-rank-pending-features`

## Architecture references

- [`0001: Local specification tracking`](../../docs/architecture/decisions/0001-local-spec-tracking.md)
- No additional architecture document is needed because this change only adds
  planning metadata and updates a non-canonical view.

## Technical spec

- Add `Priority rank` metadata to the issue template.
- Require unique positive integer ranks for pending product features; lower is higher.
- Rank issues in dependency-aware order: connection recovery, output reliability,
  permission switching, dependency diagnostics, then editor startup.
- Reorder and label the roadmap to match canonical issue metadata.

## Implementation plan

1. Document priority semantics in the tracker README and template.
2. Add unique ranks to pending feature issues.
3. Reorder and label the roadmap.
4. Validate rank uniqueness, range, and roadmap order.

## Acceptance criteria

- [x] Every pending product feature has a unique rank from 1 through 5.
- [x] Lower numbers are documented as higher priority.
- [x] Stable issue IDs and filenames are unchanged.
- [x] The roadmap order and labels match issue metadata.
- [x] Local documentation links and whitespace checks pass.

## Test plan

- Parse ranks from pending issue files and assert the sequence is exactly 1 through 5.
- Parse roadmap issue links and compare their order with sorted issue ranks.
- Run local-link validation and `git diff --check`.

## Notes

This issue is operational and is not itself part of the ranked product backlog.

## Worktree cleanup checklist

- [x] Integrate and verify the accepted change on `main`.
- [x] Remove `../rtide-worktrees/007-rank-pending-features`.
- [x] Delete `issue/007-rank-pending-features` safely.

## Completion notes

Completed on 2026-09-17. Added priority semantics to the tracker and template,
assigned unique ranks 1-5 to all pending product features, and reordered the roadmap
to match. Automated rank, order, local-link, and whitespace checks passed. No runtime
source or installed payload changed.
The issue branch was fast-forwarded into `main`, then its worktree and merged branch
were removed.
