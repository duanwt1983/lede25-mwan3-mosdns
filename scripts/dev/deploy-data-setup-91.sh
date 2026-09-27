#!/bin/sh
# macOS port of deploy-data-setup-91.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-data-setup-91.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Deploy lede-data-setup GPT fix to 192.168.9.1 and run partition setup.

router_open "${1:-192.168.9.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/libexec/lede-data-setup" '/usr/libexec/lede-data-setup'

router_sh "$(cat <<'END_REMOTE'
/usr/libexec/lede-data-setup; echo setup-exit=$?
echo "=== log ==="
tail -20 /tmp/lede-data-setup.log
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
echo "=== mount ==="
mount | grep " /data " || echo "/data not mounted"
END_REMOTE
)"
router_print
