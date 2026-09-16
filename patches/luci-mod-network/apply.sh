#!/bin/sh
# Fold full-IP DHCP fields into br-lan's existing DHCP Server tab.
set -e
ROOT="${1:-.}"
SRC="$(cd "$(dirname "$0")" && pwd)"

IFACE="$(find "$ROOT/feeds/luci" "$ROOT/package" -path '*/view/network/interfaces.js' -type f 2>/dev/null | head -n 1 || true)"
[ -n "$IFACE" ] || { echo "interfaces.js not found"; exit 1; }

python3 - "$IFACE" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")

if "view.network.iface-dhcp-extra" not in t:
    if "'require network';" in t:
        t = t.replace(
            "'require network';",
            "'require network';\n'require view.network.iface-dhcp-extra as dhcpExtra';\n'require view.network.iface-bw-extra as bwExtra';",
            1,
        )
    else:
        raise SystemExit("require network not found in interfaces.js")
elif "view.network.iface-bw-extra" not in t:
    t = t.replace(
        "'require view.network.iface-dhcp-extra as dhcpExtra';",
        "'require view.network.iface-dhcp-extra as dhcpExtra';\n'require view.network.iface-bw-extra as bwExtra';",
        1,
    )

# Interface modal uses `s`; DHCP subsection uses `ss`. Attach after protocol
# options so bandwidth fields appear at the end of the general tab.
t = re.sub(
    r"\s*if \(typeof bwExtra != 'undefined' && bwExtra\.attach\)\n"
    r"\s*bwExtra\.attach\(s, ifc\);\n",
    "\n",
    t,
    count=1,
)
if "bwExtra.attach" not in t:
    t2, n = re.subn(
        r"(ifc\.renderFormOptions\(s\);\s*)",
        r"\1\n\t\t\t\t\tif (typeof bwExtra != 'undefined' && bwExtra.attach)\n"
        r"\t\t\t\t\t\tbwExtra.attach(s, ifc);\n",
        t,
        count=1,
    )
    if n:
        t = t2
if "bwExtra.attach" not in t:
    raise SystemExit("failed to attach bwExtra after renderFormOptions")

if "dhcpExtra.attach" not in t:
    # Do not add stock Start/Limit widgets at all. Hiding after create is
    # ignored by some LuCI/Argon renders, so the 起始/限制 fields stay.
    t = re.sub(
        r"so = ss\.taboption\('ipv4', form\.Value, 'start'[\s\S]*?so\.default = '100';",
        "/* stock DHCP start omitted */\n",
        t,
        count=1,
    )
    t = re.sub(
        r"so = ss\.taboption\('ipv4', form\.Value, 'limit'[\s\S]*?so\.default = '150';",
        "/* stock DHCP limit omitted */\n"
        "\t\t\t\t\tif (typeof dhcpExtra != 'undefined' && dhcpExtra.attach)\n"
        "\t\t\t\t\t\tdhcpExtra.attach(ss, ifc);\n",
        t,
        count=1,
    )
    if "dhcpExtra.attach" not in t:
        raise SystemExit("failed to strip dhcp start/limit")


if "lan-dhcp-apply" not in t:
    old = "return view.extend({"
    if old not in t:
        raise SystemExit("view.extend not found")
    t = t.replace(
        old,
        old
        + """
	handleSaveApply(ev, mode) {
		return this.super('handleSaveApply', [ev, mode]).then(function() {
			return fs.exec('/usr/libexec/lan-dhcp-apply', [ 'reload' ]).catch(function() {});
		});
	},
""",
        1,
    )

p.write_text(t, encoding="utf-8")
print("patched", p)
PY

ACL="$(find "$ROOT/feeds/luci" "$ROOT/package" -path '*/acl.d/luci-mod-network.json' -type f 2>/dev/null | head -n 1 || true)"
if [ -n "$ACL" ]; then
	python3 - "$ACL" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
key = next(iter(data))
write = data[key].setdefault("write", {})
files = write.setdefault("file", {})
files["/usr/libexec/lan-dhcp-apply"] = ["exec"]
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("acl:", p)
PY
fi

DIAG="$(find "$ROOT/feeds/luci" "$ROOT/package" -path '*/view/network/diagnostics.js' -type f 2>/dev/null | head -n 1 || true)"
if [ -n "$DIAG" ]; then
	python3 - "$DIAG" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t2 = t.replace("openwrt.org", "baidu.com")
if t2 != t:
    p.write_text(t2, encoding="utf-8")
    print("diagnostics.js default host -> baidu.com", p)
else:
    print("diagnostics.js: no openwrt.org to replace", p)
PY
fi

LUCICFG="$(find "$ROOT/feeds/luci" "$ROOT/package" -path '*/etc/config/luci' -type f 2>/dev/null | head -n 1 || true)"
if [ -n "$LUCICFG" ]; then
	python3 - "$LUCICFG" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t2 = t.replace("openwrt.org", "baidu.com")
if t2 != t:
    p.write_text(t2, encoding="utf-8")
    print("luci config diag host -> baidu.com", p)
else:
    print("luci config: no openwrt.org to replace", p)
PY
fi
