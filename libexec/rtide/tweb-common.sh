#!/usr/bin/env bash

# Shared output routing for rtide render and rtide run.
# Call rtide_tweb_prepare before choosing a cache path, then rtide_tweb_show.

rtide_tweb_prepare() {
  [[ -n "${RTIDE_TWEB_MODE:-}" ]] && return 0

  # Capture direct harness hints before resetting the exported result fields.
  # Some command sandboxes lose TMUX_PANE and change cwd, so neither of the
  # older inference paths is guaranteed to survive a tool invocation.
  local pane_hint="${RTIDE_TWEB_PANE:-}"
  local session_hint="${RTIDE_TWEB_SESSION_HINT:-}"

  RTIDE_TWEB_MODE=standalone
  RTIDE_TWEB_PANE=
  RTIDE_TWEB_SESSION=standalone

  local anchor_pane="${pane_hint:-${TMUX_PANE:-}}"
  if [[ -z "$anchor_pane" ]]; then
    # Agent harnesses may intentionally strip TMUX/TMUX_PANE from commands.
    # Recover the workspace's registered browser pane from the command cwd.
    local workspace_root="${RTIDE_WORKSPACE:-$PWD}" registration
    workspace_root=$(realpath "$workspace_root" 2>/dev/null || printf '%s' "$workspace_root")
    while [[ -n "$workspace_root" && "$workspace_root" != / ]]; do
      registration="$workspace_root/.rtide/tweb-pane"
      if [[ -r "$registration" ]]; then
        read -r anchor_pane < "$registration" || true
        break
      fi
      workspace_root=${workspace_root%/*}
      [[ -n "$workspace_root" ]] || workspace_root=/
    done
  fi

  if [[ -n "$anchor_pane" ]]; then
    local session window pane role
    local -a matches=()
    session=$(tmux display-message -p -t "$anchor_pane" '#{session_name}' 2>/dev/null || true)
    window=$(tmux display-message -p -t "$anchor_pane" '#{window_id}' 2>/dev/null || true)
    [[ -n "$session" ]] || session="$session_hint"
    if [[ -n "$session" ]]; then
      RTIDE_TWEB_SESSION="$session"
      while read -r pane role; do
        [[ "$role" == tweb ]] && matches+=("$pane")
      done < <(tmux list-panes -t "${window:-$session:work}" -F '#{pane_id} #{@rtide-role}' 2>/dev/null || true)

      if (( ${#matches[@]} == 1 )); then
        RTIDE_TWEB_MODE=managed
        RTIDE_TWEB_PANE="${matches[0]}"
      elif (( ${#matches[@]} > 1 )); then
        RTIDE_TWEB_FAILURE=multiple
        printf 'tweb output error: multiple role=tweb panes in %s\n' "$session" >&2
        return 2
      elif [[ "$session" == rtide-* ]]; then
        RTIDE_TWEB_FAILURE=missing
        return 2
      fi
    fi
  fi

  RTIDE_TWEB_CACHE_KEY="${RTIDE_TWEB_SESSION}-${window:-work}"
  RTIDE_TWEB_CACHE_KEY=${RTIDE_TWEB_CACHE_KEY//[^a-zA-Z0-9_.-]/_}
  RTIDE_TWEB_LAST_RENDER="$HOME/.cache/rtide/$RTIDE_TWEB_CACHE_KEY/last-render"
  export RTIDE_TWEB_MODE RTIDE_TWEB_PANE RTIDE_TWEB_SESSION RTIDE_TWEB_CACHE_KEY RTIDE_TWEB_LAST_RENDER
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
    if [[ "${RTIDE_TWEB_FAILURE:-}" == missing ]] && RTIDE_WORKSPACE="$request_root" rtide_tweb_queue "$url" "$float"; then
      return 0
    fi
    return 2
  fi

  if [[ "$RTIDE_TWEB_MODE" == managed ]]; then
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
    return 0
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    if RTIDE_WORKSPACE="$request_root" rtide_tweb_queue "$url" "$float"; then
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
