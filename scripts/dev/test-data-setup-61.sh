#!/bin/sh
# macOS port of test-data-setup-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./test-data-setup-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=300

# Full first-boot simulation for lede-data-setup on 6.1 (or any router).

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/libexec/lede-data-setup" /usr/libexec/lede-data-setup
router_put "$ROOT/files/etc/init.d/lede-data" /etc/init.d/lede-data

router_sh "$(cat <<'END_REMOTE'
echo "=== mounts ==="
mount | grep -E " /data | /$ " || true
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT
echo "=== parted ==="
parted -m -s /dev/sda unit MiB print free 2>&1
echo "=== blkid LEDEDATA ==="
blkid | grep -iE "LEDEDATA|sda3" || blkid
echo "=== fstab data ==="
uci show fstab 2>/dev/null | grep -E "target=|uuid=|enabled=" || true
echo "=== markers ==="
ls -la /etc/.lede-data-init.done /data/.lede-data 2>&1
echo "=== overlay /data ==="
ls -la /overlay/upper/data 2>&1 | head -5
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
set -e
umount /data 2>/dev/null || true
n=$(sgdisk -p /dev/sda 2>/dev/null | awk "/LEDEDATA/{print \$1}" | head -1)
if [ -n "$n" ]; then
  sgdisk -d "$n" /dev/sda
  partprobe /dev/sda 2>/dev/null || true
  block detect 2>/dev/null || true
  sleep 2
  echo "deleted LEDEDATA partition $n"
fi
rm -f /etc/.lede-data-init.done
rm -f /tmp/lede-data-setup.log
if [ -d /data ] && ! mountpoint -q /data 2>/dev/null; then
  find /data -mindepth 1 -delete 2>/dev/null || true
fi
sid=$(uci -q show fstab 2>/dev/null | awk -F"[.=]" "/target='\\/data'/{print \$2; exit}")
if [ -n "$sid" ]; then
  uci -q delete "fstab.$sid"
  uci -q commit fstab
  echo "removed fstab data entry $sid"
fi
echo reset-ok
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/usr/libexec/lede-data-setup
echo setup-exit=$?
echo "=== init marker ==="
ls -la /etc/.lede-data-init.done 2>&1
echo "=== script retired? ==="
ls -la /usr/libexec/lede-data-setup 2>&1
echo "=== data marker ==="
ls -la /data/.lede-data 2>&1
echo "=== log ==="
cat /tmp/lede-data-setup.log 2>&1
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT
echo "=== mount /data ==="
mount | grep " /data " || echo "/data NOT mounted"
echo "=== df /data ==="
df -h /data 2>&1
echo "=== fstab ==="
uci show fstab | grep -E "target=|uuid=|fstype=|enabled=" || uci show fstab
echo "=== logread ==="
logread | grep lede-data | tail -15
END_REMOTE
)"
router_print
