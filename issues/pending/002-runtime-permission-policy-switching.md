# 002: Runtime permission policy switching

- Status: proposed
- Priority rank: 3
- Branch: `issue/002-runtime-permission-policy-switching`
- Worktree: `../rtide-worktrees/002-runtime-permission-policy-switching`

## Problem

Permission policy is selected at workspace startup, and changing it can disrupt the
active agent flow or make the effective policy unclear.

## Goal

Let users inspect and safely change the active workspace permission policy while
preserving their work and requiring explicit confirmation for broader access.

## Non-goals

- Circumvent permission controls enforced by an agent harness or host platform.
- Silently elevate access.
- Make all harnesses support identical sandbox semantics.

## User-facing behavior

The current policy is visible. Selecting a supported replacement applies it to
subsequent agent work, with confirmation before unrestricted access and an explicit
message if an agent restart is required.

## Dedicated worktree

- Branch: `issue/002-runtime-permission-policy-switching`
- Path: `../rtide-worktrees/002-runtime-permission-policy-switching`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- Add a permission-boundary decision before implementation if policy application or
  session continuity changes.

## Technical spec

- Treat `workspace`, `observe`, `native`, and `unrestricted` as explicit policies.
- Expose the effective policy for the active workspace.
- Persist changes in `.rtide/agent` without losing unrelated provider settings.
- Require typed confirmation before unrestricted access.
- Preserve conversation state across any required wrapper restart, or clearly state
  the limitation when a harness cannot do so.

## Implementation plan

1. Audit current `rtide permissions` behavior for every harness and policy.
2. Specify continuity and restart semantics.
3. Implement missing visibility or transition behavior and test the matrix.

## Acceptance criteria

- [ ] Current policy is visible.
- [ ] Supported policies can be selected at runtime.
- [ ] Subsequent tool calls use the new policy.
- [ ] Broader access requires confirmation.
- [ ] Existing work continues safely after a switch.

## Test plan

- Policy transition matrix for supported harnesses.
- Tool-command generation and persistence tests.
- Security review of elevation confirmation.
- Manual continuity test in an active workspace.

## Notes

RTIDE already has a `permissions` command and policy tests, but the roadmap criteria
were never reverified and the current command may restart the agent pane. Keep this
issue pending until continuity and effective-policy behavior are proven.

## Worktree cleanup checklist

- [ ] Integrate and verify the accepted change on `main`.
- [ ] Remove `../rtide-worktrees/002-runtime-permission-policy-switching`.
- [ ] Delete `issue/002-runtime-permission-policy-switching` safely.

## Completion notes

Not completed.
