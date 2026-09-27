#!/bin/sh
# macOS port of diag-data-61-detail.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-data-61-detail.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo "=== marker ==="
ls -la /data/.lede-data /etc/.lede-data-init.done 2>&1
echo "=== data top ==="
ls -la /data | head -15
echo "=== mountpoint ==="
mountpoint /data 2>&1
echo "=== overlay data ==="
ls -la /overlay/upper/data 2>&1 | head -10
echo "=== parted names ==="
parted -m -s /dev/sda unit MiB print 2>&1
echo "=== dmesg ext4 ==="
dmesg | grep -i ext4 | tail -20
echo "=== logread lede ==="
logread | grep -i lede | tail -30
echo "=== uptime ==="
uptime
END_REMOTE
)"
router_print
