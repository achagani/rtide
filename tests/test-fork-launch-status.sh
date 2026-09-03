#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'find "$TEST_TMP" -depth -type f -delete 2>/dev/null || true; find "$TEST_TMP" -depth -type d -empty -delete 2>/dev/null || true' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

launch_source=$(sed -n '/^launch_fork_window()/,/^fork_root_from_context()/p' "$ROOT/bin/rtide")
grep -F 'head -1 || true)' <<< "$launch_source" >/dev/null \
  || fail 'empty render-marker lookup can still abort a brand-new fork launch under pipefail'

STATUS="$TEST_TMP/fork/.rtide/fork-launch.json"
"$ROOT/libexec/rtide/fork-status" "$STATUS" waiting readiness 1 0 1 "Waiting for tweb"
python3 - "$STATUS" <<'PY' || exit 1
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["state"] == "waiting"
assert value["stage"] == "readiness"
assert value["readiness"] == {"nvim": True, "tweb": False, "agent": True}
assert value["message"] == "Waiting for tweb"
assert value["updated"]
PY
[[ ! -e "$STATUS.tmp" ]] || fail 'atomic status temporary file was left behind'

# Run the generated server-side dispatcher command through a fake tmux binary.
# This verifies that stderr survives popup teardown and is presented to users.
mkdir -p "$TEST_TMP/fake-bin"
cat > "$TEST_TMP/fake-bin/tmux" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == run-shell ]]; then
  bash -c "$3"
elif [[ "$1" == display-popup ]]; then
  exit 0
elif [[ "$1" == display-message ]]; then
  printf '%s\n' "${@: -1}" >> "$RTIDE_TEST_NOTICES"
fi
SH
chmod +x "$TEST_TMP/fake-bin/tmux"
cat > "$TEST_TMP/failing-rtide" <<'SH'
#!/usr/bin/env bash
printf 'details before failure\n'
printf 'precise readiness failure: tweb\n' >&2
exit 7
SH
chmod +x "$TEST_TMP/failing-rtide"
export RTIDE_TEST_NOTICES="$TEST_TMP/notices"
export TMPDIR="$TEST_TMP"
export PATH="$TEST_TMP/fake-bin:$PATH"
SCRIPT_PATH="$TEST_TMP/failing-rtide"
source <(sed -n '/^dispatch_fork_menu_action()/,/^}/p' "$ROOT/bin/rtide")
dispatch_fork_menu_action resume demo-fork %9 /dev/pts/9
DISPATCH_LOG=$(find "$TEST_TMP" -maxdepth 1 -name 'rtide-fork-dispatch-*.log' -print -quit)
grep -F 'details before failure' "$DISPATCH_LOG" >/dev/null \
  || fail 'dispatcher did not preserve stdout'
grep -F 'precise readiness failure: tweb' "$DISPATCH_LOG" >/dev/null \
  || fail 'dispatcher did not preserve stderr'
grep -F 'fork-menu-action %q %q %q %q' <<< "$(sed -n '/^dispatch_fork_menu_action()/,/^}/p' "$ROOT/bin/rtide")" >/dev/null \
  || fail 'dispatcher command does not preserve the invoking client target'
grep -F 'RTIDE fork action failed: precise readiness failure: tweb' "$RTIDE_TEST_NOTICES" >/dev/null \
  || fail 'dispatcher failure was not shown to the user'
grep -F "log: $DISPATCH_LOG" "$RTIDE_TEST_NOTICES" >/dev/null \
  || fail 'dispatcher notice omitted its durable log path'

printf 'PASS: fork launch status and background errors are durable and visible\n'
