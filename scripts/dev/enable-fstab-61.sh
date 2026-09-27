#!/bin/sh
# macOS port of enable-fstab-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./enable-fstab-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
for sid in $(uci show fstab 2>/dev/null | awk -F"[.=]" "/target='\\/mnt\\/sda3'/{print \$2}"); do
  uci delete fstab.$sid
done
uci commit fstab
/etc/init.d/fstab enable
/etc/init.d/lede-data-mount enable
echo === fstab ===
uci show fstab | grep -E "target=|uuid=|fstype=|options=|enabled="
echo === enabled ===
/etc/init.d/fstab enabled; echo fstab=$?
/etc/init.d/lede-data-mount enabled; echo lede-data-mount=$?
echo === df ===
df -h /data
END_REMOTE
)"
router_print
