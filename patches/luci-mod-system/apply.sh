#!/bin/sh
# System page: description field label -> 标题 (brand title for login/sidebar).
set -e
ROOT="${1:-.}"
SYS="$(find "$ROOT/feeds/luci" "$ROOT/package" -path '*/view/system/system.js' -type f 2>/dev/null | head -n 1 || true)"
[ -n "$SYS" ] || { echo "system.js not found"; exit 0; }

python3 - "$SYS" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
if "form.Value, 'description', _('标题')" in t:
    print("system.js description label already 标题", p)
    raise SystemExit(0)

old = (
    "o = s.taboption('general', form.Value, 'description', _('Description'), "
    "_('An optional, short description for this device'));"
)
new = (
    "o = s.taboption('general', form.Value, 'description', _('标题'), "
    "_('登录页与侧栏显示的品牌标题，留空则显示主机名'));"
)
if old in t:
    t = t.replace(old, new, 1)
else:
    t2, n = re.subn(
        r"(s\.taboption\('general', form\.Value, 'description', _\(')[^']*('\),\s*_\(')[^']*('\)\);)",
        r"\1标题\2登录页与侧栏显示的品牌标题，留空则显示主机名\3",
        t,
        count=1,
    )
    if not n:
        print("system.js description field not found", p)
        raise SystemExit(1)
    t = t2

p.write_text(t, encoding="utf-8")
print("patched", p, "description -> 标题")
PY
