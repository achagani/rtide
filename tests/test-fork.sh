#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
SESSION="rtide-fork-test-$$"
cleanup() {
  local rc=$?
  trap - EXIT
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  if [[ -d "$TEST_TMP/project/.git" ]]; then
    git -C "$TEST_TMP/project" worktree remove --force "$TEST_TMP/.rtide-worktrees/test-fork-2" 2>/dev/null || true
    git -C "$TEST_TMP/project" worktree remove --force "$TEST_TMP/.rtide-worktrees/test-fork" 2>/dev/null || true
  fi
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

tmux new-session -d -s "$SESSION" -n work -c "$TEST_TMP/project"
WINDOW=$(tmux display-message -p -t "$SESSION:work" '#{window_id}')
PANE=$(tmux display-message -p -t "$WINDOW" '#{pane_id}')
tmux set-option -p -t "$PANE" @rtide-role nvim

HOME="$TEST_TMP/home" RTIDE_FORK_NO_LAUNCH=1 \
  "$ROOT/bin/rtide" fork "$SESSION" "$WINDOW" test-fork \
  >"$TEST_TMP/fork.out" 2>"$TEST_TMP/fork.err"
FORK="$TEST_TMP/.rtide-worktrees/test-fork"
[[ -d "$FORK" ]] || fail 'worktree was not created'
[[ "$(git -C "$FORK" branch --show-current)" == rtide/fork-1 ]] || fail 'fork branch is wrong'
grep -F 'source edit' "$FORK/app.txt" >/dev/null || fail 'tracked working change was not replayed'
[[ -f "$FORK/.tweb/results/prior.html" ]] || fail 'artifact snapshot was not copied'
grep -F "file://$FORK/.tweb/results/prior.html" "$FORK/.rtide/output-history.json" >/dev/null \
  || fail 'history URLs were not rewritten to the worktree'
grep -F 'prior request' "$FORK/.rtide/fork-context.md" >/dev/null \
  || fail 'conversation context was not seeded'
grep -F 'loose.txt' "$TEST_TMP/fork.err" >/dev/null || fail 'untracked files were not reported'
[[ ! -e "$FORK/loose.txt" ]] || fail 'untracked file leaked into isolated worktree'
[[ "$(tmux list-windows -t "$SESSION" | wc -l)" == 1 ]] || fail 'no-launch test unexpectedly created a window'
if HOME="$TEST_TMP/home" RTIDE_FORK_NO_LAUNCH=1 \
    "$ROOT/bin/rtide" fork "$SESSION" "$WINDOW" test-fork >/dev/null 2>&1; then
  fail 'duplicate fork name unexpectedly succeeded'
fi

# Forking an existing fork must create a sibling worktree from the primary
# repository, never a nested .rtide-worktrees directory.
SECOND_WINDOW=$(tmux new-window -d -P -F '#{window_id}' -t "$SESSION:" -n existing-fork -c "$FORK")
SECOND_PANE=$(tmux display-message -p -t "$SECOND_WINDOW" '#{pane_id}')
tmux set-option -p -t "$SECOND_PANE" @rtide-role nvim
HOME="$TEST_TMP/home" RTIDE_FORK_NO_LAUNCH=1 \
  "$ROOT/bin/rtide" fork "$SESSION" "$SECOND_WINDOW" test-fork-2 >/dev/null
[[ -d "$TEST_TMP/.rtide-worktrees/test-fork-2" ]] || fail 'fork-of-fork was not a sibling'
[[ ! -e "$TEST_TMP/.rtide-worktrees/.rtide-worktrees" ]] || fail 'fork-of-fork nested its worktree root'
[[ "$(git -C "$TEST_TMP/.rtide-worktrees/test-fork-2" branch --show-current)" == rtide/fork-2 ]] \
  || fail 'fork-of-fork branch numbering is wrong'

printf 'PASS: isolated worktrees, fork-of-fork, changes, artifacts, history, and context\n'
