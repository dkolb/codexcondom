#!/usr/bin/env bash
set -euo pipefail

# Uninstall Codex Condoms (current version)
#
# Removes the user-local CLI and data installed by install.sh. Optional flags
# allow pruning per-workspace homes and Podman artifacts. Shell config cleanup
# is opt-in and conservative.
#
# Default actions:
# - Remove ~/.local/bin/codexcondom (also cleans up legacy codexcondomctl)
# - Remove ~/.local/share/codexcondoms/{images,in-container}
#
# Optional:
#   --prune-homes        Remove ~/codex_condoms/* (per-workspace homes)
#   --remove-image       Remove cached podman image: localhost/codex:latest
#   --remove-containers  Remove containers named like codex-condom-*
#   --purge-path         Try to remove PATH lines previously added by install.sh
#   --yes                Do not prompt for confirmation on optional removals
#   -h, --help           Show help

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }

usage() {
  cat <<USAGE
Uninstall Codex Condoms (user-local)

Usage: ./uninstall.sh [options]

Removes the CLI and resources installed by ./install.sh from this repository.

Options:
  --prune-homes        Remove ~/codex_condoms/* (per-workspace homes)
  --remove-image       Remove cached podman image: localhost/codex:latest
  --remove-containers  Remove containers named codex-condom-*
  --purge-path         Remove PATH entries added to shell configs (best-effort)
  --yes                Assume 'yes' for optional removals (non-interactive)
  -h, --help           Show this help
USAGE
}

YES=0
PRUNE_HOMES=0
REMOVE_IMAGE=0
REMOVE_CONTAINERS=0
PURGE_PATH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prune-homes) PRUNE_HOMES=1; shift ;;
    --remove-image) REMOVE_IMAGE=1; shift ;;
    --remove-containers) REMOVE_CONTAINERS=1; shift ;;
    --purge-path) PURGE_PATH=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# Determine install home (respect root explicitly)
if [ "$(id -u)" = "0" ]; then
  INSTALL_HOME="/root"
else
  INSTALL_HOME="${HOME}"
fi

TARGET_BIN_DIR="$INSTALL_HOME/.local/bin"
DATA_HOME="${XDG_DATA_HOME:-$INSTALL_HOME/.local/share}"
BASE_DATA_DIR="$DATA_HOME/codexcondoms"
RES_DST_DIR="$BASE_DATA_DIR/in-container"
IMG_DST_DIR="$BASE_DATA_DIR/images"
WS_HOMES_DIR="$INSTALL_HOME/codex_condoms"
RUNTIME_IMAGE_TAG="localhost/codex:latest"

# Escape path for sed
escape_sed() { printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }

# Prompt helper
confirm() {
  local prompt="$1"
  if [[ $YES -eq 1 ]]; then return 0; fi
  if [[ -t 0 ]]; then
    read -r -p "$prompt [y/N] " ans || return 1
    case "${ans}" in
      [Yy]*) return 0 ;; * ) return 1 ;;
    esac
  else
    return 1
  fi
}

remove_file() {
  local f="$1"
  if [[ -e "$f" ]]; then
    rm -f -- "$f"
    info "Removed $f"
  fi
}

remove_dir() {
  local d="$1"
  if [[ -d "$d" ]]; then
    rm -rf -- "$d"
    info "Removed $d"
  fi
}

purge_shell_paths() {
  local bin_dir="$TARGET_BIN_DIR"
  local esc_bin_dir="$(escape_sed "$bin_dir")"

  # sh/bash/zsh profiles: remove exact lines appended by install.sh
  for f in "$INSTALL_HOME/.profile" "$INSTALL_HOME/.bashrc" "$INSTALL_HOME/.zshrc"; do
    [[ -f "$f" ]] || continue
    cp -f "$f" "$f.bak.codexcondoms" || true
    # Drop marker line and the exact export PATH line containing our bin dir
    sed -i \
      -e "/^# Codex Condoms$/d" \
      -e "/^export PATH=\"${esc_bin_dir}:\$PATH\"$/d" \
      "$f" || true
    info "Updated $f (backup at $f.bak.codexcondoms)"
  done

  # fish: remove exact 4-line block if present
  local fish_cfg="$INSTALL_HOME/.config/fish/config.fish"
  if [[ -f "$fish_cfg" ]]; then
    cp -f "$fish_cfg" "$fish_cfg.bak.codexcondoms" || true
    awk -v BINDIR="$bin_dir" '
      BEGIN {skip=0}
      function flush_block(){skip=0}
      {
        if (skip==0 && $0=="# Codex Condoms") {
          getline l2; getline l3; getline l4;
          if (l2 ~ /^if not contains/ && index(l2, BINDIR) && \
              l3 ~ /^  set -gx PATH/ && index(l3, BINDIR) && \
              l4 == "end") {
            # matched block, skip all four lines
            next
          } else {
            # no match; print current and previously read lines
            print $0; print l2; print l3; print l4; next
          }
        }
        print $0
      }
    ' "$fish_cfg" > "$fish_cfg.tmp.codexcondoms" && mv "$fish_cfg.tmp.codexcondoms" "$fish_cfg" || true
    info "Updated $fish_cfg (backup at $fish_cfg.bak.codexcondoms)"
  fi
}

# 1) Remove CLI binary (new and legacy)
remove_file "$TARGET_BIN_DIR/codexcondom"
remove_file "$TARGET_BIN_DIR/codexcondomctl"

# 2) Remove installed resources
remove_dir "$RES_DST_DIR"
remove_dir "$IMG_DST_DIR"

# If base dir is now empty, remove it
if [[ -d "$BASE_DATA_DIR" ]] && [[ -z "$(ls -A "$BASE_DATA_DIR" 2>/dev/null || true)" ]]; then
  remove_dir "$BASE_DATA_DIR"
fi

# 3) Optional: purge PATH markers
if [[ $PURGE_PATH -eq 1 ]]; then
  purge_shell_paths
fi

# 4) Optional: remove per-workspace homes
if [[ $PRUNE_HOMES -eq 1 ]]; then
  if [[ -d "$WS_HOMES_DIR" ]]; then
    if confirm "Remove all per-workspace homes under $WS_HOMES_DIR?"; then
      remove_dir "$WS_HOMES_DIR"
    else
      warn "Skipped removing $WS_HOMES_DIR"
    fi
  fi
fi

# 5) Optional: remove podman containers and image
has_podman=0
if command -v podman >/dev/null 2>&1; then has_podman=1; fi

if [[ $REMOVE_CONTAINERS -eq 1 ]]; then
  if [[ $has_podman -eq 1 ]]; then
    mapfile -t to_rm < <(podman ps -a --format '{{.Names}}' | grep -E '^codex-condom-' || true)
    if (( ${#to_rm[@]} > 0 )); then
      if confirm "Remove containers: ${to_rm[*]}?"; then
        podman rm -f "${to_rm[@]}" || true
        info "Removed containers: ${to_rm[*]}"
      else
        warn "Skipped removing containers"
      fi
    fi
  else
    warn "podman not found; cannot remove containers"
  fi
fi

if [[ $REMOVE_IMAGE -eq 1 ]]; then
  if [[ $has_podman -eq 1 ]]; then
    if podman image exists "$RUNTIME_IMAGE_TAG"; then
      if confirm "Remove image $RUNTIME_IMAGE_TAG?"; then
        podman rmi -f "$RUNTIME_IMAGE_TAG" || true
        info "Removed image $RUNTIME_IMAGE_TAG"
      else
        warn "Skipped removing image $RUNTIME_IMAGE_TAG"
      fi
    fi
  else
    warn "podman not found; cannot remove image"
  fi
fi

info "Uninstall complete."
if [[ $PURGE_PATH -eq 0 ]]; then
  echo "Note: PATH entries in shell configs were not changed. Use --purge-path to remove them (backups will be created)."
fi
