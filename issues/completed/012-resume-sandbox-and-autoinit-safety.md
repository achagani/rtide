# 012: Resumed Codex sandbox and workspace auto-init safety

- Status: completed
- Priority rank: 1
- Branch: `issue/012-resume-sandbox-and-autoinit-safety`
- Worktree: `../rtide-worktrees/012-resume-sandbox-and-autoinit-safety`

## Problem

Two defects surfaced from real use:

1. **Every resumed Codex turn fails.** `codex exec resume` does not accept
   `--sandbox`, but issue 002 added `--sandbox workspace-write` (and
   `--sandbox read-only`) to the resume command. Codex exits with
   `error: unexpected argument '--sandbox' found`, so the agent reports a failed
   turn for any conversation with a saved session id. New sessions work.

2. **Auto-init can turn an unsafe directory into a giant repository.** For a
   workspace that is not already a Git repository, the launcher runs
   `git -C "$DIR" init` followed by `git -C "$DIR" add -A`. If a user opens
   RTIDE with `$HOME` (or another large tree) as the directory, this stages the
   entire home directory — including unreadable system data such as Waydroid —
   printing hundreds of `warning: could not open directory …: Permission denied`
   lines and writing gigabytes of loose objects. On this host it created a 5.5 GB
   `~/.git` with 86,353 blobs and no commits.

## Goal

Resume commands preserve the selected sandbox policy in a way Codex accepts, and
workspace auto-init never initializes a repository in a directory it should not,
nor scans a large or sensitive tree.

## Non-goals

- Change what Codex sandbox modes mean.
- Auto-init arbitrary user directories.
- Delete or migrate repositories RTIDE did not create.

## User-facing behavior

A resumed conversational turn runs normally under the selected permission policy.
Opening a non-repository directory initializes a small, bounded repository only
when that is safe; opening `$HOME`, an existing repository, or a directory with no
safety margin never triggers a broad `git add`.

## Dedicated worktree

- Branch: `issue/012-resume-sandbox-and-autoinit-safety`
- Path: `../rtide-worktrees/012-resume-sandbox-and-autoinit-safety`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- Update `docs/architecture/runtime-settings.md` (permission application) and add
  an auto-init safety note where the workspace lifecycle is described.

## Technical spec

### Resumed Codex sandbox

- Pass the sandbox policy to `codex exec resume` through a supported mechanism.
  `--sandbox` is rejected on resume; the config override form is accepted:
  `-c 'sandbox_mode="workspace-write"'`, `-c 'sandbox_mode="read-only"'`, or
  `-c 'sandbox_mode="danger-full-access"'`.
- `unrestricted` resume keeps `--dangerously-bypass-approvals-and-sandbox`.
- `native` resume passes no sandbox override.
- Add a regression test asserting the resumed command contains the accepted form
  and never a bare `--sandbox` on `exec resume`.

### Auto-init safety

- Never auto-init when the resolved directory is `$HOME` or a parent of it, `/`,
  a mount root, or a system directory.
- Never auto-init when the directory already contains a `.git` entry (already a
  repository) or is inside any existing Git repository.
- Never auto-init a directory whose tree is unsafe to scan: refuse when the
  directory contains another RTIDE workspace, a nested repository, or exceeds a
  bounded entry/size ceiling before staging.
- Fail the initialization path with a clear, actionable message rather than
  silently scanning; the workspace can still open without a repository, and
  fork features should report that a repository is required.
- Seed files (`.gitignore`, `.tweb/`, `.rtide/memory/`) must never be written to
  `$HOME`.

## Implementation plan

1. Fix the resume sandbox arguments and add provider tests.
2. Add an auto-init guard with explicit unsafe-directory and bounded-scan checks.
3. Add regression tests for `$HOME`-like directories and large/unsafe trees.

## Acceptance criteria

- [ ] A resumed Codex turn runs with the selected policy and no argument error.
- [ ] `unrestricted` resume still bypasses the sandbox; `native` adds nothing.
- [ ] Opening `$HOME` never runs `git init`/`git add` and never seeds files there.
- [ ] Auto-init still works for a normal small project directory.
- [ ] Unsafe or oversized directories are refused with an actionable message.
- [ ] Tests cover both defects.

## Test plan

- Provider regression tests for new, resumed, and each permission policy.
- Auto-init guard tests for `$HOME`, an existing repo, and a normal directory.
- Manual resume of an existing RTIDE conversation.

## Notes

Reproduced on this host: `codex exec resume --sandbox workspace-write …` →
`error: unexpected argument '--sandbox' found`; and RTIDE auto-init created a
5.5 GB `~/.git` with 86,353 loose blobs and no commits after opening `$HOME`.

## Worktree cleanup checklist

- [ ] Merge or otherwise integrate the accepted change into `main`.
- [ ] Verify the integrated result from the primary checkout.
- [ ] Remove `../rtide-worktrees/012-resume-sandbox-and-autoinit-safety`.
- [ ] Delete `issue/012-resume-sandbox-and-autoinit-safety` with `git branch -d`.

## Completion notes

Completed in worktree `../rtide-worktrees/012-resume-sandbox-and-autoinit-safety`,
branch `issue/012-resume-sandbox-and-autoinit-safety`, as RTIDE 0.2.62.

### Resumed Codex sandbox

`codex exec resume` rejects `--sandbox`, so resumed turns now pass the policy as
`-c sandbox_mode="workspace-write"` / `-c sandbox_mode="read-only"`.
`unrestricted` resume keeps `--dangerously-bypass-approvals-and-sandbox`, and
`native` resume adds no override. Verified end to end: a real Codex session was
created and then resumed successfully under the workspace and unrestricted
policies.

### Auto-init and workspace safety

- `rtide_workspace_safe` refuses `$HOME`, any ancestor of `$HOME`, `/`, and
  filesystem mount roots before creating or writing anything, with an actionable
  message. RTIDE stores per-workspace state in the workspace, so these can never
  be workspaces.
- `rtide_seed_safe` gates project scaffolding so convention files, `.gitignore`,
  and the memory seed are never written into a broad directory.
- `rtide_autoinit_safe` runs `git init`/`add -A` only for a small, standalone
  project directory, refusing existing/nested repositories, workspace
  containers, and directories above `RTIDE_AUTOINIT_MAX_ENTRIES` (5000). The
  nested checks use `-mindepth 2` so a workspace's own seeded `.rtide` is not
  mistaken for a child.
- The welcome page falls back to `~/.cache/rtide/welcome/` when the workspace
  cannot be written, so a refused broad directory cannot crash the launcher.

Evidence: this defect created a 5.5 GB `~/.git` (86,353 loose blobs, no commits)
and thousands of `could not open directory … Permission denied` warnings when
`$HOME` was opened. That has been removed, and a relaunch of `$HOME` is now
refused without writing `~/.git`, `~/.tweb`, `~/.gitignore`, or `~/q`. Full
`make install` suite passed; RTIDE 0.2.62 is the active immutable release. Added
`tests/test-autoinit-safety.sh` and extended `tests/test-provider.sh` and
`tests/test-permissions.sh`.

Not yet done: worktree removal and branch deletion.
