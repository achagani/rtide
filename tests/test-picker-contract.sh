#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source <(sed -n '/^searchable_choice()/,/^}/p' "$ROOT/bin/rtide")
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

result=$(searchable_choice $'query\nexisting\tbranch\tclean' new)
[[ "$result" == $'open\texisting\tbranch\tclean' ]] \
  || fail 'existing selection did not win over query'

result=$(searchable_choice $'brand-new\n' new)
[[ "$result" == $'create\tbrand-new' ]] \
  || fail 'unknown fork query did not create'

result=$(searchable_choice $'new-place\n' workspace)
[[ "$result" == $'create\tnew-place' ]] \
  || fail 'unknown workspace query did not create'

result=$(searchable_choice $'\n＋ Create new fork\tnew\t\t' new)
[[ "$result" == $'create\t' ]] \
  || fail 'explicit create row did not request guided creation'

result=$(searchable_choice '' new)
[[ "$result" == $'cancel\t' ]] \
  || fail 'empty picker result did not cancel'

printf 'PASS: searchable picker open, create, guided-create, and cancel contract\n'
