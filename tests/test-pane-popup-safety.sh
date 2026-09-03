#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/libexec/rtide/pane-popup"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -x "$HELPER" ]] || fail "pane popup helper is unavailable: $HELPER"
bash -n "$HELPER"

grep -F 'helper="$RTIDE_LIBEXEC_DIR/pane-popup"' "$ROOT/bin/rtide" >/dev/null \
  || fail 'RTIDE does not resolve the popup helper from its own release'
if grep -Fq '$HOME/.tmux/pane-popup-toggle.sh' "$ROOT/bin/rtide"; then
  fail 'RTIDE still depends on the unmanaged home-directory popup helper'
fi

grep -F 'STATE_CLIENT="${STATE_PREFIX}_client"' "$HELPER" >/dev/null \
  || fail 'helper does not persist the invoking client'
grep -F 'switch-client -c "$client" -t "$source_window"' "$HELPER" >/dev/null \
  || fail 'restore does not explicitly return the invoking client to its source window'
grep -F 'detach-client -t "$popup_client"' "$HELPER" >/dev/null \
  || fail 'restore does not limit detach to the nested popup client'
if grep -Eq '^[[:space:]]*tmux_cmd detach-client[[:space:]]*(>|$)' "$HELPER"; then
  fail 'helper still contains an untargeted detach-client operation'
fi

grep -F 'popup_target=(-c "$requested_client")' "$HELPER" >/dev/null \
  || fail 'popup is not targeted to its invoking tmux client'
grep -F 'STATE_POPUP_LEFT="${STATE_PREFIX}_left"' "$HELPER" >/dev/null \
  || fail 'helper does not publish popup geometry for graphical panes'
grep -F 'client_cell_width' "$HELPER" >/dev/null \
  || fail 'popup geometry does not validate client cell dimensions'

printf 'PASS: floating pane restore targets only its nested client\n'
