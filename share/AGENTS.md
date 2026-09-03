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
- For implementation tasks with three or more meaningful phases, use the
  `implementation-dashboard` output type via `rtide progress`. Initialize it
  before editing, publish an event whenever a substep starts, completes, or is
  blocked, and finalize it with the implementation summary, tests, version, and
  release state. Re-render the same dashboard throughout so progress is visible
  in real time; never label integration or deployment complete until verified.

## Visual communication
- Prefer the clearest visual form for the material: relevant images, maps for
  places and routes, charts for quantitative patterns, diagrams or timelines for
  systems and sequences, and tables/cards for structured comparisons.
- Put useful source and destination links beside the claim, place, or media they
  support. Give images meaningful alt text and captions where context matters.
- Make visuals responsive and readable in the tweb pane. A page's layout and CSS
  must be self-contained; remote source media is allowed when it adds real value.
- Do not add decorative filler, invent media or sources, or force a visual when
  concise text communicates the result better.

## Art direction
- Before writing HTML, choose a content-specific visual concept and composition.
  A travel brief might feel cartographic and topographic; an investigation might
  read like an editorial dossier; a system explanation might use a technical
  blueprint. Do not reuse the same dashboard/card-grid treatment by default.
- Give substantive pages one memorable visual anchor: a useful map, annotated
  diagram, data composition, timeline, image treatment, or typographic centerpiece.
  The anchor must communicate information, not merely decorate the page.
- Compose with rhythm and contrast: mix wide and narrow sections, editorial text
  blocks, whitespace, scale, layering, and asymmetry where appropriate. Avoid
  endless rounded rectangles, generic gradient backgrounds, and oversized titles.
- Use a deliberate type scale, restrained content-led palette, and consistent
  spacing system. Small details—rules, labels, captions, legends, hover/focus
  states, and transitions—should reinforce the chosen visual language.
- Read `.tweb/DESIGN_PLAYBOOK.md` before creating a substantive artifact.
  Treat `template.html` as an accessible technical foundation, not a visual theme
  to copy unchanged. Check the result at the actual tweb pane size before rendering.

## Rendering
1. Write a self-contained HTML file to `.tweb/<slug>.html`
   (inline CSS, dark theme, no external deps).
2. Render: `rtide render .tweb/<slug>.html`
   — this resolves the tweb pane belonging to the current RTIDE workspace.
3. Keep automatic output in the workspace pane, including dense content. Use
   `rtide render .tweb/<slug>.html`; never pass `--float` during an agent turn.
   Floating is an explicit user-controlled viewing action.
4. Confirm `rtide render` succeeds. Do not merely say an artifact was produced.
   Never run `tweb split`, `tweb open`, or restart the tweb daemon inside RTIDE;
   those commands can create a duplicate browser pane. Always use `rtide render`.
5. Live updates: edit the HTML and run `rtide render` again; it keeps the update in
   the current workspace.
6. Use `.tweb/template.html` as a technical foundation and the design
   playbook for art direction; adapt both to the subject instead of cloning a theme.

## Tools
- `rtide render <file>` / `rtide render --url <url>` — open a file/URL in tweb
- `rtide run -- <cmd>` — run a program, render its output in tweb (exit code, duration)
- `tweb mcp` tools — navigate, click, fill, eval, snapshot (drive the browser)

## Development isolation
- When working on RTIDE itself, do feature development in a dedicated sibling Git
  worktree and branch, not in the primary `~/rtide` checkout. Create one with
  `git worktree add ../rtide-<topic> -b <topic-branch> main`, launch RTIDE from
  that worktree, and verify the location with `git status --short --branch` and
  `git worktree list` before editing. Reserve the primary checkout for release
  integration, installation, and emergency recovery.
- RTIDE-created conversation forks use global managed storage outside Git
  repositories. Set `RTIDE_WORKTREE_ROOT` temporarily or `worktree_root` in
  `~/.rtide/config` persistently; stop a legacy fork before moving it with
  `rtide fork migrate <name>`.

## Files in the editor
- After creating or editing a file, run `rtide open <path>` to open it in the
  editor pane (nvim). The agent's terminal stays minimal; the file shows up in
  the editor window instead of the agent's output.

## Shell
- `:terminal` in nvim opens the configured hip shell (VS Code-style, on demand)
- `python script.py | rtide render -` — pipe any command's output into tweb

## Memory (auto)
- At session start, read the memory index: `rtide memory list` (or read `MEMORY.md`)
- When you discover a durable fact (user preference, decision + rationale, tool gotcha, non-obvious behavior), emit it as a one-line status: `MEM: <slug> — <fact>`
- The sweep auto-persists `MEM:` lines — no tool call needed. (You can also call `rtide memory add` directly.)
- Project facts → project scope (default); cross-project facts → `--global`
