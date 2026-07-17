#!/usr/bin/env bash
# Remove only user files created by this project; Wine apt packages stay installed.
set -Eeuo pipefail

readonly PREFIX="$HOME/.local/share/sdr-console-wine"
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sdr-console-wine"
readonly WRAPPER_PATH="$HOME/.local/bin/sdr-console"
readonly DESKTOP_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/applications/sdr-console-wine.desktop"

DRY_RUN=0
ASSUME_YES=0

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [OPTION]

Remove SDR Console's isolated Wine prefix, launchers, logs, and local state.
Wine packages installed with apt are deliberately left installed.

Options:
  --dry-run  Show what would be removed without changing anything.
  --yes      Skip the destructive-action confirmation.
  -h, --help Show this help.
EOF
}

info() {
  printf '[sdr-console] %s\n' "$*"
}

die() {
  printf '[sdr-console] error: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --yes) ASSUME_YES=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1. Run ./uninstall.sh --help for usage." ;;
    esac
    shift
  done
}

confirm_removal() {
  (( ASSUME_YES )) && return
  [[ -t 0 ]] || die 'Removal needs confirmation. Re-run interactively or add --yes.'
  printf 'This removes the isolated SDR Console Wine prefix and all SDR Console settings.\n'
  read -r -p 'Type REMOVE to continue: ' answer
  [[ "$answer" == 'REMOVE' ]] || die 'Removal cancelled.'
}

remove_if_present() {
  local path=$1
  local description=$2
  if [[ -e "$path" || -L "$path" ]]; then
    if (( DRY_RUN )); then
      info "would remove $description: $path"
    else
      rm -rf -- "$path"
      info "removed $description: $path"
    fi
  else
    info "not present: $description"
  fi
}

remove_managed_file() {
  local path=$1
  local marker=$2
  local description=$3
  if [[ ! -e "$path" ]]; then
    info "not present: $description"
  elif grep -Fqx "$marker" "$path"; then
    if (( DRY_RUN )); then
      info "would remove $description: $path"
    else
      rm -f -- "$path"
      info "removed $description: $path"
    fi
  else
    info "leaving $description not managed by this project: $path"
  fi
}

main() {
  parse_args "$@"
  (( EUID != 0 )) || die 'Do not run uninstall as root.'

  if (( DRY_RUN )); then
    info 'dry run: no files will be removed'
  else
    confirm_removal
  fi

  remove_if_present "$PREFIX" 'Wine prefix and SDR Console settings'
  remove_if_present "$STATE_DIR" 'local logs and install state'
  remove_managed_file "$WRAPPER_PATH" '# Managed by sdr-console-wine.' 'terminal launcher'
  remove_managed_file "$DESKTOP_FILE" 'X-SDR-Console-Wine-Managed=true' 'desktop launcher'
  info 'Wine apt packages were left installed intentionally.'
}

main "$@"
