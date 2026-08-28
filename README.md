# RTIDE — Rich Terminal IDE

A terminal-based agentic development workspace with a **blended single-tool UI**:
the agent's terminal is the *input* surface, and all substantive output is
channeled through **tweb** as graphically rich HTML.

```
┌──────────────┬──────────────┐
│  nvim (0)    │  tweb (2)    │
│  ~50%        │  ~50%        │
├──────────────┴──────────────┤
│  agent (1) — ~30% strip     │
└─────────────────────────────┘
```

The agent strip is a thin **input box** at the bottom — exactly as tall as its
content (3 lines by default, set with `agent_lines` in `~/.rtide/config`); the
nvim + tweb panes get the rest. It shows a one-line status (`● idle` / `● working: Edit src/app.py` /
`● done (12s)`) and a prompt — type a request, and the harness runs
non-interactively, rendering its response to tweb. Zoom it with `prefix+a` when
you need to work in it.

## What you get

- **One workspace per project** — nvim + tweb + agent strip, launched with `rtide <dir>`
- **Provider + harness selection** — on every new workspace, RTIDE asks which AI
  provider (anthropic / openai / ollama) and which harness (claude / codex / hermes /
  opencode) to use, filtered to compatible combinations and configured to actually talk
  to the chosen provider (env vars / CLI flags)
- **tweb as the output surface** — the agent renders answers as self-contained HTML
  (charts, tables, cards) in the tweb pane; the terminal stays minimal
- **Welcome screen** — each new workspace opens with a branded welcome page in tweb
  (workspace, provider/harness/model, keybindings)
- **Agent as an input box** — the agent pane is a pure input line with a one-line
  status; the harness runs non-interactively per request (`claude -p` / `codex exec` /
  `hermes chat -q` / `opencode run`) and the conversation renders in tweb,
  auto-scrolling to the newest message
- **Files in the editor** — files the agent creates or edits open in the nvim pane
  via `rtide-open <path>` (a convention the agent follows)
- **Agent-independent memory** — one store every agent reads and writes through the
  same interface (`rtide-mem`), with an auto-updater that captures `MEM:` lines
- **Hip shell surface** — `:terminal` in nvim opens your configured shell (fish by
  default); `tweb-run <cmd>` renders program output in the current workspace's tweb pane
- **Multi-tasking** — `prefix+r` jumps between workspaces; `rtide ls` shows the fleet

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/achagani/rtide/main/install.sh | bash
# or, without hosting:
git clone https://github.com/achagani/rtide ~/rtide && ~/rtide/install.sh
```

The installer clones the source to `~/rtide`, creates the runtime dir `~/.rtide/`
(`config` + `memory/`), symlinks helpers into `~/.local/bin/`, wires `~/.local/bin`
onto PATH for fish (`fish_add_path`), installs the user-level `~/.claude/CLAUDE.md`
convention, wires the `tweb` + `rtide-mem` MCP servers into every installed harness,
and runs `tweb doctor --fix`. Re-running is safe (idempotent).

**Dependencies** (checked by `rtide doctor`): `tweb`, `tmux` ≥ 3.3, `nvim`, a
terminal (`kitty` or `ghostty`), and at least one agent. The default shell **fish**
is auto-installed with `--with-deps` (apt/brew); zsh is the fallback.

## Provider & harness selection

RTIDE is agent-agnostic. On every new-workspace launch it prompts for:

1. **Provider** — `anthropic`, `openai`, or `ollama` (only those with ≥1 installed
   compatible harness are offered)
2. **Harness** — `claude`, `codex`, `hermes`, or `opencode` (only installed + compatible
   with the chosen provider)
3. **Model** — provider-specific list (free text allowed)

The choice is stored per-workspace in `$DIR/.rtide/agent` (overriding the global
config) and the agent pane is launched with the right env vars / flags for the combo.

Pickers use **fzf** when it's installed (fuzzy search, so a long ollama model list
isn't a wall of numbers) and fall back to a numbered list otherwise. The previously
selected provider / harness / model is the default — it's highlighted first, so
pressing Enter keeps it.

### Compatibility matrix

| provider \ harness | claude | codex | hermes | opencode |
|---|---|---|---|---|
| **anthropic** | ✅ | ❌ | ✅ | ✅ |
| **openai** | ❌ | ✅ | ✅ | ✅ |
| **ollama** | ✅ | ✅ | ✅ | ✅ |

- **claude + anthropic** — OAuth (`claude login`) or `ANTHROPIC_API_KEY`
- **claude + ollama** — Ollama's Anthropic-compatible endpoint
  (`ANTHROPIC_BASE_URL=http://127.0.0.1:11434`, `ANTHROPIC_AUTH_TOKEN=ollama`, …)
- **codex + openai** — OAuth (`codex login`) or `OPENAI_API_KEY`
- **codex + ollama** — native `codex --oss --local-provider ollama --model <model>`
- **hermes / opencode** — work with all three providers

