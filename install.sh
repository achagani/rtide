#!/usr/bin/env bash
# Bootstrap or update the RTIDE source checkout, then install an immutable release.
set -euo pipefail

WITH_DEPS=0
WITH_LAZYVIM=0
WITH_VOICE=0
for arg in "$@"; do
  case "$arg" in
    --with-deps) WITH_DEPS=1 ;;
    --with-lazyvim) WITH_LAZYVIM=1 ;;
    --with-voice) WITH_VOICE=1 ;;
    -h|--help)
      printf 'Usage: install.sh [--with-deps] [--with-lazyvim] [--with-voice]\n\n'
      printf '%s\n' 'Installs RTIDE. --with-deps installs supported host packages; --with-lazyvim bootstraps LazyVim only when ~/.config/nvim is absent; --with-voice prewarms the local speech environment.'
      exit 0
      ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

REPO_DIR="${RTIDE_SOURCE_DIR:-$HOME/rtide}"
RUNTIME_DIR="$HOME/.rtide"

echo "==> RTIDE bootstrap"

if [[ -d "$HOME/.rtide/bin" && ! -d "$REPO_DIR" ]]; then
  echo "   migrating legacy source to $REPO_DIR"
  mkdir -p "$REPO_DIR"
  for file in bin share scripts install.sh README.md Makefile VERSION .gitignore; do
    [[ -e "$HOME/.rtide/$file" ]] && mv "$HOME/.rtide/$file" "$REPO_DIR/"
  done
fi

if [[ -f "$HOME/.config/rtide/config" && ! -f "$RUNTIME_DIR/config" ]]; then
  mkdir -p "$RUNTIME_DIR"
  mv "$HOME/.config/rtide/config" "$RUNTIME_DIR/config"
fi

source_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)
if [[ -d "$REPO_DIR/.git" ]]; then
  if [[ "${RTIDE_INSTALL_SKIP_UPDATE:-0}" == 1 ]]; then
    echo "   using local source checkout"
  else
    echo "   updating source checkout"
    git -C "$REPO_DIR" pull --ff-only
  fi
elif [[ -n "$source_dir" && -d "$source_dir/bin" && -f "$source_dir/VERSION" ]]; then
  REPO_DIR="$source_dir"
  echo "   using source at $REPO_DIR"
else
  git clone https://github.com/achagani/rtide "$REPO_DIR"
fi

if (( WITH_DEPS )); then
  "$REPO_DIR/scripts/install-deps"
fi
if (( WITH_LAZYVIM )); then
  "$REPO_DIR/scripts/install-lazyvim"
fi
if (( WITH_VOICE )); then
  "$REPO_DIR/scripts/install-voice"
fi

make -C "$REPO_DIR" install

mkdir -p "$RUNTIME_DIR/memory"
if [[ ! -f "$RUNTIME_DIR/config" ]]; then
  echo "   first launch will run setup"
fi

BIN_DIR="$HOME/.local/bin"
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) echo "   WARN: add $BIN_DIR to PATH" ;;
esac
if command -v fish >/dev/null 2>&1; then
  fish -c "fish_add_path $BIN_DIR" 2>/dev/null || true
fi

# Direct bootstrap installs may configure per-user integrations. Package-manager
# staging never runs this script and remains side-effect free.
if command -v rtide >/dev/null 2>&1; then
  rtide mcp install
fi
if [[ ! -f "$HOME/.claude/CLAUDE.md" ]]; then
  mkdir -p "$HOME/.claude"
  cp "$REPO_DIR/share/AGENTS.md" "$HOME/.claude/CLAUDE.md"
fi

echo
rtide --version
if (( WITH_DEPS || WITH_LAZYVIM || WITH_VOICE )); then
  echo
  echo 'Dependency check:'
  rtide doctor || true
fi
echo "Installed. Run: rtide"
