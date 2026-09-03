#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'find "$TEST_TMP" -depth -type f -delete 2>/dev/null || true; find "$TEST_TMP" -depth -type d -empty -delete 2>/dev/null || true' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

new=$($ROOT/bin/rtide-provider run codex openai test-model prompt '' unrestricted)
[[ "$new" == *'--sandbox danger-full-access'* ]] || fail 'new Codex command is not unrestricted'
resumed=$($ROOT/bin/rtide-provider run codex openai test-model prompt session-1 unrestricted)
[[ "$resumed" == *'exec resume --dangerously-bypass-approvals-and-sandbox session-1'* ]] \
  || fail 'resumed Codex command is not unrestricted'
default=$($ROOT/bin/rtide-provider run codex openai test-model prompt)
[[ "$default" == *'--sandbox workspace-write'* ]] || fail 'default Codex command is not workspace sandboxed'

mkdir -p "$TEST_TMP/workspace/.rtide" "$TEST_TMP/home/.rtide"
printf 'provider=openai\nharness=codex\nmodel=test-model\n' > "$TEST_TMP/workspace/.rtide/agent"
if HOME="$TEST_TMP/home" "$ROOT/bin/rtide" permissions unrestricted "$TEST_TMP/workspace" >/dev/null 2>&1; then
  fail 'unrestricted policy did not require explicit confirmation'
fi
HOME="$TEST_TMP/home" RTIDE_CONFIRM_UNRESTRICTED=UNRESTRICTED \
  "$ROOT/bin/rtide" permissions unrestricted "$TEST_TMP/workspace" >/dev/null 2>&1
grep -Fx 'permission_policy=unrestricted' "$TEST_TMP/workspace/.rtide/agent" >/dev/null \
  || fail 'workspace permission policy was not persisted'
HOME="$TEST_TMP/home" "$ROOT/bin/rtide" permissions workspace "$TEST_TMP/workspace" >/dev/null
grep -Fx 'permission_policy=workspace' "$TEST_TMP/workspace/.rtide/agent" >/dev/null \
  || fail 'workspace sandbox could not be restored'

printf 'PASS: workspace permissions default safe and support explicit unrestricted Codex access\n'
