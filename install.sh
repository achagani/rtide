#!/usr/bin/env bash
# install.sh — one-click RTIDE installer. Idempotent: safe to re-run.
#   curl -fsSL https://raw.githubusercontent.com/achagani/rtide/main/install.sh | bash
#   # or, without hosting:
#   git clone https://github.com/achagani/rtide ~/rtide && ~/rtide/install.sh
set -euo pipefail

REPO_DIR="$HOME/rtide"        # source (git repo)
RUNTIME_DIR="$HOME/.rtide"    # runtime config + data (created here)
BIN_DIR="$HOME/.local/bin"

echo "==> RTIDE install"

# 0. One-time migration from the old layout (source used to live in ~/.rtide).
#    Source → ~/rtide; runtime (config + memory) stays in ~/.rtide.
if [[ -d "$HOME/.rtide/bin" && ! -d "$REPO_DIR" ]]; then
  echo "   migrating source from ~/.rtide to ~/rtide"
  mkdir -p "$REPO_DIR"
  for f in bin share install.sh README.md .gitignore; do
    [[ -e "$HOME/.rtide/$f" ]] && mv "$HOME/.rtide/$f" "$REPO_DIR/"
  done
fi
# Legacy config location (~/.config/rtide/config) → ~/.rtide/config
if [[ -f "$HOME/.config/rtide/config" && ! -f "$RUNTIME_DIR/config" ]]; then
  echo "   migrating config from ~/.config/rtide to ~/.rtide"
  mkdir -p "$RUNTIME_DIR"
  mv "$HOME/.config/rtide/config" "$RUNTIME_DIR/config"
fi

# 1. Clone (or pull if re-running)
if [[ -d "$REPO_DIR/.git" ]]; then
  echo "   repo exists — pulling"
  git -C "$REPO_DIR" pull --ff-only >/dev/null 2>&1 || echo "   (pull failed — continuing with existing files)"
else
  mkdir -p "$REPO_DIR"
  src="$(cd "$(dirname "$0")" && pwd)"
  if command -v git >/dev/null 2>&1; then
    git clone https://github.com/achagani/rtide "$REPO_DIR" 2>/dev/null \
      || { echo "   clone failed — copying local files"; \
           [[ "$src" != "$REPO_DIR" && -d "$src/bin" ]] && cp -r "$src/." "$REPO_DIR/"; }
  else
    echo "   git missing — copying local files"
    [[ "$src" != "$REPO_DIR" && -d "$src/bin" ]] && cp -r "$src/." "$REPO_DIR/"
  fi
fi

# 2. Runtime dir: config + memory (memory never moves)
mkdir -p "$RUNTIME_DIR/memory"
if [[ ! -f "$RUNTIME_DIR/config" ]]; then
  echo "   no config yet — first 'rtide' run will walk through setup"
  : > "$RUNTIME_DIR/config"
fi

# 3. Symlink helpers into ~/.local/bin
mkdir -p "$BIN_DIR"
for b in rtide rtide-provider rtide-mcp rtide-mem rtide-agent rtide-dictate rtide-open tweb-render tweb-run; do
  ln -sf "$REPO_DIR/bin/$b" "$BIN_DIR/$b"
  echo "   linked $b"
done

# 4. PATH wiring: ~/.local/bin must be on PATH for bash, zsh, and fish
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) echo "   WARN: $BIN_DIR is not on PATH — add it to your shell rc" ;;
esac
if command -v fish >/dev/null 2>&1; then
  fish -c "fish_add_path $BIN_DIR" 2>/dev/null && echo "   fish: added $BIN_DIR to fish_user_paths"
fi

# 5. User-level Claude convention (never clobbers)
if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
  echo "   ~/.claude/CLAUDE.md exists — leaving as-is"
else
  mkdir -p "$HOME/.claude"
  cp "$REPO_DIR/share/AGENTS.md" "$HOME/.claude/CLAUDE.md"
  echo "   installed ~/.claude/CLAUDE.md"
fi

# 6. Wire MCP servers into whatever harnesses are present
if command -v rtide-mcp >/dev/null 2>&1; then
  rtide-mcp
fi

# 7. tweb doctor --fix if tweb is present
if command -v tweb >/dev/null 2>&1; then
  tweb doctor --fix >/dev/null 2>&1 || true
fi

echo
echo "==> RTIDE installed. Verifying:"
rtide doctor || true
echo
echo "First run:  rtide            (walks through setup, then launches)"
echo "Help:       rtide doctor | rtide ls | rtide new | rtide switch | rtide agent | rtide auth"
