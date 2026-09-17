# 005: Output-pane reliability

- Status: completed
- Priority rank: 1
- Branch: `issue/005-output-pane-reliability`
- Worktree: `../rtide-worktrees/005-output-pane-reliability`

## Problem

A completed response can exist in history without a visible, verified artifact in the
workspace output pane.

## Goal

Ensure completed substantive requests produce discoverable artifacts and accurately
report whether those artifacts were displayed.

## Non-goals

- Force rich visuals when concise text is clearer.
- Treat queue submission as visual acknowledgement.
- Replace TWeb's browser responsibilities inside the agent process.

## User-facing behavior

The latest result is always discoverable through the output pane or history, and any
display failure identifies the stage that failed.

## Dedicated worktree

- Branch: `issue/005-output-pane-reliability`
- Path: `../rtide-worktrees/005-output-pane-reliability`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- Coordinate with issue 004 before changing shared output routing or acknowledgement
  semantics.

## Technical spec

- Produce self-contained artifacts for substantive completed requests.
- Record outputs in workspace history independently from live pane routing.
- Distinguish artifact creation, render queueing, navigation, and acknowledgement.
- Diagnose blank output by stage without inventing successful display state.

## Implementation plan

1. Define reliability invariants across response, command, dashboard, and custom output.
2. Add fixtures for artifact, routing, history, and blank-pane failures.
3. Close remaining gaps and verify at actual pane dimensions.

## Acceptance criteria

- [ ] Every substantive request creates a self-contained artifact.
- [ ] Render completion is distinguished from visual acknowledgement.
- [ ] Output history links to the artifact.
- [ ] Blank-pane diagnostics identify the failure stage.

## Test plan

- Output routing and history tests.
- Blank-pane regression fixtures.
- Artifact link and self-containment checks.
- Manual pane acknowledgement verification.

## Notes

Output routing, history, controls, and fallback behavior have improved substantially,
but the original roadmap criteria were not all explicitly verified. Keep this issue
pending until the remaining acknowledgement gap is resolved.

## Worktree cleanup checklist

- [ ] Integrate and verify the accepted change on `main`.
- [ ] Remove `../rtide-worktrees/005-output-pane-reliability`.
- [ ] Delete `issue/005-output-pane-reliability` safely.

## Completion notes

Completed in worktree `../rtide-worktrees/005-output-pane-reliability`, branch
`issue/005-output-pane-reliability`, as RTIDE 0.2.55.

- Extended issue 004's acknowledgement work with stage-accurate blank-output
  diagnostics. `verify_display` now returns `(ok, stage)` where stage is the
  first unsatisfied step — `artifact`, `pane`, `submit`, or `acknowledge` — and
  each maps to a distinct message (`display failed at <stage>: …`) instead of a
  generic "could not verify".
- Confirmed every substantive request still produces a self-contained artifact:
  the result page has no external `src`/`href`/`<script>` references, verified by
  test.
- Output history links each entry to its artifact and reads custom artifacts'
  authored titles; implementation dashboards remain a distinct output kind.
- Render completion (`submitted`) stays distinct from visual acknowledgement
  across `rtide render`, `rtide run`, and the agent turn boundary.

Evidence: full `make install` suite passed and RTIDE 0.2.55 is the active
immutable release. Added tests for each failure stage, distinct stage messages,
and result-artifact self-containment; existing routing, recovery, and history
tests still pass.

Not yet done: integration into `main`, worktree removal, and branch deletion.
