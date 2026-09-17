# 011: Workspace socket filesystem portability

- Status: proposed
- Priority rank: 1
- Branch: `issue/011-workspace-socket-filesystem-portability`
- Worktree: `../rtide-worktrees/011-workspace-socket-filesystem-portability`

## Problem

RTIDE places the Neovim control socket at `.rtide/nvim.sock` inside the workspace
directory. When a workspace lives on a filesystem that cannot host Unix domain
sockets — exFAT, FAT32, and some network mounts, all common for removable and
shared drives — `nvim --listen` fails with `operation not permitted` and the
editor pane never starts. RTIDE then also waits for a socket that can never
appear, so the workspace opens without a working editor.

`tweb` and `workspace-status` already place their sockets/runtime files under
`$XDG_RUNTIME_DIR`; the Neovim socket is the only workspace-local socket.

## Goal

Make workspace control sockets independent of the workspace filesystem so RTIDE
works normally on exFAT/FAT/network mounts, while preserving a stable, discoverable
socket path for `rtide open` and readiness checks.

## Non-goals

- Change where user files, history, or artifacts are stored.
- Require users to move their project off the removable/shared drive.
- Support Unix sockets on filesystems that fundamentally forbid them.

## User-facing behavior

Opening a workspace on an exFAT or similar drive starts the editor normally. The
`nvim --listen` socket lives under the runtime directory, not the project, and
`rtide open <file>` continues to work. A workspace on a supported filesystem
behaves exactly as before.

## Dedicated worktree

- Branch: `issue/011-workspace-socket-filesystem-portability`
- Path: `../rtide-worktrees/011-workspace-socket-filesystem-portability`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- Update `docs/architecture/editor-startup.md` (socket location and readiness) and
  add a runtime-path note if the boundary changes.

## Technical spec

- Resolve the Neovim socket to a per-workspace path under the runtime root:
  `${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/rtide-<uid>/nvim/<workspace-key>.sock`,
  where the key is stable for the workspace (reuse the collision-safe workspace
  identity already used for sessions/status).
- Keep a workspace-local pointer (`nvim.sock` becomes a plain text file holding
  the runtime socket path, or `.rtide/nvim-socket`), so `rtide open` and tooling
  can still discover it from the workspace without assuming socket placement.
- Readiness checks must test the resolved runtime socket, not a path inside the
  workspace, and must fail with an actionable message if the socket cannot be
  created (for example, an unwritable runtime directory).
- Clean up the runtime socket on workspace quit and fork remove, and tolerate a
  stale pointer that no longer points at a live socket.
- Explicitly tolerate a runtime root on a filesystem that also cannot host
  sockets by probing and reporting clearly rather than hanging.

## Implementation plan

1. Add a shared socket-path resolver in `bin/rtide` and use it in launch, fork,
   readiness, cleanup, and `rtide open`.
2. Write the workspace-local pointer and keep it atomic; migrate legacy
   workspace-local sockets in place.
3. Add tests for exFAT-like failure, pointer discovery, readiness, and cleanup.

## Acceptance criteria

- [ ] The editor starts on a workspace whose filesystem cannot host a socket.
- [ ] The socket path is stable and discoverable from the workspace.
- [ ] `rtide open <file>` works with the relocated socket.
- [ ] Readiness waiting uses the resolved socket and never waits on a path that
      cannot exist.
- [ ] Quit/fork-remove clean up the runtime socket and pointer.
- [ ] A stale pointer does not break startup or opening.

## Test plan

- Fixture where the workspace socket bind fails; assert the editor still starts.
- Pointer discovery from a workspace subdirectory.
- Readiness and cleanup regression tests.
- Manual launch of the live RTIDE workspace on `/run/media/.../SharedData`.

## Notes

Reproduced on this host: `/run/media/achagani/SharedData` is exFAT
(`fmask=0022,dmask=0022`) and `bind()` returns `EPERM`; `nvim --listen
.../.rtide/nvim.sock` reports `Failed to --listen: operation not permitted`.
`tweb` (`/run/user/1000/tweb/`) and `workspace-status` already avoid the project
filesystem.

## Worktree cleanup checklist

- [ ] Merge or otherwise integrate the accepted change into `main`.
- [ ] Verify the integrated result from the primary checkout.
- [ ] Remove `../rtide-worktrees/011-workspace-socket-filesystem-portability`.
- [ ] Delete `issue/011-workspace-socket-filesystem-portability` with `git branch -d`.

## Completion notes

Not completed.
