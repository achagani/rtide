#!/usr/bin/env bash
# Shared semantic presentation primitives for RTIDE's tmux and fzf surfaces.

RTIDE_UI_BG='#0b1013'
RTIDE_UI_SURFACE='#11191d'
RTIDE_UI_SURFACE_ACTIVE='#19262b'
RTIDE_UI_TEXT='#e6eee9'
RTIDE_UI_MUTED='#8b9b92'
RTIDE_UI_BORDER='#314039'
RTIDE_UI_FOCUS='#70cbd1'
RTIDE_UI_WORKING='#e1b866'
RTIDE_UI_ATTENTION='#c7a6e8'
RTIDE_UI_SUCCESS='#78d69b'
RTIDE_UI_WARNING='#e1b866'
RTIDE_UI_ERROR='#ed7b72'
RTIDE_TMUX_MENU_STYLE="bg=${RTIDE_UI_SURFACE},fg=${RTIDE_UI_TEXT}"
RTIDE_TMUX_MENU_BORDER="bg=${RTIDE_UI_BG},fg=${RTIDE_UI_BORDER}"
RTIDE_TMUX_MENU_ACTIVE="bg=${RTIDE_UI_SURFACE_ACTIVE},fg=${RTIDE_UI_FOCUS},bold"

rtide_ui_plain() {
  [[ -n "${NO_COLOR:-}" || "${RTIDE_NO_COLOR:-0}" == 1 || "${TERM:-}" == dumb ]]
}

rtide_ui_symbol() {
  local state="$1"
  if [[ "${RTIDE_ASCII:-0}" == 1 || "${LC_ALL:-${LANG:-}}" != *UTF-8* ]]; then
    case "$state" in
      ready|success) printf '[ok]' ;;
      working) printf '[..]' ;;
      input-needed|attention|warning) printf '[!]' ;;
      error) printf '[x]' ;;
      *) printf '[-]' ;;
    esac
  else
    case "$state" in
      ready|success) printf '●' ;;
      working) printf '◐' ;;
      input-needed|attention|warning) printf '!' ;;
      error) printf '×' ;;
      *) printf '○' ;;
    esac
  fi
}

rtide_ui_state_label() {
  case "$1" in
    ready) printf '%s ready' "$(rtide_ui_symbol ready)" ;;
    working) printf '%s working' "$(rtide_ui_symbol working)" ;;
    input-needed|attention) printf '%s input needed' "$(rtide_ui_symbol input-needed)" ;;
    success) printf '%s done' "$(rtide_ui_symbol success)" ;;
    warning) printf '%s warning' "$(rtide_ui_symbol warning)" ;;
    error) printf '%s error' "$(rtide_ui_symbol error)" ;;
    *) printf '%s %s' "$(rtide_ui_symbol muted)" "$1" ;;
  esac
}

# Set RTIDE_PICKER_ARGS for one consistent picker grammar. Callers can append
# data-specific delimiter, preview, sorting, and selection-policy arguments.
rtide_picker_options() {
  local policy="${1:-select}" density="${2:-full}" height=60
  [[ "$density" == compact ]] && height=40
  RTIDE_PICKER_ARGS=(
    --layout=reverse --border=sharp --height="${height}%" --no-separator
    --pointer='›' --marker='●' --prompt='› ' --info=inline-right
    --header="$(rtide_picker_header "$policy")"
  )
  # This function is called under `set -e`; a trailing `rtide_ui_plain && …`
  # would return 1 whenever color is enabled and abort the caller. In plain
  # mode omit the authored palette entirely rather than passing both
  # --color and --no-color.
  if rtide_ui_plain; then
    RTIDE_PICKER_ARGS+=(--no-color)
  else
    RTIDE_PICKER_ARGS+=(
      --color="bg:${RTIDE_UI_BG},bg+:${RTIDE_UI_SURFACE_ACTIVE},fg:${RTIDE_UI_TEXT},fg+:${RTIDE_UI_TEXT},hl:${RTIDE_UI_FOCUS},hl+:${RTIDE_UI_FOCUS},border:${RTIDE_UI_BORDER},prompt:${RTIDE_UI_FOCUS},pointer:${RTIDE_UI_FOCUS},marker:${RTIDE_UI_SUCCESS},header:${RTIDE_UI_MUTED},info:${RTIDE_UI_MUTED}"
    )
  fi
  return 0
}

