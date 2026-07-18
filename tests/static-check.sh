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
grep -Fqx '/place-setup-exe-file-here/*.exe' "$ROOT_DIR/.gitignore"
grep -Fqx '# Managed by sdr-console-wine.' "$ROOT_DIR/bin/sdr-console"
grep -Fqx '# Managed by sdr-console-wine.' "$ROOT_DIR/bin/sdr-console-rtl-tcp"
grep -Fqx 'X-SDR-Console-Wine-Managed=true' "$ROOT_DIR/setup.sh"
grep -Fqx '      --rtl-tcp) RTL_TCP=1 ;;' "$ROOT_DIR/setup.sh"
grep -Fqx '      --fix-fonts) FONT_FIX=1 ;;' "$ROOT_DIR/setup.sh"
grep -Fqx '      --dpi)' "$ROOT_DIR/setup.sh"
grep -Fqx "readonly PREFIX_WINGDINGS_FONT=\"\$PREFIX/drive_c/windows/Fonts/Wingdings.ttf\"" "$ROOT_DIR/setup.sh"
grep -Fqx "readonly FREE_WINGDINGS_SHA256='887664b9bcea8d57d81ddf9471f4c4d61d97a1318cd5626d719cc5fe9346c04e'" "$ROOT_DIR/setup.sh"

printf 'static checks passed\n'
