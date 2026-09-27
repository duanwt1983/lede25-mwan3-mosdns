#!/bin/sh
# macOS port of deploy-wanalert-prefix-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-wanalert-prefix-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Deploy PushPlus site prefix to 192.168.6.1 gateway.

router_open "${1:-192.168.6.1}" "${2:-password}"
PREFIX=${3-'6.1网点'}
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/libexec/wan-alert" '/usr/libexec/wan-alert'
router_put "$ROOT/files/www/luci-static/resources/view/status/alertmap.js" '/www/luci-static/resources/view/status/alertmap.js'

router_sh "$(cat <<'END_REMOTE'
chmod 755 /usr/libexec/wan-alert
sed -i 's/\r$//' /usr/libexec/wan-alert /www/luci-static/resources/view/status/alertmap.js
uci -q get wanalert.main.pushplus_prefix >/dev/null || uci set wanalert.main.pushplus_prefix=
END_REMOTE
)"
router_print
PRE_B64=$(printf '%s' "$PREFIX" | base64 | tr -d '\n')
router_sh "uci set wanalert.main.pushplus_prefix=\"\$(printf '%s' '$PRE_B64' | base64 -d)\""
router_print prefix
router_sh "$(cat <<'END_REMOTE'
uci commit wanalert
rm -f /tmp/wan-alert.lock
/etc/init.d/wanalert restart
sleep 1
grep -c pushplus_prefix /usr/libexec/wan-alert
grep -c pushplus_prefix /www/luci-static/resources/view/status/alertmap.js
uci -q get wanalert.main.pushplus_prefix
/usr/sbin/wan-alert test manual 2>&1 | tail -5
END_REMOTE
)"
router_print
