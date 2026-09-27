#!/bin/sh
# macOS port of deploy-wanalert-fix.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-wanalert-fix.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=60

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
chmod +x /usr/libexec/lede-autofix /etc/hotplug.d/net/90-lede-wan-carrier
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ls -la /usr/libexec/lede-autofix /etc/hotplug.d/net/90-lede-wan-carrier
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
uci -q get wanalert.main.autofix; uci -q get wanalert.main.autofix_wan; uci -q get wanalert.main.autofix_cooldown
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
uci show wanalert.main 2>/dev/null | grep wfix_ || echo no_wfix_overrides
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
test -f /tmp/lede-autofix.json && cat /tmp/lede-autofix.json | head -c 400; echo
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
grep -F "自动处理" /data/logs/alert/sys-alert.log 2>/dev/null | tail -3 || echo no_fix_log
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
grep -F "断网重启网卡" /data/logs/alert/sys-alert.log 2>/dev/null | tail -3 || echo no_bounce_log
END_REMOTE
)"
router_print
