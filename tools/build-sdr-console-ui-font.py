#!/usr/bin/env python3
"""Build the bundled, prefix-local SDR Console compatibility font."""

from __future__ import annotations

import argparse
import logging
import os
import tempfile
from pathlib import Path

from fontTools.merge import Merger
from fontTools.merge.options import Options
from fontTools.ttLib import TTFont
from fontTools.ttLib.scaleUpem import scale_upem


logging.getLogger("fontTools").setLevel(logging.ERROR)


FONT_FAMILY = "SDR Console UI"
FONT_FULL_NAME = "SDR Console UI"
FONT_UNIQUE_NAME = "SDR Console UI Regular"
FONT_POSTSCRIPT_NAME = "SDRConsoleUI"
FONT_COPYRIGHT = (
    "Copyright (c) 2003 Bitstream, Inc. All Rights Reserved. "
    "Copyright (c) 2006 Tavmjong Bah. All Rights Reserved. "
    "Copyright 2017 Google Inc. All Rights Reserved."
)
FONT_LICENSE = (
    "Composite font licensed under the SIL Open Font License, Version 1.1. "
    "See the bundled OFL and DejaVu license notices."
)
FONT_LICENSE_URL = "https://openfontlicense.org"


def rename_font(font: TTFont) -> None:
    names = {
        1: FONT_FAMILY,
        2: "Regular",
        3: FONT_UNIQUE_NAME,
        4: FONT_FULL_NAME,
        6: FONT_POSTSCRIPT_NAME,
        16: FONT_FAMILY,
        17: "Regular",
        0: FONT_COPYRIGHT,
        13: FONT_LICENSE,
        14: FONT_LICENSE_URL,
    }
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())


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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path)
    parser.add_argument("--symbols", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not all((args.base, args.symbols, args.output)):
        parser.error("--base, --symbols, and --output are required when building the font")
    return args


def main() -> None:
    args = parse_args()
    build_font(args.base, args.symbols, args.output)
    print(f"Built {FONT_FAMILY} at {args.output}.")


if __name__ == "__main__":
    main()
