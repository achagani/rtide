#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'find "$TEST_TMP" -depth -type f -delete 2>/dev/null || true; find "$TEST_TMP" -depth -type d -empty -delete 2>/dev/null || true' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$TEST_TMP/bin"
git -C "$TEST_TMP" init -q
printf '#!/usr/bin/env bash\nSELF_DIR=x\nsource "$SELF_DIR/runtime-helper"\n' > "$TEST_TMP/bin/rtide"
printf '#!/usr/bin/env bash\n' > "$TEST_TMP/bin/runtime-helper"
git -C "$TEST_TMP" add bin/rtide
git -C "$TEST_TMP" -c user.name=test -c user.email=test@example.invalid commit -qm base

source <(sed -n '/^validate_fork_snapshot()/,/^}/p' "$ROOT/bin/rtide")
if validate_fork_snapshot "$TEST_TMP" >"$TEST_TMP/out" 2>"$TEST_TMP/err"; then
  fail 'untracked runtime dependency was accepted'
fi
grep -F 'runtime dependency is untracked: bin/runtime-helper' "$TEST_TMP/err" >/dev/null \
  || fail 'missing runtime dependency was not identified'
git -C "$TEST_TMP" add bin/runtime-helper
validate_fork_snapshot "$TEST_TMP" || fail 'tracked runtime dependency was rejected'

printf 'PASS: incomplete fork snapshots are rejected before worktree creation\n'
