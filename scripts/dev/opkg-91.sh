#!/bin/sh
# macOS port of opkg-91.ps1. Talks to the router over LuCI ubus.
# Usage: ./opkg-91.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=300

router_open "${1:-192.168.9.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo "=== network ==="
ip route; ping -c1 -W2 223.5.5.5 2>&1 | tail -2
echo "=== opkg config ==="
cat /etc/opkg/distfeeds.conf 2>&1 | head -5
echo "=== opkg update ==="
opkg update 2>&1 | tail -15
echo "=== opkg install gdisk ==="
opkg install gdisk 2>&1
echo "=== which sgdisk ==="
command -v sgdisk; ls -la /usr/sbin/sgdisk /sbin/sgdisk 2>&1
END_REMOTE
)"
router_print
