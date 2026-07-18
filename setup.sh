#!/usr/bin/env bash
# Install SDR Console into an isolated per-user Wine prefix.
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly INSTALLER_DIR="$SCRIPT_DIR/place-setup-exe-file-here"
readonly PREFIX="$HOME/.local/share/sdr-console-wine"
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/sdr-console-wine"
readonly USER_BIN_DIR="$HOME/.local/bin"
readonly WRAPPER_PATH="$USER_BIN_DIR/sdr-console"
readonly APPLICATIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
readonly DESKTOP_FILE="$APPLICATIONS_DIR/sdr-console-wine.desktop"
readonly RUNNER_SOURCE="$SCRIPT_DIR/bin/sdr-console"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sdr-console-wine"
readonly RTL_TCP_CONFIG="$CONFIG_DIR/rtl-tcp.conf"
readonly SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
readonly RTL_TCP_SERVICE='sdr-console-rtl-tcp.service'
readonly RTL_TCP_SERVICE_PATH="$SYSTEMD_USER_DIR/$RTL_TCP_SERVICE"
readonly RTL_TCP_RUNNER_SOURCE="$SCRIPT_DIR/bin/sdr-console-rtl-tcp"
readonly RTL_TCP_RUNNER_PATH="$USER_BIN_DIR/sdr-console-rtl-tcp"
readonly FULL_WEBDINGS_FONT='/usr/share/fonts/truetype/msttcorefonts/Webdings.ttf'

DRY_RUN=0
DIAGNOSE=0
INTERACTIVE=0
UPGRADE=0
ASSUME_YES=0
RESET=0
RTL_TCP=0
FONT_FIX=0
DPI=""
INSTALLER_PATH=""
INSTALLER_SHA256=""
LOG_FILE=""

usage() {
  cat <<'EOF'
Usage: ./setup.sh [OPTION]

Install SDR Console in an isolated Wine prefix.

Options:
  --dry-run      Show the selected installer and planned changes only.
  --diagnose     Check the existing installation without changing anything.
  --interactive  Show the Windows installer instead of using silent mode.
  --upgrade      Intentionally install a different staged installer.
  --rtl-tcp      Install and start the local RTL-SDR TCP bridge.
  --fix-fonts    Use the full local Webdings font for missing SDR Console symbols.
  --dpi VALUE    Set the SDR Console Wine prefix DPI (for example: 96, 120, 144).
  --reset        Remove SDR Console user state, launchers, and logs.
  --yes          Confirm the vendor-terms prompt non-interactively.
  -h, --help     Show this help.

Place exactly one SDR Console .exe installer in place-setup-exe-file-here/
before using install, upgrade, or dry-run mode. The --rtl-tcp, --fix-fonts, and
--dpi options do not need an installer. Do not run this script with sudo; it
requests sudo only for required apt package installation.
EOF
}

info() {
  printf '[sdr-console] %s\n' "$*"
}

warn() {
  printf '[sdr-console] warning: %s\n' "$*" >&2
}

die() {
  printf '[sdr-console] error: %s\n' "$*" >&2
  exit 1
}

on_error() {
  local status=$?
  printf '[sdr-console] error: setup stopped at line %s (exit %s).\n' "$1" "$status" >&2
  if [[ -n "$LOG_FILE" ]]; then
    printf '[sdr-console] See the full log: %s\n' "$LOG_FILE" >&2
  fi
  exit "$status"
}

trap 'on_error "$LINENO"' ERR

require_non_root() {
  (( EUID != 0 )) || die 'Do not run setup as root. Run it as the target desktop user.'
}

read_os_release() {
  [[ -r /etc/os-release ]] || die 'Cannot read /etc/os-release.'
  # shellcheck disable=SC1091
  . /etc/os-release
}

check_platform() {
  info 'checking system'
  [[ "$(uname -m)" == 'x86_64' ]] || die 'Only 64-bit amd64 systems are supported.'

  read_os_release
  local id_like=" ${ID_LIKE:-} "
  if [[ "${ID:-}" != 'ubuntu' && "${ID:-}" != 'debian' && "$id_like" != *' debian '* ]]; then
    die "Unsupported distribution: ${PRETTY_NAME:-unknown}. Use Ubuntu 24.04 or a Debian/Ubuntu derivative."
  fi

  if [[ "${ID:-}" == 'ubuntu' && "${VERSION_ID:-}" != '24.04' ]]; then
    warn "Ubuntu ${VERSION_ID:-unknown} is outside the tested 24.04 baseline."
  fi

  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    warn 'No active graphical session was detected. Installation can proceed, but SDR Console needs a local desktop session to run.'
  fi
}

