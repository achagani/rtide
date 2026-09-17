# TUI design system

RTIDE's terminal UI is a quiet instrument panel around native tools. Tmux owns
geometry and workspace chrome, fzf owns searchable selection, the agent owns
composition, Neovim owns editing, and TWeb owns rich output. The design system
standardizes signals at those boundaries without introducing another renderer.

## Semantic tokens

`libexec/rtide/ui.sh` is the source of truth for shell-rendered chrome. Tokens
describe roles rather than hues: background, surface, active surface, text,
muted text, border, focus, working, attention, success, warning, and error.
Consumers must not infer behavior from a literal color. `NO_COLOR`,
`RTIDE_NO_COLOR=1`, or `TERM=dumb` removes authored color; `RTIDE_ASCII=1`
replaces Unicode state marks. Labels and symbols remain present in every mode.

The density vocabulary is `compact` and `full`. Compact pickers target 40% of
the terminal; full pickers target 60% or their containing popup. Borders are
sharp, spacing is one cell around labels, key hints follow `key = action`, and
help remains in headers or the Actions menu rather than occupying a permanent
row.

## State vocabulary

| State | Required label | Meaning |
| --- | --- | --- |
| `ready` | `● ready` / `[ok] ready` | Input is accepted and required surfaces are available. |
| `working` | `◐ working` / `[..] working` | A turn is active. Elapsed time may update at most once per second. |
| `input-needed` | `! input needed` | Progress is blocked on user input. |
| `success` | `● done` / `[ok] done` | The requested operation completed. |
| `warning` | `! warning` | Work can continue with a named limitation. |
| `error` | `× error` / `[x] error` | A named operation failed and should expose recovery. |

Color reinforces these labels but never replaces them. Producers publish state
only on transitions. Tmux formats read window options directly; no status
poller is permitted. The composer may add `qN`, elapsed seconds, and a bounded
activity description without creating a second vocabulary.

## Responsive modes

Each mode preserves the same pane IDs and running processes. A width of one is
a reversible collapsed state, not pane destruction.

| Mode | Geometry contract |
| --- | --- |
| `auto` | Resolves to `balanced` at 110 columns or wider and `output` below 110. |
| `balanced` | Editor and output share the upper region using configured output percentage, each at least 20 columns when possible. |
| `output` | Output is primary; editor remains alive at one column. |
| `edit` | Editor is primary; output remains alive at one column. |
| `compose` | Balanced upper region with a 40% composer, bounded to 6-16 rows. |

`rtide layout MODE` records the requested mode per tmux window. Resize hooks
recompute only on window geometry changes; ordinary pane dragging is not
polled. `auto` is the default, while an explicit named mode remains stable
across terminal resizing. Focus, zoom, and floating panes are temporary
overrides and do not destroy the recorded mode.

## Surface contracts

Pickers call `rtide_picker_options POLICY DENSITY` and append only
data-specific arguments. `select` rejects unknown values; `create` opens an
exact selected match, creates an unmatched exact query, and starts guided
creation from the explicit create row; `freeform` accepts the typed value.
Escape always cancels.

Tmux status is session-scoped and one row. It shows RTIDE identity,
workspace/window, textual agent state, layout mode, and output connection.
Pane titles identify `editor`, `output`, and `composer`; menu and popup chrome
uses the same background, border, focus, and text tokens.

TWeb authored documents remain visually sovereign. Shared output controls use
the semantic focus/border/text roles, own navigation and zoom exactly once,
and are injected on navigation or geometry events. They do not poll while idle.

## Extension contracts

Issue 008's composer may consume the state vocabulary and compact/full density
names. Compact mode owns the configured three-row strip. Expanded composition
requests `compose`, caps growth at 16 rows, publishes `input-needed` when
blocked, and restores the prior mode and focus on exit. It must not introduce a
new spinner, color-only status, or printable root-table key binding.

Issue 009's workspace rail consumes the same state labels and picker tokens.
It starts as an on-demand overlay, restores prior focus on Escape, and creates
no persistent pane or poller. A future pinned rail is allowed only at 160+
columns and must replace other navigation width rather than reducing editor or
output below their minima. Rail entries must obtain state from transition-owned
tmux options or a shared snapshot, never pane scraping.

## Performance budget

- Idle: zero recurring tmux or TWeb subprocesses; zero RTIDE wakeups.
- Active composer: changed activity paints immediately; elapsed time paints at
  most once per second and unchanged events are coalesced.
- Picker/menu first frame: 100 ms ceiling on a warm local machine.
- Layout settle: 200 ms ceiling; one geometry pass per window resize event.
- Output render: navigate once, then observe acknowledgement; retries must not
  resubmit navigation or reinject controls.
- Startup: no fixed sleep on the successful warm path; readiness is staged and
  identifies any blocking surface.

Geometry is tested at narrow and wide widths. Performance regression tests
inspect recurring-loop and subprocess contracts; machine-level CPU and remote
latency remain release smoke measurements because CI load is nondeterministic.
