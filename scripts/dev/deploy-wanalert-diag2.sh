#!/bin/sh
# macOS port of deploy-wanalert-diag2.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-wanalert-diag2.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=60

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
uci -q get wanalert.main.enabled; uci -q get wanalert.main.dingtalk_webhook | head -c 60; echo; uci -q get wanalert.main.log_enabled; uci -q get wanalert.main.alert_burst_up; uci -q get wanalert.main.alert_burst_down
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
uci -q get wanalert.main.alert_cpu; uci -q get wanalert.main.alert_down; uci -q get wanalert.main.alert_arp; uci -q get wanalert.main.autofix
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
test -f /tmp/wan-alert.state && head -c 300 /tmp/wan-alert.state; echo
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
test -f /tmp/lede-boot-reason.done && echo boot_reason_done=yes || echo boot_reason_done=no
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ls -la /data/logs/alert/ 2>/dev/null; wc -l /data/logs/alert/sys-alert.log 2>/dev/null
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/usr/libexec/wan-alert test 2>&1 | head -c 200
END_REMOTE
)"
router_print