select_installer() {
  [[ -d "$INSTALLER_DIR" ]] || die "Missing installer directory: $INSTALLER_DIR"

  local -a installers=()
  mapfile -d '' installers < <(find "$INSTALLER_DIR" -maxdepth 1 -type f -iname '*.exe' -print0)

  case "${#installers[@]}" in
    0)
      die "No .exe installer found in $INSTALLER_DIR. Download SDR Console from its official source and place exactly one .exe there."
      ;;
    1)
      INSTALLER_PATH="${installers[0]}"
      ;;
    *)
      die "Multiple .exe installers found in $INSTALLER_DIR. Leave exactly one installer there."
      ;;
  esac

  INSTALLER_SHA256="$(sha256sum -- "$INSTALLER_PATH" | awk '{print $1}')"
  info "selected installer: $(basename -- "$INSTALLER_PATH")"
  info "selected SHA-256: $INSTALLER_SHA256"
}

package_installed() {
  local package=$1
  [[ "$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)" == 'installed' ]]
}

dependencies_ready() {
  dpkg --print-foreign-architectures | grep -qx 'i386' &&
    package_installed wine &&
    package_installed wine64 &&
    package_installed wine32:i386
}

describe_dependency_plan() {
  if dpkg --print-foreign-architectures | grep -qx 'i386'; then
    info 'i386 package architecture is already enabled'
  else
    info 'would enable the i386 package architecture'
  fi

  if dependencies_ready; then
    info 'Wine dependencies are already installed'
  else
    info 'would run: sudo apt-get update'
    info 'would run: sudo apt-get install --no-install-recommends wine wine64 wine32:i386'
  fi
}

ensure_dependencies() {
  info 'checking Wine dependencies'
  if dependencies_ready; then
    info 'Wine dependencies are already installed'
    return
  fi

  info 'installing Wine dependencies'
  sudo -v
  if ! dpkg --print-foreign-architectures | grep -qx 'i386'; then
    info 'enabling the i386 package architecture'
    sudo dpkg --add-architecture i386
  fi

  info 'updating apt package metadata'
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update
  info 'installing Wine packages'
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends wine wine64 wine32:i386

  dependencies_ready || die 'Wine dependencies are still incomplete after apt installation.'
}

rtl_tcp_ready() {
  command -v rtl_tcp >/dev/null 2>&1
}

describe_rtl_tcp_plan() {
  if rtl_tcp_ready; then
    info "using existing rtl_tcp: $(command -v rtl_tcp)"
  else
    info 'would run: sudo apt-get update'
    info 'would run: sudo apt-get install --no-install-recommends rtl-sdr'
  fi
  info "would install the user service: $RTL_TCP_SERVICE_PATH"
  info "would start a local RTL-SDR bridge at 127.0.0.1:1234"
}

ensure_rtl_tcp_dependency() {
  info 'checking RTL-SDR TCP bridge dependency'
  if rtl_tcp_ready; then
    info "using existing rtl_tcp: $(command -v rtl_tcp)"
    return
  fi

  info 'installing the rtl-sdr package'
  sudo -v
  sudo env DEBIAN_FRONTEND=noninteractive apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends rtl-sdr
  rtl_tcp_ready || die 'The rtl-sdr package did not provide rtl_tcp as expected.'
}

write_rtl_tcp_config() {
  [[ -f "$RTL_TCP_CONFIG" ]] && return
  mkdir -p "$CONFIG_DIR"
  cat > "$RTL_TCP_CONFIG" <<'EOF'
# Managed by sdr-console-wine. Values are read by sdr-console-rtl-tcp.
# Keep the bridge on localhost so the USB receiver is not exposed on the LAN.
RTL_TCP_PORT=1234
RTL_TCP_SAMPLE_RATE=2048000
RTL_TCP_DEVICE_INDEX=0
RTL_TCP_GAIN=
RTL_TCP_PPM=
RTL_TCP_BIAS_T=0
EOF
}

write_rtl_tcp_service() {
  mkdir -p "$USER_BIN_DIR" "$SYSTEMD_USER_DIR"
  install -m 0755 "$RTL_TCP_RUNNER_SOURCE" "$RTL_TCP_RUNNER_PATH"
  cat > "$RTL_TCP_SERVICE_PATH" <<EOF
# Managed by sdr-console-wine.
[Unit]
Description=Local RTL-SDR bridge for SDR Console
After=default.target

[Service]
Type=simple
ExecStart=$RTL_TCP_RUNNER_PATH
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
}

