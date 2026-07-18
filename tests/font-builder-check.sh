#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly PYTHON_BIN='/usr/bin/python3'
readonly BASE_FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
readonly SYMBOL_FONT='/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf'

[[ -r "$BASE_FONT" && -r "$SYMBOL_FONT" ]] || {
  printf 'font-builder check requires fonts-dejavu-core and fonts-noto-core\n' >&2
  exit 1
}
"$PYTHON_BIN" -c 'import fontTools' >/dev/null

font_output="$(mktemp --suffix=.ttf)"
trap 'rm -f "$font_output"' EXIT

"$PYTHON_BIN" "$ROOT_DIR/tools/build-sdr-console-ui-font.py" \
  --base "$BASE_FONT" \
  --symbols "$SYMBOL_FONT" \
  --output "$font_output" >/dev/null

"$PYTHON_BIN" - "$font_output" <<'PY'
from fontTools.ttLib import TTFont
import sys

font = TTFont(sys.argv[1])
cmap = font.getBestCmap()
assert cmap[0xE777] == cmap[0x1F5A7]
assert font["hmtx"].metrics[cmap[0xE778]] == (0, 0)
assert {record.toUnicode() for record in font["name"].names if record.nameID == 16} == {"SDR Console UI"}
assert {record.toUnicode() for record in font["name"].names if record.nameID == 17} == {"Regular"}
PY

printf 'font builder check passed\n'
