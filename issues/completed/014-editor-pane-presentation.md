# 014: Editor pane and border presentation

- Status: completed
- Priority rank: 1
- Branch: `issue/014-editor-pane-presentation`
- Worktree: `../rtide-worktrees/014-editor-pane-presentation`

## Problem

A real launch exposes presentation defects that isolated API tests missed:

1. **The review view opens at ~6 columns.** RTIDE creates the window detached at
   80x24, then collapses the editor pane to one column during layout. The
   review-first module opens the Snacks Explorer while the pane is still one
   column wide, so the sidebar clamps to a 6-column sliver over the LazyVim
   dashboard and never reflows. Reproduced with the pane at both 89 and 6
   columns; once opened narrow it stays narrow (`snacks_layout_box` 6x49).
2. **Pane borders show raw launch commands.** `rtide_tmux_chrome` sets
   `pane-border-format` to `#{pane_title}`, and the pane title is the process
   command line, so borders read `SHELL=fish nvim --li /r/m/a/S/P/rtide`,
   `tweb open file:///ru …`, and `/home/achagani/.loca …` instead of
   `editor`, `output`, and `composer`.
3. **Pane titles leak into status/chrome** and are truncated mid-path.

## Goal

A fresh workspace shows a readable review view in a normal-width editor pane and
borders labelled by pane role.

## Non-goals

- Change Snacks Explorer itself.
- Remove the review-first entry behavior.

## User-facing behavior

The editor pane shows the project tree and Git state at full width. Pane borders
read `editor`, `output`, and `composer` and never show command lines.

## Dedicated worktree

- Branch: `issue/014-editor-pane-presentation`
- Path: `../rtide-worktrees/014-editor-pane-presentation`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- Update `docs/architecture/editor-startup.md` and `docs/architecture/tui-design-system.md`.

## Technical spec

### Review view sizing

- The review view must only open once the editor pane is at least a usable width
  (target 40 columns). If it is narrower at startup, defer and open on the first
  `VimResized`/layout settle that reaches the threshold.
- If the view was already opened while narrow, reflow or reopen it once the pane
  widens, so the sidebar is never left clamped.
- Keep the review view optional and non-fatal: if it never gets a usable width,
  leave the normal editor usable and do not block startup.
- The launcher must settle pane geometry before the editor opens where possible,
  reducing the chance the editor ever starts at one column.

### Border labels

- Set a stable per-pane `@rtide-label` (`editor`, `output`, `composer`) at launch
  and in forks.
- `pane-border-format` must render the role label, not `#{pane_title}`. Use the
  role option with a label override and a safe fallback, and never show a raw
  command line.
- Keep no-color and plain modes working.

## Implementation plan

1. Gate/reflow the review view on a usable editor width.
2. Label panes by role and fix the border format.
3. Add tests and verify with a real launch at real client size.

## Acceptance criteria

- [ ] The review view is readable (>= 40 columns) in a normal workspace.
- [ ] Opening narrow and then widening reflows instead of staying clamped.
- [ ] Pane borders read `editor`, `output`, and `composer`.
- [ ] No border or title shows a raw command line.
- [ ] Plain/no-color mode still shows labels.
- [ ] Existing startup and routing behavior is unchanged.

## Test plan

- Headless Neovim check that the view defers under a narrow pane and opens after
  resize.
- Border-format expansion test for each role.
- Real launch at 223x56 verifying the tree width and border labels.

## Notes

Found only by launching a real session. The original issue-001 test asserted the
Snacks API was called and an unnamed buffer existed; it never checked the
resulting window width, so the clamped sidebar passed.

## Worktree cleanup checklist

- [ ] Merge or otherwise integrate the accepted change into `main`.
- [ ] Verify the integrated result from the primary checkout.
- [x] Remove `../rtide-worktrees/014-editor-pane-presentation`.
- [x] Delete `issue/014-editor-pane-presentation` with `git branch -d`.

## Completion notes

Completed in worktree `../rtide-worktrees/014-editor-pane-presentation`, branch
`issue/014-editor-pane-presentation`, as RTIDE 0.2.65.

### Review-view sizing

`share/rtide-review.lua` is now width-aware. It reconciles the Snacks Explorer
against the current pane width on every `VimResized` and on `VeryLazy`: it opens
only at `RTIDE_REVIEW_MIN_COLUMNS` (default 40), closes a sidebar opened below
`RTIDE_REVIEW_MIN_SIDEBAR` (default 30), and collapses duplicates. Verified in a
real session: the editor pane recovered to 89 columns and the Explorer opened at
40 columns instead of a 6-column sliver over the dashboard.

### Pane border labels

`rtide_tmux_chrome` builds `pane-border-format` from a role/label expression
(`@rtide-label` override, else `nvim`→`editor`, `agent`→`composer`,
`tweb`→`output`, else `terminal`). It no longer uses `#{pane_title}`, so borders
no longer show `SHELL=fish nvim --li …`. Verified in the live client: the
rendered borders read `editor`, `output`, and `composer`.

### Two bugs found only in a real launch

1. The module read the picker source from `picker.source`, but Snacks stores it
   at `picker.opts.source`, so every resize spawned another Explorer (visible as
   stacked `Explorer` panels and a wrong file list).
2. `vim.defer_fn` returns userdata, so `vim.fn.timer_stop` raised
   `E5101: Cannot convert given Lua type` inside the resize autocommand. Replaced
   with a libuv timer.

The test stub now mirrors the real `picker.opts.source` field, and a regression
check asserts no stacked explorers, so both defects are caught headlessly.

Evidence: full `make install` suite passed and RTIDE 0.2.65 is the active
immutable release. Added `tests/test-review-view.sh`; the real live session was
restarted and inspected for geometry, borders, and errors.

Not yet done: worktree removal and branch deletion.
