# 006: Adopt local issue and architecture workflow

- Status: completed
- Branch: `issue/006-local-spec-workflow`
- Worktree: `../rtide-worktrees/006-local-spec-workflow`

## Problem

RTIDE has a visually useful roadmap and local progress dashboards, but no tracked,
reviewable source of truth connecting implementation scope, architecture decisions,
acceptance criteria, and worktree cleanup.

## Goal

Establish a repository-local issue/spec workflow, migrate the existing roadmap
identities, add durable architecture documentation, and standardize issue-scoped
worktrees without imposing RTIDE repository conventions on downstream projects.

## Non-goals

- Add a hosted issue tracker or third-party project-management dependency.
- Change the runtime implementation of `rtide progress`.
- Mark migrated roadmap work complete without explicitly verifying its criteria.
- Add RTIDE repository-specific process rules to `share/AGENTS.md`.

## User-facing behavior

Contributors and agents can find pending and completed implementation specs under
`issues/`, follow their architecture references, work in predictable isolated
worktrees, and trace completion evidence without duplicating the full specification
in local progress state.

## Dedicated worktree

- Branch: `issue/006-local-spec-workflow`
- Path: `../rtide-worktrees/006-local-spec-workflow`

## Architecture references

- `docs/architecture/README.md` (created by this issue)
- `docs/architecture/decisions/0001-local-spec-tracking.md` (created by this issue)

## Technical spec

- Make Markdown files under `issues/` canonical for implementation scope and state.
- Preserve the numeric identities of `RTIDE-001` through `RTIDE-005` during migration.
- Keep `docs/roadmap.html` as a non-canonical visual index linked to issue files.
- Store durable design reasoning under `docs/architecture/` and decisions under
  `docs/architecture/decisions/`.
- Require issue paths in `rtide progress` objectives without changing its data schema.
- Adopt `issue/NNN-short-slug` branches and
  `../rtide-worktrees/NNN-short-slug` worktrees for manual implementation work.

## Implementation plan

1. Add workflow documentation and a reusable issue template.
2. Migrate the five existing roadmap items into pending issue files.
3. Add an architecture index and decision record for the tracking model.
4. Update root `AGENTS.md`, `README.md`, and the roadmap presentation.
5. Validate structure, references, and documented commands.

## Acceptance criteria

- [x] `issues/README.md`, `issues/TEMPLATE.md`, `issues/pending/`, and
      `issues/completed/` are tracked.
- [x] Existing roadmap IDs `001` through `005` have pending issue files.
- [x] Every issue template section requested by the workflow is present.
- [x] `docs/architecture/README.md` and a tracking decision record are present.
- [x] Root agent and contributor-facing docs use the selected branch/worktree naming.
- [x] Progress guidance references issue files instead of duplicating specifications.
- [x] The roadmap clearly identifies issue files as canonical and links to them.
- [x] Validation finds no broken local Markdown or roadmap issue links.

## Test plan

- Check all required directories and files exist in Git's index candidate set.
- Verify issue filenames have unique stable three-digit prefixes.
- Verify required template headings and migrated issue headings.
- Resolve every repository-relative Markdown link and roadmap issue link.
- Run `git diff --check` and inspect the final diff.

## Notes

- The primary checkout already contains unrelated, uncommitted RTIDE `0.2.48`
  runtime changes. Integration must preserve them.
- The workflow applies prospectively; existing completed work is not retroactively
  reconstructed as issue files.

## Worktree cleanup checklist

- [x] Merge or otherwise integrate the accepted change into `main`.
- [x] Verify the integrated files from the primary checkout.
- [x] Remove `../rtide-worktrees/006-local-spec-workflow`.
- [x] Delete `issue/006-local-spec-workflow` with `git branch -d` when Git recognizes
      it as merged; use `-D` only when an accepted squash prevents detection.

## Completion notes

Completed on 2026-09-17. Added the canonical issue workflow and template, migrated
RTIDE-001 through RTIDE-005 as pending specs, added the architecture index and ADR,
converted the roadmap into a linked non-canonical view, and updated root agent and
README guidance. Required-section, unique-ID, local-link, and whitespace validation
passed. This documentation/process change does not modify runtime source, bump the
version, or require installation. The issue worktree and branch were removed after
integration verification.
