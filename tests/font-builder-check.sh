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
label_fixture="$(mktemp --suffix=.dll)"
trap 'rm -f "$font_output" "$label_fixture"' EXIT

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
assert cmap[0xE779] == cmap[0x1F4BB]
assert font["hmtx"].metrics[cmap[0xE77A]] == (0, 0)
assert cmap[0xE77B] == cmap[0x1F50A]
assert font["hmtx"].metrics[cmap[0xE77C]] == (0, 0)
assert {record.toUnicode() for record in font["name"].names if record.nameID == 16} == {"SDR Console UI"}
assert {record.toUnicode() for record in font["name"].names if record.nameID == 17} == {"Regular"}
PY

"$PYTHON_BIN" - "$label_fixture" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_bytes(
    "\U0001F4BB  Console Streamer\0\U0001F5A7  V3 Server\0\U0001F50A Recording\0".encode("utf-16le")
)
PY

"$PYTHON_BIN" "$ROOT_DIR/tools/build-sdr-console-ui-font.py" \
  --patch-symbol-labels --font "$font_output" "$label_fixture" >/dev/null

second_repair_output="$("$PYTHON_BIN" "$ROOT_DIR/tools/build-sdr-console-ui-font.py" \
  --patch-symbol-labels --font "$font_output" "$label_fixture")"
[[ "$second_repair_output" == 'Installed SDR Console label symbols are already repaired.' ]]

"$PYTHON_BIN" - "$label_fixture" <<'PY'
from pathlib import Path
import sys

contents = Path(sys.argv[1]).read_bytes()
assert "\ue779\ue77a  Console Streamer\0".encode("utf-16le") in contents
assert "\ue777\ue778  V3 Server\0".encode("utf-16le") in contents
assert "\ue77b\ue77c Recording\0".encode("utf-16le") in contents
PY

printf 'font builder check passed\n'
