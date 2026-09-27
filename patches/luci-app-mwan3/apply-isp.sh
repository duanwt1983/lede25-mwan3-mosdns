#!/bin/sh
# Patch luci-app-mwan3: ISP label on interfaces; Chinese labels for ISP nft sets.
set -e
ROOT="${1:-.}"
APP="$(find "$ROOT/package" -type d -name luci-app-mwan3 | head -n 1)"
[ -n "$APP" ] || { echo "luci-app-mwan3 not found"; exit 1; }

IFACE="$(find "$APP" -path '*/view/mwan3/network/interface.js' -type f | head -n 1)"
RULE="$(find "$APP" -path '*/view/mwan3/network/rule.js' -type f | head -n 1)"

if [ -n "$IFACE" ]; then
	python3 - "$IFACE" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
if "option(form.ListValue, 'isp'" in t:
    print("interface.js already has isp")
    raise SystemExit(0)
pat = re.compile(
    r"o = s\.option\(form\.Flag, 'enabled', _\('Enabled'\)\);\r?\n[ \t]*o\.default = false;"
)
m = pat.search(t)
if not m:
    i = t.find("'enabled'")
    print("interface.js enabled flag not found", p)
    print(repr(t[max(0, i-80): i+160] if i >= 0 else t[:400]))
    raise SystemExit(1)
insert = m.group(0) + """

		o = s.option(form.ListValue, 'isp', _('运营商'),
			_('只作标注，方便对照。不会因为选了运营商就自动分流；请到规则里选目的 NFT 集（isp_chinanet / isp_unicom / isp_cmcc / isp_other）并指定策略。多条线同一家运营商时尤其不要自动分流。'));
		o.value('', _('未标注'));
		o.value('chinanet', _('中国电信'));
		o.value('unicom', _('中国联通'));
		o.value('cmcc', _('中国移动'));
		o.optional = true;
		o.rmempty = true;
"""
t = t[:m.start()] + insert + t[m.end():]
p.write_text(t, encoding="utf-8")
print("patched", p, "isp")
PY
fi

if [ -n "$RULE" ]; then
	python3 - "$RULE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
old = "_('Match destination addresses against this nft set (declare sets in /etc/config/mwan3; dnsmasq syntax: nftset=/youtube.com/4#inet#mwan3#youtube)'));"
new = "_('目的地址集合。运营商分流用 isp_chinanet（电信）、isp_unicom（联通）、isp_cmcc（移动）、isp_other（其它国内 ISP：教育网/广电/鹏博士等）。海外及未命中地址请另加一条不选目的集的兜底规则。地址库由国内源自动更新，需在本页手动添加规则。'));"
if old in t:
    t = t.replace(old, new, 1)
old2 = "const label = s_name + (family_label[nftset_info[s_name].type] || '');"
new2 = """const ispLabel = { isp_chinanet: _('中国电信地址库'), isp_unicom: _('中国联通地址库'), isp_cmcc: _('中国移动地址库'), isp_other: _('其它（教育网/广电/其它ISP）') }[s_name];
			const label = (ispLabel || s_name) + (family_label[nftset_info[s_name].type] || '');"""
if old2 in t and "ispLabel" not in t:
    t = t.replace(old2, new2)
p.write_text(t, encoding="utf-8")
print("patched", p, "rule.js")
PY
fi

# Destination NFT set dropdown: also list UCI ipset sections (not only live nft).
if [ -n "$RULE" ]; then
	python3 - "$RULE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
needle = "Object.keys(nftset_info)"
inject = """uci.sections('mwan3', 'ipset', function(sid) {
				const n = uci.get('mwan3', sid, 'name') || sid;
				if (uci.get('mwan3', sid, 'enabled') === '0')
					return;
				if (nftset_info && !nftset_info[n])
					nftset_info[n] = { type: (uci.get('mwan3', sid, 'family') === 'ipv6') ? 'ipv6_addr' : 'ipv4_addr' };
			});
			Object.keys(nftset_info || {})"""
if "uci.sections('mwan3', 'ipset'" not in t and needle in t:
    t = t.replace(needle, inject, 1)
    p.write_text(t, encoding="utf-8")
    print("patched", p, "uci ipset dropdown")
else:
    print("rule.js uci ipset merge skipped")
PY
fi

PATCH_IPSET="$(cd "$(dirname "$0")" && pwd)/patch-ipset-pages.py"
if [ -f "$PATCH_IPSET" ]; then
	python3 "$PATCH_IPSET" "$ROOT"
fi

LOCK_STOCK="$(cd "$(dirname "$0")" && pwd)/lock-stock-pages.py"
if [ -f "$LOCK_STOCK" ]; then
	python3 "$LOCK_STOCK" "$ROOT"
fi

ACL="$(find "$APP" -path '*/acl.d/*.json' -type f | head -n 1)"
if [ -n "$ACL" ]; then
	python3 - "$ACL" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
