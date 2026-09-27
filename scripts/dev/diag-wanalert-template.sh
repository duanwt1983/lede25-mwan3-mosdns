#!/bin/sh
# macOS port of diag-wanalert-template.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-wanalert-template.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=60

PASS=${ROUTER_PASS:-password}
if [ "$#" -eq 0 ]; then
  set -- 192.168.8.1 192.168.6.1
fi
for ROUTER_IP in "$@"; do
router_open "$ROUTER_IP" "$PASS" || { echo "FAILED $ROUTER_IP"; continue; }
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo keyword=$(uci -q get wanalert.main.keyword)
echo extra_text=$(uci -q get wanalert.main.extra_text)
echo pushplus_prefix=$(uci -q get wanalert.main.pushplus_prefix)
grep -nE 'SHYX|晋城' /etc/config/wanalert /usr/libexec/wan-alert 2>/dev/null || echo repo-hardcode=not-found-on-device
END_REMOTE
)"
router_print
done
