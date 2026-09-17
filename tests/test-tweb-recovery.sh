#!/usr/bin/env bash
# TWeb connection recovery: state classification, honest acknowledgement, and
# safe reconnect/recreate without duplicate panes.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURES="$ROOT/tests/fixtures"
TEST_TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  trap - EXIT
  rm -rf "$TEST_TMP"
  exit "$rc"
}
trap cleanup EXIT
chmod +x "$FIXTURES/tmux" "$FIXTURES/tweb-ack"

# A dedicated bin dir so the state-aware fake `tweb` shadows the simple logger.
mkdir -p "$TEST_TMP/bin"
ln -sf "$FIXTURES/tmux" "$TEST_TMP/bin/tmux"
ln -sf "$FIXTURES/tweb-ack" "$TEST_TMP/bin/tweb"
export PATH="$TEST_TMP/bin:$FIXTURES:/usr/bin:/bin"
export HOME="$TEST_TMP/home"
export FAKE_TWEB_LOG="$TEST_TMP/tweb.log"
unset RTIDE_TWEB_MODE RTIDE_TWEB_PANE RTIDE_TWEB_SESSION_HINT RTIDE_WORKSPACE RTIDE_TWEB_STATE
mkdir -p "$HOME" "$TEST_TMP/pages"
PAGE="$TEST_TMP/pages/page.html"
printf '<h1>recover me</h1>\n' > "$PAGE"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
log() { cat "$FAKE_TWEB_LOG" 2>/dev/null || true; }
assert_log() { grep -F -- "$1" "$FAKE_TWEB_LOG" >/dev/null || fail "missing log: $1"; }
assert_no_log() { ! grep -F -- "$1" "$FAKE_TWEB_LOG" >/dev/null || fail "unexpected log: $1"; }

mkdir -p "$TEST_TMP/ws/.rtide"
printf '%%9\n' > "$TEST_TMP/ws/.rtide/tweb-pane"

# status: connected when a browser is running in the registered pane.
: > "$FAKE_TWEB_LOG"
state=$(TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%1 nvim\n%2 agent\n%9 tweb\n' \
  FAKE_TWEB_LIVE=1 "$ROOT/bin/rtide" tweb status "$TEST_TMP/ws")
[[ "$state" == connected$'\t'%9$'\t'* ]] || fail "connected state was '$state'"

# status: disconnected when the pane exists but no browser is running.
state=$(TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%1 nvim\n%2 agent\n%9 tweb\n' \
  FAKE_TWEB_LIVE=0 "$ROOT/bin/rtide" tweb status "$TEST_TMP/ws")
[[ "$state" == disconnected$'\t'%9$'\t'* ]] || fail "disconnected state was '$state'"

# status: missing when the workspace has no registered role pane.
state=$(TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%1 nvim\n%2 agent\n' \
  FAKE_TWEB_LIVE=1 "$ROOT/bin/rtide" tweb status "$TEST_TMP/ws")
[[ "$state" == missing$'\t'* ]] || fail "missing state was '$state'"

# status: multiple role panes is a configuration error.
state=$(TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%9 tweb\n%10 tweb\n' \
  FAKE_TWEB_LIVE=1 "$ROOT/bin/rtide" tweb status "$TEST_TMP/ws")
[[ "$state" == multiple$'\t'* ]] || fail "multiple state was '$state'"

# A render into a disconnected pane reconnects in place, reusing the pane, and
# reports acknowledged display (never a duplicate pane).
: > "$FAKE_TWEB_LOG"
: > "$TEST_TMP/active"
out=$(TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%1 nvim\n%2 agent\n%9 tweb\n' \
  FAKE_TWEB_LIVE=1 FAKE_TWEB_STATE="$TEST_TMP/active" \
  "$ROOT/bin/rtide" render "$PAGE")
[[ "$out" == *"rendered to tweb pane %9"* ]] || fail "render did not acknowledge: $out"
assert_log 'navigate --pane %9'
assert_no_log 'open '
assert_no_log 'split '

# A render into a missing pane is queued, not claimed as displayed.
: > "$FAKE_TWEB_LOG"
rm -f "$TEST_TMP/ws/.rtide/render-request"
out=$(TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%1 nvim\n%2 agent\n' \
  FAKE_TWEB_LIVE=1 RTIDE_WORKSPACE="$TEST_TMP/ws" \
  "$ROOT/bin/rtide" render "$PAGE" 2>/dev/null || true)
grep -F 'queued' <<< "$out" >/dev/null || fail "missing-pane render was not queued: $out"
[[ "$out" != *"rendered to"* ]] || fail 'missing-pane render falsely claimed display'
grep -Fx "file://$PAGE" "$TEST_TMP/ws/.rtide/render-request" >/dev/null \
  || fail 'queued render did not preserve the target'

# recover reconnects a live paneless browser without creating a pane.
: > "$FAKE_TWEB_LOG"
out=$(TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%1 nvim\n%2 agent\n%9 tweb\n' \
  FAKE_TWEB_LIVE=0 "$ROOT/bin/rtide" tweb recover "$TEST_TMP/ws")
grep -F 'reconnected pane %9' <<< "$out" >/dev/null || fail "recover did not reconnect: $out"
assert_no_log 'split '

# recreate refuses when a role pane already exists (never duplicates).
: > "$FAKE_TWEB_LOG"
if TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%9 tweb\n' \
  FAKE_TWEB_LIVE=1 "$ROOT/bin/rtide" tweb recreate "$TEST_TMP/ws" 2>/dev/null; then
  fail 'recreate created a duplicate pane'
fi
assert_no_log 'split-window'

printf 'PASS: tweb connection states, acknowledgement, and safe recovery\n'
