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

The agent strip is a thin input/output bar at the bottom (default 30% of the
window, set with `agent_pct` in `~/.rtide/config`); the nvim + tweb panes get
the rest. Zoom it with `prefix+a` when you need to work in it.

## What you get

- **One workspace per project** — nvim + tweb + agent strip, launched with `rtide <dir>`
- **Provider + harness selection** — on every new workspace, RTIDE asks which AI
  provider (anthropic / openai / ollama) and which harness (claude / codex / hermes /
  opencode) to use, filtered to compatible combinations and configured to actually talk
  to the chosen provider (env vars / CLI flags)
- **tweb as the output surface** — the agent renders answers as self-contained HTML
  (charts, tables, cards) in the tweb pane; the terminal stays minimal
- **Agent-independent memory** — one store every agent reads and writes through the
  same interface (`rtide-mem`), with an auto-updater that captures `MEM:` lines
- **Hip shell surface** — `:terminal` in nvim opens your configured shell (fish by
  default); `tweb run <cmd>` renders program output in tweb
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
rtide            → launch/attach the default workspace (first run walks through setup)
rtide <dir>      → launch/attach the workspace for <dir> (prompts for provider/harness/model)
rtide new        → guided new workspace
rtide switch     → picker over all rtide-* sessions (fzf if present)
rtide ls         → list workspaces
rtide sweep      → capture pending MEM: memories from every live session
rtide quit [dir] → sweep that session's memories, then kill it (from inside or out)
rtide kill [dir] → alias for quit
rtide agent      → re-pick provider/harness/model for the current workspace
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
prefix+Q → quit workspace (asks y/n, sweeps memories first)
prefix+z → zoom any pane  (tmux default)
```

`prefix+Q` is the clean way out: it confirms, captures any pending `MEM:` lines
from the agent pane, then kills the session (detaching you back to your shell).
`prefix+d` detaches without quitting — the workspace keeps running.

## Conventions

The agent follows the rules in `AGENTS.md` / `CLAUDE.md` (seeded per project, never
clobbered): terminal is the input surface (one-line status only), substantive output
is rendered as HTML in tweb, and durable facts are emitted as `MEM: <slug> — <fact>`
one-liners that the sweep auto-persists to memory.

## Layout

Source and runtime are separated: `~/rtide/` is the git repo (source), `~/.rtide/`
is created by the installer and holds config + data.

```
~/rtide/                  # source (git repo)
├── install.sh
├── bin/rtide             # workspace launcher
├── bin/rtide-provider    # provider/harness knowledge base (compat, launch, check, models)
├── bin/rtide-mcp         # MCP wiring helper (tweb + rtide-mem)
├── bin/rtide-mem         # agent-independent memory (CLI + MCP server)
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
