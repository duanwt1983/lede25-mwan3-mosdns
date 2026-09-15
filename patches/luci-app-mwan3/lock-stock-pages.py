# -*- coding: utf-8 -*-
"""Disable Add / Edit / Remove on mwan3 interface, member, policy, rule pages."""
from pathlib import Path
import sys

MARKER = "s.renderRowActions=function(){return E('td',{'class':'td'});};"


def lock(text):
    orig = text
    text = text.replace("s.addremove = true", "s.addremove = false")
    text = text.replace("s.addremove=true", "s.addremove=false")
    if MARKER not in text:
        if "s.nodescriptions=true;" in text:
            text = text.replace(
                "s.nodescriptions=true;",
                "s.nodescriptions=true;" + MARKER,
                1,
            )
        elif "s.nodescriptions = true;" in text:
            text = text.replace(
                "s.nodescriptions = true;",
                "s.nodescriptions = true;\n\t\t" + MARKER,
                1,
            )
    return text, text != orig


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    app = next((p for p in root.glob("package/**/luci-app-mwan3") if p.is_dir()), None)
    if not app:
        print("luci-app-mwan3 not found")
        return 0
    n = 0
    for name in ("interface.js", "member.js", "policy.js", "rule.js"):
        hits = list(app.glob("**/view/mwan3/network/" + name))
        if not hits:
            print("skip missing", name)
            continue
        p = hits[0]
        t, ch = lock(p.read_text(encoding="utf-8"))
        if ch:
            p.write_text(t, encoding="utf-8")
            print("locked", p)
            n += 1
        else:
            print("already locked", p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
