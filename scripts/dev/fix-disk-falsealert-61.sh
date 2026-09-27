#!/bin/sh
# macOS port of fix-disk-falsealert-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./fix-disk-falsealert-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Deploy sda128 false-alert fix + repair sda3 ext4 counters on 6.1.

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/share/ucode/lede-diag.uc" '/usr/share/ucode/lede-diag.uc'

router_sh "$(cat <<'END_REMOTE'
/etc/init.d/rpcd restart 2>/dev/null; /etc/init.d/uwsgi restart 2>/dev/null; true
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
echo "=== before e2fsck ==="
e2fsck -n /dev/sda3 2>&1 | tail -8

# stop services using /data binds briefly
/etc/init.d/mosdns stop 2>/dev/null || true
/etc/init.d/passwall stop 2>/dev/null || true
for mp in /etc/mosdns/rule/adlist /usr/share/passwall/rules /usr/share/xray /usr/share/v2ray; do
  umount "$mp" 2>/dev/null || true
done
umount /data 2>/dev/null || true

echo "=== e2fsck repair ==="
e2fsck -f -y /dev/sda3 2>&1 | tail -15

mount /dev/sda3 /data
[ -x /usr/libexec/lede-data-mount ] && /usr/libexec/lede-data-mount bind

/etc/init.d/mosdns start 2>/dev/null || true
/etc/init.d/passwall start 2>/dev/null || true

echo "=== after ==="
mount | grep sda3
touch /data/.rwtest && rm -f /data/.rwtest && echo rw_ok
smartctl -H /dev/sda 2>&1 | grep -i "SMART overall-health"
END_REMOTE
)"
router_print
