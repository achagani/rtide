# 002: Live workspace settings and permission reliability

- Status: proposed
- Priority rank: 1
- Branch: `issue/002-runtime-permission-policy-switching`
- Worktree: `../rtide-worktrees/002-runtime-permission-policy-switching`

## Problem

Workspace settings are fragmented across setup, startup prompts, global config,
workspace config, and runtime commands. The installed `0.2.48` unrestricted startup
path succeeds, but live agent and permission changes persist desired state without
reliably changing the running agent because pane discovery parses literal `\t` text
as real tab delimiters. This can falsely report a security de-escalation.

## Goal

Provide one in-session settings surface for every startup-configurable option, with
truthful desired/effective state, safe permission transitions, explicit apply timing,
verification, rollback, and preserved work.

## Non-goals

- Circumvent permission controls enforced by an agent harness or host platform.
- Silently elevate access.
- Pretend all harnesses support identical sandbox semantics.
- Apply restart-bound settings silently or lose active conversation state.
- Replace user-level configuration with workspace-only state.

## User-facing behavior

From a running workspace, users can open Settings and modify provider, harness, model,
permission policy, agent height, output width, shell, auto-float, default directory,
and worktree root where their scope permits. The UI distinguishes desired, effective,
pending, failed, and restart-required values. Unrestricted startup and live switching
work with explicit confirmation; unsupported harness capabilities are never presented
as effective.

## Dedicated worktree

- Branch: `issue/002-runtime-permission-policy-switching`
- Path: `../rtide-worktrees/002-runtime-permission-policy-switching`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- `docs/architecture/runtime-settings.md` (to be created by this issue)

## Technical spec

- Define one settings schema with type, scope, default, validation, precedence,
  capability requirements, apply class, verification, and rollback behavior.
- Represent global desired defaults, workspace desired overrides, and runtime
  effective state separately.
- Support explicit apply classes: immediate, next turn, next operation, and
  restart-required.
- Fix tmux pane discovery using an unambiguous format/parser contract and verify the
  effective running agent before reporting success.
- Treat `workspace`, `observe`, `native`, and `unrestricted` as explicit policies;
  require typed confirmation before broader access.
- Declare permission capabilities per harness and reject or label unsupported modes.
- Parse config as data rather than sourcing arbitrary shell, and write atomically.
- Preserve conversation state across controlled agent restarts when supported; roll
  back desired state or report a clear pending/failed state otherwise.

## Implementation plan

1. Document the settings schema, scopes, precedence, and apply classes.
2. Fix pane discovery and add effective-state verification for agent changes.
3. Add one live Settings interface covering all startup-configurable values.
4. Add per-harness capability handling, rollback, and transition tests.
5. Reproduce unrestricted startup and live transitions end to end.

## Acceptance criteria

- [ ] Unrestricted startup reaches a ready workspace after typed confirmation.
- [ ] The current effective policy and all startup-configurable settings are visible.
- [ ] Every startup setting can be changed in working mode or clearly marked as
      restart-required with an explicit apply action.
- [ ] Supported permission policies apply to subsequent tool calls and are verified
      against the running agent.
- [ ] Broader access requires confirmation; unsupported harness policies cannot be
      displayed as effective.
- [ ] Failed transitions preserve or restore the previous effective configuration.
- [ ] Existing conversation and workspace state continue safely after a switch.
- [ ] Config writes preserve unrelated values and cannot execute shell content.

## Test plan

- Unit tests for settings schema, validation, precedence, and atomic persistence.
- Pane-discovery regression tests using literal and real delimiter fixtures.
- Policy and capability matrix for every harness.
- Runtime tests proving desired and effective values converge or fail visibly.
- Pseudo-terminal unrestricted startup and active-workspace settings tests.
- Security review of elevation, rollback, and config parsing.

## Notes

Installed `0.2.48` fixes the older fzf confirmation exit and unrestricted startup was
reproduced successfully. The confirmed current defect is live application: tmux emits
literal `\t` sequences while `awk -F '\t'` expects actual tabs, so the running agent
is not found or restarted even though `.rtide/agent` changes. Provider, model, and
permission commands share this risk. `agent_lines` and `tweb_pct` are currently live;
other settings have mixed or unused behavior that this issue must make explicit.

## Worktree cleanup checklist

- [ ] Integrate and verify the accepted change on `main`.
- [ ] Remove `../rtide-worktrees/002-runtime-permission-policy-switching`.
- [ ] Delete `issue/002-runtime-permission-policy-switching` safely.

## Completion notes

Completed in worktree `../rtide-worktrees/002-runtime-permission-policy-switching`,
branch `issue/002-runtime-permission-policy-switching`, as RTIDE 0.2.49.

- Added `libexec/rtide/settings`: one schema, safe non-executing atomic
  persistence, desired/effective resolution, capability checks, and process
  published effective state (`docs/architecture/runtime-settings.md`).
- Replaced every `source "$CONFIG"` with `load_config_file`; partial or
  hand-edited configs fall back to schema defaults instead of aborting.
- Fixed pane discovery: tmux now filters `@rtide-role=agent` and each candidate
  path is queried separately, so literal `\t` and real tabs in paths both work.
- `rtide agent`, `rtide permissions`, and `rtide settings apply` restart the
  wrapper and verify a new PID published matching effective state before
  reporting success; failures roll desired state back to the last effective
  agent configuration.
- Added the in-session `rtide settings edit` surface plus `status`, `schema`,
  `set`, and `apply`; surfaced `settings` in help and the action menu.
- Declared the per-harness permission capability matrix: codex enforces
  workspace/observe/native/unrestricted, others are `native` only and cannot be
  shown as effective for unsupported policies.
- Made `auto_float` explicitly `explicit-only`, since RTIDE never floats during
  an agent turn; it is stored but never reported as an applied runtime value.
- Codex resumed turns now enforce the selected sandbox for `workspace` and
  `observe`, not only new turns.

Evidence: full `make install` suite passed and RTIDE 0.2.49 is the active
immutable release. End-to-end unrestricted startup reached a ready workspace
with `permission_policy=unrestricted` and the agent PID published in
`.rtide/effective-settings.json`; a non-converging transition test confirmed
rollback to the previous effective policy.

Not yet done: integration into `main`, worktree removal, and branch deletion.
