#!/bin/sh
# Run from OpenWrt tree after luci-app-mosdns is cloned.
set -e
ROOT="${1:-.}"
SRC="$(cd "$(dirname "$0")" && pwd)"

MOSDNS_PKG="$(find "$ROOT/package" -type d -name luci-app-mosdns | head -n 1)"
[ -n "$MOSDNS_PKG" ] || { echo "luci-app-mosdns package not found"; exit 1; }

# Repo layout: luci-app-mosdns/luci-app-mosdns/... or flattened.
APP="$MOSDNS_PKG"
if [ -d "$MOSDNS_PKG/luci-app-mosdns" ]; then
	APP="$MOSDNS_PKG/luci-app-mosdns"
fi

YAML_DST=""
if [ -d "$APP/root/etc/mosdns" ]; then
	YAML_DST="$APP/root/etc/mosdns/config_custom.yaml"
elif [ -d "$APP/files/etc/mosdns" ]; then
	YAML_DST="$APP/files/etc/mosdns/config_custom.yaml"
fi
if [ -n "$YAML_DST" ] && [ -f "$SRC/../mosdns/config_custom.yaml" ]; then
	cp "$SRC/../mosdns/config_custom.yaml" "$YAML_DST"
	echo "installed $YAML_DST"
fi

# mosdns-mwan owns /usr/share/mosdns/gen-config-custom. A second copy
# in luci-app-mosdns makes opkg fail at package/install.
rm -f "$APP/root/usr/share/mosdns/gen-config-custom" \
	"$APP/files/usr/share/mosdns/gen-config-custom"
echo "dropped luci-app-mosdns gen-config-custom (provided by mosdns-mwan)"

VIEW="$APP/htdocs/luci-static/resources/view/mosdns"
if [ -d "$VIEW" ] && [ -f "$SRC/custom.js" ]; then
	cp "$SRC/custom.js" "$VIEW/custom.js"
	echo "installed custom.js"
fi
if [ -f "$VIEW/logs.js" ]; then
	python3 - "$VIEW/logs.js" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
old = "logTextarea.value=res.log||_('No log data.');"
new = "logTextarea.value=res.log||res.error||_('No log data.');"
if old in t:
    p.write_text(t.replace(old, new, 1), encoding="utf-8")
    print("patched logs.js missing-file message")
PY
fi

MENU="$APP/root/usr/share/luci/menu.d/luci-app-mosdns.json"
if [ -f "$MENU" ]; then
	python3 - "$MENU" <<'PY'
import json, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as f:
    data = json.load(f)
if data.pop("admin/services/mosdns/custom", None) is not None:
    print("menu: removed standalone Custom Config")
