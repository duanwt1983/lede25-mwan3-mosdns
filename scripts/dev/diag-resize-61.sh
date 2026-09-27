#!/bin/sh
# macOS port of diag-resize-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-resize-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo blockdev=$(blockdev --getsz /dev/sda3 2>&1)
echo sgdisk=$(sgdisk -i 3 /dev/sda 2>&1 | grep -E "First|Last")
echo resize2fs=$(resize2fs /dev/sda3 2>&1)
echo blockdev_after=$(blockdev --getsz /dev/sda3 2>&1)
df -h /data
dumpe2fs -h /dev/sda3 2>/dev/null | grep -E "Block count|Block size"
END_REMOTE
)"
router_print
