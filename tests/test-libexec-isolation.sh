#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  trap - EXIT
  find "$TEST_TMP" -depth -type f -delete 2>/dev/null || true
  find "$TEST_TMP" -depth -type d -empty -delete 2>/dev/null || true
  exit "$rc"
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$TEST_TMP/fake-bin" "$TEST_TMP/home" "$TEST_TMP/workspace"
export RTIDE_FAKE_HELPER_LOG="$TEST_TMP/fake-helper.log"
for command in rtide-provider rtide-progress rtide-mem rtide-memory-index rtide-forks tweb-render; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0" >> "$RTIDE_FAKE_HELPER_LOG"\nexit 97\n' \
    > "$TEST_TMP/fake-bin/$command"
  chmod +x "$TEST_TMP/fake-bin/$command"
done

export HOME="$TEST_TMP/home"
export PATH="$TEST_TMP/fake-bin:/usr/local/bin:/usr/bin:/bin"
export RTIDE_ROOT="$ROOT"

"$ROOT/bin/rtide" matrix >/dev/null
(
  cd "$TEST_TMP/workspace"
  "$ROOT/bin/rtide" memory init >/dev/null
  "$ROOT/bin/rtide" progress --workspace . --no-render init Isolation --steps Paths >/dev/null
)

[[ ! -s "$RTIDE_FAKE_HELPER_LOG" ]] \
  || fail 'an RTIDE workflow invoked a legacy helper from PATH'
printf 'PASS: runtime helpers are resolved from the selected release, not PATH\n'