install_rtl_tcp_bridge() {
  info 'configuring the local RTL-SDR TCP bridge'
  [[ -x "$RTL_TCP_RUNNER_SOURCE" ]] || die "Missing RTL-SDR bridge runner: $RTL_TCP_RUNNER_SOURCE"
  command -v systemctl >/dev/null 2>&1 || die 'systemctl is required to manage the RTL-SDR bridge.'

  ensure_rtl_tcp_dependency
  write_rtl_tcp_config
  write_rtl_tcp_service
  systemctl --user daemon-reload
  systemctl --user enable --now "$RTL_TCP_SERVICE"

  if ! systemctl --user is-active --quiet "$RTL_TCP_SERVICE"; then
    journalctl --user -u "$RTL_TCP_SERVICE" -n 30 --no-pager >&2 || true
    die "The RTL-SDR bridge did not start. Check: journalctl --user -u $RTL_TCP_SERVICE"
  fi

  info 'RTL-SDR bridge is active at 127.0.0.1:1234'
  info 'In SDR Console, add or select "RTL Dongle (TCP)" with address 127.0.0.1 and port 1234.'
}

full_webdings_available() {
  [[ -f "$FULL_WEBDINGS_FONT" ]]
}

configure_webdings_font() {
  [[ -d "$PREFIX" ]] || die 'The SDR Console Wine prefix is missing. Run ./setup.sh first.'
  full_webdings_available || die "The full Webdings font is not installed. Install ttf-mscorefonts-installer, then re-run ./setup.sh --fix-fonts."

  info 'configuring the full Webdings font for Wine'
  WINEPREFIX="$PREFIX" wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
    /v 'Webdings (TrueType)' /t REG_SZ /d 'Z:\usr\share\fonts\truetype\msttcorefonts\Webdings.ttf' /f
  info 'font repair complete; close and restart SDR Console to reload its fonts'
}

configure_webdings_font_if_available() {
  if full_webdings_available; then
    configure_webdings_font
  else
    warn 'The full Webdings font is unavailable. If SDR Console shows rectangles for the >|< control, install ttf-mscorefonts-installer and run ./setup.sh --fix-fonts.'
  fi
}

validate_dpi() {
  [[ "$DPI" =~ ^[0-9]+$ ]] || die '--dpi requires an integer value.'
  (( DPI >= 96 && DPI <= 384 )) || die '--dpi must be between 96 and 384.'
}

configure_dpi() {
  [[ -d "$PREFIX" ]] || die 'The SDR Console Wine prefix is missing. Run ./setup.sh first.'
  validate_dpi

  info "setting SDR Console Wine prefix DPI to $DPI"
  WINEPREFIX="$PREFIX" wine reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d "$DPI" /f
  WINEPREFIX="$PREFIX" wine reg add 'HKCU\Control Panel\Desktop' /v Win8DpiScaling /t REG_DWORD /d 1 /f
  info 'DPI change complete; close and restart SDR Console to apply it'
}

find_application() {
  local drive_c="$PREFIX/drive_c"
  [[ -d "$drive_c" ]] || return 1
  find "$drive_c" -type f -iname 'SDR Console.exe' -print -quit
}

current_installer_sha256() {
  local state_file="$STATE_DIR/installer.sha256"
  [[ -r "$state_file" ]] || return 1
  tr -d '\r\n' < "$state_file"
}

write_state() {
  local application=$1
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$INSTALLER_SHA256" > "$STATE_DIR/installer.sha256"
  printf '%s\n' "$(basename -- "$INSTALLER_PATH")" > "$STATE_DIR/installer.filename"
  printf '%s\n' "$application" > "$STATE_DIR/application.path"
  printf '%s\n' "$(date --iso-8601=seconds)" > "$STATE_DIR/installed-at"
  wine --version > "$STATE_DIR/wine.version" 2>&1 || true
}

confirm_vendor_terms() {
  (( ASSUME_YES )) && return
  [[ -t 0 ]] || die 'Vendor terms need confirmation. Re-run interactively or add --yes after reviewing the vendor terms.'

  printf '\n'
  printf 'You are about to run a manually downloaded SDR Console installer.\n'
  printf 'Confirm that you obtained it from the official source and accept its applicable vendor terms.\n'
  read -r -p 'Type yes to continue: ' answer
  [[ "$answer" == 'yes' ]] || die 'Installation cancelled because vendor terms were not confirmed.'
}

