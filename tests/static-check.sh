#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

check_file() {
  [[ -f "$ROOT_DIR/$1" ]] || {
    printf 'missing required file: %s\n' "$1" >&2
    exit 1
  }
}

check_file setup.sh
check_file uninstall.sh
check_file bin/sdr-console
check_file bin/sdr-console-rtl-tcp
check_file tools/build-sdr-console-ui-font.py
check_file tests/font-builder-check.sh
check_file fonts/SDRConsoleUI.ttf
check_file fonts/README.md
check_file fonts/LICENSES/OFL-1.1.txt
check_file fonts/LICENSES/DEJAVU-LICENSE.txt
check_file README.md
check_file LICENSE
check_file .gitignore
check_file place-setup-exe-file-here/README.md

bash -n "$ROOT_DIR/setup.sh"
bash -n "$ROOT_DIR/uninstall.sh"
bash -n "$ROOT_DIR/bin/sdr-console"
bash -n "$ROOT_DIR/bin/sdr-console-rtl-tcp"

[[ -x "$ROOT_DIR/setup.sh" ]]
[[ -x "$ROOT_DIR/uninstall.sh" ]]
[[ -x "$ROOT_DIR/bin/sdr-console" ]]
[[ -x "$ROOT_DIR/bin/sdr-console-rtl-tcp" ]]
[[ -x "$ROOT_DIR/tools/build-sdr-console-ui-font.py" ]]
[[ -x "$ROOT_DIR/tests/font-builder-check.sh" ]]
grep -Fqx '/place-setup-exe-file-here/*.exe' "$ROOT_DIR/.gitignore"
grep -Fqx '# Managed by sdr-console-wine.' "$ROOT_DIR/bin/sdr-console"
grep -Fqx '# Managed by sdr-console-wine.' "$ROOT_DIR/bin/sdr-console-rtl-tcp"
grep -Fqx 'X-SDR-Console-Wine-Managed=true' "$ROOT_DIR/setup.sh"
grep -Fqx '      --rtl-tcp) RTL_TCP=1 ;;' "$ROOT_DIR/setup.sh"
grep -Fqx '      --fix-fonts) FONT_FIX=1 ;;' "$ROOT_DIR/setup.sh"
grep -Fqx '      --dpi)' "$ROOT_DIR/setup.sh"
grep -Fqx '      --window-decoration)' "$ROOT_DIR/setup.sh"
grep -Fqx 'readonly BUNDLED_COMPATIBILITY_FONT="$SCRIPT_DIR/fonts/SDRConsoleUI.ttf"' "$ROOT_DIR/setup.sh"
grep -Fqx "readonly SEGOE_UI_REPLACEMENT='SDR Console UI'" "$ROOT_DIR/setup.sh"
! "/usr/bin/python3" "$ROOT_DIR/tools/build-sdr-console-ui-font.py" --help | grep -F -- '--patch' >/dev/null

dry_run_output="$($ROOT_DIR/setup.sh --fix-fonts --dry-run)"
grep -Fqx '[sdr-console] would not modify SDR Console executable or DLL files' <<<"$dry_run_output"

dry_run_output="$($ROOT_DIR/setup.sh --window-decoration off --dry-run)"
grep -Fqx '[sdr-console] would disable the Wine title bar for SDR Console only' <<<"$dry_run_output"

printf 'static checks passed\n'
