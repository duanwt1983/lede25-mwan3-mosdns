#!/bin/sh
# macOS port of fix-passwall-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./fix-passwall-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Diagnose and fix PassWall on 6.1 (geodata bind, mosdns, enable/start).

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin; df -h /data; ls -la /data/geodata 2>&1 | head -5; ls -la /usr/share/xray 2>&1; mount | grep -E "xray|passwall|/data"; opkg list-installed | grep -iE "xray|passwall|sing-box|chinadns"; ps w | grep -iE "xray|passwall|mosdns|sing-box" | grep -v grep
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin; wc -l /etc/init.d/passwall; head -5 /etc/init.d/passwall; file /etc/init.d/passwall 2>/dev/null; /etc/init.d/passwall enabled; echo enabled_exit=$?; ls -la /etc/rc.d/*passwall* 2>&1
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
mkdir -p /data/geodata /usr/share/xray
[ -f /data/geodata/geoip.dat ] || echo "WARN: missing geoip.dat"
[ -f /data/geodata/geosite.dat ] || echo "WARN: missing geosite.dat"
if ! mount | grep -q " /usr/share/xray "; then
  mount --bind /data/geodata /usr/share/xray && echo "bind ok" || echo "bind failed"
fi
ls -la /usr/share/xray 2>&1 | head -5
if [ -x /usr/libexec/lede-data-mount ]; then
  /usr/libexec/lede-data-mount bind
fi
mount | grep -E "xray|passwall"
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin; uci get mosdns.config.enabled 2>&1; /etc/init.d/mosdns enabled; echo mosdns_enabled_exit=$?; /etc/init.d/mosdns start 2>&1; sleep 1; netstat -lntp 2>/dev/null | grep 5335 || ss -lntp | grep 5335
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
uci show passwall.@global[0].enabled 2>&1
/etc/init.d/passwall enable
/etc/init.d/passwall enabled; echo enabled_exit=$?
/etc/init.d/passwall stop 2>&1 || true
/etc/init.d/passwall start 2>&1
sleep 5
ps w | grep -iE "xray|passwall|sing-box|chinadns|haproxy" | grep -v grep
[ -f /tmp/log/passwall.log ] && tail -30 /tmp/log/passwall.log
logread | tail -20
END_REMOTE
)"
router_print
