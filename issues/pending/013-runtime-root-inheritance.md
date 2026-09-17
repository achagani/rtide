# 013: Runtime root inheritance and launcher resilience

- Status: proposed
- Priority rank: 1
- Branch: `issue/013-runtime-root-inheritance`
- Worktree: `../rtide-worktrees/013-runtime-root-inheritance`

## Problem

RTIDE exports `RTIDE_ROOT`, `RTIDE_LIBEXEC_DIR`, `RTIDE_BIN_DIR`, and
`RTIDE_SHARE_DIR` as absolute paths into one specific version directory. When
RTIDE creates a tmux server, tmux snapshots the creating environment as the
server's global environment. The installer then prunes all but the two newest
releases, deleting that exact version. Every subsequent RTIDE launch in the
affected tmux server inherits the dead root and fails immediately:

```
/home/achagani/.local/lib/rtide/current/bin/rtide: line 34:
/home/achagani/.local/lib/rtide/versions/0.2.58/libexec/rtide/picker.sh:
No such file or directory
```

`bin/rtide` also trusts `RTIDE_ROOT` unconditionally, so
`RTIDE_ROOT=/nonexistent bin/rtide --version` fails instead of falling back to
the release it was actually invoked from.

## Goal

A stale inherited runtime root must never break an RTIDE launch: the entry point
validates the root it is told to use and falls back to the release containing the
running script.

## Non-goals

- Change how versions are retained or pruned.
- Stop exporting runtime paths for child processes.

## User-facing behavior

Starting RTIDE in a tmux server that holds stale runtime paths works normally and
uses the currently active release.

## Dedicated worktree

- Branch: `issue/013-runtime-root-inheritance`
- Path: `../rtide-worktrees/013-runtime-root-inheritance`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- Note the version-activation boundary in a runtime architecture document if the
  entry-point contract changes.

## Technical spec

- `bin/rtide` accepts `RTIDE_ROOT` only when it is a valid runtime root: it must
  contain `libexec/rtide/picker.sh` and `VERSION`. Otherwise it recomputes the
  root from the resolved script path.
- A clearly invalid root must not abort the launch; it is ignored and replaced.
- Keep honoring a valid explicit root so `rtide-dev` and tests continue to work.
- Do not reintroduce the failure by exporting the stale value again.

## Implementation plan

1. Validate the inherited root and fall back to the script's own release.
2. Add regression tests for a stale/invalid root and a valid override.

## Acceptance criteria

- [ ] A stale inherited `RTIDE_ROOT` no longer breaks a launch.
- [ ] An invalid `RTIDE_ROOT` falls back to the running release.
- [ ] A valid `RTIDE_ROOT` override is still honored.
- [ ] `rtide --version` works with a nonexistent inherited root.

## Test plan

- Invoke the entry point with stale, invalid, and valid `RTIDE_ROOT` values.
- Confirm the resolved root matches the invoked release.

## Notes

Found only by launching a real session: the live tmux server carried
`RTIDE_ROOT=…/versions/0.2.58` after that version was pruned by retention.

## Worktree cleanup checklist

- [ ] Merge or otherwise integrate the accepted change into `main`.
- [ ] Verify the integrated result from the primary checkout.
- [ ] Remove `../rtide-worktrees/013-runtime-root-inheritance`.
- [ ] Delete `issue/013-runtime-root-inheritance` with `git branch -d`.

## Completion notes

Not completed.
