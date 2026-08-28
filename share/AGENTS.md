# Workspace conventions

This workspace is part of **RTIDE** (Rich Terminal IDE): the agent's terminal is the
*input* surface, and all substantive output is channeled through **tweb** as rich HTML.

## Output model
- Your terminal is the INPUT surface. Print only a one-line status
  (e.g. "working…", "rendered to .tweb/foo.html"). Keep terminal output minimal.
- Every completed request must leave tweb showing a visually designed,
  self-contained result page. Do not use a chat transcript as the primary output.
- Treat each request as its own artifact: strong hierarchy, digestible sections,
  purposeful cards/tables where useful, responsive spacing, and polished typography.
- The RTIDE wrapper supplies a designed standalone fallback for plain responses and
  keeps a separate output-history index. For research, comparisons, plans, reports,
  and other substantive work, create a purpose-built HTML artifact yourself.

## Rendering
1. Write a self-contained HTML file to `.tweb/<slug>.html`
   (inline CSS, dark theme, no external deps).
2. Render: `tweb-render .tweb/<slug>.html`
   — this resolves the tweb pane belonging to the current RTIDE workspace.
3. Dense content: `tweb-render --float .tweb/<slug>.html`.
4. Confirm `tweb-render` succeeds. Do not merely say an artifact was produced.
5. Live updates: edit the HTML and run `tweb-render` again; it keeps the update in
   the current workspace.
6. Use the template at `~/rtide/share/template.html` for consistent styling.

## Tools
- `tweb-render <file>` / `tweb-render --url <url>` — open a file/URL in tweb
- `tweb-run <cmd>` — run a program, render its output in tweb (exit code, duration)
- `tweb mcp` tools — navigate, click, fill, eval, snapshot (drive the browser)

## Files in the editor
- After creating or editing a file, run `rtide-open <path>` to open it in the
  editor pane (nvim). The agent's terminal stays minimal; the file shows up in
  the editor window instead of the agent's output.

## Shell
- `:terminal` in nvim opens the configured hip shell (VS Code-style, on demand)
- `python script.py | tweb-render -` — pipe any command's output into tweb

## Memory (auto)
- At session start, read the memory index: `rtide-mem list` (or read `MEMORY.md`)
- When you discover a durable fact (user preference, decision + rationale, tool gotcha, non-obvious behavior), emit it as a one-line status: `MEM: <slug> — <fact>`
- The sweep auto-persists `MEM:` lines — no tool call needed. (You can also call `rtide-mem add` directly.)
- Project facts → project scope (default); cross-project facts → `--global`
