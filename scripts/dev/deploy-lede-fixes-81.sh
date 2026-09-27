#!/bin/sh
# macOS port of deploy-lede-fixes-81.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-lede-fixes-81.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Hot-deploy mwan3 quality, MosDNS LuCI apply, Samba dedupe, lede-diag to 8.1.

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/share/rpcd/ucode/mwan3.uc" '/usr/share/rpcd/ucode/mwan3.uc'
router_put "$ROOT/files/usr/libexec/lede-mwan3-setup" '/usr/libexec/lede-mwan3-setup'
router_put "$ROOT/files/usr/share/ucode/lede-diag.uc" '/usr/share/ucode/lede-diag.uc'
router_put "$ROOT/files/usr/libexec/lede-samba-policy" '/usr/libexec/lede-samba-policy'
router_put "$ROOT/files/usr/libexec/lede-samba-sync" '/usr/libexec/lede-samba-sync'
router_put "$ROOT/files/etc/init.d/lede-samba-policy" '/etc/init.d/lede-samba-policy'
router_put "$ROOT/files/etc/init.d/lede-samba-sync" '/etc/init.d/lede-samba-sync'
router_put "$ROOT/files/etc/init.d/samba4" '/etc/init.d/samba4'
router_put "$ROOT/files/etc/hotplug.d/block/20-smb" '/etc/hotplug.d/block/20-smb'
router_put "$ROOT/files/etc/hotplug.d/block/21-lede-samba-policy" '/etc/hotplug.d/block/21-lede-samba-policy'
router_put "$ROOT/files/www/luci-static/resources/view/samba4.js" '/www/luci-static/resources/view/samba4.js'
router_put "$ROOT/files/usr/share/ucitrack/luci-app-samba4.json" '/usr/share/ucitrack/luci-app-samba4.json'
router_put "$ROOT/package/mosdns-mwan/files/usr/libexec/mosdns-gen" '/usr/libexec/mosdns-gen'
router_put "$ROOT/package/mosdns-mwan/files/usr/libexec/mosdns-apply-luci" '/usr/libexec/mosdns-apply-luci'
router_put "$ROOT/patches/luci-app-mwan3/detail.js" '/www/luci-static/resources/view/mwan3/status/detail.js'

PYPATCH=$(mktemp)
cat > "$PYPATCH" << 'END_REMOTE'
from pathlib import Path
p = Path('/usr/share/mosdns/mosdns.uc')
if not p.is_file():
    print('skip mosdns.uc patch (missing)')
    raise SystemExit(0)
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
chmod 755 /usr/libexec/lede-samba-policy /usr/libexec/lede-samba-sync \
	/etc/init.d/lede-samba-policy /etc/init.d/lede-samba-sync /etc/init.d/samba4 \
	/etc/hotplug.d/block/20-smb /etc/hotplug.d/block/21-lede-samba-policy 2>/dev/null || true
rm -f /usr/libexec/lede-samba-dedupe /etc/init.d/lede-samba-dedupe 2>/dev/null || true
for f in /usr/share/rpcd/ucode/mwan3.uc /usr/share/ucode/lede-diag.uc; do
  [ -f "$f" ] && sed -i "s/\r$//" "$f"
done
# mwan3 check_quality backfill (same as 44-lede-mwan3-quality)
[ -f /etc/config/mwan3 ] && for sid in $(uci -q show mwan3 2>/dev/null | sed -n "s/^mwan3\.\([^=]*\)=interface$/\1/p"); do
  [ "$(uci -q get mwan3.$sid.lede_auto)" = "1" ] || continue
  [ "$(uci -q get mwan3.$sid.enabled)" = "0" ] && continue
  case "$(uci -q get mwan3.$sid.check_quality 2>/dev/null)" in 1|yes|on|true) continue ;; esac
  uci -q set "mwan3.$sid.check_quality=1"
  uci -q set "mwan3.$sid.failure_latency=2000"
  uci -q set "mwan3.$sid.failure_loss=40"
  uci -q set "mwan3.$sid.recovery_latency=1000"
  uci -q set "mwan3.$sid.recovery_loss=10"
done
uci -q commit mwan3 2>/dev/null || true
/etc/init.d/lede-samba-policy enable 2>/dev/null || true
/etc/init.d/lede-samba-sync enable 2>/dev/null || true
/etc/init.d/lede-samba-policy start 2>/dev/null || /usr/libexec/lede-samba-policy 2>/dev/null || true
/usr/libexec/lede-samba-sync 2>/dev/null || true
/etc/init.d/rpcd restart
sleep 2
/etc/init.d/mwan3 restart
echo PREP_OK
END_REMOTE
)"
router_print
router_open "$ROUTER_IP" "$ROUTER_PASS"
echo RELOGIN_OK
router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
grep -c "for (let tf in track_files)" /usr/share/rpcd/ucode/mwan3.uc 2>/dev/null || echo mwan3_uc=0
grep -c "check_quality" /www/luci-static/resources/view/mwan3/status/detail.js 2>/dev/null || echo detail_js=0
test -x /usr/libexec/mosdns-apply-luci && echo mosdns_apply=ok
grep -c "sda128" /usr/share/ucode/lede-diag.uc 2>/dev/null || true
ubus list 2>/dev/null | grep -w mwan3 || true
uci -q show mwan3 | grep check_quality | head -5
END_REMOTE
)"
router_print
