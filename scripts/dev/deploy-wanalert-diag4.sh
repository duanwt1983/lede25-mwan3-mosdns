#!/bin/sh
# macOS port of deploy-wanalert-diag4.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-wanalert-diag4.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=60

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
for k in alert_burst_up alert_burst_down alert_down alert_cpu alert_arp alert_mem; do echo -n "$k="; uci -q get wanalert.main.$k; echo; done
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
awk -F"|" 
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
$2=="严重" || $2=="中等" {print}
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
 /data/logs/alert/sys-alert.log | tail -5
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
test -f /tmp/wan-alert.last && cat /tmp/wan-alert.last | head -c 200; echo
END_REMOTE
)"
router_print
