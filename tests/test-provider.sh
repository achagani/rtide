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

# Codex resume rejects `--sandbox`; the policy must be passed as a config
# override so resumed turns are still sandboxed.
for pair in "workspace:sandbox_mode=\"workspace-write\"" "observe:sandbox_mode=\"read-only\""; do
  policy=${pair%%:*}; expected=${pair#*:}
  resumed=$("$ROOT/libexec/rtide/provider" run codex openai model prompt session-1 "$policy")
  [[ "$resumed" == *"exec resume"* ]] \
    || { printf 'FAIL: %s resume did not resume: %s\n' "$policy" "$resumed" >&2; exit 1; }
  [[ "$resumed" == *"$expected"* ]] \
    || { printf 'FAIL: %s resume missing %s: %s\n' "$policy" "$expected" "$resumed" >&2; exit 1; }
  if [[ "$resumed" == *'--sandbox'* ]]; then
    printf 'FAIL: %s resume uses unsupported --sandbox: %s\n' "$policy" "$resumed" >&2; exit 1
  fi
done

# New (non-resumed) Codex turns still use --sandbox, which `codex exec` accepts.
fresh=$("$ROOT/libexec/rtide/provider" run codex openai model prompt '' workspace)
[[ "$fresh" == *'--sandbox workspace-write'* ]] \
  || { printf 'FAIL: fresh Codex turn lost its sandbox: %s\n' "$fresh" >&2; exit 1; }

# unrestricted resume keeps the bypass flag; native resume adds no override.
unrestricted=$("$ROOT/libexec/rtide/provider" run codex openai model prompt s1 unrestricted)
[[ "$unrestricted" == *'--dangerously-bypass-approvals-and-sandbox'* ]] \
  || { printf 'FAIL: unrestricted resume lost the bypass: %s\n' "$unrestricted" >&2; exit 1; }
native=$("$ROOT/libexec/rtide/provider" run codex openai model prompt s1 native)
if [[ "$native" == *'sandbox_mode'* || "$native" == *'--sandbox'* ]]; then
  printf 'FAIL: native resume added a sandbox override: %s\n' "$native" >&2; exit 1
fi

printf 'PASS: provider attachment capability and resume sandbox\n'
