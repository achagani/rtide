#!/usr/bin/env bash
# A stale or invalid inherited RTIDE_ROOT must never break a launch. A tmux
# server snapshots its creator's environment, so a path to a since-pruned
# release can survive and would otherwise abort every later launch.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

expected="rtide $(tr -d '[:space:]' < "$ROOT/VERSION")"

# Stale root pointing at a deleted/pruned release.
stale_out=$(RTIDE_ROOT="$TEST_TMP/versions/0.2.58-nonexistent" "$ROOT/bin/rtide" --version 2>&1) \
  || fail 'a stale RTIDE_ROOT aborted the launch'
[[ "$stale_out" == *"$expected"* ]] || fail "stale root did not fall back: $stale_out"
grep -F 'ignoring unusable RTIDE_ROOT' <<< "$stale_out" >/dev/null \
  || fail 'stale root was silently ignored without explanation'

# Invalid root that is a file or empty.
invalid_out=$(RTIDE_ROOT=/nonexistent/plain/path "$ROOT/bin/rtide" --version 2>&1) \
  || fail 'an invalid RTIDE_ROOT aborted the launch'
[[ "$invalid_out" == *"$expected"* ]] || fail "invalid root did not fall back: $invalid_out"

# A valid override is still honored.
valid_out=$(RTIDE_ROOT="$ROOT" "$ROOT/bin/rtide" --version 2>&1) \
  || fail 'a valid RTIDE_ROOT was rejected'
[[ "$valid_out" == *"$expected"* ]] || fail "valid override failed: $valid_out"
if grep -F 'ignoring unusable' <<< "$valid_out" >/dev/null; then
  fail 'a valid RTIDE_ROOT was reported as unusable'
fi

# No override resolves to the release containing the script.
unset_out=$(env -u RTIDE_ROOT "$ROOT/bin/rtide" --version 2>&1) \
  || fail 'launch without RTIDE_ROOT failed'
[[ "$unset_out" == *"$expected"* ]] || fail "default root failed: $unset_out"

# The entry point must validate before sourcing helpers.
grep -F 'rtide_root_usable' "$ROOT/bin/rtide" >/dev/null \
  || fail 'entry point does not validate the inherited runtime root'

printf 'PASS: stale and invalid runtime roots fall back safely\n'
