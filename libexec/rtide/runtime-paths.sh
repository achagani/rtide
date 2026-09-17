#!/usr/bin/env bash
# Shared runtime path resolution for RTIDE workspace control sockets.
#
# A workspace can live on a filesystem that cannot host Unix domain sockets
# (exFAT, FAT32, some network mounts). Control sockets therefore live under the
# runtime root, and a workspace-local pointer file records the live path so
# `rtide open` and readiness checks can discover it without assuming placement.

# Runtime root for per-user RTIDE control state. XDG_RUNTIME_DIR is a per-user
# tmpfs on Linux; fall back to TMPDIR for platforms that do not define it.
rtide_runtime_root() {
  printf '%s/rtide-%s' "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}" "$(id -u)"
}

# Stable, collision-safe key for a workspace directory.
rtide_workspace_key() {
  local dir
  dir=$(realpath -m "${1:?workspace required}")
  printf '%s' "$dir" | sha256sum | cut -c1-16
}

# Preferred Neovim control socket for a workspace (under the runtime root).
rtide_nvim_socket() {
  printf '%s/nvim/%s.sock' "$(rtide_runtime_root)" "$(rtide_workspace_key "$1")"
}

# Workspace-local pointer file recording the live control socket path.
rtide_nvim_pointer() {
  printf '%s/.rtide/nvim-socket' "$(realpath -m "$1")"
}

# Whether a directory can host a Unix domain socket. Probes by binding and
# removing a throwaway socket; never leaves a file behind.
rtide_can_bind_socket() {
  local dir="$1" probe rc=1
  [[ -d "$dir" ]] || return 1
  command -v python3 >/dev/null 2>&1 || return 0
  probe="$dir/.rtide-socket-probe.$$"
  python3 - "$probe" <<'PY' 2>/dev/null
import socket, sys
try:
    probe = socket.socket(socket.AF_UNIX)
    probe.bind(sys.argv[1])
    probe.close()
except OSError:
    sys.exit(1)
PY
  rc=$?
  rm -f -- "$probe" 2>/dev/null || true
  return $rc
}

# Resolve the control socket a workspace should use. Prefers the runtime root;
# falls back to the workspace's own .rtide/ only when the runtime root cannot
# host a socket. Returns non-zero when neither location can host one.
rtide_resolve_nvim_socket() {
  local dir="$1" preferred
  dir=$(realpath -m "$dir")
  preferred=$(rtide_nvim_socket "$dir")
  if mkdir -p "$(dirname "$preferred")" 2>/dev/null \
      && rtide_can_bind_socket "$(dirname "$preferred")"; then
    printf '%s\n' "$preferred"
    return 0
  fi
  if rtide_can_bind_socket "$dir/.rtide"; then
    printf '%s\n' "$dir/.rtide/nvim.sock"
    return 0
  fi
  return 1
}

# Atomically record the live control socket path for a workspace.
rtide_write_nvim_pointer() {
  local dir="$1" socket="$2" pointer tmp
  pointer=$(rtide_nvim_pointer "$dir")
  mkdir -p "$(dirname "$pointer")" 2>/dev/null || return 0
  tmp="$pointer.$$"
  if printf '%s\n' "$socket" > "$tmp" 2>/dev/null; then
    mv -f -- "$tmp" "$pointer" 2>/dev/null || rm -f -- "$tmp" 2>/dev/null || true
  fi
}

# Remove a workspace's control socket and pointer. Tolerates stale state.
rtide_cleanup_nvim_socket() {
  local dir="$1" pointer socket
  pointer=$(rtide_nvim_pointer "$dir")
  if [[ -r "$pointer" ]]; then
    read -r socket < "$pointer" || true
    [[ -z "$socket" ]] || rm -f -- "$socket" 2>/dev/null || true
  fi
  rm -f -- "$pointer" 2>/dev/null || true
  rm -f -- "$(rtide_nvim_socket "$dir")" 2>/dev/null || true
  rm -f -- "$(realpath -m "$dir")/.rtide/nvim.sock" 2>/dev/null || true
}

# Locate the live control socket for a workspace. Reads the pointer first, then
# falls back to a legacy workspace-local socket. Prints nothing when neither is
# a live socket.
rtide_locate_nvim_socket() {
  local dir="$1" pointer socket=""
  pointer=$(rtide_nvim_pointer "$dir")
  if [[ -r "$pointer" ]]; then
    read -r socket < "$pointer" || true
  fi
  if [[ -n "$socket" && -S "$socket" ]]; then
    printf '%s\n' "$socket"
    return 0
  fi
  socket="$(realpath -m "$dir")/.rtide/nvim.sock"
  if [[ -S "$socket" ]]; then
    printf '%s\n' "$socket"
    return 0
  fi
  return 1
}
