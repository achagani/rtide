#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PNG="$TMP/image with spaces.png"
TEXT="$TMP/notes.txt"
printf '\x89PNG\r\n\x1a\nfixture' > "$PNG"
printf 'notes\n' > "$TEXT"

cmd=$("$ROOT/libexec/rtide/provider" run codex openai model $'line one\nline two' '' workspace \
  --attachment "$PNG" image/png shot.png)
[[ "$cmd" == *'-i '* && "$cmd" == *'image\ with\ spaces.png'* ]] \
  || { printf 'FAIL: codex image flag missing: %s\n' "$cmd" >&2; exit 1; }

cmd=$("$ROOT/libexec/rtide/provider" run opencode openai model prompt session workspace \
  --attachment "$TEXT" text/plain notes.txt)
[[ "$cmd" == *'-f '* && "$cmd" == *'--session session'* ]] \
  || { printf 'FAIL: opencode file flag missing: %s\n' "$cmd" >&2; exit 1; }

cmd=$("$ROOT/libexec/rtide/provider" run claude anthropic model prompt '' workspace \
  --attachment "$TEXT" text/plain notes.txt)
[[ "$cmd" == *'RTIDE attachments'* && "$cmd" == *'notes.txt'* ]] \
  || { printf 'FAIL: claude path disclosure missing: %s\n' "$cmd" >&2; exit 1; }

if "$ROOT/libexec/rtide/provider" run codex openai model prompt '' workspace \
    --attachment "$TEXT" text/plain notes.txt >/dev/null 2>&1; then
  printf 'FAIL: codex accepted a non-image attachment\n' >&2; exit 1
fi
if "$ROOT/libexec/rtide/provider" run hermes openai model prompt '' workspace \
    --attachment "$PNG" image/png one.png \
    --attachment "$PNG" image/png two.png >/dev/null 2>&1; then
  printf 'FAIL: hermes accepted multiple images\n' >&2; exit 1
fi
if "$ROOT/libexec/rtide/provider" run opencode openai model prompt '' workspace \
    --attachment "$TMP/missing.png" image/png missing.png >/dev/null 2>&1; then
  printf 'FAIL: provider accepted a missing attachment\n' >&2; exit 1
fi

printf 'PASS: provider attachment capability matrix\n'
