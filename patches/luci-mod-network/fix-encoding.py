#!/usr/bin/env python3
"""Avoid mojibake in minified luci-mod-network interfaces.js (ellipsis, guillemet)."""
from pathlib import Path
import re
import sys


def fix_text(text: str) -> str:
    text = text.replace("\u2026", "...")
    text = text.replace("…", "...")
    text = text.replace("+ ' » ' +", "+ ' / ' +")
    text = text.replace("' » '", "' / '")

    text = re.sub(
        r"_\('Add device configuration[^']*'\)",
        "_('Add device configuration...')",
        text,
    )
    text = re.sub(
        r"_\('Configure[^']*'\)",
        "_('Configure...')",
        text,
    )
    text = re.sub(
        r"_\('New interface name[^']*'\)",
        "_('New interface name...')",
        text,
    )
    text = re.sub(
        r"_\('Loading data[^']*'\)",
        "_('Loading data...')",
        text,
    )
    text = re.sub(
        r"return _\('Interfaces'\)\+'[^']*'\+section_id",
        "return _('Interfaces')+' / '+section_id",
        text,
    )
    text = re.sub(
        r"return _\('Interfaces'\) \+ '[^']*' \+ section_id",
        "return _('Interfaces') + ' / ' + section_id",
        text,
    )
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
