#!/bin/sh
# macOS port of deploy-wanalert-pushplus.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-wanalert-pushplus.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Sync PushPlus WeChat/App alerting to 192.168.8.1.
# Does not overwrite live wanalert config, and does not restart network/mosdns/mwan3.

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/libexec/wan-alert" '/usr/libexec/wan-alert'
router_put "$ROOT/files/www/luci-static/resources/view/status/alertmap.js" '/www/luci-static/resources/view/status/alertmap.js'
router_put "$ROOT/files/www/luci-static/resources/view/status/wanalert-layout.js" '/www/luci-static/resources/view/status/wanalert-layout.js'
router_put "$ROOT/files/www/luci-static/resources/view/status/alertlog.js" '/www/luci-static/resources/view/status/alertlog.js'

router_sh "$(cat <<'END_REMOTE'
chmod 755 /usr/libexec/wan-alert
for f in \
  /usr/libexec/wan-alert \
  /www/luci-static/resources/view/status/alertmap.js \
  /www/luci-static/resources/view/status/wanalert-layout.js \
  /www/luci-static/resources/view/status/alertlog.js
do
  [ -f "$f" ] && sed -i "s/\r$//" "$f"
done
uci -q get wanalert.main.pushplus_enabled >/dev/null || uci set wanalert.main.pushplus_enabled=0
uci -q get wanalert.main.pushplus_wechat >/dev/null || uci set wanalert.main.pushplus_wechat=1
uci -q get wanalert.main.pushplus_app >/dev/null || uci set wanalert.main.pushplus_app=1
uci -q get wanalert.main.pushplus_token >/dev/null || uci set wanalert.main.pushplus_token=
uci -q get wanalert.main.pushplus_prefix >/dev/null || uci set wanalert.main.pushplus_prefix=
uci commit wanalert
rmdir /tmp/wan-alert.lock 2>/dev/null || true
/etc/init.d/wanalert restart
sleep 1
echo PREP_OK
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print \"LAN \" \$2}"
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
echo === markers ===
grep -c "function send_pushplus" /usr/libexec/wan-alert
grep -c "batchSend" /usr/libexec/wan-alert
grep -c "pushplus_token" /www/luci-static/resources/view/status/alertmap.js
grep -c "pushplus_prefix" /usr/libexec/wan-alert
grep -c "depends('enabled', '1')" /www/luci-static/resources/view/status/alertmap.js
grep -c "depends('pushplus_enabled', '1')" /www/luci-static/resources/view/status/alertmap.js
grep -c "pushplus_prefix" /usr/libexec/wan-alert
grep -c "depends('enabled', '1')" /www/luci-static/resources/view/status/alertmap.js
grep -c "depends('pushplus_enabled', '1')" /www/luci-static/resources/view/status/alertmap.js
grep -c "optionBox(sec, 'pushplus_token')" /www/luci-static/resources/view/status/wanalert-layout.js
grep -c "PushPlus" /www/luci-static/resources/view/status/alertlog.js
echo === exec ===
ls -l /usr/libexec/wan-alert
head -c 2 /usr/libexec/wan-alert
echo
echo === uci flags ===
uci -q get wanalert.main.pushplus_enabled
uci -q get wanalert.main.pushplus_wechat
uci -q get wanalert.main.pushplus_app
echo token_set=$(uci -q get wanalert.main.pushplus_token >/dev/null && echo yes || echo no)
echo ding_enabled=$(uci -q get wanalert.main.enabled)
echo === service ===
pgrep -af wan-alert || true
/etc/init.d/wanalert enabled; echo enabled=$?
echo === lan ===
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print}"
END_REMOTE
)"
router_print
