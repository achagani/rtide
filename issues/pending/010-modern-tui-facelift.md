# 010: Modern fast TUI facelift

- Status: proposed
- Priority rank: 2
- Branch: `issue/010-modern-tui-facelift`
- Worktree: `../rtide-worktrees/010-modern-tui-facelift`

## Problem

RTIDE's tmux chrome, menus, status labels, startup feedback, and interaction surfaces
have grown independently. The result works but feels visually flat, inconsistent, and
less polished than current terminal tools; some presentation paths also rely on
repeated subprocess or polling work that can undermine fluidity.

## Goal

Create a coherent modern TUI visual system and interaction language that feels fast,
calm, legible, and distinctive while preserving RTIDE's existing ownership model and
low dependency footprint.

## Non-goals

- Replace tmux, Neovim, TWeb, or fzf with a new full-screen framework.
- Add decoration that reduces information density or accessibility.
- Implement the composer or workspace rail business logic owned by issues 008/009.
- Trade idle performance for animation.

## User-facing behavior

RTIDE presents a restrained "quiet instrument panel": consistent typography-like
hierarchy, semantic color, spacing, borders, focus, state labels, responsive layouts,
and contextual help across startup, status, menus, composer, workspace rail, and
output controls. Interactions feel immediate with no background flicker or churn.

## Dedicated worktree

- Branch: `issue/010-modern-tui-facelift`
- Path: `../rtide-worktrees/010-modern-tui-facelift`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- `docs/architecture/tui-design-system.md` (to be created by this issue)
- Coordinate visual contracts with issues 008 and 009 before final integration.

## Technical spec

- Define reusable semantic tokens for focus, muted text, working, attention, success,
  warning, error, borders, spacing, and compact/full density.
- Normalize tmux status, pane borders/titles, fzf pickers, startup/ready feedback,
  menus, and output chrome around those tokens and one state vocabulary.
- Provide named responsive modes such as balanced, output, edit, and compose while
  preserving pane roles and user resizing.
- Make hints progressive rather than permanently consuming rows; keep actions
  discoverable through the command palette/help.
- Consolidate picker construction and remove avoidable subprocess/polling churn.
- Use event-driven updates and bounded timers only where elapsed time is visible.
- Set measurable startup, interaction, idle CPU, process, and redraw budgets.
- Respect terminal color capability, no-color preferences, keyboard-only operation,
  narrow widths, and reduced-motion expectations.

## Implementation plan

1. Document the design tokens, states, responsive modes, and performance budget.
2. Refactor shared tmux/fzf/status presentation primitives.
3. Apply the system to startup, status, menus, panes, and output controls.
4. Integrate composer and workspace-rail surfaces after their functional merges.
5. Run geometry, accessibility, performance, and end-to-end visual verification.

## Acceptance criteria

- [ ] One documented semantic token/state system drives all RTIDE TUI chrome.
- [ ] Focus, working, input-needed, success, warning, and error are distinguishable
      without relying only on color.
- [ ] Startup, action menus, pickers, pane titles, and status lines share consistent
      spacing, labels, borders, and key-hint grammar.
- [ ] Balanced, output, edit, and compose layouts are reachable and preserve user work.
- [ ] Narrow terminals degrade gracefully without clipped critical actions.
- [ ] Keyboard-only flows and no-color/reduced-motion modes remain usable.
- [ ] Idle RTIDE adds negligible CPU use and no high-frequency process spawning.
- [ ] Common picker/menu actions respond without perceptible delay or flicker.
- [ ] Composer and workspace rail use the same visual/state vocabulary after merge.
- [ ] Existing output routing, pane safety, and workspace lifecycle tests continue to pass.

## Test plan

- Snapshot/text fixtures for tmux format strings and picker construction.
- Narrow, normal, wide, no-color, and reduced-motion manual checks.
- Pane-role, popup-safety, routing, and layout regression suites.
- Startup timing, idle CPU/process count, picker latency, and burst-update measurements.
- Final integrated visual walkthrough after issues 008 and 009 merge.

## Notes

Reference patterns include Zellij's compact chrome, fzf's responsive previews,
Lazygit's context modes, OpenCode's adaptive TUI, Yazi's bounded preview work, and
Ratatui's changed-cell rendering. RTIDE should borrow the principles without adding
a heavyweight runtime dependency.

## Worktree cleanup checklist

- [ ] Integrate and verify the accepted change on `main`.
- [ ] Remove `../rtide-worktrees/010-modern-tui-facelift`.
- [ ] Delete `issue/010-modern-tui-facelift` safely.

## Completion notes

Not completed.
