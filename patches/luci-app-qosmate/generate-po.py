#!/usr/bin/env python3
"""Generate po/zh_Hans/qosmate.po for luci-app-qosmate with Simplified Chinese."""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def escape_po(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def unescape_po(s: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt == "n":
                out.append("\n")
                i += 2
                continue
            if nxt == '"':
                out.append('"')
                i += 2
                continue
            if nxt == "\\":
                out.append("\\")
                i += 2
                continue
        out.append(s[i])
        i += 1
    return "".join(out)


def parse_po(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8", errors="replace")
    entries: dict[str, str] = {}
    msgid: str | None = None
    msgstr_lines: list[str] = []
    in_msgstr = False

    def flush() -> None:
        nonlocal msgid, msgstr_lines, in_msgstr
        if msgid is not None:
            entries[msgid] = unescape_po("".join(msgstr_lines))
        msgid = None
        msgstr_lines = []
        in_msgstr = False

    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("msgid "):
            flush()
            msgid = unescape_po(line[7:-1].strip('"'))
        elif line.startswith("msgstr ") and msgid is not None:
            in_msgstr = True
            msgstr_lines = [line[8:-1].strip('"')]
        elif in_msgstr and line.startswith('"') and line.endswith('"'):
            msgstr_lines.append(line[1:-1])
        elif not line or line.startswith("#"):
            continue
        else:
            flush()

    flush()
    return entries


def collect_strings(pkg: Path) -> set[str]:
    strings: set[str] = set()
    view_dir = pkg / "htdocs/luci-static/resources/view"
    if view_dir.is_dir():
        for js in view_dir.rglob("*.js"):
            text = js.read_text(encoding="utf-8", errors="replace")
            for m in re.finditer(r"_\(\s*'((?:\\'|[^'])*)'\s*\)", text):
                strings.add(m.group(1).replace("\\'", "'"))
            for m in re.finditer(r'_\(\s*"((?:\\"|[^"])*)"\s*\)', text):
                strings.add(m.group(1).replace('\\"', '"'))

    for menu in pkg.rglob("menu.d/*.json"):
        try:
            data = json.loads(menu.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict):
            for item in data.values():
                if isinstance(item, dict) and isinstance(item.get("title"), str):
                    strings.add(item["title"])
    return strings


def po_header() -> str:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M+0000")
    return (
        'msgid ""\n'
        'msgstr ""\n'
        f'"Project-Id-Version: luci-app-qosmate\\n"\n'
        f'"Report-Msgid-Bugs-To: \\n"\n'
        f'"POT-Creation-Date: {now}\\n"\n'
        f'"PO-Revision-Date: {now}\\n"\n'
        '"Last-Translator: \\n"\n'
        '"Language-Team: Chinese (Simplified)\\n"\n'
        '"Language: zh_CN\\n"\n'
        '"MIME-Version: 1.0\\n"\n'
        '"Content-Type: text/plain; charset=UTF-8\\n"\n'
        '"Content-Transfer-Encoding: 8bit\\n"\n'
        '"Plural-Forms: nplurals=1; plural=0;\\n"\n'
        "\n"
    )


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <package/luci-app-qosmate>", file=sys.stderr)
        return 2

    pkg = Path(sys.argv[1]).resolve()
    if not pkg.is_dir():
        print(f"Package path not found: {pkg}", file=sys.stderr)
        return 1

    patch_dir = Path(__file__).resolve().parent
    extra_path = patch_dir / "zh-cn-extra.json"
    upstream_po = pkg / "po/zh_Hans/qosmate.po"
    out_po = upstream_po

    strings = collect_strings(pkg)
    upstream = parse_po(upstream_po) if upstream_po.is_file() else {}
    extra: dict[str, str] = {}
    if extra_path.is_file():
        extra = json.loads(extra_path.read_text(encoding="utf-8"))

    merged: dict[str, str] = {}
    for msgid in sorted(strings, key=lambda s: (s.lower(), s)):
        if msgid in extra and extra[msgid]:
            merged[msgid] = extra[msgid]
        elif msgid in upstream and upstream[msgid]:
            merged[msgid] = upstream[msgid]
        else:
            merged[msgid] = msgid

    out_po.parent.mkdir(parents=True, exist_ok=True)
    parts = [po_header()]
    for msgid, msgstr in merged.items():
        parts.append(f'msgid "{escape_po(msgid)}"\n')
        parts.append(f'msgstr "{escape_po(msgstr)}"\n')
        parts.append("\n")

    out_po.write_text("".join(parts), encoding="utf-8")
    print(
        f"Wrote {out_po}: {len(merged)} entries "
        f"(extra={sum(1 for s in strings if s in extra)}, "
        f"upstream={sum(1 for s in strings if s in upstream and s not in extra)}, "
        f"fallback={sum(1 for s in strings if s not in extra and s not in upstream)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
