# Workspace conventions

This workspace is part of **RTIDE** (Rich Terminal IDE): the agent's terminal is the
*input* surface, and all substantive output is channeled through **tweb** as rich HTML.

## Output model
- Your terminal is the INPUT surface. Print only a one-line status
  (e.g. "working…", "rendered to .tweb/foo.html"). Keep terminal output minimal.
- Short answers (a sentence or two) → answer inline.
- Substantive output (research, comparisons, explanations, status, diffs)
  → render as HTML in tweb.

## Rendering
1. Write a self-contained HTML file to `.tweb/<slug>.html`
   (inline CSS, dark theme, no external deps).
2. Render: `tweb navigate file://<abs path to .tweb/<slug>.html>`
   — this shows the page in the tweb pane, wherever you run it from.
3. Dense content: render, then `tweb float` to pop the tweb pane to a desktop window.
4. Live updates: render once, then `tweb eval "…"` to update the page in place.
5. Use the template at `~/rtide/share/template.html` for consistent styling.

## Tools
- `tweb navigate <url>` — show a page in the tweb pane (the agent's render command)
- `tweb-render <file>` / `tweb-render --url <url>` — open a file/URL in tweb
- `tweb-run <cmd>` — run a program, render its output in tweb (exit code, duration)
- `tweb float` / `tweb pin` — pop to desktop window / return to pane
- `tweb mcp` tools — navigate, click, fill, eval, snapshot (drive the browser)

## Shell
- `:terminal` in nvim opens the configured hip shell (VS Code-style, on demand)
- `python script.py | tweb-render -` — pipe any command's output into tweb

## Memory (auto)
- At session start, read the memory index: `rtide-mem list` (or read `MEMORY.md`)
- When you discover a durable fact (user preference, decision + rationale, tool gotcha, non-obvious behavior), emit it as a one-line status: `MEM: <slug> — <fact>`
- The sweep auto-persists `MEM:` lines — no tool call needed. (You can also call `rtide-mem add` directly.)
- Project facts → project scope (default); cross-project facts → `--global`
