#!/bin/sh
# macOS port of diag-mounts-detail-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-mounts-detail-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo "=== block vs bind (findmnt) ==="
findmnt -t ext4 /data 2>/dev/null
echo "---"
findmnt -R /data 2>/dev/null | head -20
echo "=== df key paths ==="
df -h /data /usr/share/xray /usr/share/v2ray /etc/mosdns/rule/adlist /usr/share/passwall/rules 2>&1
echo "=== same file inode test ==="
ls -li /data/geodata/geoip.dat /usr/share/xray/geoip.dat /usr/share/v2ray/geoip.dat 2>&1
ls -li /data/mosdns/adlist/mosdns_adrules.txt /etc/mosdns/rule/adlist/mosdns_adrules.txt 2>&1
echo "=== /mnt entries ==="
mount | grep /mnt || echo none
END_REMOTE
)"
router_print
