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

# Development dispatch uses source directly and isolated configuration.
dev_version=$(bash "$ROOT/scripts/rtide-dev" "$TEST_TMP/dev workspace" --version)
[[ "$dev_version" == "rtide $(tr -d '[:space:]' < "$ROOT/VERSION")" ]] || fail 'development runner did not use source'
grep -F 'RTIDE_ROOT/docs/assets/rtide-mark.png' "$ROOT/bin/rtide" >/dev/null \
  || fail 'source development asset fallback is missing'
grep -F 'export RTIDE_DEV_MODE=1' "$ROOT/scripts/rtide-dev" >/dev/null \
  || fail 'development launcher does not enable its visual identity'
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
last_select=$(grep -n 'tmux select-window -t "$fork_window"' <<< "$fork_launch_source" | tail -1 | cut -d: -f1)
ready_check=$(grep -n 'launch incomplete' <<< "$fork_launch_source" | tail -1 | cut -d: -f1)
(( last_select > ready_check )) || fail 'fork window is selected before readiness completes'
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
for action in 'Create new fork' 'Resume or switch' 'View status' 'Stop runtime' 'Review memories' 'Repair runtime state' 'Finish and remove'; do
  grep -F "$action" <<< "$manager_source" >/dev/null \
    || fail "Fork Manager is missing lifecycle action: $action"
done
grep -F 'dispatch_fork_menu_action' <<< "$manager_source" >/dev/null \
  || fail 'Fork Manager does not use its outside-popup action dispatcher'
grep -F 'dispatch_fork_menu_action create "$selected" "$pane"' <<< "$manager_source" >/dev/null \
  || fail 'Fork Manager creation still runs in the popup-owned process'
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
grep -F 'failed readiness' <<< "$launch_source" >/dev/null \
  || fail 'fork readiness status does not record the failed stage'

python3 "$ROOT/scripts/package-tool" build --root "$ROOT" \
  --build-dir "$TEST_TMP/build" --dist-dir "$TEST_TMP/dist" >/dev/null
BASE="$TEST_TMP/build/rtide-$(tr -d '[:space:]' < "$ROOT/VERSION")"
[[ -f "$BASE/share/assets/rtide-mark.png" ]] || fail 'release payload omitted the RTIDE logo'
[[ -x "$BASE/bin/rtide-forks" && -x "$BASE/bin/rtide-memory-index" ]] \
  || fail 'release payload omitted fork manager helpers'
[[ -x "$BASE/bin/rtide-picker" ]] || fail 'release payload omitted the shared picker helper'
[[ -x "$BASE/bin/rtide-progress" ]] || fail 'release payload omitted implementation dashboard helper'
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
FIRST=$(make_payload 0.1.1)
bash "$ROOT/scripts/install-user" "$FIRST" >/dev/null
[[ -f "$HOME/.rtide/memory/.index-v2/index.json" ]] \
  || fail 'installation did not create the additive global memory index'
[[ ! -L "$RTIDE_BIN_DIR/rtide" && -x "$RTIDE_BIN_DIR/rtide" ]] || fail 'stable launcher was not installed'
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

# Package staging is contained entirely beneath DESTDIR and uses flat links.
STAGE="$TEST_TMP/stage"
DESTDIR="$STAGE" PREFIX=/usr bash "$ROOT/scripts/stage-package" "$FIRST" >/dev/null
[[ -x "$STAGE/usr/lib/rtide/bin/rtide" ]] || fail 'staged payload is missing rtide'
[[ "$(readlink "$STAGE/usr/bin/rtide")" == ../lib/rtide/bin/rtide ]] || fail 'staged command link is incorrect'
HOME="$TEST_TMP/package-home" "$STAGE/usr/lib/rtide/bin/rtide" --version \
  | grep -Fx 'rtide 0.1.1' >/dev/null || fail 'staged payload is not relocatable'
[[ ! -e "$TEST_TMP/package-home" ]] || fail 'package staging modified user state'

printf 'PASS: immutable install, collision safety, rollback, retention, and package staging\n'
