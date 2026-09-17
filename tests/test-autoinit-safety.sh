#!/usr/bin/env bash
# Auto-init safety: RTIDE must never seed files or `git add -A` a broad tree such
# as $HOME, an ancestor, a mount root, or a directory that contains repositories.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Load the guard helpers exactly as the launcher defines them.
eval "$(sed -n '/^RTIDE_AUTOINIT_MAX_ENTRIES=/,/^}/p' "$ROOT/bin/rtide")"
eval "$(sed -n '/^rtide_workspace_safe()/,/^}/p' "$ROOT/bin/rtide")"
eval "$(sed -n '/^rtide_seed_safe()/,/^}/p' "$ROOT/bin/rtide")"
eval "$(sed -n '/^rtide_autoinit_safe()/,/^}/p' "$ROOT/bin/rtide")"

# A broad directory must be refused as a workspace entirely: RTIDE writes
# per-workspace state into the workspace, so $HOME and mount roots are unsafe.
for unsafe in "$HOME" / /home "$(dirname "$HOME")"; do
  if rtide_workspace_safe "$unsafe" >/dev/null 2>&1; then
    fail "broad directory accepted as a workspace: $unsafe"
  fi
done
mkdir -p "$TEST_TMP/project-later"
rtide_workspace_safe "$TEST_TMP/project-later" >/dev/null 2>&1 \
  || fail 'a project directory was refused as a workspace'
grep -F 'rtide_workspace_safe "$DIR" || exit 2' "$ROOT/bin/rtide" >/dev/null \
  || fail 'launcher does not refuse broad directories before writing state'

# Seed safety: never $HOME, an ancestor, a mount root, or a system directory.
for unsafe in "$HOME" / /home /etc /tmp /usr /var "$(dirname "$HOME")"; do
  if rtide_seed_safe "$unsafe"; then
    fail "seed considered unsafe directory safe: $unsafe"
  fi
done

# A normal project directory is safe.
project="$TEST_TMP/project"
mkdir -p "$project"
printf 'hello\n' > "$project/app.txt"
rtide_seed_safe "$project" || fail 'a normal project directory was not seed-safe'
rtide_autoinit_safe "$project" || fail 'a normal project directory was not autoinit-safe'

# Existing repository, and a directory inside one, are never auto-initialized.
git -C "$project" init -q
rtide_autoinit_safe "$project" && fail 'an existing repository was autoinit-safe'
mkdir -p "$project/sub"
rtide_autoinit_safe "$project/sub" && fail 'a directory inside a repository was autoinit-safe'

# A directory that contains nested repositories is refused.
container="$TEST_TMP/container"
mkdir -p "$container/child"
git -C "$container/child" init -q
rtide_autoinit_safe "$container" && fail 'a container of repositories was autoinit-safe'

# A directory containing another RTIDE workspace is refused.
ws_container="$TEST_TMP/ws-container"
mkdir -p "$ws_container/other/.rtide"
rtide_autoinit_safe "$ws_container" && fail 'a workspace container was autoinit-safe'

# An oversized directory is refused as a broad tree.
big="$TEST_TMP/big"
mkdir -p "$big"
for i in $(seq 1 6000); do : > "$big/f$i"; done
rtide_autoinit_safe "$big" && fail 'an oversized directory was autoinit-safe'

# The launcher must gate seeding and auto-init on these helpers.
grep -F 'if rtide_seed_safe "$DIR"' "$ROOT/bin/rtide" >/dev/null \
  || fail 'launcher does not gate file seeding on rtide_seed_safe'
grep -F 'if rtide_autoinit_safe "$DIR"' "$ROOT/bin/rtide" >/dev/null \
  || fail 'launcher does not gate auto-init on rtide_autoinit_safe'
grep -F 'not seeding RTIDE project files' "$ROOT/bin/rtide" >/dev/null \
  || fail 'launcher does not explain when seeding is skipped'

# The welcome page must fall back to the runtime cache when seeding is skipped,
# so opening a broad directory never crashes trying to write into it.
grep -F 'welcome_out="$HOME/.cache/rtide/welcome/' "$ROOT/bin/rtide" >/dev/null \
  || fail 'welcome page has no runtime fallback for unseeded directories'
grep -F 'file://$welcome_out' "$ROOT/bin/rtide" >/dev/null \
  || fail 'launcher readiness does not use the resolved welcome path'

printf 'PASS: auto-init refuses broad, repository, and oversized directories\n'
