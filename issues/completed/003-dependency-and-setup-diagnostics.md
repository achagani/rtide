# 003: Dependency and setup diagnostics

- Status: completed
- Priority rank: 1
- Branch: `issue/003-dependency-and-setup-diagnostics`
- Worktree: `../rtide-worktrees/003-dependency-and-setup-diagnostics`

## Problem

Installation and runtime diagnostics can disagree about required tools, supported
package managers, or whether a missing dependency blocks RTIDE.

## Goal

Define requirements once so installation provisions supported dependencies and
`rtide doctor` gives accurate, actionable remediation.

## Non-goals

- Support every operating system or package manager.
- Install optional tools without user intent.
- Hide unsupported-platform limitations.

## User-facing behavior

Installation either provides required dependencies or stops with a clear remedy.
`rtide doctor` distinguishes blockers from optional capabilities and uses the same
requirements as installation.

## Dedicated worktree

- Branch: `issue/003-dependency-and-setup-diagnostics`
- Path: `../rtide-worktrees/003-dependency-and-setup-diagnostics`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- Add a dependency-provisioning document if requirement ownership or package-manager
  boundaries change.

## Technical spec

- Maintain one dependency classification for required, build-time, and optional tools.
- Reuse it across bootstrap installation, package staging, and diagnostics where
  their side-effect constraints allow.
- Keep package-manager staging side-effect free.
- Include concrete commands or documentation links in actionable failures.

## Implementation plan

1. Reconcile existing installer, package-tool, and doctor checks.
2. Identify unsupported or inconsistent cases.
3. Consolidate requirement data and add platform fixtures.

## Acceptance criteria

- [ ] Required dependencies are defined in one matrix.
- [ ] Installer provisions supported dependencies.
- [ ] Doctor reports actionable missing-tool guidance.
- [ ] Optional warnings are separated from blockers.

## Test plan

- Clean-home and clean-machine installation fixtures.
- Supported package-manager matrix.
- Doctor output and exit-code tests.
- Side-effect checks for package-manager staging.

## Notes

Several dependency commits landed after the original roadmap was written, but its
acceptance statuses remain unverified. Reassess the remaining gap rather than
assuming the historical commits completed this issue.

## Worktree cleanup checklist

- [ ] Integrate and verify the accepted change on `main`.
- [ ] Remove `../rtide-worktrees/003-dependency-and-setup-diagnostics`.
- [ ] Delete `issue/003-dependency-and-setup-diagnostics` safely.

## Completion notes

Completed in worktree `../rtide-worktrees/003-dependency-and-setup-diagnostics`,
branch `issue/003-dependency-and-setup-diagnostics`, as RTIDE 0.2.56.

- Added `libexec/rtide/deps`, one canonical matrix classifying every requirement
  as `required`, `build`, or `optional`, with detection, per-manager host
  packages, and an actionable remedy (`docs/architecture/dependency-provisioning.md`).
- `rtide doctor` now renders that matrix, separating `MISSING` blockers from
  `WARN (optional)` capabilities, printing a remedy for each blocker, and
  reporting build tools as informational when TWeb is already installed.
- `scripts/install-deps` requests the exact missing packages for the detected
  manager from the same matrix, so it cannot provision satisfied or
  optional-only tools, and still stops with the explicit missing list when no
  manager is supported.
- The optional speech engine is a warning, never a blocker; the required agent
  harness and tweb remain blockers with concrete remediation.

Evidence: full `make install` suite passed and RTIDE 0.2.56 is the active
immutable release. Added `tests/test-deps.py` (matrix classification, level
separation, per-manager package selection, install scope, and doctor blocker vs
optional separation). Existing installation assertions now verify the matrix is
the single source of truth.

Not yet done: integration into `main`, worktree removal, and branch deletion.