with open(p, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
fi

RPCD="$(find "$APP" -name luci.mosdns -type f | head -n 1)"
if [ -n "$RPCD" ]; then
	python3 - "$RPCD" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
fn = '''
function get_api_port() {
	let uci_cursor = cursor();
	uci_cursor.load('mosdns');
	let configfile = uci_cursor.get('mosdns', 'config', 'configfile');
	if (configfile && configfile != '/var/etc/mosdns.yaml' && configfile != '/var/etc/mosdns.json') {
		let content = readfile(configfile);
		if (content) {
			let m = match(content, /http:\\s*["']?[^"'\\s]+:([0-9]+)/);
			if (m && m[1])
				return m[1];
		}
	}
	return uci_cursor.get('mosdns', 'config', 'listen_port_api') || '9091';
}

'''
if "function get_api_port(" not in t:
    needle = "function call_mosdns_api(endpoint, method) {"
    if needle not in t:
        raise SystemExit("call_mosdns_api not found")
    t = t.replace(needle, fn + needle, 1)
t = t.replace(
    "let port = uci_cursor.get('mosdns', 'config', 'listen_port_api') || '9091';",
    "let port = get_api_port();",
)
old_flush = 'let res = exec_sys(`wget -q -O - "http://127.0.0.1:${port}/plugins/lazy_cache/flush"`);'
new_flush = '''let ok = false;
			let tags = [ "lazy_cache", "lazy_cache_w1", "lazy_cache_w2", "lazy_cache_w3", "lazy_cache_w4" ];
			for (let i = 0; i < length(tags); i++) {
				let res = exec_sys(`wget -q -O - "http://127.0.0.1:${port}/plugins/${tags[i]}/flush"`);
				if (res.code === 0)
					ok = true;
			}
			let res = { code: ok ? 0 : 1, stdout: "" };'''
if old_flush in t:
    t = t.replace(old_flush, new_flush, 1)
t = t.replace(
    "if (configfile && configfile != '/var/etc/mosdns.json') {",
    "if (configfile && configfile != '/var/etc/mosdns.yaml' && configfile != '/var/etc/mosdns.json') {",
)
p.write_text(t, encoding="utf-8")
print("patched", p)
PY
fi

RULES="$(find "$APP" -path '*/view/mosdns/rules.js' | head -n 1)"
if [ -n "$RULES" ]; then
	python3 - "$RULES" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = t.replace(
    "The list of rules only apply to \\'Default Config\\' profiles.",
    "Whitelist, blocklist, greylist, hosts, redirect and PTR are applied by MosDNS.",
    1,
)
if "hideMosRule" not in t:
    t = t.replace(
        "const rules = [",
        "const hideMosRule = { ddnslist: 1, streamingmedialist: 1 };\n"
        "\t\tconst rules = [",
        1,
    )
    t = t.replace(
        "rules.forEach(rule => {",
        "rules.filter(rule => !hideMosRule[rule.name]).forEach(rule => {",
        1,
    )
p.write_text(t, encoding="utf-8")
print("patched rules.js")
PY
fi

STATS="$(find "$APP" -path '*/view/mosdns/statistics.js' | head -n 1)"
if [ -n "$STATS" ]; then
	python3 - "$STATS" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
t = t.replace("_('Top Blocked Domains')", "_('解析失败（超时/无应答）')")
p.write_text(t, encoding="utf-8")
print("patched statistics.js blocked label", p)
PY
fi

BASIC="$(find "$APP" -path '*/view/mosdns/basic.js' | head -n 1)"
if [ -n "$BASIC" ]; then
	python3 - "$BASIC" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
if "view.mosdns.custom" not in t:
    t = t.replace("'require view';", "'require view';\n'require view.mosdns.custom as mosCustom';", 1)
t = re.sub(
    r"return Promise\.all\(\[\s*L\.resolveDefault\(callMosdns\(\), null\),?\s*\]\);",
    "return Promise.all([\n\t\tL.resolveDefault(callMosdns(), null),\n\t\tuci.load('network'),\n\t\tuci.load('mwan3').catch(() => null),\n\t]);",
    t,
    count=1,
)
t = re.sub(
    r"o\.value\('/var/etc/mosdns\.json',\s*_\('Default Config'\)\);",
    "o.value('/var/etc/mosdns.yaml', _('自定义规则（自动生成）'));",
    t,
    count=1,
)
t = re.sub(
    r"\n\t\to\.value\('/etc/mosdns/config_custom\.yaml',\s*_\('Custom Config'\)\);",
    "",
    t,
    count=1,
)
t = re.sub(
    r"(o = s\.taboption\('basic', form\.ListValue, 'configfile', _\('Config File'\)\);[\s\S]*?o\.rmempty = false;)",
    r"\1\n\t\to.readonly = true;\n\t\to.hidden = true;",
    t,
    count=1,
)
t = re.sub(r"o\.default = 52001;", "o.default = 9091;", t)
t = re.sub(
    r"o = s\.taboption\('basic', form\.Flag, 'custom_local_dns', _\('Custom China DNS'\)[^\n]*\n\t\to\.depends\('configfile', '/var/etc/mosdns\.json'\);\n\t\to\.default = false;",
    "o = s.taboption('basic', form.Flag, 'custom_local_dns', _('Custom China DNS'));\n\t\to.default = true;\n\t\to.readonly = true;\n\t\to.hidden = true;",
    t,
    count=1,
)
t = re.sub(
    r"\n\t\to\.depends\('configfile', '/etc/mosdns/config_custom\.yaml'\);",
    "",
    t,
)
t = re.sub(
    r"/\* configuration \*/\s*let configeditor = null;[\s\S]*?},\s*600\);",
    "/* yaml editor removed; runtime config is generated */",
    t,
    count=1,
)
t2, n = re.subn(
    r"o = s\.taboption\('basic', form\.TextValue, '_custom'[\s\S]*?\n\t\t\};\n\n",
    "/* custom yaml editor removed */\n\n",
    t,
    count=1,
)
if n == 1:
    t = t2
    print("patched basic.js yaml editor")
else:
    print("basic.js yaml editor: not replaced (n=%s)" % n)
if "mosCustom.attach" not in t:
    t = t.replace("return m.render();", "try { mosCustom.attach(m); } catch (e) {}\n\t\treturn m.render();", 1)
t = t.replace("/var/etc/mosdns.json", "/var/etc/mosdns.yaml")
p.write_text(t, encoding="utf-8")
print("patched basic.js form hook")
PY
fi

INIT="$(find "$APP" -path '*/init.d/mosdns' -type f | head -n 1)"
if [ -n "$INIT" ]; then
	python3 - "$INIT" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
# Runtime file is always YAML. UCI is the single source; migrate leftover .json.
t = t.replace(
    "CONF=$(uci -q get mosdns.config.configfile)",
    'CONF=$(uci -q get mosdns.config.configfile)\n'
    '\t[ "$CONF" = "/var/etc/mosdns.json" ] && CONF=/var/etc/mosdns.yaml\n'
    '\t[ -n "$CONF" ] || CONF=/var/etc/mosdns.yaml',
    1,
)
if t.startswith("CONF=/var/etc/mosdns.yaml") or "\nCONF=/var/etc/mosdns.yaml" in t:
    t = t.replace(
        "CONF=/var/etc/mosdns.yaml",
        'CONF=$(uci -q get mosdns.config.configfile)\n'
        '\t[ "$CONF" = "/var/etc/mosdns.json" ] && CONF=/var/etc/mosdns.yaml\n'
        '\t[ -n "$CONF" ] || CONF=/var/etc/mosdns.yaml',
        1,
    )
old = '[ "${CONF}" = "/var/etc/mosdns.json" ] && generate_config'
new = (
    "[ -x /usr/share/mosdns/gen-config-custom ] && /usr/share/mosdns/gen-config-custom; "
    "[ -x /usr/sbin/wan-src-hash ] && /usr/sbin/wan-src-hash; true\n"
    "\t# " + old
)
# Section type may be mosdns (LuCI) or config (stock /etc/config/mosdns).
cfg_load = 'config_foreach get_config "mosdns"\n\tconfig_foreach get_config "config"'
if 'config_foreach get_config "config"' not in t:
    t = t.replace(
        'config_foreach get_config "mosdns"',
        cfg_load,
        1,
    )
    print("init.d mosdns: load config section type too")
stop_old = (
    'stop_service() {\n'
    '\tconfig_load "mosdns"\n'
    '\tconfig_foreach get_config "mosdns"'
)
if stop_old in t and 'stop_service() {\n\tconfig_load "mosdns"\n\tconfig_foreach get_config "mosdns"\n\tconfig_foreach get_config "config"' not in t:
    t = t.replace(stop_old, stop_old + '\n\tconfig_foreach get_config "config"', 1)
    print("init.d mosdns: stop_service loads config section")
server_line = 'uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#${listen_port:-5335}"'
t, server_dups = re.subn(
    r'(\n[ \t]*' + re.escape(server_line) + r')(?:\n[ \t]*' + re.escape(server_line) + r')+',
    r'\1',
    t,
)
if server_dups:
    print("init.d mosdns: dedupe dhcp forward entry")
t = re.sub(
    r'(\n[ \t]*config_foreach get_config "config")(?:\n[ \t]*config_foreach get_config "config")+',
    r'\1',
    t,
)
stale = (
    '\t# Ensure stale daemon does not block listen ports (do not use killall mosdns: it matches init script too).\n'
    '\tfor _p in $(pidof mosdns); do\n'
    '\t\t[ -x "/proc/${_p}/exe" ] || continue\n'
    '\t\t[ "$(readlink "/proc/${_p}/exe" 2>/dev/null)" = "/usr/bin/mosdns" ] && kill "${_p}" 2>/dev/null\n'
    '\tdone\n'
    '\tsleep 1\n\n'
    '\tprocd_open_instance mosdns'
)
if 'do not use killall mosdns' not in t:
    t = t.replace('\tprocd_open_instance mosdns', stale, 1)
    print("init.d mosdns: stale daemon cleanup before procd")
# YAML also listens on :5301 (WAN hash). Always forward dnsmasq to MosDNS listen_port.
needle = 'uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#$(awk'
if '127.0.0.1#${listen_port:-5335}"' not in t and needle in t:
    t = t.replace(
        needle,
        'uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#${listen_port:-5335}"\n\t\t# ' + needle,
        1,
    )
    print("init.d mosdns: dhcp forward uses listen_port")
if "mkdir -p /var/log" not in t:
    t = t.replace(
        "\trm -rf /tmp/log/mosdns*\n",
        "\trm -rf /tmp/log/mosdns*\n"
        "\tmkdir -p /var/log /etc/mosdns\n"
        '\t: > "${log_file:-/var/log/mosdns.log}"\n'
        "\t[ -s /etc/mosdns/cache.dump ] || { [ -f /usr/share/mosdns/cache.dump ] && cp -a /usr/share/mosdns/cache.dump /etc/mosdns/cache.dump; }\n",
        1,
    )
    print("init.d mosdns: keep log/cache dump files")
if "gen-config-custom" not in t and old in t:
    t = t.replace(old, new, 1)
    print("patched generator hook", p)
elif "gen-config-custom" in t:
    if "wan-src-hash" not in t:
        t = t.replace(
            "[ -x /usr/share/mosdns/gen-config-custom ] && /usr/share/mosdns/gen-config-custom",
            "[ -x /usr/share/mosdns/gen-config-custom ] && /usr/share/mosdns/gen-config-custom; "
            "[ -x /usr/sbin/wan-src-hash ] && /usr/sbin/wan-src-hash",
            1,
        )
        print("init.d mosdns: added wan-src-hash")
    print("init.d mosdns: generator hooked")
else:
    print("init.d mosdns: generate_config line not found")
p.write_text(t, encoding="utf-8")
PY
fi
