#!/usr/bin/env python3
"""Build SDR Console's prefix-local compatibility font and label-symbol repair."""

from __future__ import annotations

import argparse
import logging
import os
import re
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
FIXED_SYMBOL_PRIVATE_USE = {
    NETWORK_CODEPOINT: NETWORK_PRIVATE_CODEPOINT,
    0x1F4BB: 0xE779,  # Laptop, used by Console Streamer.
    0x1F50A: 0xE77B,  # Speaker, used by audio-device labels.
}
LABEL_SYMBOL_PATTERN = re.compile(
    rb"(?P<high>[\x00-\xff][\xd8-\xdb])(?P<low>[\x00-\xff][\xdc-\xdf])\x20\x00"
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


def symbol_private_use_map(cmap: dict[int, str]) -> dict[int, int]:
    """Return the BMP replacement slots for the confirmed SDR Console icons."""
    missing = [
        f"U+{codepoint:04X}"
        for codepoint in FIXED_SYMBOL_PRIVATE_USE
        if codepoint not in cmap
    ]
    if missing:
        raise RuntimeError(f"The merged font is missing: {', '.join(missing)}.")
    return FIXED_SYMBOL_PRIVATE_USE


def add_private_use_glyphs(font: TTFont) -> None:
    cmap = font.getBestCmap()
    replacements = symbol_private_use_map(cmap)

    if BLANK_GLYPH_NAME not in font.getGlyphOrder():
        font["glyf"].glyphs[BLANK_GLYPH_NAME] = TTGlyphPen(None).glyph()
        font["hmtx"].metrics[BLANK_GLYPH_NAME] = (0, 0)
        font.setGlyphOrder(font.getGlyphOrder() + [BLANK_GLYPH_NAME])

    for table in font["cmap"].tables:
        if table.isUnicode():
            for source_codepoint, replacement_codepoint in replacements.items():
                table.cmap[replacement_codepoint] = cmap[source_codepoint]
                table.cmap[replacement_codepoint + 1] = BLANK_GLYPH_NAME


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


def patch_symbol_labels(font_path: Path, target_paths: list[Path]) -> str:
    """Replace label-leading surrogate pairs with same-width BMP pairs.

    Wine 9 passes a supplementary-plane glyph to GDI as two independent
    surrogate code units. SDR Console places its icon glyphs before a space in
    resource labels, so retaining that following UTF-16 space makes the scan
    specific to labels and avoids changing arbitrary binary data.
    """
    if not font_path.is_file():
        raise RuntimeError(f"Compatibility font is missing: {font_path}")

    font = TTFont(font_path, lazy=True)
    cmap = font.getBestCmap()
    replacements = symbol_private_use_map(cmap)
    blank_glyph = cmap.get(BLANK_PRIVATE_CODEPOINT)
    if blank_glyph != BLANK_GLYPH_NAME:
        raise RuntimeError("Compatibility font does not contain its blank spacer glyph.")

    for source_codepoint, replacement_codepoint in replacements.items():
        if (
            cmap.get(replacement_codepoint) != cmap[source_codepoint]
            or cmap.get(replacement_codepoint + 1) != BLANK_GLYPH_NAME
        ):
            raise RuntimeError("Compatibility font has an unexpected symbol mapping.")

    changed_files = 0
    changed_symbols = 0
    for target_path in target_paths:
        if not target_path.is_file():
            raise RuntimeError(f"Installed application file is missing: {target_path}")

        contents = target_path.read_bytes()
        file_symbols = 0

        def repair_label_symbol(match: re.Match[bytes]) -> bytes:
            nonlocal file_symbols
            high = int.from_bytes(match.group("high"), "little")
            low = int.from_bytes(match.group("low"), "little")
            source_codepoint = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
            replacement_codepoint = replacements.get(source_codepoint)
            if replacement_codepoint is None:
                return match.group(0)

            file_symbols += 1
            return (
                chr(replacement_codepoint).encode("utf-16le")
                + chr(replacement_codepoint + 1).encode("utf-16le")
                + b"\x20\x00"
            )

        repaired = LABEL_SYMBOL_PATTERN.sub(repair_label_symbol, contents)

        if file_symbols:
            target_path.write_bytes(repaired)
            changed_files += 1
            changed_symbols += file_symbols

    if changed_symbols:
        return (
            f"Repaired {changed_symbols} label symbol(s) in "
            f"{changed_files} installed SDR Console file(s)."
        )
    return "Installed SDR Console label symbols are already repaired."


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path)
    parser.add_argument("--symbols", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--patch-symbol-labels", action="store_true")
    parser.add_argument("--font", type=Path)
    parser.add_argument("targets", type=Path, nargs="*")
    args = parser.parse_args()
    if args.patch_symbol_labels:
        if any(value is not None for value in (args.base, args.symbols, args.output)):
            parser.error("--patch-symbol-labels cannot be combined with font-build arguments")
        if not args.font or not args.targets:
            parser.error("--patch-symbol-labels requires --font and at least one target")
    elif args.font or args.targets or not all((args.base, args.symbols, args.output)):
        parser.error("--base, --symbols, and --output are required when building the font")
    return args


def main() -> None:
    args = parse_args()
    if args.patch_symbol_labels:
        print(patch_symbol_labels(args.font, args.targets))
        return
    build_font(args.base, args.symbols, args.output)
    print(f"Built {FONT_FAMILY} at {args.output}.")


if __name__ == "__main__":
    main()
