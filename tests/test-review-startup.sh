#!/usr/bin/env bash
# Review-first startup: fresh launch opens a project review view with no real
# file buffer, and explicit file arguments still open directly.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# The launcher must build a review-first command for a fresh pane and pass the
# file through when one is given.
review_cmd=$(bash -c '
  RTIDE_SHARE_DIR="'"$ROOT"'/share"
  RTIDE_REVIEW_LUA="$RTIDE_SHARE_DIR/rtide-review.lua"
  '"$(sed -n '/^rtide_nvim_command()/,/^}/p' "$ROOT/bin/rtide")"'
  rtide_nvim_command "/tmp/ws" bash
')
grep -F 'nvim --listen' <<< "$review_cmd" >/dev/null || fail 'launcher lost the editor socket'
grep -F 'rtide-review.lua' <<< "$review_cmd" >/dev/null || fail 'fresh launch does not use review-first entry'
grep -F "m.setup" <<< "$review_cmd" >/dev/null || fail 'review module is not invoked'

file_cmd=$(bash -c '
  RTIDE_SHARE_DIR="'"$ROOT"'/share"
  RTIDE_REVIEW_LUA="$RTIDE_SHARE_DIR/rtide-review.lua"
  '"$(sed -n '/^rtide_nvim_command()/,/^}/p' "$ROOT/bin/rtide")"'
  rtide_nvim_command "/tmp/ws" bash "src/app.py"
')
grep -F 'src/app.py' <<< "$file_cmd" >/dev/null || fail 'explicit file argument was dropped'
if grep -F 'rtide-review.lua' <<< "$file_cmd" >/dev/null; then
  fail 'explicit file argument did not bypass the review-first entry'
fi

# The module itself must open the review view, request Git status, and leave no
# real file buffer named. Snacks is stubbed so this runs headlessly.
if command -v nvim >/dev/null 2>&1; then
  # A project file exists so a real buffer *would* be named if the review view
  # failed to start. The stub records what the module opened.
  mkdir -p "$TEST_TMP/ws" "$TEST_TMP/lua"
  printf 'print("hi")\n' > "$TEST_TMP/ws/app.py"
  cat > "$TEST_TMP/lua/snacks.lua" <<'LUA'
return {
  explorer = {
    open = function(opts)
      local out = io.open(os.getenv("REVIEW_RESULT"), "w")
      out:write("opened=true\n")
      out:write("cwd=" .. tostring(opts and opts.cwd) .. "\n")
      out:write("git_status=" .. tostring(opts and opts.git_status) .. "\n")
      out:write("buffer_name=" .. vim.api.nvim_buf_get_name(0) .. "\n")
      out:close()
      return true
    end,
  },
}
LUA
  REVIEW_RESULT="$TEST_TMP/result" nvim --headless --clean -u NONE \
    -c "set rtp+=$TEST_TMP" -c "cd $TEST_TMP/ws" \
    -c "lua local m=dofile('$ROOT/share/rtide-review.lua'); assert(m.open(vim.fn.getcwd()))" \
    -c "qa!" 2>"$TEST_TMP/nvim.err" || fail "review module errored: $(cat "$TEST_TMP/nvim.err")"
  [[ -f "$TEST_TMP/result" ]] || fail 'review module did not reach the explorer'
  grep -Fx 'opened=true' "$TEST_TMP/result" >/dev/null || fail 'review module did not open the explorer'
  grep -Fx "cwd=$TEST_TMP/ws" "$TEST_TMP/result" >/dev/null || fail 'review view was not rooted at the workspace'
  grep -Fx 'git_status=true' "$TEST_TMP/result" >/dev/null || fail 'review view does not show Git status'
  grep -Fx 'buffer_name=' "$TEST_TMP/result" >/dev/null || fail 'fresh review view left a real file buffer named'

  # Without Snacks the module must degrade safely rather than crash startup.
  REVIEW_RESULT="$TEST_TMP/result2" nvim --headless --clean -u NONE \
    -c "cd $TEST_TMP/ws" \
    -c "lua local m=dofile('$ROOT/share/rtide-review.lua'); assert(m.open(vim.fn.getcwd()) == false)" \
    -c "qa!" 2>/dev/null || fail 'missing Snacks did not degrade safely'
fi

printf 'PASS: review-first startup, Git-aware entry, and explicit-file precedence\n'
