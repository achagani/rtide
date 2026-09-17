#!/usr/bin/env bash
# The review-first explorer must open only at a usable editor width, close when
# the pane becomes narrow, and reopen when it widens again. A sidebar opened
# while the pane was collapsed must never be left clamped.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

command -v nvim >/dev/null 2>&1 || { printf 'PASS: review-view test skipped (nvim unavailable)\n'; exit 0; }

mkdir -p "$TEST_TMP/lua"
cp "$ROOT/tests/fixtures/snacks-stub.lua" "$TEST_TMP/lua/snacks.lua"

cat > "$TEST_TMP/test.lua" <<LUA
vim.opt.runtimepath:prepend("$TEST_TMP")
local review = dofile("$ROOT/share/rtide-review.lua")
local Snacks = require("snacks")
local state = package.loaded["rtide_snacks_state"]
local fails = 0
local function check(cond, msg)
  io.stdout:write((cond and "ok   " or "FAIL ") .. msg .. "\n")
  if not cond then fails = fails + 1 end
end
local function is_open() return Snacks.picker.get()[1] ~= nil end

vim.o.columns = 200; vim.o.lines = 60
check(review.open("/tmp/proj") == true, "M.open opens a wide pane")
check(state.opened_cwd == "/tmp/proj", "opens at the given directory")

vim.o.columns = 20
review.reconcile()
check(not is_open(), "closes when the pane becomes narrow")

vim.o.columns = 120
review.reconcile()
check(is_open(), "reopens when the pane widens again")

review.reconcile(); review.reconcile()
check(#Snacks.picker.get() == 1, "reconcile is idempotent (single explorer)")

-- A sidebar opened narrow reports a clamped width; widening must replace it.
state.reported_width = 6
review.reconcile()
check(#Snacks.picker.get() == 1, "clamped sidebar is replaced, not stacked")
state.reported_width = 40
review.reconcile()
check(is_open(), "sidebar present after the pane widens")

vim.o.columns = 20
check(review.open("/tmp/proj") == false, "M.open refuses a narrow pane")

io.stdout:flush()
os.exit(fails == 0 and 0 or 1)
LUA

nvim --headless -u NONE -c "luafile $TEST_TMP/test.lua" 2>&1 | grep -v '^$'
rc=${PIPESTATUS[0]}
[[ $rc -eq 0 ]] || fail 'review-view contract violated'

# The border format must label panes by role, never by pane_title.
grep -F 'pane-border-format' "$ROOT/libexec/rtide/ui.sh" >/dev/null \
  || fail 'ui.sh does not set pane-border-format'
if sed -n '/pane-border-format/p' "$ROOT/libexec/rtide/ui.sh" | grep -F '#{pane_title}' >/dev/null; then
  fail 'pane borders still render the raw pane title'
fi
grep -F '@rtide-label' "$ROOT/libexec/rtide/ui.sh" >/dev/null \
  || fail 'pane borders do not consult @rtide-label'
for role in nvim agent tweb; do
  grep -F "@rtide-role},$role" "$ROOT/libexec/rtide/ui.sh" >/dev/null \
    || fail "pane border mapping is missing role: $role"
done

printf 'PASS: review view sizing and role-based pane borders\n'
