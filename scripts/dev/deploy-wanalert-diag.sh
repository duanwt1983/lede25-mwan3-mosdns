#!/bin/sh
# macOS port of deploy-wanalert-diag.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-wanalert-diag.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=60

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
uci -q show wanalert.main.enabled wanalert.main.dingtalk_webhook wanalert.main.log_path wanalert.main.check_interval 2>/dev/null
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/etc/init.d/wanalert enabled; /etc/init.d/wanalert status 2>&1
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ps w | grep -E "[w]an-alert|sys-alert-watch|wan-fail-watch" || true
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ls -la /usr/libexec/wan-alert /usr/sbin/wan-alert /etc/init.d/wanalert 2>&1
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
pgrep -a procd | head -3; pgrep -af wan-alert || true
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
tail -n 8 /data/logs/alert/sys-alert.log 2>/dev/null || tail -n 8 /overlay/logs/sys-alert.log 2>/dev/null || tail -n 8 /var/log/sys-alert.log 2>/dev/null || echo NO_ALERT_LOG
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ubus call wanmonitor snapshot 2>&1 | head -c 600
END_REMOTE
)"
router_print
