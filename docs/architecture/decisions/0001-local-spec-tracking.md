# 0001: Local specification tracking

- Status: accepted
- Date: 2026-09-17
- Issue: [`006-local-spec-workflow`](../../../issues/completed/006-local-spec-workflow.md)

## Context

RTIDE had three disconnected forms of planning evidence: a single-file visual
roadmap, ignored local progress dashboards, and Git history. The roadmap was easy to
scan but difficult to review and had already fallen behind implementation. Progress
dashboards captured execution detail but were not durable tracked specifications.

## Decision

- Markdown files under `issues/` are canonical for implementation scope, behavior,
  acceptance criteria, tests, and completion evidence.
- Stable three-digit IDs connect issue files, branches, and manual worktrees.
- Architecture documents contain durable design reasoning; issues link to them.
- The HTML roadmap is a non-canonical presentation that links to issue records.
- Local progress dashboards reference issue paths and carry only execution status and
  concise handoff context.
- Every implementation change begins with an issue and uses its own worktree.

## Consequences

- Specs become independently reviewable and move through a visible Git lifecycle.
- Worktree ownership and cleanup are explicit.
- The roadmap requires synchronization or generation from issue metadata; it cannot
  independently define status.
- Small fixes incur a short issue-writing step, trading speed for traceability.
- Existing work is not considered complete solely because related commits exist; its
  acceptance criteria must be verified.

## Alternatives considered

### Keep the HTML roadmap canonical

Rejected because one compressed file creates noisy diffs, has weak worktree and test
metadata, and had stale statuses.

### Keep issue specs and roadmap as equal sources

Rejected because conflicting scope and status would be inevitable.

### Use only hosted issues

Deferred. A repository-local system remains available offline, branches with the
code, and does not require a hosting provider.
