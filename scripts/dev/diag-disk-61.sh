#!/bin/sh
# macOS port of diag-disk-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-disk-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
echo "=== uptime ==="
uptime
echo "=== block devices ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,RO,MODEL 2>&1
echo "=== mounts ==="
mount | grep -E 'sda|/data|overlay|root'
echo "=== df ==="
df -hT 2>&1
echo "=== dmesg disk/io errors ==="
dmesg 2>/dev/null | grep -iE 'sda|I/O error|Buffer I/O|EXT4|error|fail|reset|timeout|corrupt|read-only' | tail -60
echo "=== logread disk ==="
logread 2>/dev/null | grep -iE 'sda|disk|I/O|ext4|read.?only|error|lede-data|wanalert|alert' | tail -40
echo "=== smartctl ==="
smartctl -H -A /dev/sda 2>&1 | head -40
echo "=== fstab ==="
uci show fstab 2>&1
echo "=== e2fsck dry-run ==="
e2fsck -n /dev/sda3 2>&1 | tail -25
echo "=== rw test /data ==="
touch /data/.rwtest 2>&1 && echo rwtest_ok && rm -f /data/.rwtest || echo rwtest_fail
echo "=== overlay rw ==="
touch /overlay/.rwtest 2>&1 && echo overlay_ok && rm -f /overlay/.rwtest || echo overlay_fail
echo "=== ro mounts ==="
mount | grep ' ro,' || echo none_ro
END_REMOTE
)"
router_print
