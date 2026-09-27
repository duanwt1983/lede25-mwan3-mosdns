#!/bin/sh
# macOS port of diag-data-partition.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-data-partition.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo "=== /data status ==="
mount | grep " /data " || echo "/data not mounted"
ls -la /data/.lede-data 2>/dev/null || echo "no marker"
echo "=== lede-data scripts ==="
ls -la /usr/libexec/lede-data-setup /etc/init.d/lede-data 2>&1
/etc/init.d/lede-data enabled 2>&1; echo lede-data-enabled=$?
/etc/init.d/fstab enabled 2>&1; echo fstab-enabled=$?
echo "=== uci fstab ==="
uci show fstab 2>/dev/null | grep -i data || echo no-fstab-data
echo "=== setup log ==="
tail -20 /tmp/lede-data-setup.log 2>/dev/null || echo no-log
echo "=== disk free (parted) ==="
ROOT=$(awk '$2=="/"{print $1; exit}' /proc/mounts)
echo root=$ROOT
command -v parted >/dev/null && parted -m -s $(echo $ROOT | sed 's/p[0-9]*$//' | sed 's/[0-9]*$//') unit MiB print free 2>/dev/null | tail -5 || echo parted-fail
blkid | grep -i LEDEDATA || blkid | grep -i data || echo no-LEDEDATA-part
END_REMOTE
)"
router_print