`rtide matrix` prints this table; `rtide auth` checks the configured provider is
authenticated; `rtide agent` re-picks provider/harness/model for the current workspace
and restarts its agent pane.

## Usage

```
rtide            → pick a workspace to resume or start one (unknown names only search; type `new` or pick `+ new workspace` to create — first run walks through setup)
rtide <dir>      → launch/attach the workspace for <dir> (prompts for provider/harness/model)
rtide new        → guided new workspace
rtide switch     → same picker as bare rtide (resume / new)
rtide ls         → list workspaces
rtide sweep      → capture pending MEM: memories from every live session
rtide quit [dir] → sweep that session's memories, then kill it (from inside or out)
rtide kill [dir] → alias for quit
rtide agent      → re-pick provider/harness/model for the current workspace
rtide config     → view/edit/reset the global config (set key=value, reset [layout|agent|all])
rtide refresh    → apply the global config's layout to a running workspace (prefix+R)
rtide menu       → open the quick-switcher menu for a session (prefix+M)
rtide auth       → check auth for the configured provider
rtide matrix     → print the provider×harness compatibility matrix
rtide setup      → re-run the wizard
rtide doctor     → verify deps
rtide --no-ask   → skip the provider/harness prompt (use stored config)
```

**In-workspace keybindings** (tmux prefix, default `Ctrl-b`):

```
prefix+t → zoom tweb      (chat mode)
prefix+a → zoom agent
prefix+r → switch workspace
prefix+R → refresh workspace layout (apply global config to panes)
prefix+M → quick-switcher menu (switch / change agent / new / refresh / zoom / config / sweep / quit)
prefix+Q → quit workspace (asks y/n, sweeps memories first)
prefix+z → zoom any pane  (tmux default)
```

**Applying settings** — layout settings (`agent_lines`, `nvim_pct`, `shell`) live only in
`~/.rtide/config`: the single source of truth, read at launch. `rtide refresh` re-reads it
and applies it to a **running** workspace — no relaunch, nothing materialized per-workspace.

| You want to… | Do this |
|---|---|
| Refresh current workspace's layout | `prefix+R` — any pane in the workspace |
| From a shell inside the workspace | `rtide refresh` (resolves the current session) |
| From outside tmux | `rtide refresh <dir-or-session>` |
| View / change / reset settings | `rtide config` · `rtide config set key=value` · `rtide config reset` |

The provider/harness/model combo stays per-workspace in `.rtide/agent` (`rtide agent`
re-picks it) and is never touched by `rtide refresh`.

`prefix+Q` is the clean way out: it confirms, captures any pending `MEM:` lines
from the agent pane, then kills the session (detaching you back to your shell).
`prefix+d` detaches without quitting — the workspace keeps running.

## Conventions

The agent follows the rules in `AGENTS.md` / `CLAUDE.md` (seeded per project, never
clobbered): terminal is the input surface (one-line status only), substantive output
is rendered as HTML in tweb, files it creates or edits are opened in the editor pane
via `rtide-open <path>`, and durable facts are emitted as `MEM: <slug> — <fact>`
one-liners that the sweep auto-persists to memory.

## Layout

Source and runtime are separated: `~/rtide/` is the git repo (source), `~/.rtide/`
is created by the installer and holds config + data.

```
~/rtide/                  # source (git repo)
├── install.sh
├── bin/rtide             # workspace launcher
├── bin/rtide-provider    # provider/harness knowledge base (compat, launch, run, check, models)
├── bin/rtide-mcp         # MCP wiring helper (tweb + rtide-mem)
├── bin/rtide-mem         # agent-independent memory (CLI + MCP server)
├── bin/rtide-agent       # minimal agent input box (status + prompt, renders to tweb)
├── bin/rtide-open        # open a file in the workspace's nvim pane
├── bin/tweb-render       # render helper (file / stdin)
├── bin/tweb-run          # run a command, render output in tweb
└── share/AGENTS.md       # convention source
    share/template.html   # report template

~/.rtide/                 # runtime (created by install.sh, not in git)
├── config                # global provider/harness/model + layout settings
└── memory/               # global memory store
```

Per-project (seeded automatically): `AGENTS.md`, `CLAUDE.md`, `.tweb/` (gitignored),
`.rtide/agent` (per-workspace provider/harness/model override), `.rtide/memory/`
(committed).

### Output routing

Use `tweb-render <file>` or `tweb-run <command>` from an RTIDE agent or nvim terminal.
The helpers resolve the current tmux session's pane tagged `@rtide-role=tweb`, so
multiple workspaces cannot steal each other's output. They fail clearly if that pane
is missing or duplicated instead of starting a blocking browser in the caller's pane.
Generated command and pipe reports are HTML-escaped and stored under a per-session
cache directory in `~/.cache/rtide/`.

Use `rtide-open <file>` to open a file in the workspace's nvim pane. It finds the
workspace root (nearest `.rtide/` dir) and talks to nvim over its `--listen` socket
(`.rtide/nvim.sock`), so it works from any subdirectory and any harness.
