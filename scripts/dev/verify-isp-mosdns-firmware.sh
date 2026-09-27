#!/bin/sh
# Post-flash smoke test for ISP address library + MosDNS integration.
# Usage: ssh root@router 'sh -s' < scripts/dev/verify-isp-mosdns-firmware.sh
set -e

fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "OK: $*"; }

[ -f /etc/config/isp-ip ] || fail "missing /etc/config/isp-ip"
[ -x /usr/libexec/isp-ip-update ] || fail "missing or not executable: isp-ip-update"
[ -f /www/luci-static/resources/view/mwan3/ispupdate.js ] || \
	fail "missing LuCI view ispupdate.js"
grep -q 'luci.ispip' /www/luci-static/resources/view/mwan3/ispupdate.js || \
	fail "ispupdate.js missing luci.ispip RPC"
grep -q 'syncCron' /www/luci-static/resources/view/mwan3/ispupdate.js || \
	fail "ispupdate.js missing syncCron (cron will not sync on save)"
grep -q 'ui.changes.apply' /www/luci-static/resources/view/mwan3/ispupdate.js || \
	fail "ispupdate.js missing save-and-apply cron hook"

[ -f /usr/share/rpcd/ucode/luci.isp-ip.uc ] || fail "missing luci.isp-ip.uc"
ubus list 2>/dev/null | grep -q '^luci.ispip$' || fail "ubus object luci.ispip not registered"

[ -f /usr/share/rpcd/acl.d/luci-mwan3-isp.json ] || fail "missing ACL luci-mwan3-isp.json"
grep -q 'luci.ispip' /usr/share/rpcd/acl.d/luci-mwan3-isp.json || \
	fail "ACL missing luci.ispip (read and write names must match)"

# sync-cron round-trip: enable then disable
uci -q set isp-ip.main.auto='1'
uci -q set isp-ip.main.week='3'
uci -q set isp-ip.main.hour='3'
uci commit isp-ip
/usr/libexec/isp-ip-update sync-cron 1 3 3
grep -q 'isp-ip-update' /etc/crontabs/root || fail "sync-cron did not add cron when auto=1"
/usr/libexec/isp-ip-update sync-cron 0
grep -q 'isp-ip-update' /etc/crontabs/root && fail "sync-cron did not remove cron when auto=0"
uci -q set isp-ip.main.auto='0'
uci commit isp-ip

[ -f /etc/config/mosdns ] || fail "missing /etc/config/mosdns"
if grep -q "option enabled '0'" /etc/config/mosdns; then
	ok "mosdns ships disabled in /etc/config/mosdns"
elif [ "$(uci -q get mosdns.config.enabled 2>/dev/null)" = "1" ]; then
	echo "NOTE: mosdns enabled by user on this router (OK)"
else
	fail "mosdns missing enabled option"
fi
[ -x /usr/libexec/mosdns-gen ] || fail "missing mosdns-gen"
[ -x /usr/share/mosdns/gen-config-custom ] || fail "missing gen-config-custom"

if [ -x /etc/init.d/mosdns ]; then
	grep -q 'do not use killall mosdns' /etc/init.d/mosdns || \
		echo "WARN: mosdns init missing stale-process guard (run mosdns-fix-dns-forward)"
	grep -q 'gen-config-custom' /etc/init.d/mosdns || \
		fail "mosdns init not hooked to gen-config-custom"
fi

[ -x /etc/init.d/isp-ip-update ] || fail "missing init.d isp-ip-update"
/etc/init.d/isp-ip-update enabled >/dev/null 2>&1 || \
	echo "WARN: isp-ip-update init not enabled (cron sync on boot may be skipped)"

ok "ISP + MosDNS firmware integration checks passed"
