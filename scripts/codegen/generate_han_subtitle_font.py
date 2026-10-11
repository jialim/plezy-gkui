#!/usr/bin/env python3
"""Generate assets/go-noto-current-han.ttf, the Chinese companion of the
subtitle font assets/go-noto-current-regular.ttf.

Why a companion file exists
---------------------------
Go Noto Current-Regular covers 11928 CJK Unified Ideographs, which leaves
827 of the 6763 GB2312 hanzi (for example 诶, 诨, 诓, 谘), 4941 of the 13302
Big5 characters and 8974 of the 20902 GBK hanzi without a glyph. The Android
libmpv build has no system-font fallback, so those characters rendered as
empty boxes in Chinese subtitles. The primary is near the 65535-glyph limit,
so the missing hanzi ship as a second file, the same way the Hangul companion
does (see scripts/codegen/generate_hangul_subtitle_font.py for how libass
picks glyphs across files of one family).

Source: Noto Sans SC Regular (SIL Open Font License 1.1), as shipped in the
npm package @expo-google-fonts/noto-sans-sc 0.4.4,
400Regular/NotoSansSC_400Regular.ttf (sha256
d45f67f0a7c0ca3f256950777ce6a61cc7ce5f9696d02900cbbaac25f8aa7d16).
The OFL lets modified versions be bundled under a name other than the
Reserved Font Name ("Source"); this file is renamed to the primary's family.

Coverage rule
-------------
The companion's cmap is ``(GBK ∪ GB2312 ∪ Big5 hanzi) ∩ cmap(source) −
cmap(primary) − cmap(Hangul companion)``, so no two files of the family ever
compete for a codepoint. Hinting is dropped: subtitles render large, and the
file stays about 3.3 MB.

Usage
-----
    python3 scripts/codegen/generate_han_subtitle_font.py --source NotoSansSC_400Regular.ttf
    python3 scripts/codegen/generate_han_subtitle_font.py --check

Requires fontTools. The default ``--source`` is the committed companion, so
regeneration from it is offline and reproducible.
"""

from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]
PRIMARY_PATH = ROOT / "assets/go-noto-current-regular.ttf"
HANGUL_PATH = ROOT / "assets/go-noto-kurrent-hangul.ttf"
HAN_PATH = ROOT / "assets/go-noto-current-han.ttf"

# Byte-identical to SubtitleFontLoader.fontName (lib/mpv/font_loader.dart).
FAMILY = "Go Noto Current-Regular"
SUBFAMILY = "Regular"
FULL_NAME = "Go Noto Current-Regular Han"
POSTSCRIPT_NAME = "GoNotoCurrent-Regular-Han"

NAME_ID_FAMILY = 1
NAME_ID_SUBFAMILY = 2
NAME_ID_UNIQUE = 3
NAME_ID_FULL = 4
NAME_ID_POSTSCRIPT = 6
NAME_ID_TYPO_FAMILY = 16
NAME_ID_TYPO_SUBFAMILY = 17
PLATFORM_MICROSOFT = 3
MAX_GLYPHS = 65535

OS2_WEIGHT_REGULAR = 400
OS2_WIDTH_MEDIUM = 5
FS_SELECTION_ITALIC = 1 << 0
FS_SELECTION_BOLD = 1 << 5
FS_SELECTION_REGULAR = 1 << 6
FS_SELECTION_OBLIQUE = 1 << 9


def load(path: Path) -> TTFont:
    return TTFont(io.BytesIO(path.read_bytes()), recalcTimestamp=False)


def double_byte_set(encoding: str, leads: range, trails: list[int]) -> set[int]:
    result = set()
    for lead in leads:
        for trail in trails:
            try:
                text = bytes([lead, trail]).decode(encoding)
            except UnicodeDecodeError:
                continue
            if len(text) == 1:
                result.add(ord(text))
    return result


def is_han(codepoint: int) -> bool:
    return 0x3400 <= codepoint <= 0x4DBF or 0x4E00 <= codepoint <= 0x9FFF or 0xF900 <= codepoint <= 0xFAFF


def wanted_hanzi() -> set[int]:
    gb2312 = double_byte_set("gb2312", range(0xB0, 0xF8), list(range(0xA1, 0xFF)))
    big5 = double_byte_set("big5", range(0xA4, 0xFA), list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)))
    gbk = double_byte_set("gbk", range(0x81, 0xFF), list(range(0x40, 0xFF)))
    return {cp for cp in gb2312 | big5 | gbk if is_han(cp)}


def name_records(font: TTFont, name_id: int) -> dict[tuple[int, int, int], str]:
    return {
        (r.platformID, r.platEncID, r.langID): r.toUnicode()
        for r in font["name"].names
        if r.nameID == name_id
    }