changed = False
for key, body in data.items():
    for side in ("read", "write"):
        files = body.setdefault(side, {}).setdefault("file", {})
        if "/usr/libexec/isp-ip-update" not in files:
            files["/usr/libexec/isp-ip-update"] = ["exec"]
            changed = True
        if "/bin/sh" not in files:
            files["/bin/sh"] = ["exec"]
            changed = True
        if "/etc/init.d/mwan3" not in files:
            files["/etc/init.d/mwan3"] = ["exec"]
            changed = True
        if "/usr/libexec/lede-mwan3-setup" not in files:
            files["/usr/libexec/lede-mwan3-setup"] = ["exec"]
            changed = True
        if "/usr/libexec/lede-mwan3-setup *" not in files:
            files["/usr/libexec/lede-mwan3-setup *"] = ["exec"]
            changed = True
        uci = body.setdefault(side, {}).setdefault("uci", [])
        if isinstance(uci, list) and "isp-ip" not in uci:
            uci.append("isp-ip")
            changed = True
        if isinstance(uci, list) and "mwan3" not in uci:
            uci.append("mwan3")
            changed = True
        ubus = body.setdefault(side, {}).setdefault("ubus", {})
        isp_rpc = ubus.setdefault("luci.ispip", [])
        if side == "read" and "get_update_log" not in isp_rpc:
            isp_rpc.append("get_update_log")
            changed = True
        if side == "write" and "start_update" not in isp_rpc:
            isp_rpc.append("start_update")
            changed = True
        if "/var/log/isp-ip-update.log" not in files:
            files["/var/log/isp-ip-update.log"] = ["read"]
            changed = True
        if "/var/run/isp-ip-update.status" not in files:
            files["/var/run/isp-ip-update.status"] = ["read"]
            changed = True
if changed:
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("acl isp-ip-update", p)
else:
    print("acl already has isp-ip-update")
PY
fi

CFG="$(find "$ROOT/package" -path '*/mwan3/files/etc/config/mwan3' -type f | head -n 1)"
if [ -n "$CFG" ]; then
	python3 - "$CFG" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
# Keep globals (and any ipset). Drop stock interface / member / policy / rule.
parts = re.split(r'(?=^config )', t, flags=re.M)
out = []
for b in parts:
    head = b.lstrip().split('\n', 1)[0] if b.strip() else ''
    if re.match(r"config (interface|member|policy|rule)\b", head):
        continue
    out.append(b)
t = ''.join(out).rstrip() + '\n'
p.write_text(t, encoding="utf-8")
print("stripped default mwan3 interface/member/policy/rule", p)
PY
fi

ZH="$(cd "$(dirname "$0")" && pwd)/zh.py"
if [ -f "$ZH" ]; then
	for rel in \
		'*/view/mwan3/network/simulator.js' \
		'*/menu.d/luci-app-mwan3.json'
	do
		f="$(find "$APP" -path "$rel" | head -n 1)"
		if [ -n "$f" ] && [ -f "$f" ]; then
			python3 "$ZH" "$f"
		fi
	done
fi

MENU="$(find "$APP" -path '*/menu.d/luci-app-mwan3.json' -type f | head -n 1)"
if [ -n "$MENU" ]; then
	python3 - "$MENU" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))
key = "admin/network/mwan3/globals"
if key in data:
    data[key]["title"] = "自动配置"
    p.write_text(json.dumps(data, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print("menu globals tab -> 自动配置", p)
PY
fi

TAB_OVR="$(cd "$(dirname "$0")/../.." && pwd)/files/usr/share/luci/menu.d/zzz-luci-mwan3-tab.json"
if [ -f "$TAB_OVR" ]; then
	mkdir -p "$APP/root/usr/share/luci/menu.d"
	cp "$TAB_OVR" "$APP/root/usr/share/luci/menu.d/zzz-luci-mwan3-tab.json"
	echo "menu override: zzz-luci-mwan3-tab.json"
fi

# ISP address library page + RPC (also in files/ overlay; copy into package for compile self-check).
FILES_OVR="$(cd "$(dirname "$0")/../.." && pwd)/files"
PKG_ROOT="$APP/root"
[ -d "$PKG_ROOT" ] || PKG_ROOT="$APP"
HTDOCS="$APP/htdocs/luci-static/resources/view/mwan3"
[ -d "$APP/htdocs" ] || HTDOCS="$PKG_ROOT/www/luci-static/resources/view/mwan3"
for rel in \
	usr/share/luci/menu.d/luci-mwan3-isp.json \
	usr/share/rpcd/acl.d/luci-mwan3-isp.json \
	usr/share/rpcd/ucode/luci.isp-ip.uc
do
	src="$FILES_OVR/$rel"
	[ -f "$src" ] || continue
	dst="$PKG_ROOT/$rel"
	mkdir -p "$(dirname "$dst")"
	cp "$src" "$dst"
	echo "isp bundle: $rel"
done
if [ -f "$FILES_OVR/www/luci-static/resources/view/mwan3/ispupdate.js" ]; then
	mkdir -p "$HTDOCS"
	cp "$FILES_OVR/www/luci-static/resources/view/mwan3/ispupdate.js" "$HTDOCS/ispupdate.js"
	echo "isp bundle: ispupdate.js"
fi
