#!/usr/bin/env bash
# Bootstrap or update the RTIDE source checkout, then install an immutable release.
set -euo pipefail

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
if command -v rtide-mcp >/dev/null 2>&1; then
  rtide-mcp
fi
if [[ ! -f "$HOME/.claude/CLAUDE.md" ]]; then
  mkdir -p "$HOME/.claude"
  cp "$REPO_DIR/share/AGENTS.md" "$HOME/.claude/CLAUDE.md"
fi

echo
rtide --version
echo "Installed. Run: rtide"
