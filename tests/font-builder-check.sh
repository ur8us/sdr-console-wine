#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly PYTHON_BIN='/usr/bin/python3'
readonly BASE_FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
readonly SYMBOL_FONT='/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf'
readonly BUNDLED_FONT="$ROOT_DIR/fonts/SDRConsoleUI.ttf"

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

"$PYTHON_BIN" - "$BASE_FONT" "$font_output" "$BUNDLED_FONT" <<'PY'
from fontTools.ttLib import TTFont
import sys

base_cmap = TTFont(sys.argv[1]).getBestCmap()
for path in sys.argv[2:]:
    font = TTFont(path)
    cmap = font.getBestCmap()
    assert all(codepoint in cmap for codepoint in (0x1F4BB, 0x1F5A7, 0x1F50A))
    assert not any(0xE777 <= codepoint <= 0xE77C for codepoint in cmap)
    assert len(cmap.keys() - base_cmap.keys()) == 1682
    assert all(cmap[codepoint] == base_cmap[codepoint] for codepoint in cmap.keys() & base_cmap.keys())
    assert {record.toUnicode() for record in font["name"].names if record.nameID == 16} == {"SDR Console UI"}
    assert {record.toUnicode() for record in font["name"].names if record.nameID == 17} == {"Regular"}
    assert any("SIL Open Font License" in record.toUnicode() for record in font["name"].names if record.nameID == 13)
PY

printf 'font builder check passed\n'
