# 009: Workspace status and switching rail

- Status: proposed
- Priority rank: 3
- Branch: `issue/009-workspace-status-rail`
- Worktree: `../rtide-worktrees/009-workspace-status-rail`

## Problem

RTIDE can run multiple tmux workspace sessions, but users must leave their current
context or open a picker to discover them. Agent state is scattered across terminal
text and window titles, so users cannot see which workspace is working, waiting for
input, complete but unseen, or failed.

## Goal

Add a responsive workspace rail that provides instant switching and trustworthy
agent attention status across concurrent workspaces and conversation forks.

## Non-goals

- Replace tmux as the workspace/session owner.
- Run one central agent process for all workspaces.
- Display fabricated status inferred only from elapsed time.
- Force a permanent wide column on narrow terminals.

## User-facing behavior

A compact full-height rail lists active workspaces and nested forks with clear states:
working, input needed, done unseen, ready, error, and stale. Keyboard and mouse actions
switch immediately. Attention states remain visible until the relevant user action,
and the rail collapses to an overlay/picker when width is constrained.

## Dedicated worktree

- Branch: `issue/009-workspace-status-rail`
- Path: `../rtide-worktrees/009-workspace-status-rail`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- `docs/architecture/workspace-control-plane.md` (to be created by this issue)

## Technical spec

- Define one atomic per-window status record with workspace identity, branch/fork,
  lifecycle state, attention reason, timestamp, and acknowledgement state.
- Make the agent wrapper publish event-driven transitions for working, input needed,
  done, ready, and error; derive stale only from explicit heartbeat policy.
- Keep input-needed and done-unseen sticky until answer/focus acknowledgement.
- Build a responsive tmux-owned rail or pane that discovers all RTIDE sessions without
  basename collisions, groups fork windows, and switches the invoking client only.
- Avoid per-cell or high-frequency polling; update from status events plus a bounded
  low-rate stale timer.
- Preserve current pane roles, TWeb routing, floating behavior, and multi-client safety.
- Expose the same status model to existing pickers and titles to eliminate divergent
  state semantics.

## Implementation plan

1. Document workspace identity, lifecycle, attention, acknowledgement, and stale rules.
2. Implement atomic status publication and fixtures in the agent/session lifecycle.
3. Build responsive rail rendering and invoking-client switching.
4. Integrate forks, mouse/keyboard actions, compact fallback, and attention clearing.
5. Add multi-session, multi-client, stale-state, geometry, and performance tests.

## Acceptance criteria

- [ ] All active RTIDE workspaces appear once with collision-safe identity.
- [ ] Fork windows appear under the correct workspace.
- [ ] Working, input-needed, done-unseen, ready, error, and stale states are distinct
      and driven by documented lifecycle events.
- [ ] Input-needed and done-unseen remain sticky until appropriate acknowledgement.
- [ ] Keyboard and mouse switching target only the invoking tmux client.
- [ ] Switching does not recreate sessions, lose drafts, or reroute another workspace's
      TWeb output.
- [ ] The rail collapses gracefully below its minimum width and can be hidden.
- [ ] Dead sessions and stale records disappear or become stale predictably.
- [ ] Idle status monitoring stays within the documented CPU/process budget.
- [ ] Existing workspace and fork pickers consume the same canonical status data.

## Test plan

- Status state-machine and atomic-write tests.
- Multi-session fixtures including duplicate basenames and nested forks.
- Multi-client switching and acknowledgement tests.
- Dead session, stale heartbeat, error, and input-needed regression tests.
- Narrow/normal/wide geometry snapshots.
- Idle and burst update performance measurements.

## Notes

Herdr (`https://github.com/herdrdev/herdr`) is the primary inspiration for persistent
agent lifecycle visibility. RTIDE should borrow explicit status semantics while
retaining its tmux, Neovim, TWeb, and per-workspace agent ownership model.

## Worktree cleanup checklist

- [ ] Integrate and verify the accepted change on `main`.
- [ ] Remove `../rtide-worktrees/009-workspace-status-rail`.
- [ ] Delete `issue/009-workspace-status-rail` safely.

## Completion notes

Not completed.
