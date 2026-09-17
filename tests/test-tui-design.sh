#!/usr/bin/env bash
# TUI design-system contracts: semantic tokens, plain/ASCII modes, responsive
# geometry, and one shared picker grammar that is safe under `set -e`.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# The picker builder must not abort a `set -e` caller when color is enabled.
# Regression: a trailing `rtide_ui_plain && …` returned 1 and killed the fork menu.
out=$(bash -euc "source '$ROOT/libexec/rtide/ui.sh'; source '$ROOT/libexec/rtide/picker.sh'; rtide_picker_options create full; printf '%s\n' \"\${#RTIDE_PICKER_ARGS[@]}\"" 2>&1) \
  || fail 'rtide_picker_options aborts under set -e when color is enabled'
[[ "$out" =~ ^[0-9]+$ ]] || fail "picker arg count was not numeric: $out"

# No-color removes authored color but keeps the option grammar and header.
nocolor=$(bash -euc "source '$ROOT/libexec/rtide/ui.sh'; source '$ROOT/libexec/rtide/picker.sh'; NO_COLOR=1 rtide_picker_options select full; printf '%s\n' \"\${RTIDE_PICKER_ARGS[*]}\"")
grep -F -- '--no-color' <<< "$nocolor" >/dev/null \
  || fail 'NO_COLOR did not add --no-color to picker args'
grep -F -- '--header=' <<< "$nocolor" >/dev/null \
  || fail 'plain picker lost its header grammar'

# State labels stay distinguishable without relying on color, and ASCII mode
# replaces the Unicode marks.
labels=$(bash -euc "source '$ROOT/libexec/rtide/ui.sh'; for s in ready working input-needed success warning error; do rtide_ui_state_label \$s; echo; done")
for word in ready working 'input needed' done warning error; do
  grep -Fq "$word" <<< "$labels" || fail "state vocabulary missing '$word'"
done
ascii=$(bash -euc "source '$ROOT/libexec/rtide/ui.sh'; RTIDE_ASCII=1 rtide_ui_state_label ready")
[[ "$ascii" == '[ok] ready' ]] || fail "ASCII ready label is '$ascii'"

# Responsive geometry: auto resolves by width, modes preserve pane liveness at
# width 1, and compose bounds the composer to 6-16 rows.
geo() { bash -euc "source '$ROOT/libexec/rtide/ui.sh'; rtide_layout_geometry $1"; }
[[ "$(geo '60 30 60 3 auto' | cut -f1)" == output ]] \
  || fail 'narrow auto layout did not resolve to output'
[[ "$(geo '140 40 60 3 auto' | cut -f1)" == balanced ]] \
  || fail 'wide auto layout did not resolve to balanced'
[[ "$(geo '140 40 60 3 output' | cut -f3)" == 1 ]] \
  || fail 'output mode did not collapse the editor to one column'
[[ "$(geo '140 40 60 3 edit' | cut -f4)" == 1 ]] \
  || fail 'edit mode did not collapse the output to one column'
compose=$(geo '140 40 60 3 compose'); h=$(cut -f2 <<< "$compose")
(( h >= 6 && h <= 16 )) || fail "compose height $h is outside 6-16"

# A no-color render must never emit an ANSI escape from the chrome builder.
if grep -F -- '--color=' <<< "$nocolor" >/dev/null; then
  fail 'no-color picker args still carry an explicit palette'
fi

printf 'PASS: TUI tokens, plain/ASCII modes, geometry, and picker grammar\n'
