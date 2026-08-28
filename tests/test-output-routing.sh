#!/usr/bin/env bash
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
chmod +x "$FIXTURES/tmux" "$FIXTURES/tweb"

export PATH="$FIXTURES:/usr/bin:/bin"
export HOME="$TEST_TMP/home"
export FAKE_TWEB_LOG="$TEST_TMP/tweb.log"
mkdir -p "$HOME" "$TEST_TMP/pages"
printf '<h1>route me</h1>\n' > "$TEST_TMP/pages/page with spaces.html"

reset_log() { : > "$FAKE_TWEB_LOG"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_log() {
  grep -F -- "$1" "$FAKE_TWEB_LOG" >/dev/null || fail "missing log fragment: $1"
}
assert_no_log() {
  ! grep -F -- "$1" "$FAKE_TWEB_LOG" >/dev/null || fail "unexpected log fragment: $1"
}

# A managed RTIDE caller must target its own role=tweb pane.
reset_log
TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%1 nvim\n%2 agent\n%9 tweb\n' \
  "$ROOT/bin/tweb-render" "$TEST_TMP/pages/page with spaces.html" || fail 'managed render failed'
assert_log 'navigate --pane %9'
assert_no_log 'open '
grep -F "file://$TEST_TMP/pages/page with spaces.html" \
  "$HOME/.cache/rtide/rtide-alpha/last-render" >/dev/null \
  || fail 'managed render did not record its target'

# Float must target the same pane instead of relying on global inference.
reset_log
TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%1 nvim\n%2 agent\n%9 tweb\n' \
  "$ROOT/bin/tweb-render" --float "$TEST_TMP/pages/page with spaces.html" || fail 'managed float failed'
assert_log 'float --pane %9'

# Duplicate role panes are a configuration error and must never spawn a browser.
reset_log
if TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%9 tweb\n%10 tweb\n' \
  "$ROOT/bin/tweb-render" "$TEST_TMP/pages/page with spaces.html" 2>/dev/null; then
  fail 'duplicate tweb panes unexpectedly succeeded'
fi
[[ ! -s "$FAKE_TWEB_LOG" ]] || fail 'duplicate panes invoked tweb'

# A noninteractive caller outside RTIDE must fail clearly instead of blocking in tweb open.
reset_log
if env -u TMUX -u TMUX_PANE "$ROOT/bin/tweb-render" "$TEST_TMP/pages/page with spaces.html" \
  </dev/null >/dev/null 2>/dev/null; then
  fail 'noninteractive standalone render unexpectedly succeeded'
fi
[[ ! -s "$FAKE_TWEB_LOG" ]] || fail 'noninteractive fallback invoked tweb'

# Piped content must be escaped and written to a session-scoped file.
reset_log
printf '<script>alert("x")</script>&\n' | \
  TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-alpha FAKE_PANES='%9 tweb\n' \
  "$ROOT/bin/tweb-render" - || fail 'piped render failed'
PIPE_FILE="$HOME/.cache/rtide/rtide-alpha/pipe.html"
grep -F '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;&amp;' "$PIPE_FILE" >/dev/null \
  || fail 'piped HTML was not escaped'

# Command and output text must be escaped; the report records the command exit status.
reset_log
TMUX=fake TMUX_PANE=%2 FAKE_SESSION=rtide-beta FAKE_PANES='%7 tweb\n' \
  "$ROOT/bin/tweb-run" /bin/sh -c 'printf "<b>bad & raw</b>"; exit 7' || fail 'command report render failed'
RUN_FILE="$HOME/.cache/rtide/rtide-beta/run.html"
grep -F '&lt;b&gt;bad &amp; raw&lt;/b&gt;' "$RUN_FILE" >/dev/null || fail 'command output was not escaped'
grep -F 'exit 7' "$RUN_FILE" >/dev/null || fail 'command exit status was not recorded'
assert_log 'navigate --pane %7'

printf 'PASS: output routing, fallback, isolation, and escaping\n'
