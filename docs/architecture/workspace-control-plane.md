# Workspace control plane

## Decision

Tmux remains the owner of RTIDE sessions, windows, clients, and pane geometry. RTIDE
adds a small control plane that records agent lifecycle state independently from
terminal text and presents that state through tmux. It does not introduce a daemon
or a shared agent process.

`libexec/rtide/workspace-status` is the canonical status API. Agent wrappers publish
to it, workspace and fork pickers read from it, and the workspace rail uses it for
discovery and switching. Tmux inventory is authoritative for liveness, so a record
cannot keep a dead session in the UI.

## Identity and storage

Each active RTIDE window has one record keyed by tmux server identity and immutable
tmux window ID. The record also carries a collision-safe workspace identity derived
from the canonical absolute path. Session names and basenames are labels only and
are never identity keys. Fork records include their source path and branch, allowing
the UI to group them beneath the source workspace without assuming naming patterns.

Records live under `$RTIDE_STATUS_DIR`, or otherwise
`$XDG_RUNTIME_DIR/rtide-$UID/workspace-status` (with the system temporary directory
as the final fallback). Writes take a per-record advisory lock, write and fsync a
unique temporary file, atomically rename it, then fsync the directory. This prevents
partial reads and lost updates between lifecycle and heartbeat writers.

The schema contains:

- workspace identity, canonical path, branch, fork source, tmux server/session/window
- lifecycle: `working`, `input-needed`, `done`, `ready`, or `error`
- attention reason and acknowledgement state
- event update and heartbeat timestamps plus publisher PID

`stale` is a read-time presentation state, not a fabricated lifecycle transition.
It is derived only when the explicit heartbeat age exceeds 90 seconds (configurable
for tests with `RTIDE_STATUS_STALE_SECONDS`).

## Lifecycle and attention

The agent publishes `ready` after initialization, `working` immediately before a
turn, `input-needed` when a completed response explicitly requests an answer,
`done` after other successful turns, and `error` after a failed turn or result load.
The existing agent process emits a heartbeat every 30 seconds.

`input-needed` and its reason remain sticky until an answer is submitted. Merely
viewing that workspace does not clear it. `done` carries `done-unseen` attention and
becomes `ready` only when a client focuses the window. Starting another turn also
acknowledges prior input attention. Error remains visible until a later lifecycle
event supersedes it.

## Rail and switching

Prefix `w` opens a tmux-owned overlay. Clients at least 72 columns wide receive a
full-height right rail; smaller clients receive a centered compact picker. Escape
hides it without changing layout. Enter or a mouse selection switches using
`tmux switch-client -c <invoking-client> -t <target-window>`. The explicit client is
captured before the popup opens, so one attached client cannot move another.

The rail never creates or recreates a session and never changes pane roles, TWeb
routing files, or floating-pane state. Tmux window formats expose the same canonical
state icon for ambient visibility. The workspace picker and fork manager obtain
their lifecycle labels from the same inventory rather than inferring status from
window names or elapsed activity.

## Cost model

There is no status daemon and no per-cell command. Publication performs one atomic
write and updates two tmux window options only on lifecycle events. Each live agent
does one heartbeat write every 30 seconds. Opening a rail or picker performs one
`tmux list-windows` call and one bounded pass over small JSON records; the rail does
not poll while hidden. Stale evaluation occurs during those reads.
