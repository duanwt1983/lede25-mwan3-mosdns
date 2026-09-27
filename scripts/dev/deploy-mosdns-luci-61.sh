#!/bin/sh
# macOS port of deploy-mosdns-luci-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-mosdns-luci-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Hot-deploy MosDNS LuCI-consistent update/apply fixes to 6.1.

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/package/mosdns-mwan/files/usr/libexec/mosdns-gen" '/usr/libexec/mosdns-gen'
router_put "$ROOT/package/mosdns-mwan/files/usr/libexec/mosdns-apply-luci" '/usr/libexec/mosdns-apply-luci'

PYPATCH=$(mktemp)
cat > "$PYPATCH" << 'END_REMOTE'
from pathlib import Path
p = Path('/usr/share/mosdns/mosdns.uc')
t = p.read_text(encoding='utf-8')
apply_fn = """
function apply_luci_config() {
	let r = exec_sys('/usr/libexec/mosdns-apply-luci');
	if (r.code != 0)
		print('apply_luci_config: ' + r.stdout + '\\n');
	stdout.flush();
}

"""
if 'function apply_luci_config(' not in t:
	t = t.replace('let action = ARGV[0];', apply_fn + 'let action = ARGV[0];', 1)
old = '\t\tupdate_geodat();\n\t\tupdate_adlist();\n\t\tv2dat_dump();\n\t\tprint("UPDATE_FINISHED\\n");'
new = '\t\tupdate_geodat();\n\t\tupdate_adlist();\n\t\tv2dat_dump();\n\t\tapply_luci_config();\n\t\tprint("UPDATE_FINISHED\\n");'
if old in t:
	t = t.replace(old, new, 1)
old_else = "\t} else {\n\t\texec_sys(`geo2txt geoip -f ${v2dat_dir}/geoip.dat -e cn -o /var/mosdns`);\n\t\texec_sys(`geo2txt geosite -f ${v2dat_dir}/geosite.dat -e cn -e 'geolocation-!cn' -o /var/mosdns`);\n\n\t\tlet geoip_tags"
new_else = "\t} else {\n\t\texec_sys(`geo2txt geoip -f ${v2dat_dir}/geoip.dat -e cn -o /var/mosdns`);\n\t\texec_sys(`geo2txt geosite -f ${v2dat_dir}/geosite.dat -e cn -e 'geolocation-!cn' -o /var/mosdns`);\n\t\tif (adblock === '1' && index(ad_source, 'geosite.dat') !== -1) {\n\t\t\texec_sys(`geo2txt geosite -f ${v2dat_dir}/geosite.dat -e category-ads-all -o /var/mosdns`);\n\t\t}\n\n\t\tlet geoip_tags"
if old_else in t:
	t = t.replace(old_else, new_else, 1)
p.write_text(t, encoding='utf-8')
print('patched mosdns.uc')
END_REMOTE
router_put "$PYPATCH" /tmp/lede-patch-1.py
rm -f "$PYPATCH"
router_sh 'python3 /tmp/lede-patch-1.py; rm -f /tmp/lede-patch-1.py'
router_print patch
router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
echo "adblock=$(uci -q get mosdns.config.adblock)"
echo "ad_source:"
uci -q get mosdns.config.ad_source 2>/dev/null
echo "enabled=$(uci -q get mosdns.config.enabled)"
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/usr/libexec/mosdns-apply-luci; echo apply_exit=$?
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
grep -A20 'tag: blocklist' /var/etc/mosdns.yaml 2>/dev/null | head -25
ls -la /etc/mosdns/rule/adlist/ 2>/dev/null | head -8
ls -la /var/mosdns/geosite_category-ads-all.txt 2>/dev/null
END_REMOTE
)"
router_print
