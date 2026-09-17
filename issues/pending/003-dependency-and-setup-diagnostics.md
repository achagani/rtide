# 003: Dependency and setup diagnostics

- Status: proposed
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

Not completed.
