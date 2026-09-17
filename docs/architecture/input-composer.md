# Input composer architecture

## Boundary

The agent controller owns capture and lifecycle, while `provider` owns harness CLI
syntax. Input crosses that boundary as an immutable `Submission`: exact LF-normalized
text plus zero or more immutable `Attachment` records. Queue, steer, resend, history,
and provider dispatch retain the whole submission rather than consulting mutable
composer state.

`libexec/rtide/composer.py` is dependency-free so the installed runtime remains a
single self-contained payload. It uses raw terminal mode only while idle composition
is active and restores terminal settings in `finally`. Enter sends, Ctrl+J and
recognized modified-Enter sequences insert LF, Ctrl+G invokes `$VISUAL`/`$EDITOR`,
Alt+V reads an image clipboard, and bracketed paste inserts one atomic text value.
Unknown escape sequences are ignored rather than inserted into the draft.

## Viewport and status

The composer redraws one status row, an optional attachment row, and a scrolling
text viewport. The viewport is bounded to eight rows and to the current terminal
height. In the default three-row pane it scrolls rather than resizing tmux, preserving
the editor and output geometry. During a harness turn the existing compact live
control line remains available for queue, steer, interrupt, and resend commands.

## Attachments

User paths and clipboard bytes are snapshots, never pass-through references. Staged
files live under `.rtide/attachments/<agent-run>/`, directories are mode `0700`, and
files are mode `0600`. PNG and JPEG are validated by signatures; text, JSON, XML,
and PDF local files require a recognized MIME suffix. Empty, missing, special,
unsupported, and oversized inputs fail before provider execution. Defaults are 10
MiB per item and eight items per submission; `RTIDE_ATTACHMENT_MAX_BYTES` can lower
or raise the byte bound.

Wayland uses `wl-paste --list-types` and an explicit MIME read. X11 uses `xclip` as a
fallback. Helpers run without a shell and with timeouts. Clipboard capture accepts
PNG or JPEG only and reports text-only/headless states without altering the clipboard.
`/attach PATH`, `/attachments`, and `/remove NUMBER` provide a portable path and
inspection lifecycle independent of desktop clipboard support.

The run-specific staging directory is removed when the controller exits. Removing a
token deletes only its staged copy. Source paths are never deleted. Keeping staged
copies for the controller lifetime allows exact resend semantics without reopening a
possibly changed user file.

## Provider capabilities

The agent passes repeated `--attachment PATH MIME NAME` triples to `provider run`.
The adapter validates existence and capability before emitting any harness command:

| Harness | Representation | Constraint |
|---|---|---|
| Codex | repeated `-i PATH` | PNG/JPEG only |
| OpenCode | repeated `-f PATH` | accepted staged file types |
| Hermes | `--image PATH` | one PNG/JPEG |
| Claude | explicit attachment path block appended to prompt | accepted staged file types |

Claude's path representation is deliberately visible in the effective request. No
adapter silently drops an attachment. Shell output remains `%q`-quoted and provider
execution continues through Bash for multiline safety.

## Failure and compatibility

One-line Enter remains the immediate path. Slash commands and status markers remain
controller commands. Attachment validation and capability errors occur before the
harness process starts. External-editor failure or cancellation leaves the original
draft intact, and its private temporary file is removed. Non-TTY input retains a
line-oriented fallback for automation.
