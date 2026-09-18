# 015: Composer prompt renders at the header's end column

- Status: completed
- Priority rank: 1
- Branch: `issue/015-composer-prompt-alignment`
- Worktree: `../rtide-worktrees/015-composer-prompt-alignment`

## Problem

In a real session the composer's input line renders indented by the width of the
status/header line. The pane shows:

```
╭─ RTIDE  ● ready · type, edit, or prefix+v to speak
RTIDE  ● ready · Enter send · Ctrl+J newline · Ctrl+G editor
                                                            ╰─❯
```

The `╰─❯` prompt starts at column 60 (the header's visible width) instead of
column 0.

Root cause: `Composer._render` writes each line as `"\x1b[2K" + line` followed by
`"\n"`. `ESC[2K` erases the line but does not reset the cursor column, and in raw
mode `\n` performs a line feed without a carriage return. The first rendered line
gets its column reset by the `\r` in the redraw up-move sequence, but every
subsequent line inherits the column where the previous line ended, so the prompt
row is written at the header's end column.

## Goal

The composer's status row, attachment row, and every draft row always start at
column 0 regardless of the previous row's length.

## Non-goals

- Changing the status/header text or the prompt glyph.
- Changing viewport bounds, attachment handling, or key bindings.

## User-facing behavior

Before: the `╰─❯` prompt and any wrapped draft rows start at the column where the
previous row ended. After: every rendered row begins flush left at column 0.

## Dedicated worktree

- Branch: `issue/015-composer-prompt-alignment`
- Path: `../rtide-worktrees/015-composer-prompt-alignment`

## Architecture references

- [`docs/architecture/input-composer.md`](../../docs/architecture/input-composer.md)
- No durable boundary changes; the viewport/status contract is unchanged. No
  architecture update required.

## Technical spec

- In `Composer._render`, each line write must reset the column before erasing:
  emit `"\r\x1b[2K" + line` instead of `"\x1b[2K" + line`.
- The final cursor reposition (`\r` + up-move + `ESC[<col>C`) and the
  extra-line erase block remain otherwise unchanged.
- Raw-mode column model for verification: `\n` preserves the column, `\r` resets
  it to 0, CSI sequences do not move the cursor, `ESC[2K` erases without moving.

## Implementation plan

1. Fix the line write in `Composer._render` to prefix `\r`.
2. Add a headless regression test that models raw-mode columns and asserts every
   visible row (especially the `╰─❯` prompt row) starts at column 0 with a long
   header.
3. Run the full suite via `make install` and verify in a real session.

## Acceptance criteria

- [ ] With a header longer than the prompt prefix, the prompt row renders at
      column 0.
- [ ] Multi-line drafts render every row at column 0.
- [ ] Existing render bounds and redraw behavior are unchanged.
- [ ] Full test suite passes and the installed release renders flush-left in a
      real session.

## Test plan

- `tests/test-composer.py`: new test that feeds `_render` output through a
  raw-mode column model and asserts the visible start column of each row is 0.
- Real-session check: launch the composer in a 3-row pane with the standard
  status line and confirm the prompt is flush left.

## Notes

Found in a live session; the existing render test only counted `ESC[2K`
occurrences and never checked columns, so the misalignment passed unnoticed.

## Worktree cleanup checklist

- [x] Merge or otherwise integrate the accepted change into `main`.
- [x] Verify the integrated result from the primary checkout.
- [x] Remove `../rtide-worktrees/015-composer-prompt-alignment`.
- [x] Delete `issue/015-composer-prompt-alignment` with `git branch -d`.

## Completion notes

Completed in worktree `../rtide-worktrees/015-composer-prompt-alignment` as
RTIDE 0.2.66.

`Composer._render` now writes each row as `\r\x1b[2K` + text, so every row
starts at column 0 regardless of the previous row's length. Two regression
tests in `tests/test-composer.py` model raw-mode columns (`\n` preserves the
column, `\r` resets it, CSI never moves) and assert every visible row —
including the `╰─❯` prompt row — starts flush left; both were confirmed to
fail against the pre-fix code (prompt at column 60) and pass after.

Evidence: full `make install` suite passed; 0.2.66 is the active immutable
release; a real 3-row pane running the installed `composer.py` renders the
prompt at column 0. Limitation: the agent pane of the session that was
already running keeps the pre-fix renderer until that session restarts.
