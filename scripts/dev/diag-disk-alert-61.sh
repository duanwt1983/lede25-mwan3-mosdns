#!/bin/sh
# macOS port of diag-disk-alert-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-disk-alert-61.sh [router-ip] [password]
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
echo "=== recent alerts ==="
ls -lt /data/logs/alert 2>/dev/null | head -10
for f in $(ls -t /data/logs/alert/*.json 2>/dev/null | head -5); do echo "--- $f ---"; cat "$f"; echo; done
echo "=== grep disk alerts in log ==="
grep -r -iE '磁盘|I/O|sda128|F2FS|ext4-fs error|Buffer I/O|读写出错' /data/logs/alert /data/logs/syslog /var/log 2>/dev/null | tail -30
echo "=== sda128 partition ==="
sgdisk -p /dev/sda 2>/dev/null | tail -8
parted -s /dev/sda unit MiB print 2>/dev/null | tail -8
echo "=== block info sda128 ==="
blkid /dev/sda128 2>&1
file -s /dev/sda128 2>&1 | head -3
END_REMOTE
)"
router_print
