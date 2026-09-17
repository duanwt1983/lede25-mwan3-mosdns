#!/usr/bin/env python3
"""Repair mojibake without changing valid upstream LuCI punctuation."""
from pathlib import Path
import sys


def fix_text(text: str) -> str:
    # The 8.1 runtime page uses the original Unicode ellipsis and guillemet.
    # Only repair their common UTF-8-as-Latin-1 corruptions; do not normalize
    # legitimate punctuation to three dots or a slash.
    repairs = {
        "â€¦": "…",
        "â¦": "…",
        "Â»": "»",
        "âº": "›",
    }
    for bad, good in repairs.items():
        text = text.replace(bad, good)
    return text


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: fix-encoding.py <interfaces.js>", file=sys.stderr)
        return 1
    path = Path(sys.argv[1])
    if not path.is_file():
        print("missing", path, file=sys.stderr)
        return 1
    text = path.read_text(encoding="utf-8", errors="surrogateescape")
    fixed = fix_text(text)
    if fixed == text:
        print("encoding ok", path)
        return 0
    path.write_text(fixed, encoding="utf-8", newline="\n")
    print("encoding fixed", path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
