#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
cleanup() {
  local rc=$?
  trap - EXIT
  find "$TEST_TMP" -depth -type f -delete 2>/dev/null || true
  find "$TEST_TMP" -depth -type l -delete 2>/dev/null || true
  find "$TEST_TMP" -depth -type d -empty -delete 2>/dev/null || true
  exit "$rc"
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

export HOME="$TEST_TMP/home"
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
export RTIDE_INSTALL_ROOT="$HOME/.local/lib/rtide"
export RTIDE_BIN_DIR="$HOME/.local/bin"
mkdir -p "$RTIDE_BIN_DIR" "$TEST_TMP/build" "$TEST_TMP/dist"

# The managed worktree root is visible and persistently configurable.
mkdir -p "$HOME/.rtide"
cat > "$HOME/.rtide/config" <<'EOF'
provider=
harness=
model=
default_dir=
agent_lines=3
tweb_pct=60
shell=bash
auto_float=false
worktree_root=
EOF
configured_root="$TEST_TMP/configured-worktrees"
bash "$ROOT/bin/rtide" config set "worktree_root=$configured_root" >/dev/null
grep -Fx "worktree_root=$configured_root" "$HOME/.rtide/config" >/dev/null \
  || fail 'config did not persist the managed worktree root'
grep -F "worktree_root $configured_root" <(bash "$ROOT/bin/rtide" config) >/dev/null \
  || fail 'config did not display the managed worktree root'

# Development dispatch uses source directly and isolated configuration.
dev_version=$(bash "$ROOT/scripts/rtide-dev" "$TEST_TMP/dev workspace" --version)
[[ "$dev_version" == "rtide $(tr -d '[:space:]' < "$ROOT/VERSION")" ]] || fail 'development runner did not use source'
grep -F 'RTIDE_ROOT/docs/assets/rtide-mark.png' "$ROOT/bin/rtide" >/dev/null \
  || fail 'source development asset fallback is missing'
grep -F 'export RTIDE_DEV_MODE=1' "$ROOT/scripts/rtide-dev" >/dev/null \
  || fail 'development launcher does not enable its visual identity'
startup_source=$(sed -n '/^# A detached `make dev` may be the first RTIDE command/,/^tmux set-option -w -t "\$S:work" @rtide-workspace/p' "$ROOT/bin/rtide")
new_session_line=$(grep -n '^tmux new-session -d ' <<< "$startup_source" | cut -d: -f1)
mouse_option_line=$(grep -n '^tmux set-option -g mouse on$' <<< "$startup_source" | cut -d: -f1)
(( new_session_line < mouse_option_line )) \
  || fail 'first-run launcher applies tmux options before creating its server'
grep -F 'DEV BUILD' "$ROOT/bin/rtide" >/dev/null \
  || fail 'development tmux badge is missing'
grep -F 'body class="{{DEV_CLASS}}"' "$ROOT/share/welcome.html" >/dev/null \
  || fail 'development welcome theme is missing'
grep -F '.rtide/agent-ready' "$ROOT/bin/rtide" >/dev/null \
  || fail 'workspace launcher lacks a stable agent readiness marker'
if grep -Fq "grep -Fq '● idle'" "$ROOT/bin/rtide"; then
  fail 'workspace launcher still waits for the obsolete idle label'
fi
fork_launch_source=$(sed -n '/^launch_fork_window()/,/^fork_root_from_context()/p' "$ROOT/bin/rtide")
for signal in 'ready_nvim' 'ready_tweb' 'ready_agent'; do
  grep -F "$signal" <<< "$fork_launch_source" >/dev/null \
    || fail "fork launcher does not wait for $signal"
done
last_select=$(grep -n 'tmux switch-client -c "$target_client" -t "$fork_window"' <<< "$fork_launch_source" | tail -1 | cut -d: -f1)
ready_check=$(grep -n 'launch incomplete' <<< "$fork_launch_source" | tail -1 | cut -d: -f1)
(( last_select > ready_check )) || fail 'invoking client is switched before readiness completes'
grep -F 'client=$(tmux display-message -p -t "$pane" '\''#{client_name}'\''' <<< "$(sed -n '/^cmd_fork_menu()/,/^cmd_fork_new_popup()/p' "$ROOT/bin/rtide")" >/dev/null \
  || fail 'Fork Manager does not capture its invoking tmux client'
grep -F 'tmux switch-client -c "$target_client" -t "$running"' <<< "$fork_launch_source" >/dev/null \
  || fail 'resume does not activate an already-running fork for the invoking client'
grep -F '"Fork Manager…"' "$ROOT/bin/rtide" >/dev/null \
  || fail 'actions menu does not expose the Fork Manager'
grep -F 'Escape' "$ROOT/bin/rtide" >/dev/null \
  || fail 'new fork prompt does not document Escape cancellation'
name_source=$(sed -n '/^cmd_fork_new_popup()/,/^cmd_fork()/p' "$ROOT/bin/rtide")
grep -F 'fzf --print-query' <<< "$name_source" >/dev/null \
  || fail 'new fork prompt does not use native cancellable input'
grep -F 'enter:accept-or-print-query' <<< "$name_source" >/dev/null \
  || fail 'new fork prompt cannot submit a typed name without a list match'
if grep -F 'read -r -e name' <<< "$name_source" >/dev/null; then
  fail 'new fork prompt still depends on inherited readline bindings'
fi
setup_source=$(sed -n '/^setup_wizard()/,/^cmd_doctor()/p' "$ROOT/bin/rtide")
grep -F 'cancellable_input' <<< "$setup_source" >/dev/null \
  || fail 'workspace setup does not use cancellable input'
grep -F 'setup cancelled' <<< "$setup_source" >/dev/null \
  || fail 'workspace setup does not stop cleanly on cancellation'
grep -F '＋ Create new fork' "$ROOT/bin/rtide" >/dev/null \
  || fail 'Fork Manager does not include fork creation'
if grep -F '"New fork…"' "$ROOT/bin/rtide" >/dev/null; then
  fail 'fork creation is duplicated outside the Fork Manager'
fi
manager_source=$(sed -n '/^cmd_fork_menu()/,/^cmd_fork_new_popup()/p' "$ROOT/bin/rtide")
if grep -F -- '--preview-window=right:' <<< "$manager_source" >/dev/null; then
  fail 'Fork Manager still uses a clipping side preview'
fi
for action in 'Create new fork' 'Resume or switch' 'View status' 'Stop runtime' 'Review memories' 'Repair runtime state' 'Move to managed storage' 'Finish and remove'; do
  grep -F "$action" <<< "$manager_source" >/dev/null \
    || fail "Fork Manager is missing lifecycle action: $action"
done
grep -F 'Permanent removal' <<< "$manager_source" >/dev/null \
  || fail 'Fork Manager removal does not confirm inside the interactive popup'
grep -F 'Yes — finish and remove worktree' <<< "$manager_source" >/dev/null \
  || fail 'Fork Manager removal lacks an explicit confirmation choice'
action_source=$(sed -n '/^cmd_fork_menu_action()/,/^dispatch_fork_menu_action()/p' "$ROOT/bin/rtide")
if grep -F 'read -r answer' <<< "$action_source" >/dev/null; then
  fail 'background Fork Manager action still attempts to read confirmation from stdin'
fi
grep -F 'dispatch_fork_menu_action' <<< "$manager_source" >/dev/null \
  || fail 'Fork Manager does not use its outside-popup action dispatcher'
grep -F 'dispatch_fork_menu_action create "$selected" "$pane" "$client"' <<< "$manager_source" >/dev/null \
  || fail 'Fork Manager creation still runs in the popup-owned process'
grep -F 'with-nth=1,3,4,6) || true' <<< "$manager_source" >/dev/null \
  || fail 'Fork Manager discards unmatched queries when fzf returns nonzero'
grep -F '[[ -n "$output" ]] || return 0' <<< "$manager_source" >/dev/null \
  || fail 'Fork Manager does not distinguish a printed query from cancellation'
dispatch_source=$(sed -n '/^dispatch_fork_menu_action()/,/^cmd_fork_menu()/p' "$ROOT/bin/rtide")
grep -F 'tmux run-shell -b "$command"' <<< "$dispatch_source" >/dev/null \
  || fail 'Fork Manager dispatcher is not owned by the tmux server'
grep -F 'fork-menu-action' <<< "$dispatch_source" >/dev/null \
  || fail 'Fork Manager dispatcher does not invoke the lifecycle action command'
grep -F 'tmux display-popup -C' <<< "$dispatch_source" >/dev/null \
  || fail 'Fork Manager actions do not close their popup after dispatch'
dispatch_line=$(grep -n 'tmux run-shell -b' <<< "$dispatch_source" | cut -d: -f1)
close_line=$(grep -n 'tmux display-popup -C' <<< "$dispatch_source" | cut -d: -f1)
(( dispatch_line < close_line )) || fail 'Fork Manager closes its popup before handing work to tmux'
grep -F '● running' <<< "$manager_source" >/dev/null \
  || fail 'Fork Manager does not show runtime state'
grep -F 'rtide_picker_decode "$output" create new' <<< "$manager_source" >/dev/null \
  || fail 'Fork Manager does not create an unknown search query'
workspace_picker=$(sed -n '/^cmd_pick()/,/^cmd_sweep()/p' "$ROOT/bin/rtide")
grep -F 'rtide_picker_decode "$out" create workspace' <<< "$workspace_picker" >/dev/null \
  || fail 'workspace picker does not share searchable-create behavior'
fork_source=$(sed -n '/^cmd_fork()/,/^install_session_hooks()/p' "$ROOT/bin/rtide")
grep -F 'validate_fork_snapshot "$root"' <<< "$fork_source" >/dev/null \
  || fail 'fork creation does not validate development snapshot completeness'
snapshot_source=$(sed -n '/^validate_fork_snapshot()/,/^}/p' "$ROOT/bin/rtide")
grep -F 'runtime dependency is untracked' <<< "$snapshot_source" >/dev/null \
  || fail 'fork snapshot validation does not identify untracked runtime dependencies'
launch_source=$(sed -n '/^launch_fork_window()/,/^fork_root_from_context()/p' "$ROOT/bin/rtide")
for diagnostic in 'fork-launch.json' 'fork-launch-nvim.log' 'fork-launch-tweb.log' 'fork-launch-agent.log'; do
  grep -F "$diagnostic" <<< "$launch_source" >/dev/null \
    || fail "fork launch diagnostics omit $diagnostic"
done
grep -F 'fork_launch_notice' <<< "$launch_source" >/dev/null \
  || fail 'fork readiness failures are not announced to the user'
pane_popup_source=$(sed -n '/^cmd_pane_popup()/,/^bind_if_free()/p' "$ROOT/bin/rtide")
grep -F 'request-restore "$client"' <<< "$pane_popup_source" >/dev/null \
  || fail 'RTIDE does not pass the nested popup client to targeted restore'
grep -F 'failed readiness' <<< "$launch_source" >/dev/null \
  || fail 'fork readiness status does not record the failed stage'
grep -F -- '--with-lazyvim' "$ROOT/install.sh" >/dev/null \
  || fail 'installer does not expose LazyVim bootstrap'
grep -F -- '--with-voice' "$ROOT/install.sh" >/dev/null \
  || fail 'installer does not expose voice bootstrap'
grep -F 'LazyVim config' "$ROOT/bin/rtide" >/dev/null \
  || fail 'doctor does not report LazyVim state'
grep -F 'speech engine not prepared' "$ROOT/bin/rtide" >/dev/null \
  || grep -F 'speech engine faster-whisper' "$ROOT/bin/rtide" >/dev/null \
  || fail 'doctor does not report voice state'
grep -F -- '--without-deps' "$ROOT/install.sh" >/dev/null \
  || fail 'installer does not expose dependency opt-out'
grep -F 'existing Neovim config preserved at' "$ROOT/scripts/install-lazyvim" >/dev/null \
  || fail 'LazyVim bootstrap does not preserve an existing Neovim config'
grep -F 'LazyVim already active' "$ROOT/scripts/install-lazyvim" >/dev/null \
  || fail 'LazyVim bootstrap does not recognize an existing LazyVim config'
grep -F 'https://github.com/keyolk/tweb.git' "$ROOT/scripts/install-tweb" >/dev/null \
  || fail 'TWeb source fallback URL is missing'
grep -F 'scripts/install-tweb' "$ROOT/install.sh" >/dev/null \
  || fail 'installer does not invoke the TWeb source fallback'
grep -F 'cargo' "$ROOT/scripts/install-deps" >/dev/null \
  || fail 'dependency installer does not provision Cargo for TWeb'
for package in atk-devel gtk3-devel webkit2gtk4.1-devel; do
  grep -F "$package" "$ROOT/scripts/install-deps" >/dev/null \
    || fail "dependency installer does not provision Fedora TWeb package: $package"
done

python3 "$ROOT/scripts/package-tool" build --root "$ROOT" \
  --build-dir "$TEST_TMP/build" --dist-dir "$TEST_TMP/dist" >/dev/null
BASE="$TEST_TMP/build/rtide-$(tr -d '[:space:]' < "$ROOT/VERSION")"
[[ -f "$BASE/share/assets/rtide-mark.png" ]] || fail 'release payload omitted the RTIDE logo'
[[ -x "$BASE/libexec/rtide/forks" && -x "$BASE/libexec/rtide/memory-index" ]] \
  || fail 'release payload omitted fork manager helpers'
[[ -x "$BASE/libexec/rtide/uninstall" ]] || fail 'release payload omitted uninstall helper'
[[ -x "$BASE/libexec/rtide/picker.sh" ]] || fail 'release payload omitted the shared picker helper'
[[ -x "$BASE/libexec/rtide/progress" ]] || fail 'release payload omitted implementation dashboard helper'
[[ -x "$BASE/libexec/rtide/pane-popup" ]] || fail 'release payload omitted pane popup helper'
[[ "$(find "$BASE/bin" -mindepth 1 -maxdepth 1 -printf '%f\n')" == rtide ]] \
  || fail 'release payload exposes commands other than rtide'
grep -F 'helper="$RTIDE_LIBEXEC_DIR/pane-popup"' "$BASE/bin/rtide" >/dev/null \
  || fail 'packaged RTIDE does not use its packaged pane popup helper'
grep -F 'src="assets/rtide-mark.png"' "$BASE/share/welcome.html" >/dev/null \
  || fail 'welcome screen does not use the packaged logo'

make_payload() {
  local version="$1" destination="$TEST_TMP/payload-$1"
  cp -a "$BASE" "$destination"
  printf '%s\n' "$version" > "$destination/VERSION"
  printf 'version=%s\nsource_revision=test\n' "$version" > "$destination/BUILD-INFO"
  python3 "$ROOT/scripts/package-tool" manifest "$destination"
  printf '%s\n' "$destination"
}

# Migrate an existing source link into a stable launcher and immutable release.
ln -s "$ROOT/bin/rtide" "$RTIDE_BIN_DIR/rtide"
ln -s "$RTIDE_INSTALL_ROOT/current/bin/rtide-open" "$RTIDE_BIN_DIR/rtide-open"
printf 'user owned\n' > "$RTIDE_BIN_DIR/tweb-run"
FIRST=$(make_payload 0.1.1)
bash "$ROOT/scripts/install-user" "$FIRST" >/dev/null
[[ -f "$HOME/.rtide/memory/.index-v2/index.json" ]] \
  || fail 'installation did not create the additive global memory index'
[[ ! -L "$RTIDE_BIN_DIR/rtide" && -x "$RTIDE_BIN_DIR/rtide" ]] || fail 'stable launcher was not installed'
[[ ! -e "$RTIDE_BIN_DIR/rtide-open" && ! -L "$RTIDE_BIN_DIR/rtide-open" ]] \
  || fail 'managed legacy helper symlink was not removed'
grep -Fx 'user owned' "$RTIDE_BIN_DIR/tweb-run" >/dev/null \
  || fail 'installer removed a user-owned legacy-named file'
[[ "$(readlink "$RTIDE_INSTALL_ROOT/current")" == versions/0.1.1 ]] || fail 'initial release was not activated'
[[ "$(rtide --version)" == 'rtide 0.1.1' ]] || fail 'installed version is incorrect'
grep -F "$RTIDE_INSTALL_ROOT/versions/0.1.1" <(rtide version --verbose) >/dev/null \
  || fail 'verbose version omitted the immutable root'

# A legacy metadata format may be repaired only when runtime contents match.
sed -i '/^content_digest=/d' "$RTIDE_INSTALL_ROOT/versions/0.1.1/BUILD-INFO"
bash "$ROOT/scripts/install-user" "$FIRST" >/dev/null
grep -q '^content_digest=' "$RTIDE_INSTALL_ROOT/versions/0.1.1/BUILD-INFO" \
  || fail 'legacy release metadata was not migrated'

# Reinstalling identical contents is idempotent.
bash "$ROOT/scripts/install-user" "$FIRST" >/dev/null

# Provenance may change after a source commit without changing runtime identity.
PROVENANCE="$TEST_TMP/provenance"
cp -a "$FIRST" "$PROVENANCE"
sed -i 's/^source_revision=.*/source_revision=committed-later/' "$PROVENANCE/BUILD-INFO"
python3 "$ROOT/scripts/package-tool" manifest "$PROVENANCE"
bash "$ROOT/scripts/install-user" "$PROVENANCE" >/dev/null

# Changed contents under the same version must fail without changing current.
COLLISION="$TEST_TMP/collision"
cp -a "$FIRST" "$COLLISION"
printf '\nchanged\n' >> "$COLLISION/share/AGENTS.md"
python3 "$ROOT/scripts/package-tool" manifest "$COLLISION"
if bash "$ROOT/scripts/install-user" "$COLLISION" >/dev/null 2>&1; then
  fail 'same-version content collision unexpectedly installed'
fi
[[ "$(readlink "$RTIDE_INSTALL_ROOT/current")" == versions/0.1.1 ]] || fail 'collision changed active release'

# Upgrades retain the active release plus two rollback candidates.
for version in 0.1.2 0.1.3 0.1.4; do
  payload=$(make_payload "$version")
  bash "$ROOT/scripts/install-user" "$payload" >/dev/null
done
[[ "$(readlink "$RTIDE_INSTALL_ROOT/current")" == versions/0.1.4 ]] || fail 'upgrade did not activate latest release'
[[ ! -e "$RTIDE_INSTALL_ROOT/versions/0.1.1" ]] || fail 'old release was not pruned'
[[ -d "$RTIDE_INSTALL_ROOT/versions/0.1.2" && -d "$RTIDE_INSTALL_ROOT/versions/0.1.3" ]] \
  || fail 'rollback releases were not retained'
grep -F '* 0.1.4' <(rtide versions) >/dev/null || fail 'versions did not mark active release'

rtide use 0.1.3 >/dev/null
[[ "$(rtide --version)" == 'rtide 0.1.3' ]] || fail 'rollback did not activate requested release'

# Package staging is contained entirely beneath DESTDIR and exposes only rtide.
STAGE="$TEST_TMP/stage"
DESTDIR="$STAGE" PREFIX=/usr bash "$ROOT/scripts/stage-package" "$FIRST" >/dev/null
[[ -x "$STAGE/usr/lib/rtide/bin/rtide" ]] || fail 'staged payload is missing rtide'
[[ "$(readlink "$STAGE/usr/bin/rtide")" == ../lib/rtide/bin/rtide ]] || fail 'staged command link is incorrect'
[[ "$(find "$STAGE/usr/bin" -mindepth 1 -maxdepth 1 -printf '%f\n')" == rtide ]] \
  || fail 'package staging exposed private helper commands'
HOME="$TEST_TMP/package-home" "$STAGE/usr/lib/rtide/bin/rtide" --version \
  | grep -Fx 'rtide 0.1.1' >/dev/null || fail 'staged payload is not relocatable'
[[ ! -e "$TEST_TMP/package-home" ]] || fail 'package staging modified user state'

# Exercise the public installed dispatch as well as the source helper.
printf 'keep me\n' > "$RTIDE_BIN_DIR/unrelated"
mkdir -p "$HOME/project/.rtide"
printf 'keep project\n' > "$HOME/project/.rtide/agent"
rtide uninstall --purge --yes >/dev/null
[[ ! -e "$RTIDE_INSTALL_ROOT" && ! -e "$RTIDE_BIN_DIR/rtide" ]] || fail 'public uninstall left managed state behind'
[[ -f "$RTIDE_BIN_DIR/unrelated" && -f "$HOME/project/.rtide/agent" ]] \
  || fail 'public uninstall removed unrelated or project state'

printf 'PASS: immutable install, collision safety, rollback, retention, and package staging\n'

# The installed command removes only RTIDE-managed state; user-owned files and
# project workspaces remain intact.  Use a separate HOME so this cannot affect
# the rest of the installation fixture.
UNINSTALL_HOME="$TEST_TMP/uninstall-home"
UNINSTALL_BIN="$UNINSTALL_HOME/.local/bin"
UNINSTALL_ROOT="$UNINSTALL_HOME/.local/lib/rtide"
mkdir -p "$UNINSTALL_BIN" "$UNINSTALL_ROOT/versions/0.2.33" "$UNINSTALL_HOME/.rtide/memory" "$UNINSTALL_HOME/project/.rtide"
cp "$ROOT/VERSION" "$UNINSTALL_ROOT/versions/0.2.33/VERSION"
ln -s versions/0.2.33 "$UNINSTALL_ROOT/current"
cp "$ROOT/scripts/rtide-launcher" "$UNINSTALL_BIN/rtide"
printf 'keep me\n' > "$UNINSTALL_BIN/other-file"
printf 'keep project\n' > "$UNINSTALL_HOME/project/.rtide/agent"
HOME="$UNINSTALL_HOME" RTIDE_INSTALL_ROOT="$UNINSTALL_ROOT" RTIDE_BIN_DIR="$UNINSTALL_BIN" \
  bash "$ROOT/libexec/rtide/uninstall" --purge --yes >/dev/null
[[ ! -e "$UNINSTALL_ROOT" && ! -e "$UNINSTALL_BIN/rtide" ]] || fail 'uninstall left managed RTIDE state behind'
[[ -f "$UNINSTALL_BIN/other-file" ]] || fail 'uninstall removed an unrelated bin file'
[[ -f "$UNINSTALL_HOME/project/.rtide/agent" ]] || fail 'uninstall removed project workspace state'

printf 'PASS: uninstall preserves unrelated files and project state\n'
