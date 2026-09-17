# 004: TWeb connection recovery

- Status: proposed
- Priority rank: 3
- Branch: `issue/004-tweb-connection-recovery`
- Worktree: `../rtide-worktrees/004-tweb-connection-recovery`

## Problem

A render can be queued while the registered TWeb browser pane is missing,
disconnected, or not yet able to display it.

## Goal

Distinguish queued, connected, and visibly acknowledged output states, and recover a
missing connection when doing so is safe.

## Non-goals

- Claim visual display based only on successful command submission.
- Create duplicate browser panes during an agent turn.
- Mask failures in tmux, TWeb, or workspace registration.

## User-facing behavior

Users see an accurate connection state and an actionable recovery path. RTIDE never
reports output as displayed when it was only queued.

## Dedicated worktree

- Branch: `issue/004-tweb-connection-recovery`
- Path: `../rtide-worktrees/004-tweb-connection-recovery`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- Add or update an output-routing design before changing pane registration,
  acknowledgement, or reconnection boundaries.

## Technical spec

- Model queue submission, pane connection, navigation, and visual acknowledgement as
  distinct states.
- Detect stale or missing registered pane IDs before making display claims.
- Prefer reconnecting the registered pane; create a replacement only through an
  explicit safe path.
- Preserve queued output and explain any state that cannot be automatically recovered.

## Implementation plan

1. Build fixtures for missing, stale, and late-connected panes.
2. Specify acknowledgement and safe recovery behavior.
3. Implement recovery and surface state without duplicate panes.

## Acceptance criteria

- [ ] Missing browser pane is detected before a render claim.
- [ ] Connection state is visible to the user.
- [ ] A safe reconnect or recreate path exists.
- [ ] Queued output is never reported as displayed.

## Test plan

- Disconnected and stale-pane fixtures.
- Reconnect integration tests.
- Duplicate-pane prevention tests.
- Manual visual acknowledgement verification.

## Notes

Readiness and frame-sizing fixes landed after this roadmap item was created, but safe
recovery and visual acknowledgement remain broader than startup readiness.

## Worktree cleanup checklist

- [ ] Integrate and verify the accepted change on `main`.
- [ ] Remove `../rtide-worktrees/004-tweb-connection-recovery`.
- [ ] Delete `issue/004-tweb-connection-recovery` safely.

## Completion notes

Not completed.
