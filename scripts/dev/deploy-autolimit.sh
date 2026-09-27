#!/bin/sh
# macOS port of deploy-autolimit.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-autolimit.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Deploy lede-autolimit to a live OpenWrt/LEDE router via ubus (dev only).

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/etc/config/lede-autolimit" '/etc/config/lede-autolimit'
router_put "$ROOT/files/etc/init.d/lede-autolimit" '/etc/init.d/lede-autolimit'
router_put "$ROOT/files/etc/uci-defaults/43-lede-autolimit" '/etc/uci-defaults/43-lede-autolimit'
router_put "$ROOT/files/usr/libexec/lede-autolimit" '/usr/libexec/lede-autolimit'
router_put "$ROOT/files/usr/libexec/lede-autolimit-loop" '/usr/libexec/lede-autolimit-loop'
router_put "$ROOT/files/usr/libexec/rpcd/lede-autolimit" '/usr/libexec/rpcd/lede-autolimit'
router_put "$ROOT/files/usr/share/ucode/lede-autolimit.uc" '/usr/share/ucode/lede-autolimit.uc'
router_put "$ROOT/files/www/luci-static/resources/view/status/autolimit.js" '/www/luci-static/resources/view/status/autolimit.js'

router_sh "$(cat <<'END_REMOTE'
chmod +x /usr/libexec/lede-autolimit /usr/libexec/lede-autolimit-loop /usr/libexec/rpcd/lede-autolimit /etc/init.d/lede-autolimit
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/etc/init.d/rpcd restart
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/etc/init.d/lede-autolimit reload
END_REMOTE
)"
router_print
sleep 2
router_sh "$(cat <<'END_REMOTE'
ls -la /usr/libexec/lede-autolimit /usr/libexec/rpcd/lede-autolimit
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ubus list 2>/dev/null | grep -i autolimit || true
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ubus call lede-autolimit status 2>&1 | head -c 400
END_REMOTE
)"
router_print