init_logging() {
  mkdir -p "$STATE_DIR/logs"
  LOG_FILE="$STATE_DIR/logs/setup-$(date +%Y%m%dT%H%M%S%z).log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  info "writing detailed output to $LOG_FILE"
}

initialize_prefix() {
  info 'creating or updating the Wine prefix'
  mkdir -p "$PREFIX"
  WINEPREFIX="$PREFIX" WINEARCH=win64 wineboot -u
  WINEPREFIX="$PREFIX" wineserver -w
}

run_installer() {
  info 'installing SDR Console'
  if (( INTERACTIVE )); then
    info 'opening the Windows installer interactively'
    WINEPREFIX="$PREFIX" WINEARCH=win64 wine "$INSTALLER_PATH"
  else
    info 'running the Windows installer in silent mode'
    WINEPREFIX="$PREFIX" WINEARCH=win64 wine "$INSTALLER_PATH" /S
  fi
  WINEPREFIX="$PREFIX" wineserver -w
}

write_launchers() {
  info 'creating launchers'
  [[ -x "$RUNNER_SOURCE" ]] || die "Missing launcher source: $RUNNER_SOURCE"
  mkdir -p "$USER_BIN_DIR" "$APPLICATIONS_DIR"
  install -m 0755 "$RUNNER_SOURCE" "$WRAPPER_PATH"

  local escaped_wrapper=${WRAPPER_PATH//\\/\\\\}
  escaped_wrapper=${escaped_wrapper//\"/\\\"}
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=SDR Console (Wine)
Comment=Run SDR Console through its isolated Wine prefix
Exec="$escaped_wrapper"
Icon=wine
Terminal=false
Categories=AudioVideo;Utility;
StartupNotify=true
X-SDR-Console-Wine-Managed=true
EOF
}

verify_installation() {
  local application
  info 'verifying installation'
  application="$(find_application || true)"
  [[ -n "$application" ]] || die "SDR Console.exe was not found in $PREFIX after installation. Re-run with --interactive and inspect the log."
  [[ -x "$WRAPPER_PATH" ]] || die "Launcher wrapper was not created: $WRAPPER_PATH"
  [[ -f "$DESKTOP_FILE" ]] || die "Desktop launcher was not created: $DESKTOP_FILE"
  write_state "$application"
  info "found application: $application"
  info 'setup complete'
  info 'Start SDR Console from the application menu or run: sdr-console'
  if [[ ":${PATH}:" != *":$USER_BIN_DIR:"* ]]; then
    warn "$USER_BIN_DIR is not currently on PATH. Open a new terminal session or start it from the application menu."
  fi
}

diagnose() {
  local failures=0
  info 'diagnosing installation without making changes'

  if [[ "$(uname -m)" == 'x86_64' ]]; then
    info 'ok: 64-bit amd64 system'
  else
    warn 'problem: this is not a 64-bit amd64 system'
    failures=1
  fi

  if dependencies_ready; then
    info 'ok: Wine packages and i386 support are installed'
  else
    warn 'problem: Wine packages or i386 support are missing; run ./setup.sh'
    failures=1
  fi

  local application
  application="$(find_application || true)"
  if [[ -n "$application" ]]; then
    info "ok: application found at $application"
  else
    warn "problem: SDR Console.exe was not found in $PREFIX"
    failures=1
  fi

  if [[ -x "$WRAPPER_PATH" ]] && grep -Fqx '# Managed by sdr-console-wine.' "$WRAPPER_PATH"; then
    info "ok: terminal launcher found at $WRAPPER_PATH"
  else
    warn "problem: terminal launcher is missing or not managed by this project: $WRAPPER_PATH"
    failures=1
  fi

  if [[ -f "$DESKTOP_FILE" ]] && grep -Fqx 'X-SDR-Console-Wine-Managed=true' "$DESKTOP_FILE"; then
    info "ok: desktop launcher found at $DESKTOP_FILE"
  else
    warn "problem: desktop launcher is missing or not managed by this project: $DESKTOP_FILE"
    failures=1
  fi

  (( failures == 0 )) || return 1
  info 'diagnostic completed successfully'
}

handle_reset() {
  local -a args=()
  (( DRY_RUN )) && args+=(--dry-run)
  (( ASSUME_YES )) && args+=(--yes)
  exec "$SCRIPT_DIR/uninstall.sh" "${args[@]}"
}

parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --diagnose) DIAGNOSE=1 ;;
      --interactive) INTERACTIVE=1 ;;
      --upgrade) UPGRADE=1 ;;
      --rtl-tcp) RTL_TCP=1 ;;
      --fix-fonts) FONT_FIX=1 ;;
      --dpi)
        shift
        (( $# > 0 )) || die '--dpi requires a value, for example: --dpi 144.'
        DPI="$1"
        ;;
      --reset) RESET=1 ;;
      --yes) ASSUME_YES=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1. Run ./setup.sh --help for usage." ;;
    esac
    shift
  done

  if (( DIAGNOSE + RESET > 1 )); then
    die '--diagnose and --reset cannot be used together.'
  fi
  if (( DRY_RUN && DIAGNOSE )); then
    die '--dry-run cannot be combined with --diagnose.'
  fi
  if (( RTL_TCP && (DIAGNOSE || INTERACTIVE || UPGRADE || RESET) )); then
    die '--rtl-tcp cannot be combined with --diagnose, --interactive, --upgrade, or --reset.'
  fi
  if (( FONT_FIX && (DIAGNOSE || INTERACTIVE || UPGRADE || RESET || RTL_TCP) )); then
    die '--fix-fonts cannot be combined with --diagnose, --interactive, --upgrade, --rtl-tcp, or --reset.'
  fi
  if [[ -n "$DPI" ]] && (( DIAGNOSE || INTERACTIVE || UPGRADE || RESET || RTL_TCP || FONT_FIX )); then
    die '--dpi cannot be combined with --diagnose, --interactive, --upgrade, --rtl-tcp, --fix-fonts, or --reset.'
  fi
}

