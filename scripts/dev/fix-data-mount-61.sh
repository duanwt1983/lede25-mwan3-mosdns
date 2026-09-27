#!/bin/sh
# macOS port of fix-data-mount-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./fix-data-mount-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Deploy lede-data-mount, fix fstab, mount /data on 6.1.

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/libexec/lede-data-mount" /usr/libexec/lede-data-mount
router_put "$ROOT/files/etc/init.d/lede-data-mount" /etc/init.d/lede-data-mount

router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
rm -f /tmp/lede-data-mount.log

UUID=$(blkid -o value -s UUID /dev/sda3 2>/dev/null || echo 95defcea-e708-485f-8633-80097aaae94e)
echo uuid=$UUID

# remove stale auto-detect entries for this UUID
for sid in $(uci -q show fstab 2>/dev/null | awk -F"[.=]" "/uuid='${UUID}'/{print \$2}"); do
  tgt=$(uci -q get fstab.$sid.target)
  [ "$tgt" = "/data" ] && continue
  echo "delete stale fstab.$sid target=$tgt"
  uci -q delete fstab.$sid
done

sid=$(uci -q show fstab 2>/dev/null | awk -F"[.=]" "/target='\\/data'/{print \$2; exit}")
if [ -z "$sid" ]; then
  uci add fstab mount >/dev/null
  sid=$(uci -q show fstab 2>/dev/null | awk -F"[.=]" "/target='\\/data'/{print \$2; exit}")
  [ -z "$sid" ] && sid=$(uci -q show fstab | awk -F"[.=]" '/=mount$/{print $2}' | tail -1)
fi
uci set fstab.$sid.uuid="$UUID"
uci set fstab.$sid.target=/data
uci set fstab.$sid.fstype=ext4
uci delete fstab.$sid.options 2>/dev/null || true
uci set fstab.$sid.enabled=1
uci commit fstab
echo "=== fstab /data ==="
uci show fstab | grep -E "target=|uuid=|fstype=|options=|enabled="

partprobe /dev/sda 2>/dev/null || true
blockdev --rereadpt /dev/sda 2>/dev/null || true
partx -a /dev/sda 2>/dev/null || true
partx -u /dev/sda 2>/dev/null || true
block detect 2>/dev/null || true
sleep 2
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT /dev/sda 2>&1

if [ -b /dev/sda3 ]; then
  e2fsck -f -y /dev/sda3 2>&1 | tail -3
fi

/usr/libexec/lede-data-mount mount
echo mount-exit=$?

echo "=== df /data ==="
df -h /data
echo "=== mount ==="
mount | grep -E ' /data |sda3'
echo "=== fstab enabled ==="
/etc/init.d/fstab enabled; echo fstab-enabled=$?
echo "=== marker ==="
ls -la /data/.lede-data 2>&1
echo "=== lede-log paths ==="
uci show lede-log 2>/dev/null | grep path
echo "=== mount log tail ==="
tail -15 /tmp/lede-data-mount.log 2>&1
END_REMOTE
)"
router_print
