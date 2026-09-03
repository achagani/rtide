#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/libexec/rtide/picker.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

result=$(rtide_picker_decode $'existing\nexisting\tbranch\tclean' create new)
[[ "$result" == $'open\texisting\tbranch\tclean' ]] \
  || fail 'existing selection did not win over query'

result=$(rtide_picker_decode $'exis\nexisting\tbranch\tclean' create new)
[[ "$result" == $'create\texis' ]] \
  || fail 'partial fuzzy match opened an existing item instead of creating exact query'

query_only=$(printf 'brand-new\n')
result=$(rtide_picker_decode "$query_only" create new)
[[ "$result" == $'create\tbrand-new' ]] \
  || fail 'query-only fzf result with stripped trailing newline did not create'

result=$(rtide_picker_decode $'a-very-long-fork-name\n' create new)
[[ "$result" == $'create\ta-very-long-fork-name' ]] \
  || fail 'long unknown fork query did not create'

result=$(rtide_picker_decode $'new-place\n' create workspace)
[[ "$result" == $'create\tnew-place' ]] \
  || fail 'unknown workspace query did not create'

result=$(rtide_picker_decode $'\n＋ Create new fork\tnew\t\t' create new)
[[ "$result" == $'create\t' ]] \
  || fail 'explicit create row did not request guided creation'

result=$(rtide_picker_decode '' create new)
[[ "$result" == $'cancel\t' ]] \
  || fail 'empty picker result did not cancel'

result=$(rtide_picker_decode $'query\nknown\tvalue' select ignored)
[[ "$result" == $'open\tknown\tvalue' ]] || fail 'select-only policy rejected selection'
result=$(rtide_picker_decode $'custom-model\n' freeform ignored)
[[ "$result" == $'value\tcustom-model' ]] || fail 'freeform policy rejected value'

printf 'PASS: searchable picker open, create, guided-create, and cancel contract\n'
