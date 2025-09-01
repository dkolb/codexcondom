#!/usr/bin/env bash
set -euo pipefail

# Install codexcondom to the invoking user's home. If run as root,
# install to root's home (/root). Global installs are not supported.

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$SCRIPT_DIR"

# Determine install home (respect root explicitly)
if [ "$(id -u)" = "0" ]; then
  INSTALL_HOME="/root"
else
  INSTALL_HOME="${HOME}"
fi

# Source locations (local repo) and remote fallback
SRC_CLI_LOCAL="$REPO_ROOT/bin/codexcondom"
SRC_IMG_LOCAL="$REPO_ROOT/images/codex.Containerfile"

# Remote base (override with CODEX_CONDOM_REF=<branch|tag|sha>)
REPO_SLUG="dkolb/codex-condom"
REPO_REF="${CODEX_CONDOM_REF:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPO_SLUG}/${REPO_REF}"

TARGET_BIN_DIR="$INSTALL_HOME/.local/bin"
DATA_HOME="${XDG_DATA_HOME:-$INSTALL_HOME/.local/share}"
IMG_DST_DIR="$DATA_HOME/codexcondoms/images"
UPDATED_FILES=()

fetch_to_temp() {
  local src_path="$1" # path relative to repo root for remote
  local out
  out=$(mktemp)
  curl -fsSL "${RAW_BASE}/${src_path}" -o "$out"
  echo "$out"
}

install_cli() {
  mkdir -p "$TARGET_BIN_DIR"
  local tmp
  if [[ -f "$SRC_CLI_LOCAL" ]]; then
    install -m 0755 "$SRC_CLI_LOCAL" "$TARGET_BIN_DIR/codexcondom"
  else
    tmp=$(fetch_to_temp "bin/codexcondom")
    install -m 0755 "$tmp" "$TARGET_BIN_DIR/codexcondom"
    rm -f "$tmp" || true
  fi
  info "Installed CLI to $TARGET_BIN_DIR/codexcondom"
}

install_resources() {
  mkdir -p "$IMG_DST_DIR"
  local tmp
  if [[ -f "$SRC_IMG_LOCAL" ]]; then
    install -m 0644 "$SRC_IMG_LOCAL" "$IMG_DST_DIR/codex.Containerfile"
  else
    tmp=$(fetch_to_temp "images/codex.Containerfile")
    install -m 0644 "$tmp" "$IMG_DST_DIR/codex.Containerfile"
    rm -f "$tmp" || true
  fi
  info "Installed image Containerfile to $IMG_DST_DIR"
}

is_in_path() {
  case ":$PATH:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
}

append_if_missing() {
  local file="$1"; shift
  local line="$*"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -Fq "$line" "$file" 2>/dev/null; then
    printf "\n# Codex Condoms\n%s\n" "$line" >> "$file"
    info "Updated $file"
    UPDATED_FILES+=("$file")
  fi
}

detect_current_shell() {
  local s
  s=$(basename -- "$0")
  s=${s#-}
  case "$s" in
    bash|sh|zsh|fish) echo "$s" ;;
    *) echo sh ;;
  esac
}

setup_shell() {
  local shell_name="$1"   # bash|sh|zsh|fish
  local add_path="$2"     # 1/0
  local lb="$TARGET_BIN_DIR"

  case "$shell_name" in
    sh)
      [[ "$add_path" == "1" ]] && append_if_missing "$INSTALL_HOME/.profile" "export PATH=\"$lb:\$PATH\""
      ;;
    bash)
      [[ "$add_path" == "1" ]] && append_if_missing "$INSTALL_HOME/.bashrc" "export PATH=\"$lb:\$PATH\""
      ;;
    zsh)
      [[ "$add_path" == "1" ]] && append_if_missing "$INSTALL_HOME/.zshrc" "export PATH=\"$lb:\$PATH\""
      ;;
    fish)
      local fish_cfg="$INSTALL_HOME/.config/fish/config.fish"
      mkdir -p "$(dirname "$fish_cfg")"
      if [[ "$add_path" == "1" ]] && ! grep -Fq "set -gx PATH $lb" "$fish_cfg" 2>/dev/null; then
        printf "\n# Codex Condoms\nif not contains %s \$PATH\n  set -gx PATH %s \$PATH\nend\n" "$lb" "$lb" >> "$fish_cfg"
        info "Updated $fish_cfg (PATH)"
        UPDATED_FILES+=("$fish_cfg")
      fi
      ;;
  esac
}

main() {
  install_cli
  install_resources

  local add_path=0
  CUR_SHELL=$(detect_current_shell)

  if ! is_in_path "$TARGET_BIN_DIR"; then
    if [[ -t 0 ]]; then
      echo ""
      read -r -p "Add $TARGET_BIN_DIR to PATH in your $CUR_SHELL config? [Y/n] " ans
      ans=${ans:-Y}
      case "$ans" in
        [Yy]*) add_path=1 ;;
        *) add_path=0 ;;
      esac
    else
      # Non-interactive: warn but do not modify PATH
      warn "$TARGET_BIN_DIR is not in PATH. Add it to use codexcondom."
    fi
  else
    add_path=0
  fi

  if [[ "$add_path" == "1" ]]; then
    setup_shell "$CUR_SHELL" "$add_path"
    echo ""
    info "Shell config updated. Restart your shell or 'source' the rc file."
    if (( ${#UPDATED_FILES[@]} > 0 )); then
      # Print a unique list
      declare -A _seen=()
      echo "Updated shell config files:"
      for f in "${UPDATED_FILES[@]}"; do
        if [[ -z "${_seen[$f]:-}" ]]; then
          echo "  $f"
          _seen[$f]=1
        fi
      done
    fi
  fi

  echo ""
  info "Try: codexcondom --help"
}

main "$@"
