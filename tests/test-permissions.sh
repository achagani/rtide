#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'find "$TEST_TMP" -depth -type f -delete 2>/dev/null || true; find "$TEST_TMP" -depth -type d -empty -delete 2>/dev/null || true' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

new=$($ROOT/libexec/rtide/provider run codex openai test-model prompt '' unrestricted)
[[ "$new" == *'--sandbox danger-full-access'* ]] || fail 'new Codex command is not unrestricted'
resumed=$($ROOT/libexec/rtide/provider run codex openai test-model prompt session-1 unrestricted)
[[ "$resumed" == *'exec resume --dangerously-bypass-approvals-and-sandbox session-1'* ]] \
  || fail 'resumed Codex command is not unrestricted'
default=$($ROOT/libexec/rtide/provider run codex openai test-model prompt)
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

# Development defaults to unrestricted and supports an explicit safe override.
HOME="$TEST_TMP/home" RTIDE_DEV_PERMISSION_POLICY=unrestricted \
  bash "$ROOT/scripts/rtide-dev" "$TEST_TMP/workspace" --version >/dev/null 2>"$TEST_TMP/dev.err"
grep -Fx 'permission_policy=unrestricted' "$TEST_TMP/workspace/.rtide/agent" >/dev/null \
  || fail 'development launcher did not default the workspace to unrestricted'
grep -F 'permissions=unrestricted' "$TEST_TMP/dev.err" >/dev/null \
  || fail 'development launcher did not display its effective permissions'
HOME="$TEST_TMP/home" RTIDE_DEV_PERMISSION_POLICY=workspace \
  bash "$ROOT/scripts/rtide-dev" "$TEST_TMP/workspace" --version >/dev/null 2>/dev/null
grep -Fx 'permission_policy=workspace' "$TEST_TMP/workspace/.rtide/agent" >/dev/null \
  || fail 'explicit development workspace override was ignored'

grep -F 'RTIDE_DEV_PERMISSION_POLICY="$(or $(PERMISSION),unrestricted)"' "$ROOT/Makefile" >/dev/null \
  || fail 'make dev does not default permission to unrestricted'
grep -F 'export RTIDE_DEV_PERMISSION_CONFIRMED=1' "$ROOT/scripts/rtide-dev" >/dev/null \
  || fail 'development launcher does not pre-confirm its explicit permission policy'
grep -F 'export RTIDE_ASK="${RTIDE_ASK:-0}"' "$ROOT/scripts/rtide-dev" >/dev/null \
  || fail 'development launcher does not skip the redundant startup agent picker'
grep -F 'RTIDE_DEV_PERMISSION_CONFIRMED' "$ROOT/bin/rtide" >/dev/null \
  || fail 'agent picker ignores development permission confirmation'
picker_source=$(sed -n '/^cancellable_input()/,/^# --- commands/p' "$ROOT/bin/rtide")
[[ $(grep -Fc "enter:accept-or-print-query" <<< "$picker_source") -eq 2 ]] \
  || fail 'free-form fzf prompts do not accept unmatched values'

printf 'PASS: installed workspaces default safe and development defaults to unrestricted\n'
