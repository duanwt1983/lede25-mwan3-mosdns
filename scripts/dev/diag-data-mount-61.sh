#!/bin/sh
# macOS port of diag-data-mount-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-data-mount-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo "=== df -h ==="
df -h
echo "=== mount /data ==="
mount | grep -E ' /data |sda3'
echo "=== mountpoint ==="
mountpoint /data 2>&1
echo "=== ls -la /data ==="
ls -la /data | head -15
echo "=== overlay data ==="
ls -la /overlay/upper/data 2>&1 | head -10
echo "=== blkid sda3 ==="
blkid /dev/sda3 2>&1
echo "=== lsblk ==="
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
echo "=== fstab ==="
uci show fstab
echo "=== fstab enabled ==="
/etc/init.d/fstab enabled; echo exit=$?
echo "=== lede-log paths ==="
uci show lede-log 2>/dev/null | grep path
echo "=== marker ==="
ls -la /data/.lede-data /etc/.lede-data-init.done 2>&1
echo "=== block mount ==="
block info 2>&1
END_REMOTE
)"
router_print
