#!/usr/bin/env bash

# Shared output routing for rtide render and rtide run.
# Call rtide_tweb_prepare before choosing a cache path, then rtide_tweb_show.

# How long to wait for a submission to be acknowledged as the active tab.
# Kept short for interactive render/run so output stays immediate; the agent
# controller does its own longer verification at the end of a turn.
RTIDE_TWEB_ACK_TRIES="${RTIDE_TWEB_ACK_TRIES:-3}"
RTIDE_TWEB_ACK_DELAY="${RTIDE_TWEB_ACK_DELAY:-0.05}"

# Resolve the workspace root that owns a registered browser pane, walking
# upward from a starting directory. Prints nothing when none is found.
rtide_tweb_workspace_root() {
  local root="${1:-${RTIDE_WORKSPACE:-$PWD}}"
  root=$(realpath "$root" 2>/dev/null || printf '%s' "$root")
  while [[ -n "$root" && "$root" != / ]]; do
    if [[ -r "$root/.rtide/tweb-pane" ]]; then
      printf '%s\n' "$root"
      return 0
    fi
    root=${root%/*}
    [[ -n "$root" ]] || root=/
  done
  return 1
}

# Whether a browser is actually running in the pane. A pane that exists without
# a live browser is disconnected, not connected.
rtide_tweb_pane_live() {
  local pane="$1"
  [[ -n "$pane" ]] || return 1
  tweb status --pane "$pane" >/dev/null 2>&1
}

# Classify the workspace output connection. Sets RTIDE_TWEB_STATE and, when a
# pane is known, RTIDE_TWEB_PANE. Never claims a browser exists without probing.
rtide_tweb_state() {
  local pane_hint="${1:-${RTIDE_TWEB_PANE:-}}" session_hint="${2:-${RTIDE_TWEB_SESSION_HINT:-}}" registration
  local anchor_pane="$pane_hint" session window
  RTIDE_TWEB_STATE=standalone
  RTIDE_TWEB_PANE=
  RTIDE_TWEB_SESSION="${session_hint:-standalone}"

  if [[ -z "$anchor_pane" ]]; then
    registration=$(rtide_tweb_workspace_root "${RTIDE_WORKSPACE:-$PWD}" 2>/dev/null || true)
    [[ -n "$registration" ]] && read -r anchor_pane < "$registration/.rtide/tweb-pane" || true
    [[ -n "$anchor_pane" ]] || anchor_pane="${TMUX_PANE:-}"
  fi
  if [[ -z "$anchor_pane" ]]; then
    if [[ -n "$(rtide_tweb_workspace_root "${RTIDE_WORKSPACE:-$PWD}" 2>/dev/null || true)" ]]; then
      RTIDE_TWEB_STATE=missing
    fi
    return 0
  fi

  session=$(tmux display-message -p -t "$anchor_pane" '#{session_name}' 2>/dev/null || true)
  window=$(tmux display-message -p -t "$anchor_pane" '#{window_id}' 2>/dev/null || true)
  [[ -n "$session" ]] || session="$session_hint"
  RTIDE_TWEB_SESSION="${session:-standalone}"
  if [[ -z "$session" ]]; then
    RTIDE_TWEB_STATE=missing
    return 0
  fi

  local pane role
  local -a matches=()
  while read -r pane role; do
    [[ "$role" == tweb ]] && matches+=("$pane")
  done < <(tmux list-panes -t "${window:-$session:work}" -F '#{pane_id} #{@rtide-role}' 2>/dev/null || true)

  if (( ${#matches[@]} > 1 )); then
    RTIDE_TWEB_STATE=multiple
    return 0
  fi
  if (( ${#matches[@]} == 0 )); then
    [[ "$session" == rtide-* ]] && RTIDE_TWEB_STATE=missing || RTIDE_TWEB_STATE=standalone
    return 0
  fi
  RTIDE_TWEB_PANE="${matches[0]}"
  if rtide_tweb_pane_live "${matches[0]}"; then
    RTIDE_TWEB_STATE=connected
  else
    RTIDE_TWEB_STATE=disconnected
  fi
}

rtide_tweb_prepare() {
  [[ -n "${RTIDE_TWEB_MODE:-}" ]] && return 0

  # Capture direct harness hints before resetting the exported result fields.
  # Some command sandboxes lose TMUX_PANE and change cwd, so neither of the
  # older inference paths is guaranteed to survive a tool invocation.
  local pane_hint="${RTIDE_TWEB_PANE:-}"
  local session_hint="${RTIDE_TWEB_SESSION_HINT:-}"
  local window

  rtide_tweb_state "$pane_hint" "$session_hint" || true

  RTIDE_TWEB_MODE=standalone
  RTIDE_TWEB_FAILURE=
  case "$RTIDE_TWEB_STATE" in
    connected|disconnected)
      RTIDE_TWEB_MODE=managed
      ;;
    multiple)
      RTIDE_TWEB_FAILURE=multiple
      printf 'tweb output error: multiple role=tweb panes in %s\n' "$RTIDE_TWEB_SESSION" >&2
      return 2
      ;;
    missing)
      RTIDE_TWEB_FAILURE=missing
      return 2
      ;;
  esac

  window=$(tmux display-message -p -t "${RTIDE_TWEB_PANE:-${TMUX_PANE:-}}" '#{window_id}' 2>/dev/null || true)
  RTIDE_TWEB_CACHE_KEY="${RTIDE_TWEB_SESSION}-${window:-work}"
  RTIDE_TWEB_CACHE_KEY=${RTIDE_TWEB_CACHE_KEY//[^a-zA-Z0-9_.-]/_}
  RTIDE_TWEB_LAST_RENDER="$HOME/.cache/rtide/$RTIDE_TWEB_CACHE_KEY/last-render"
  export RTIDE_TWEB_MODE RTIDE_TWEB_PANE RTIDE_TWEB_SESSION RTIDE_TWEB_STATE \
    RTIDE_TWEB_CACHE_KEY RTIDE_TWEB_LAST_RENDER
}

# Wait (bounded) for the active tab to become the submitted target. Returns 0
# only on acknowledged display; never infers it from a successful submission.
rtide_tweb_acknowledge() {
  local pane="$1" target="$2" tries="${3:-$RTIDE_TWEB_ACK_TRIES}" i active
  for (( i = 0; i < tries; i++ )); do
    active=$(tweb status --pane "$pane" --json 2>/dev/null \
      | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(next(t["url"] for t in d["tabs"]["tabs"] if t.get("active")))
except (ValueError, KeyError, TypeError, StopIteration):
    pass' 2>/dev/null || true)
    [[ -n "$active" && "$active" == "$target" ]] && return 0
    sleep "$RTIDE_TWEB_ACK_DELAY"
  done
  return 1
}

# Reconnect a live-but-browserless registered pane, or repair a stale
# registration when the window has exactly one role pane. Reuses the pane; it
# never creates a second browser pane. The recorded target is restored.
rtide_tweb_reconnect() {
  local pane="${1:-${RTIDE_TWEB_PANE:-}}" workspace_root="${2:-}"
  [[ -n "$pane" ]] || return 1
  if ! tmux display-message -p -t "$pane" '#{pane_id}' >/dev/null 2>&1; then
    return 1
  fi
  [[ -n "$workspace_root" ]] || workspace_root=$(rtide_tweb_workspace_root "${RTIDE_WORKSPACE:-$PWD}" 2>/dev/null || true)
  # Prefer the workspace's last acknowledged artifact, then its welcome page.
  local last="" target=""
  if [[ -n "$workspace_root" ]]; then
    local key="${RTIDE_TWEB_SESSION:-standalone}-work"
    last="$HOME/.cache/rtide/${key//[^a-zA-Z0-9_.-]/_}/last-render"
  fi
  if [[ -r "$last" ]]; then
    target=$(head -n1 "$last" 2>/dev/null || true)
  fi
  tmux send-keys -t "$pane" "tweb open '${target:-about:blank}'" Enter
  return 0
}

# Explicit safe creation of the one role pane. Refuses when a role pane already
# exists so it can never create a duplicate. Never used during an agent turn.
rtide_tweb_recreate() {
  local window="${1:-}" workspace_root="${2:-}" existing pane
  [[ -n "$window" ]] || window=$(tmux display-message -p '#{window_id}' 2>/dev/null || true)
  [[ -n "$window" ]] || { printf 'tweb recreate: no RTIDE window\n' >&2; return 1; }
  existing=$(tmux list-panes -t "$window" -F '#{pane_id} #{@rtide-role}' 2>/dev/null \
    | awk '$2=="tweb"{print $1; exit}')
  if [[ -n "$existing" ]]; then
    printf 'tweb recreate: refusing — pane %s already has role=tweb\n' "$existing" >&2
    return 2
  fi
  pane=$(tmux split-window -d -h -P -F '#{pane_id}' -t "$window" 2>/dev/null) || return 1
  tmux set-option -p -t "$pane" @rtide-role tweb
  tmux select-pane -t "$pane" -T output 2>/dev/null || true
  [[ -n "$workspace_root" ]] && printf '%s\n' "$pane" > "$workspace_root/.rtide/tweb-pane"
  printf 'tweb recreate: created pane %s\n' "$pane"
  return 0
}

# Human-readable connection state for `rtide tweb status` and diagnostics.
rtide_tweb_report() {
  rtide_tweb_state
  case "$RTIDE_TWEB_STATE" in
    connected)    printf 'connected\t%s\tbrowser running\n' "${RTIDE_TWEB_PANE:-}" ;;
    disconnected) printf 'disconnected\t%s\tpane live, no browser\n' "${RTIDE_TWEB_PANE:-}" ;;
    missing)      printf 'missing\t-\tno registered browser pane\n' ;;
    multiple)     printf 'multiple\t-\tmore than one role=tweb pane\n' ;;
    *)            printf 'standalone\t-\tno RTIDE workspace context\n' ;;
  esac
}

rtide_tweb_queue() {
  local url="$1" float="${2:-0}" queue_root="${RTIDE_WORKSPACE:-$PWD}" request tmp
  queue_root=$(realpath "$queue_root" 2>/dev/null || printf '%s' "$queue_root")
  while [[ -n "$queue_root" && "$queue_root" != / ]]; do
    if [[ -r "$queue_root/.rtide/tweb-pane" ]]; then
      request="$queue_root/.rtide/render-request"
      tmp="$request.$$"
      printf '%s\n%s\n' "$float" "$url" > "$tmp" || return 1
      mv -f -- "$tmp" "$request" || return 1
      printf 'queued render for RTIDE tweb pane\n'
      return 0
    fi
    queue_root=${queue_root%/*}
    [[ -n "$queue_root" ]] || queue_root=/
  done
  return 1
}

rtide_tweb_show() {
  local url="$1" float="${2:-0}" request_root="${RTIDE_WORKSPACE:-$PWD}"
  if ! rtide_tweb_prepare; then
    # A missing pane is recoverable by the workspace controller: preserve the
    # artifact so it is displayed once the connection returns. Never claim it
    # was displayed.
    if [[ "${RTIDE_TWEB_FAILURE:-}" == missing ]] \
        && RTIDE_WORKSPACE="$request_root" rtide_tweb_queue "$url" "$float"; then
      printf 'queued render · workspace browser pane missing\n'
      return 0
    fi
    return 2
  fi

  if [[ "$RTIDE_TWEB_MODE" == managed ]]; then
    # A live pane without a browser is reconnected in place, reusing the pane.
    if [[ "$RTIDE_TWEB_STATE" == disconnected ]]; then
      rtide_tweb_reconnect "$RTIDE_TWEB_PANE" "$request_root" \
        || { printf 'tweb output error: could not reconnect pane %s\n' "$RTIDE_TWEB_PANE" >&2; return 1; }
      sleep 0.3
    fi
    tweb navigate --pane "$RTIDE_TWEB_PANE" "$url" || {
      printf 'tweb output error: navigation failed for pane %s\n' "$RTIDE_TWEB_PANE" >&2
      return 1
    }
    rtide_tweb_controls "$RTIDE_TWEB_PANE"
    mkdir -p "$(dirname "$RTIDE_TWEB_LAST_RENDER")"
    printf '%s\n' "$url" > "$RTIDE_TWEB_LAST_RENDER"
    if [[ "$float" == 1 ]]; then
      tweb float --pane "$RTIDE_TWEB_PANE"
    fi
    # Report honestly: acknowledged display only when the active tab matches.
    if rtide_tweb_acknowledge "$RTIDE_TWEB_PANE" "$url"; then
      printf 'rendered to tweb pane %s\n' "$RTIDE_TWEB_PANE"
    else
      printf 'submitted to tweb pane %s · awaiting acknowledgement\n' "$RTIDE_TWEB_PANE"
    fi
    return 0
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    if RTIDE_WORKSPACE="$request_root" rtide_tweb_queue "$url" "$float"; then
      printf 'queued render · no interactive tweb pane\n'
      return 0
    fi
    printf 'tweb output error: no RTIDE tweb pane; refusing a blocking browser in a noninteractive shell\n' >&2
    return 1
  fi
  tweb open "$url"
}

rtide_html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
      -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

rtide_tweb_controls() {
  local pane="$1" workspace pid helper command
  helper="$(dirname -- "${BASH_SOURCE[0]}")/output-controls"
  workspace=$(tmux display-message -p -t "$pane" '#{@rtide-workspace}' 2>/dev/null || true)
  [[ -d "$workspace" ]] || workspace="${RTIDE_WORKSPACE:-$PWD}"
  python3 "$helper" --once "$pane" "$workspace" || true
  pid=$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null || true)
  if [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
    printf -v command 'python3 %q --watch %q %q %q' "$helper" "$pane" "$workspace" "$pid"
    tmux run-shell -b "$command" >/dev/null 2>&1 || true
  fi
}
