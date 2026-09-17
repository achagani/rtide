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
resumed_workspace=$($ROOT/libexec/rtide/provider run codex openai test-model prompt session-1 workspace)
[[ "$resumed_workspace" == *'exec resume --sandbox workspace-write session-1'* ]] \
  || fail 'resumed Codex workspace policy is not enforced'
resumed_observe=$($ROOT/libexec/rtide/provider run codex openai test-model prompt session-1 observe)
[[ "$resumed_observe" == *'exec resume --sandbox read-only session-1'* ]] \
  || fail 'resumed Codex observe policy is not enforced'

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

# A partial config must display with schema defaults instead of aborting, and
# the config surface must accept every startup setting including permission_policy.
partial="$TEST_TMP/partial"
mkdir -p "$partial/.rtide"
printf 'permission_policy=observe\n' > "$partial/config"
HOME="$TEST_TMP/home" RTIDE_CONFIG_DIR="$partial" "$ROOT/bin/rtide" config >/dev/null 2>&1 \
  || fail 'partial config display aborted'
view=$(HOME="$TEST_TMP/home" RTIDE_CONFIG_DIR="$partial" "$ROOT/bin/rtide" config 2>&1)
grep -F 'permission_policy observe' <<< "$view" >/dev/null \
  || fail 'config display omitted permission_policy'
HOME="$TEST_TMP/home" RTIDE_CONFIG_DIR="$partial" "$ROOT/bin/rtide" config set permission_policy=native >/dev/null \
  || fail 'config set permission_policy was rejected'
grep -Fx 'permission_policy=native' "$partial/config" >/dev/null \
  || fail 'config set permission_policy did not persist'
if HOME="$TEST_TMP/home" RTIDE_CONFIG_DIR="$partial" "$ROOT/bin/rtide" config set permission_policy=bogus >/dev/null 2>&1; then
  fail 'config set accepted an invalid permission policy'
fi

# The settings surface is discoverable and its commands exit instead of falling
# through into a workspace launch.
HOME="$TEST_TMP/home" "$ROOT/bin/rtide" help 2>&1 | grep -F 'settings' >/dev/null \
  || fail 'rtide help does not surface settings'
HOME="$TEST_TMP/home" RTIDE_CONFIG_DIR="$partial" "$ROOT/bin/rtide" settings status "$TEST_TMP/workspace" >/dev/null \
  || fail 'rtide settings status did not exit cleanly'

# Pane discovery uses one pane ID per record and queries paths separately, so
# literal backslash-t and actual tab characters in workspace paths are safe.
mkdir -p "$TEST_TMP/fake-bin"
ln -s "$ROOT/tests/fixtures/tmux-settings" "$TEST_TMP/fake-bin/tmux"
chmod +x "$ROOT/tests/fixtures/tmux-settings"
for workspace in "$TEST_TMP/literal\\tpath" "$TEST_TMP/real"$'\t'"path"; do
  mkdir -p "$workspace/.rtide"
  printf 'provider=openai\nharness=codex\nmodel=test-model\npermission_policy=workspace\n' > "$workspace/.rtide/agent"
  printf '{"provider":"openai","harness":"codex","model":"test-model","permission_policy":"workspace","agent_pid":901}\n' \
    > "$workspace/.rtide/effective-settings.json"
  : > "$TEST_TMP/tmux.log"
  PATH="$TEST_TMP/fake-bin:$PATH" FAKE_TMUX_LOG="$TEST_TMP/tmux.log" FAKE_WS="$workspace" \
    REAL_SETTINGS="$ROOT/libexec/rtide/settings" EXPECTED_POLICY=observe HOME="$TEST_TMP/home" \
    "$ROOT/bin/rtide" permissions observe "$workspace" >/dev/null
  "$ROOT/libexec/rtide/settings" verify "$workspace" permission_policy=observe --not-pid 901 \
    || fail "runtime policy did not converge for delimiter workspace: $workspace"
  grep -F "list-panes -a -F #{pane_id} -f #{==:#{@rtide-role},agent}" "$TEST_TMP/tmux.log" >/dev/null \
    || fail 'pane discovery did not use the unambiguous role-filter contract'
done

# A transition that never converges must fail, restore the previous desired
# agent state, and never present the failed policy as effective.
rollback_ws="$TEST_TMP/rollback"
mkdir -p "$rollback_ws/.rtide"
printf 'provider=openai\nharness=codex\nmodel=test-model\npermission_policy=workspace\n' \
  > "$rollback_ws/.rtide/agent"
printf '{"provider":"openai","harness":"codex","model":"test-model","permission_policy":"workspace","agent_pid":700}\n' \
  > "$rollback_ws/.rtide/effective-settings.json"
if PATH="$TEST_TMP/fake-bin:$PATH" FAKE_TMUX_LOG="$TEST_TMP/tmux.log" FAKE_WS="$rollback_ws" \
    REAL_SETTINGS="$ROOT/libexec/rtide/settings" EXPECTED_POLICY=observe FAIL_TRANSITION=1 \
    HOME="$TEST_TMP/home" "$ROOT/bin/rtide" settings apply "$rollback_ws" >/dev/null 2>&1; then
  fail 'a non-converging transition reported success'
fi
grep -Fx 'permission_policy=workspace' "$rollback_ws/.rtide/agent" >/dev/null \
  || fail 'failed transition did not restore desired agent state'
[[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["permission_policy"])' \
  "$rollback_ws/.rtide/effective-settings.json")" == workspace ]] \
  || fail 'failed transition presented the failed policy as effective'

printf 'PASS: permission startup, capabilities, and verified runtime transitions\n'
