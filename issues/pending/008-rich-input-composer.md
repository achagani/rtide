# 008: Rich multiline input composer

- Status: proposed
- Priority rank: 1
- Branch: `issue/008-rich-input-composer`
- Worktree: `../rtide-worktrees/008-rich-input-composer`

## Problem

RTIDE's agent pane is a single-line `readline` prompt. It cannot comfortably compose
structured multiline requests, review larger text before submission, or attach pasted
images and files as first-class input.

## Goal

Replace the one-line prompt with a fast bounded composer supporting multiline editing,
reliable text paste, image/file attachments, external-editor handoff, and structured
submission to harness adapters.

## Non-goals

- Rebuild the entire agent harness TUI inside RTIDE.
- Require image-capable models or silently discard unsupported attachments.
- Store clipboard images permanently outside workspace runtime state.
- Make ordinary one-line submissions slower or more complicated.

## User-facing behavior

The input area grows within a bounded height as users write multiple lines. Enter
submits by default; Ctrl+J and configured modified-Enter bindings add a newline, and
an external editor is available for long drafts. Pasting text preserves content.
Pasting or dropping an image/file creates a removable attachment item showing name,
type, and size. Submission clearly reports unsupported attachment capabilities.

## Dedicated worktree

- Branch: `issue/008-rich-input-composer`
- Path: `../rtide-worktrees/008-rich-input-composer`

## Architecture references

- [`docs/architecture/README.md`](../../docs/architecture/README.md)
- `docs/architecture/input-composer.md` (to be created by this issue)

## Technical spec

- Introduce a dedicated composer process/module with an in-memory multiline buffer,
  cursor movement, history, bounded viewport, paste detection, and attachment list.
- Emit a structured submission containing text plus validated attachment metadata;
  keep provider/harness formatting in adapter code.
- Stage clipboard images under ignored workspace runtime storage with safe names,
  restrictive permissions, size limits, cleanup, and MIME validation.
- Prefer Wayland clipboard MIME discovery (`wl-paste`) with explicit fallbacks; accept
  dropped/local paths independently of clipboard support.
- Define capability negotiation so image-capable harnesses receive attachments and
  unsupported combinations fail before a turn starts.
- Preserve slash commands, question answering, history, cancellation, readiness
  markers, and low-latency one-line use.
- Handle terminal key ambiguity explicitly and keep Ctrl+J as a portable newline path.

## Implementation plan

1. Document composer state, submission schema, key contract, and attachment lifecycle.
2. Build the bounded multiline editor and external-editor handoff.
3. Add text paste plus image/file staging and capability-aware provider adaptation.
4. Integrate the composer with agent status and tmux resizing.
5. Add unit, pseudo-terminal, and end-to-end attachment tests.

## Acceptance criteria

- [ ] Users can edit and submit multiline text without escape-sequence leakage.
- [ ] One-line Enter submission remains immediate and backward-compatible.
- [ ] Text pastes preserve newlines and large pastes remain responsive.
- [ ] Image clipboard paste and local image/file attachment are supported when host
      helpers and the selected harness capability are available.
- [ ] Attachments can be inspected and removed before submission.
- [ ] Unsupported, oversized, missing, or invalid attachments fail clearly before a
      provider request starts.
- [ ] External-editor handoff round-trips the draft and handles cancellation safely.
- [ ] Composer growth is bounded and does not collapse editor or output panes.
- [ ] Draft/attachment cleanup does not delete user-owned source files.
- [ ] Idle composer CPU remains negligible and normal keystrokes render without
      perceptible lag.

## Test plan

- Buffer, cursor, history, viewport, keybinding, and paste unit tests.
- Clipboard helper fixtures for image MIME, text-only, unavailable helper, and errors.
- Attachment validation, staging permissions, cleanup, and capability matrix tests.
- Pseudo-terminal tests for multiline submission, Escape/cancel, and external editor.
- End-to-end tests proving structured text/image input reaches supported adapters.
- Geometry and latency checks at narrow, normal, and large terminal sizes.

## Notes

Reference patterns: Claude Code supports modified newline and image paste/drag/drop;
Codex exposes interactive image input and a multiline composer; OpenCode provides
file references and external-editor composition; Gemini CLI implements multiline
buffers, paste placeholders, and clipboard MIME helpers. Useful primary sources:
https://code.claude.com/docs/en/common-workflows#work-with-images,
https://developers.openai.com/codex/image-inputs,
https://opencode.ai/docs/tui/, and
https://geminicli.com/docs/reference/keyboard-shortcuts.

## Worktree cleanup checklist

- [ ] Integrate and verify the accepted change on `main`.
- [ ] Remove `../rtide-worktrees/008-rich-input-composer`.
- [ ] Delete `issue/008-rich-input-composer` safely.

## Completion notes

Not completed.