def rewrite_names(font: TTFont) -> None:
    table = font["name"]
    keys = {(r.platformID, r.platEncID, r.langID) for r in table.names}
    table.names = [r for r in table.names if r.nameID not in (NAME_ID_TYPO_FAMILY, NAME_ID_TYPO_SUBFAMILY)]
    unique = name_records(font, NAME_ID_UNIQUE)
    for platform_id, enc_id, lang_id in sorted(keys):
        table.setName(FAMILY, NAME_ID_FAMILY, platform_id, enc_id, lang_id)
        table.setName(SUBFAMILY, NAME_ID_SUBFAMILY, platform_id, enc_id, lang_id)
        table.setName(FULL_NAME, NAME_ID_FULL, platform_id, enc_id, lang_id)
        table.setName(POSTSCRIPT_NAME, NAME_ID_POSTSCRIPT, platform_id, enc_id, lang_id)
        old_unique = unique.get((platform_id, enc_id, lang_id))
        if old_unique is not None and ";" in old_unique:
            prefix = old_unique.rsplit(";", 1)[0]
            table.setName(f"{prefix};{POSTSCRIPT_NAME}", NAME_ID_UNIQUE, platform_id, enc_id, lang_id)


def force_regular_attributes(font: TTFont) -> None:
    os2 = font["OS/2"]
    os2.usWeightClass = OS2_WEIGHT_REGULAR
    os2.usWidthClass = OS2_WIDTH_MEDIUM
    os2.fsSelection &= ~(FS_SELECTION_ITALIC | FS_SELECTION_BOLD | FS_SELECTION_OBLIQUE)
    os2.fsSelection |= FS_SELECTION_REGULAR
    font["head"].macStyle = 0


def generate(source: Path, output: Path) -> None:
    font = load(source)
    taken = load(PRIMARY_PATH).getBestCmap().keys() | load(HANGUL_PATH).getBestCmap().keys()
    unicodes = sorted((wanted_hanzi() & font.getBestCmap().keys()) - taken)
    options = Options()
    options.layout_features = []
    options.hinting = False
    options.notdef_outline = True
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    subsetter = Subsetter(options=options)
    subsetter.populate(unicodes=unicodes)
    subsetter.subset(font)
    rewrite_names(font)
    force_regular_attributes(font)
    font.save(output)
    print(f"wrote {output} ({output.stat().st_size} bytes, {len(unicodes)} codepoints)")


def check(han: Path) -> int:
    han_font = load(han)
    primary_font = load(PRIMARY_PATH)
    hangul_font = load(HANGUL_PATH)
    failures: list[str] = []

    def require(ok: bool, message: str) -> None:
        print(f"  [{'ok' if ok else 'FAIL'}] {message}")
        if not ok:
            failures.append(message)

    families = name_records(han_font, NAME_ID_FAMILY)
    require(any(k[0] == PLATFORM_MICROSOFT for k in families), "has a Microsoft-platform family name")
    for key, family in sorted(families.items()):
        require(family == FAMILY, f"family {key} == {FAMILY!r} (got {family!r})")
    han_cmap = han_font.getBestCmap().keys()
    for label, other in (("primary", primary_font), ("hangul", hangul_font)):
        overlap = sorted(han_cmap & other.getBestCmap().keys())
        require(not overlap, f"cmap disjoint from {label} (overlap {len(overlap)})")
    covered = primary_font.getBestCmap().keys() | han_cmap
    for char in "诶诨诓谘":
        require(ord(char) in covered, f"{char} U+{ord(char):04X} is covered")
    gb2312 = {cp for cp in double_byte_set("gb2312", range(0xB0, 0xF8), list(range(0xA1, 0xFF))) if is_han(cp)}
    missing = sorted(gb2312 - covered)
    require(not missing, f"all {len(gb2312)} GB2312 hanzi covered (missing {len(missing)})")
    require(len(han_font.getGlyphOrder()) <= MAX_GLYPHS, "glyph count within the TrueType limit")
    os2 = han_font["OS/2"]
    require(os2.usWeightClass == OS2_WEIGHT_REGULAR and os2.usWidthClass == OS2_WIDTH_MEDIUM, "regular weight and width")
    require(han_font["head"].macStyle == 0, "head.macStyle 0")
    if failures:
        print(f"{len(failures)} invariant(s) violated", file=sys.stderr)
        return 1
    print("all invariants hold")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--source", type=Path, default=HAN_PATH, help="NotoSansSC Regular or an existing companion")
    parser.add_argument("--output", type=Path, default=HAN_PATH)
    parser.add_argument("--check", action="store_true", help="verify --output instead of generating")
    args = parser.parse_args()
    if args.check:
        return check(args.output)
    generate(args.source, args.output)
    return check(args.output)


if __name__ == "__main__":
    sys.exit(main())