rtide_tmux_chrome() {
  local session="$1" window="$2" dev="${3:-0}" version="${4:-}" label="${5:-DEVELOPMENT}"
  local state ready_style left right border active title
  state=$(rtide_ui_state_label ready)
  # Border labels name the pane's role. Never use #{pane_title}: RTIDE starts
  # each pane with its launch command, so the title leaks a raw command line.
  # @rtide-label overrides the role mapping when set.
  local label_expr
  label_expr='#{?#{==:#{@rtide-label},},#{?#{==:#{@rtide-role},nvim},editor,#{?#{==:#{@rtide-role},agent},composer,#{?#{==:#{@rtide-role},tweb},output,terminal}}},#{@rtide-label}}'
  if rtide_ui_plain; then
    ready_style='default'
    left=' RTIDE  #S:#W '
    right=" #{@rtide-state}  #{@rtide-layout-mode}  output:live ${version:+ v$version }"
    border='default'; active='bold'; title=" ${label_expr} "
  else
    ready_style="bg=${RTIDE_UI_BG},fg=${RTIDE_UI_TEXT}"
    left="#[bg=${RTIDE_UI_FOCUS},fg=${RTIDE_UI_BG},bold] RTIDE #[bg=${RTIDE_UI_BG},fg=${RTIDE_UI_TEXT}] #S:#W "
    right="#[fg=${RTIDE_UI_MUTED}] #{@rtide-state}  mode:#{@rtide-layout-mode}  output:live ${version:+ v$version }"
    border="fg=${RTIDE_UI_BORDER}"
    active="fg=${RTIDE_UI_FOCUS},bold"
    title="#[fg=${RTIDE_UI_MUTED}] ${label_expr} "
  fi
  if [[ "$dev" == 1 ]]; then
    left="#[bg=${RTIDE_UI_WARNING},fg=${RTIDE_UI_BG},bold] DEV #[bg=${RTIDE_UI_BG},fg=${RTIDE_UI_TEXT}] #S:#W "
    right="#[fg=${RTIDE_UI_WARNING}] ${label}  #{@rtide-state}  mode:#{@rtide-layout-mode} ${version:+ v$version }"
  fi
  tmux set-option -t "$session" status on
  tmux set-option -t "$session" status-position top
  tmux set-option -t "$session" status-interval 1
  tmux set-option -t "$session" status-style "$ready_style"
  tmux set-option -t "$session" status-left-length 80
  tmux set-option -t "$session" status-right-length 100
  tmux set-option -t "$session" status-left "$left"
  tmux set-option -t "$session" status-right "$right"
  tmux set-option -w -t "$window" @rtide-state "$state"
  tmux set-option -w -t "$window" @rtide-layout-request auto
  tmux set-option -w -t "$window" @rtide-layout-mode auto
  tmux set-option -w -t "$window" pane-border-status top
  tmux set-option -w -t "$window" pane-border-style "$border"
  tmux set-option -w -t "$window" pane-active-border-style "$active"
  tmux set-option -w -t "$window" pane-border-format "$title"
}

# Print: effective-mode, agent-height, nvim-width, tweb-width. Width 1 means
# collapsed but alive; pane identity and process state are never replaced.
rtide_layout_geometry() {
  local width="$1" height="$2" tweb_pct="$3" agent_lines="$4" requested="${5:-auto}"
  local mode="$requested" top_height agent_h tweb_w nvim_w
  if [[ "$mode" == auto ]]; then
    (( width >= 110 )) && mode=balanced || mode=output
  fi
  agent_h="$agent_lines"
  if [[ "$mode" == compose ]]; then
    agent_h=$(( height * 40 / 100 ))
    (( agent_h < 6 )) && agent_h=6
    (( agent_h > 16 )) && agent_h=16
  fi
  top_height=$(( height - agent_h - 1 ))
  (( top_height < 2 )) && agent_h=$(( height > 4 ? height - 3 : 1 ))
  case "$mode" in
    output) nvim_w=1; tweb_w=$(( width - 1 )) ;;
    edit) nvim_w=$(( width - 1 )); tweb_w=1 ;;
    balanced|compose)
      tweb_w=$(( width * tweb_pct / 100 ))
      (( tweb_w < 20 )) && tweb_w=20
      (( tweb_w > width - 20 )) && tweb_w=$(( width - 20 ))
      nvim_w=$(( width - tweb_w ))
      ;;
    *) return 2 ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$mode" "$agent_h" "$nvim_w" "$tweb_w"
}
