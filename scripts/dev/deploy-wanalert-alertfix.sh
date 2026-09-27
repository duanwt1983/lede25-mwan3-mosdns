#!/bin/sh
# macOS port of deploy-wanalert-alertfix.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-wanalert-alertfix.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/libexec/wan-alert" '/usr/libexec/wan-alert'
router_put "$ROOT/files/usr/libexec/lede-autofix" '/usr/libexec/lede-autofix'
router_put "$ROOT/files/usr/share/ucode/lede-watch.uc" '/usr/share/ucode/lede-watch.uc'
router_put "$ROOT/files/usr/share/ucode/lede-diag.uc" '/usr/share/ucode/lede-diag.uc'
router_put "$ROOT/files/etc/init.d/wanalert" '/etc/init.d/wanalert'
router_put "$ROOT/files/etc/hotplug.d/iface/26-wan-alert" '/etc/hotplug.d/iface/26-wan-alert'
router_put "$ROOT/files/www/luci-static/resources/view/status/alertmap.js" '/www/luci-static/resources/view/status/alertmap.js'

router_sh "$(cat <<'END_REMOTE'
chmod 755 /usr/libexec/wan-alert /usr/libexec/lede-autofix /etc/hotplug.d/iface/26-wan-alert /etc/init.d/wanalert
rmdir /tmp/wan-alert.lock 2>/dev/null || true
rmdir /tmp/lede-autofix-Wan_2.lock /tmp/lede-autofix-Wan_1.lock /tmp/lede-autofix-Wan_3.lock 2>/dev/null || true
uci -q get wanalert.main.wan_down_hold >/dev/null || uci set wanalert.main.wan_down_hold=5
uci -q get wanalert.main.wan_up_hold >/dev/null || uci set wanalert.main.wan_up_hold=3
uci commit wanalert
/etc/init.d/wanalert restart
sleep 2
echo === files ===
ls -la /usr/libexec/wan-alert /usr/share/ucode/lede-watch.uc /etc/hotplug.d/iface/26-wan-alert
echo === uci hold ===
uci -q get wanalert.main.wan_down_hold; uci -q get wanalert.main.wan_up_hold
echo === hotplug head ===
head -n 5 /etc/hotplug.d/iface/26-wan-alert
echo === grep fix markers ===
grep -E 'try_flush_offline_queue|mark_ding_offline|wan_down_hold' /usr/libexec/wan-alert /usr/share/ucode/lede-watch.uc | head -n 6
echo === wanalert ===
pgrep -af wan-alert || true
/etc/init.d/wanalert enabled; echo enabled=$?
END_REMOTE
)"
router_print