main() {
  parse_args "$@"
  require_non_root

  if (( RESET )); then
    handle_reset
  fi

  if (( DIAGNOSE )); then
    if ! diagnose; then
      exit 1
    fi
    return
  fi

  check_platform

  if (( RTL_TCP )); then
    if (( DRY_RUN )); then
      info 'dry run: no packages, configuration, or user services will be changed'
      describe_rtl_tcp_plan
      return
    fi
    init_logging
    install_rtl_tcp_bridge
    return
  fi

  if (( FONT_FIX )); then
    if (( DRY_RUN )); then
      info 'dry run: no Wine registry values will be changed'
      if full_webdings_available; then
        info "would map Webdings to $FULL_WEBDINGS_FONT in the SDR Console Wine prefix"
      else
        info 'would require ttf-mscorefonts-installer before the font repair can run'
      fi
      return
    fi
    init_logging
    configure_webdings_font
    return
  fi

  if [[ -n "$DPI" ]]; then
    if (( DRY_RUN )); then
      validate_dpi
      info 'dry run: no Wine registry values will be changed'
      info "would set the SDR Console Wine prefix DPI to $DPI"
      return
    fi
    init_logging
    configure_dpi
    return
  fi

  select_installer

  if (( DRY_RUN )); then
    local application installed_sha
    info 'dry run: no files, packages, Wine prefixes, or launchers will be changed'
    describe_dependency_plan
    application="$(find_application || true)"
    if [[ -n "$application" ]]; then
      info "existing application: $application"
      installed_sha="$(current_installer_sha256 || true)"
      if (( UPGRADE )); then
        info 'would run the staged installer as an explicit upgrade'
      elif [[ -z "$installed_sha" ]]; then
        info 'would require --upgrade because the existing installation has no recorded installer hash'
      elif [[ "$installed_sha" != "$INSTALLER_SHA256" ]]; then
        info 'would require --upgrade because the staged installer differs from the recorded installation'
      fi
    else
      info "would create Wine prefix: $PREFIX"
      info "would create terminal launcher: $WRAPPER_PATH"
      info "would create desktop launcher: $DESKTOP_FILE"
    fi
    return
  fi

  local application installed_sha
  application="$(find_application || true)"
  installed_sha="$(current_installer_sha256 || true)"
  if [[ -n "$application" && "$UPGRADE" -eq 0 ]]; then
    if [[ -z "$installed_sha" ]]; then
      die 'The existing installation has no recorded installer hash. Re-run with --upgrade to install the staged release intentionally, or use --reset.'
    fi
    if [[ "$installed_sha" != "$INSTALLER_SHA256" ]]; then
      die 'A different installer is staged. Existing SDR Console settings are preserved; re-run with --upgrade to update intentionally.'
    fi
    info 'existing SDR Console installation matches the staged installer; repairing launchers only'
    ensure_dependencies
    init_logging
    configure_webdings_font_if_available
    write_launchers
    verify_installation
    return
  fi

  confirm_vendor_terms
  ensure_dependencies
  init_logging
  initialize_prefix
  configure_webdings_font_if_available
  run_installer
  write_launchers
  verify_installation
}

main "$@"
