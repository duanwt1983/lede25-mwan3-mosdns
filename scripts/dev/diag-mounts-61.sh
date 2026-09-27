#!/bin/sh
# macOS port of diag-mounts-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-mounts-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo "=== lsblk ==="
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
echo "=== mounts sda3/data ==="
mount | grep -E 'sda3| /data |xray|mosdns|passwall|v2ray|geodata'
echo "=== mountinfo ==="
awk '$3 ~ /sda3/ || $5 ~ /data|xray|mosdns|passwall|geodata/ {print}' /proc/self/mountinfo
echo "=== fstab all ==="
uci show fstab
echo "=== findmnt sda3 ==="
findmnt -S /dev/sda3 -R 2>/dev/null || true
END_REMOTE
)"
router_print
