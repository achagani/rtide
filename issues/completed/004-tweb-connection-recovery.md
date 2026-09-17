# 004: TWeb connection recovery

- Status: completed
- Priority rank: 1
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
- [x] Remove `../rtide-worktrees/004-tweb-connection-recovery`.
- [x] Delete `issue/004-tweb-connection-recovery` safely.

## Completion notes

Completed in worktree `../rtide-worktrees/004-tweb-connection-recovery`, branch
`issue/004-tweb-connection-recovery`, as RTIDE 0.2.54.

- Added a five-state connection model (`connected`, `disconnected`, `missing`,
  `multiple`, `standalone`) to `libexec/rtide/tweb-common.sh`. A pane is only
  reported connected after `tweb status` confirms a running browser in it.
- Queued output is tracked separately; `rtide render`/`run` now print
  `rendered` (acknowledged), `submitted … awaiting acknowledgement`, or
  `queued`, and never claim display for a queued or merely submitted target.
- Recovery reuses the registered pane: `disconnected` panes are reconnected in
  place, and `rtide tweb recover` repairs a browserless registration without
  creating a pane.
- `rtide tweb recreate` is the explicit safe path for a missing pane. It refuses
  when a role pane already exists, so it cannot create a duplicate, and it is
  not invoked during an agent turn.
- Added `rtide tweb status|recover|recreate` and documented the routing contract
  in `docs/architecture/output-routing.md`.

Evidence: full `make install` suite passed and RTIDE 0.2.54 is the active
immutable release. Added `tests/test-tweb-recovery.sh` plus a state-aware `tweb`
fixture covering connected/disconnected/missing/multiple classification,
acknowledged display, queued preservation, in-place reconnect, and
duplicate-refusing recreation. Existing output-routing tests still pass.

Not yet done: integration into `main`, worktree removal, and branch deletion.
