# Editor startup

A fresh RTIDE workspace should begin with the project and its Git state visible,
not with an arbitrary file already open. Review-first startup changes only the
*entry view*; it never changes LazyVim, the plugin manager, or the editor
lifecycle.

## Precedence

1. **Explicit file argument** — when the launcher builds an editor command with a
   file, that file opens directly and the review view is skipped.
2. **Resumed workspace** — a running session keeps its editor state; review-first
   applies only when a fresh editor pane is created.
3. **Fresh launch** — the editor opens the review view with no real file buffer.
4. **`RTIDE_REVIEW_FIRST=0`** — opt out and restore plain editor startup.

## Mechanism

`share/rtide-review.lua` is a self-contained module the launcher `dofile`s after
startup, so it does not depend on the user's keymaps or plugin list. It:

- requires the LazyVim-provided Snacks Explorer;
- opens it rooted at the workspace with `git_status` enabled so changed,
  staged, and untracked files are visible;
- leaves the initial buffer unnamed (`buflisted = false`), so no real project
  file is selected on a fresh launch;
- degrades safely: if Snacks is unavailable it notifies the user and returns
  `false` instead of breaking editor startup.

The launcher builds the command in `rtide_nvim_command`, which is shared by the
fresh-workspace and fork launch paths. Explicit-file precedence and the opt-out
are enforced there, so the review view cannot leak into a direct open.

## Control socket placement

The editor control socket does **not** live in the workspace. `.rtide/nvim.sock`
inside a project breaks whenever the project is on a filesystem that cannot host
a Unix domain socket — exFAT, FAT32, and some network mounts, all common for
removable and shared drives. Neovim then fails with `Failed to --listen:
operation not permitted` and the editor pane never starts.

`libexec/rtide/runtime-paths.sh` resolves the socket under the per-user runtime
root:

```
${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/rtide-<uid>/nvim/<workspace-key>.sock
```

The workspace keeps a small pointer file, `.rtide/nvim-socket`, recording the
live path, so `rtide open` and readiness checks remain discoverable from any
subdirectory without assuming socket placement. Resolution probes the runtime
root first and only falls back to `.rtide/` when the runtime root itself cannot
host a socket; if neither can, RTIDE fails with an actionable message instead of
waiting on a path that can never exist. Quit and fork removal delete the runtime
socket and pointer.

## Boundaries

- LazyVim remains the editor configuration; the module adds one entry behavior.
- Session restoration is owned by Neovim/LazyVim `persistence`; review-first does
  not replace or interfere with restored buffers, because it runs only on a fresh
  editor.
- Selecting a file in the explorer is the normal path into editing; tracked
  changed files open through the same explorer and can use LazyVim's Git tooling.
- Control sockets are runtime state, not project state: they live outside the
  workspace just like `tweb`'s and `workspace-status`'s sockets already do.
