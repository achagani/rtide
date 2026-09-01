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

python3 "$ROOT/scripts/package-tool" build --root "$ROOT" \
  --build-dir "$TEST_TMP/build" --dist-dir "$TEST_TMP/dist" >/dev/null
BASE="$TEST_TMP/build/rtide-$(tr -d '[:space:]' < "$ROOT/VERSION")"
[[ -f "$BASE/share/assets/rtide-mark.png" ]] || fail 'release payload omitted the RTIDE logo'
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
