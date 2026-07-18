#!/usr/bin/env python3
"""Build SDR Console's prefix-local compatibility font and guarded tab patch."""

from __future__ import annotations

import argparse
import logging
import os
import tempfile
from pathlib import Path

from fontTools.merge import Merger
from fontTools.merge.options import Options
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.scaleUpem import scale_upem


logging.getLogger("fontTools").setLevel(logging.ERROR)


FONT_FAMILY = "SDR Console UI"
FONT_FULL_NAME = "SDR Console UI"
FONT_UNIQUE_NAME = "SDR Console UI Regular"
FONT_POSTSCRIPT_NAME = "SDRConsoleUI"
NETWORK_CODEPOINT = 0x1F5A7
NETWORK_PRIVATE_CODEPOINT = 0xE777
BLANK_PRIVATE_CODEPOINT = 0xE778
BLANK_GLYPH_NAME = "sdrBlankSpacer"

# The UTF-16LE label used by supported SDR Console releases. Wine 9 sends this
# supplementary-plane icon as two surrogate halves, so replace it locally with
# two BMP private-use glyphs that the generated font provides.
SERVER_LABEL_SOURCE = (
    b"\x20\x00\x3d\xd8\xa7\xdd\x20\x00\x53\x00\x65\x00\x72\x00"
    b"\x76\x00\x65\x00\x72\x00\x20\x00\x00\x00"
)
SERVER_LABEL_TARGET = (
    b"\x20\x00\x77\xe7\x78\xe7\x20\x00\x53\x00\x65\x00\x72\x00"
    b"\x76\x00\x65\x00\x72\x00\x20\x00\x00\x00"
)


def rename_font(font: TTFont) -> None:
    names = {
        1: FONT_FAMILY,
        2: "Regular",
        3: FONT_UNIQUE_NAME,
        4: FONT_FULL_NAME,
        6: FONT_POSTSCRIPT_NAME,
        16: FONT_FAMILY,
        17: "Regular",
    }
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())


def add_private_use_glyphs(font: TTFont) -> None:
    cmap = font.getBestCmap()
    network_glyph = cmap.get(NETWORK_CODEPOINT)
    if not network_glyph:
        raise RuntimeError("The merged font does not contain U+1F5A7.")

    if BLANK_GLYPH_NAME not in font.getGlyphOrder():
        font["glyf"].glyphs[BLANK_GLYPH_NAME] = TTGlyphPen(None).glyph()
        font["hmtx"].metrics[BLANK_GLYPH_NAME] = (0, 0)
        font.setGlyphOrder(font.getGlyphOrder() + [BLANK_GLYPH_NAME])

    for table in font["cmap"].tables:
        if table.isUnicode():
            table.cmap[NETWORK_PRIVATE_CODEPOINT] = network_glyph
            table.cmap[BLANK_PRIVATE_CODEPOINT] = BLANK_GLYPH_NAME


def build_font(base_path: Path, symbols_path: Path, output_path: Path) -> None:
    if not base_path.is_file():
        raise RuntimeError(f"Base font is missing: {base_path}")
    if not symbols_path.is_file():
        raise RuntimeError(f"Symbol font is missing: {symbols_path}")

    base_font = TTFont(base_path)
    symbols_font = TTFont(symbols_path)
    scale_upem(symbols_font, base_font["head"].unitsPerEm)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sdr-console-font-") as temp_dir:
        scaled_symbols_path = Path(temp_dir) / "NotoSansSymbols2-scaled.ttf"
        symbols_font.save(scaled_symbols_path)
        options = Options(drop_tables=["GDEF", "GPOS", "GSUB", "MATH"])
        font = Merger(options).merge([str(base_path), str(scaled_symbols_path)])

    rename_font(font)
    add_private_use_glyphs(font)

    with tempfile.NamedTemporaryFile(
        prefix=".SDRConsoleUI-", suffix=".ttf", dir=output_path.parent, delete=False
    ) as temp_file:
        temporary_output = Path(temp_file.name)
    try:
        font.save(temporary_output)
        os.replace(temporary_output, output_path)
    finally:
        if temporary_output.exists():
            temporary_output.unlink()


def patch_server_tab(dll_path: Path) -> str:
    if not dll_path.is_file():
        raise RuntimeError(f"SDRSelectRadio.dll is missing: {dll_path}")

    contents = dll_path.read_bytes()
    source_count = contents.count(SERVER_LABEL_SOURCE)
    target_count = contents.count(SERVER_LABEL_TARGET)
    if source_count == 0 and target_count == 1:
        return "Server-tab network-symbol repair is already applied."
    if source_count != 1 or target_count != 0:
        raise RuntimeError(
            "The DLL does not contain exactly one supported Server-tab label."
        )

    dll_path.write_bytes(contents.replace(SERVER_LABEL_SOURCE, SERVER_LABEL_TARGET))
    return "Applied the guarded Server-tab network-symbol repair."


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path)
    parser.add_argument("--symbols", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--patch-server-tab", type=Path, metavar="PATH")
    args = parser.parse_args()
    if args.patch_server_tab:
        if any(value is not None for value in (args.base, args.symbols, args.output)):
            parser.error("--patch-server-tab cannot be combined with font-build arguments")
    elif not all((args.base, args.symbols, args.output)):
        parser.error("--base, --symbols, and --output are required when building the font")
    return args


def main() -> None:
    args = parse_args()
    if args.patch_server_tab:
        print(patch_server_tab(args.patch_server_tab))
        return
    build_font(args.base, args.symbols, args.output)
    print(f"Built {FONT_FAMILY} at {args.output}.")


if __name__ == "__main__":
    main()
