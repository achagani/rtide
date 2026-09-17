#!/usr/bin/env bash
# Workspace control sockets must live under the runtime root so workspaces on
# exFAT/FAT32/network mounts (which cannot host Unix domain sockets) still get a
# working editor. The workspace keeps a discoverable pointer file.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Isolate the runtime root so the test never touches the real one.
export RTIDE_TEST_RUNTIME="$TEST_TMP/runtime"
export XDG_RUNTIME_DIR="$RTIDE_TEST_RUNTIME"
mkdir -p "$XDG_RUNTIME_DIR"

source "$ROOT/libexec/rtide/runtime-paths.sh"

mkdir -p "$TEST_TMP/workspace/.rtide"

# The socket path is under the runtime root, not the workspace.
socket=$(rtide_nvim_socket "$TEST_TMP/workspace")
[[ "$socket" == "$XDG_RUNTIME_DIR"/* ]] \
  || fail "socket is not under the runtime root: $socket"
case "$socket" in
  "$TEST_TMP/workspace"*) fail 'socket was placed inside the workspace' ;;
esac

# The key is stable for the same workspace and distinct across workspaces.
[[ "$(rtide_nvim_socket "$TEST_TMP/workspace")" == "$socket" ]] \
  || fail 'socket path is not stable'
other=$(rtide_workspace_key "$TEST_TMP/other")
[[ "$other" != "$(rtide_workspace_key "$TEST_TMP/workspace")" ]] \
  || fail 'distinct workspaces share a socket key'

# Resolving prefers the runtime root on a normal host and records a pointer.
resolved=$(rtide_resolve_nvim_socket "$TEST_TMP/workspace")
[[ "$resolved" == "$socket" ]] || fail "resolve did not prefer the runtime root: $resolved"
rtide_write_nvim_pointer "$TEST_TMP/workspace" "$resolved"
pointer=$(rtide_nvim_pointer "$TEST_TMP/workspace")
[[ -r "$pointer" ]] || fail 'pointer file was not written'
[[ "$(head -n1 "$pointer")" == "$resolved" ]] || fail 'pointer does not record the live socket'

# Discovery reads the pointer and only reports a live socket.
if rtide_locate_nvim_socket "$TEST_TMP/workspace" >/dev/null 2>&1; then
  fail 'discovery reported a socket that does not exist yet'
fi
python3 - "$resolved" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.listen(1)
PY
discovered=$(rtide_locate_nvim_socket "$TEST_TMP/workspace")
[[ "$discovered" == "$resolved" ]] || fail "discovery did not find the live socket: $discovered"

# A stale pointer must not break startup or opening.
printf '%s\n' "$TEST_TMP/gone.sock" > "$pointer"
if rtide_locate_nvim_socket "$TEST_TMP/workspace" >/dev/null 2>&1; then
  fail 'stale pointer was treated as a live socket'
fi

# Cleanup removes both the runtime socket and the pointer.
rtide_write_nvim_pointer "$TEST_TMP/workspace" "$resolved"
rtide_cleanup_nvim_socket "$TEST_TMP/workspace"
[[ ! -e "$resolved" ]] || fail 'cleanup left the runtime socket behind'
[[ ! -e "$pointer" ]] || fail 'cleanup left the pointer behind'
[[ -d "$TEST_TMP/workspace/.rtide" ]] || fail 'cleanup removed workspace runtime state'

# rtide open reports a clear error when no live socket exists, from any subdir.
mkdir -p "$TEST_TMP/workspace/sub"
open_err=$( (cd "$TEST_TMP/workspace/sub" && "$ROOT/libexec/rtide/open" file.txt) 2>&1 || true )
grep -Fq 'nvim not running' <<< "$open_err" \
  || fail "rtide open did not report a missing live socket clearly: $open_err"

# With a live socket recorded, rtide open targets it via nvim --server.
python3 - "$resolved" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.listen(1)
PY
rtide_write_nvim_pointer "$TEST_TMP/workspace" "$resolved"
mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/nvim" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --server ]]; then printf '%s\n' "$2" > "$NVIM_TARGET_FILE"; exit 0; fi
exit 1
EOF
chmod +x "$TEST_TMP/bin/nvim"
export NVIM_TARGET_FILE="$TEST_TMP/nvim.target"
if ! ( cd "$TEST_TMP/workspace/sub" \
    && PATH="$TEST_TMP/bin:$PATH" "$ROOT/libexec/rtide/open" file.txt ) >/dev/null; then
  fail 'rtide open failed with a live relocated socket'
fi
[[ "$(cat "$TEST_TMP/nvim.target")" == "$resolved" ]] \
  || fail 'rtide open targeted the wrong socket path'

printf 'PASS: runtime socket placement, pointer discovery, stale tolerance, and cleanup\n'
