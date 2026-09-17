# 005: Output-pane reliability

- Status: proposed
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

Not completed.
