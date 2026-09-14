#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
SESSION="rtide-fork-test-$$"
MANAGED_BASE="$TEST_TMP/managed-worktrees"
cleanup() {
  local rc=$?
  trap - EXIT
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  if [[ -d "$TEST_TMP/project/.git" ]]; then
    [[ -z "${SECOND:-}" ]] || git -C "$TEST_TMP/project" worktree remove --force "$SECOND" 2>/dev/null || true
    [[ -z "${FORK:-}" ]] || git -C "$TEST_TMP/project" worktree remove --force "$FORK" 2>/dev/null || true
  fi
  [[ -z "${NESTED_FORK:-}" || ! -d "$TEST_TMP/outer/inner/.git" ]] \
    || git -C "$TEST_TMP/outer/inner" worktree remove --force "$NESTED_FORK" 2>/dev/null || true
  find "$TEST_TMP" -depth -type f -delete 2>/dev/null || true
  find "$TEST_TMP" -depth -type l -delete 2>/dev/null || true
  find "$TEST_TMP" -depth -type d -empty -delete 2>/dev/null || true
  exit "$rc"
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$TEST_TMP/home/.rtide" "$TEST_TMP/project/.rtide" \
  "$TEST_TMP/project/.tweb/results"
cat > "$TEST_TMP/home/.rtide/config" <<'EOF'
provider=openai
harness=codex
model=test-model
agent_lines=3
tweb_pct=60
shell=bash
EOF
cat > "$TEST_TMP/project/.rtide/agent" <<'EOF'
provider=openai
harness=codex
model=test-model
EOF
printf '.tweb/\n.rtide/*\n!.rtide/memory/\n' > "$TEST_TMP/project/.gitignore"
printf 'baseline\n' > "$TEST_TMP/project/app.txt"
printf '<html><head><title>Forked artifact</title></head><body><main>prior answer</main></body></html>\n' \
  > "$TEST_TMP/project/.tweb/results/prior.html"
cat > "$TEST_TMP/project/.rtide/output-history.json" <<EOF
[{"request":"prior request","title":"Prior result","kind":"custom artifact","url":"file://$TEST_TMP/project/.tweb/results/prior.html","created":"now","elapsed":1}]
EOF
git -C "$TEST_TMP/project" init -q
git -C "$TEST_TMP/project" add .gitignore app.txt
git -C "$TEST_TMP/project" -c user.name=test -c user.email=test@example.invalid commit -qm baseline
printf 'source edit\n' >> "$TEST_TMP/project/app.txt"
printf 'untracked\n' > "$TEST_TMP/project/loose.txt"
printf '%%77\n' > "$TEST_TMP/project/.rtide/tweb-pane"
printf '99999\n' > "$TEST_TMP/project/.rtide/agent-ready"

tmux new-session -d -s "$SESSION" -n work -c "$TEST_TMP/project"
WINDOW=$(tmux display-message -p -t "$SESSION:work" '#{window_id}')
PANE=$(tmux display-message -p -t "$WINDOW" '#{pane_id}')
tmux set-option -p -t "$PANE" @rtide-role nvim

HOME="$TEST_TMP/home" RTIDE_WORKTREE_ROOT="$MANAGED_BASE" RTIDE_FORK_NO_LAUNCH=1 \
  "$ROOT/bin/rtide" fork "$SESSION" "$WINDOW" test-fork \
  >"$TEST_TMP/fork.out" 2>"$TEST_TMP/fork.err"
FORK=$(find "$MANAGED_BASE" -mindepth 2 -maxdepth 2 -type d -name test-fork -print -quit)
[[ -d "$FORK" ]] || fail 'worktree was not created'
[[ "$FORK" == "$MANAGED_BASE"/*/test-fork ]] || fail 'worktree was not created under the managed global root'
[[ "$(git -C "$FORK" branch --show-current)" == rtide/fork-1 ]] || fail 'fork branch is wrong'
grep -F 'source edit' "$FORK/app.txt" >/dev/null || fail 'tracked working change was not replayed'
[[ -f "$FORK/.tweb/results/prior.html" ]] || fail 'artifact snapshot was not copied'
grep -F "file://$FORK/.tweb/results/prior.html" "$FORK/.rtide/output-history.json" >/dev/null \
  || fail 'history URLs were not rewritten to the worktree'
grep -F 'prior request' "$FORK/.rtide/fork-context.md" >/dev/null \
  || fail 'conversation context was not seeded'
grep -F 'loose.txt' "$TEST_TMP/fork.err" >/dev/null || fail 'untracked files were not reported'
[[ ! -e "$FORK/loose.txt" ]] || fail 'untracked file leaked into isolated worktree'
[[ ! -e "$FORK/.rtide/agent-ready" ]] || fail 'source readiness marker leaked into first fork'
[[ "$(tmux list-windows -t "$SESSION" | wc -l)" == 1 ]] || fail 'no-launch test unexpectedly created a window'
grep -F 'launch_fork_window "$sess" "$fork_dir" "$name" "$initial_prompt" "$target_client"' "$ROOT/bin/rtide" >/dev/null \
  || fail 'new fork window does not use the selected fork name'
if HOME="$TEST_TMP/home" RTIDE_WORKTREE_ROOT="$MANAGED_BASE" RTIDE_FORK_NO_LAUNCH=1 \
    "$ROOT/bin/rtide" fork "$SESSION" "$WINDOW" test-fork >/dev/null 2>&1; then
  fail 'duplicate fork name unexpectedly succeeded'
fi

# Migration is deliberately blocked while a fork runtime owns the worktree.
ACTIVE_WINDOW=$(tmux new-window -d -P -F '#{window_id}' -t "$SESSION:" -n active-fork -c "$FORK")
tmux set-option -w -t "$ACTIVE_WINDOW" @rtide-workspace "$FORK"
if HOME="$TEST_TMP/home" RTIDE_WORKTREE_ROOT="$MANAGED_BASE" \
    "$ROOT/bin/rtide" fork migrate test-fork "$PANE" \
    >"$TEST_TMP/active-migrate.out" 2>"$TEST_TMP/active-migrate.err"; then
  fail 'running fork was allowed to migrate'
fi
grep -F 'stop the runtime before migrating' "$TEST_TMP/active-migrate.err" >/dev/null \
  || fail 'running migration rejection did not explain how to proceed'
tmux kill-window -t "$ACTIVE_WINDOW"

# A stopped legacy worktree can be moved into managed storage without losing
# dirty changes, artifacts, or self-contained file URLs.
LEGACY="$TEST_TMP/legacy/test-fork"
mkdir -p "$(dirname "$LEGACY")"
git -C "$TEST_TMP/project" worktree move "$FORK" "$LEGACY"
sed -i "s|$FORK|$LEGACY|g" "$LEGACY/.rtide/output-history.json" "$LEGACY/.tweb/results/prior.html"
FORK="$LEGACY"
HOME="$TEST_TMP/home" RTIDE_WORKTREE_ROOT="$MANAGED_BASE" \
  "$ROOT/bin/rtide" fork migrate test-fork "$PANE" >/dev/null
FORK=$(git -C "$TEST_TMP/project" worktree list --porcelain \
  | awk '$1=="worktree"{path=$2} $1=="branch" && $2=="refs/heads/rtide/fork-1"{print path; exit}')
[[ "$FORK" == "$MANAGED_BASE"/*/test-fork && -d "$FORK" ]] \
  || fail 'legacy worktree was not migrated into managed storage'
[[ ! -e "$LEGACY" ]] || fail 'legacy worktree path remained after migration'
grep -F "file://$FORK/.tweb/results/prior.html" "$FORK/.rtide/output-history.json" >/dev/null \
  || fail 'migration did not rewrite copied artifact URLs'

# Forking an existing fork must create a sibling worktree from the primary
# repository, never a nested .rtide-worktrees directory.
SECOND_WINDOW=$(tmux new-window -d -P -F '#{window_id}' -t "$SESSION:" -n existing-fork -c "$FORK")
SECOND_PANE=$(tmux display-message -p -t "$SECOND_WINDOW" '#{pane_id}')
tmux set-option -p -t "$SECOND_PANE" @rtide-role nvim
# Simulate the live runtime files that exist when a second fork is created
# from an already running first fork.
printf '%%88\n' > "$FORK/.rtide/tweb-pane"
printf '12345\n' > "$FORK/.rtide/agent-ready"
HOME="$TEST_TMP/home" RTIDE_WORKTREE_ROOT="$MANAGED_BASE" RTIDE_FORK_NO_LAUNCH=1 \
  "$ROOT/bin/rtide" fork "$SESSION" "$SECOND_WINDOW" test-fork-2 >/dev/null
SECOND=$(find "$MANAGED_BASE" -mindepth 2 -maxdepth 2 -type d -name test-fork-2 -print -quit)
[[ -d "$SECOND" ]] || fail 'fork-of-fork was not created in managed storage'
[[ "$(dirname "$SECOND")" == "$(dirname "$FORK")" ]] || fail 'fork-of-fork did not reuse its repository namespace'
[[ "$(git -C "$SECOND" branch --show-current)" == rtide/fork-2 ]] \
  || fail 'fork-of-fork branch numbering is wrong'
[[ ! -e "$SECOND/.rtide/tweb-pane" && ! -e "$SECOND/.rtide/agent-ready" ]] \
  || fail 'second fork inherited live runtime routing from first fork'
grep -F "file://$SECOND/.tweb/results/prior.html" "$SECOND/.rtide/output-history.json" >/dev/null \
  || fail 'second fork history did not target its own artifacts'

# An independent repository nested inside another repository still creates its
# managed worktree outside both repositories.
mkdir -p "$TEST_TMP/outer/inner"
git -C "$TEST_TMP/outer" init -q
printf 'outer\n' > "$TEST_TMP/outer/outer.txt"
git -C "$TEST_TMP/outer" add outer.txt
git -C "$TEST_TMP/outer" -c user.name=test -c user.email=test@example.invalid commit -qm outer
git -C "$TEST_TMP/outer/inner" init -q
printf 'inner\n' > "$TEST_TMP/outer/inner/inner.txt"
git -C "$TEST_TMP/outer/inner" add inner.txt
git -C "$TEST_TMP/outer/inner" -c user.name=test -c user.email=test@example.invalid commit -qm inner
NESTED_WINDOW=$(tmux new-window -d -P -F '#{window_id}' -t "$SESSION:" -n nested -c "$TEST_TMP/outer/inner")
NESTED_PANE=$(tmux display-message -p -t "$NESTED_WINDOW" '#{pane_id}')
tmux set-option -p -t "$NESTED_PANE" @rtide-role nvim
if HOME="$TEST_TMP/home" RTIDE_WORKTREE_ROOT="$TEST_TMP/outer/managed" RTIDE_FORK_NO_LAUNCH=1 \
    "$ROOT/bin/rtide" fork "$SESSION" "$NESTED_WINDOW" rejected-nested \
    >"$TEST_TMP/nested.out" 2>"$TEST_TMP/nested.err"; then
  fail 'worktree root inside an enclosing repository was accepted'
fi
grep -F 'managed worktree root is inside a Git repository' "$TEST_TMP/nested.err" >/dev/null \
  || fail 'unsafe managed-root rejection did not explain the nesting problem'
printf 'worktree_root=%s\n' "$MANAGED_BASE" >> "$TEST_TMP/home/.rtide/config"
HOME="$TEST_TMP/home" RTIDE_FORK_NO_LAUNCH=1 \
  "$ROOT/bin/rtide" fork "$SESSION" "$NESTED_WINDOW" nested-safe >/dev/null
NESTED_FORK=$(git -C "$TEST_TMP/outer/inner" worktree list --porcelain \
  | awk '$1=="worktree"{path=$2} $1=="branch" && $2=="refs/heads/rtide/fork-1"{print path; exit}')
[[ "$NESTED_FORK" == "$MANAGED_BASE"/*/nested-safe && -d "$NESTED_FORK" ]] \
  || fail 'nested repository created a nested managed worktree'
[[ "$NESTED_FORK" != "$TEST_TMP/outer"/* ]] \
  || fail 'managed worktree leaked inside the enclosing repository'

mkdir -p "$TEST_TMP/doctor-home"
(
  cd "$TEST_TMP/outer/inner"
  HOME="$TEST_TMP/doctor-home" RTIDE_WORKTREE_ROOT="$MANAGED_BASE" \
    FAKE_TWEB_LOG="$TEST_TMP/doctor-tweb.log" \
    PATH="$ROOT/tests/fixtures:/usr/local/bin:/usr/bin:/bin" \
    "$ROOT/bin/rtide" doctor || true
) >"$TEST_TMP/doctor.out" 2>/dev/null
grep -F "WARN: independent Git checkout is nested inside $TEST_TMP/outer" "$TEST_TMP/doctor.out" >/dev/null \
  || fail 'doctor did not identify the enclosing independent repository'
grep -F 'worktree root:' "$TEST_TMP/doctor.out" >/dev/null \
  || fail 'doctor did not report the resolved managed worktree root'

printf 'PASS: global worktree placement, migration, nesting safety, changes, artifacts, history, and context\n'
