#!/bin/sh
# macOS port of test-data-grow-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./test-data-grow-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=300

# Simulate new-firmware first boot: small prebuilt LEDEDATA + grow to disk end.

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/libexec/lede-data-setup" /usr/libexec/lede-data-setup
router_put "$ROOT/files/etc/init.d/lede-data" /etc/init.d/lede-data

router_sh "$(cat <<'END_REMOTE'
set -e
rm -f /etc/.lede-data-init.done /tmp/lede-data-setup.log
for mp in /data /usr/share/xray /usr/share/passwall/rules /etc/mosdns/rule/adlist /usr/share/v2ray; do
  umount "$mp" 2>/dev/null || true
done
n=$(sgdisk -p /dev/sda 2>/dev/null | awk "/LEDEDATA/{print \$1}" | head -1)
[ -n "$n" ] && sgdisk -d "$n" /dev/sda
sgdisk -n 0:0:+512M -c 0:LEDEDATA -t 0:8300 /dev/sda
partprobe /dev/sda 2>/dev/null || true
partx -u /dev/sda 2>/dev/null || true
block detect 2>/dev/null || true
sleep 3
p=$(blkid -t LABEL=LEDEDATA -o device 2>/dev/null | head -1)
[ -n "$p" ] || p=/dev/sda3
i=0
while [ ! -b "$p" ] && [ "$i" -lt 10 ]; do sleep 1; block detect; i=$((i+1)); done
mkfs.ext4 -F -L LEDEDATA -m 0 "$p"
echo placeholder=$p
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT
find /data -mindepth 1 -delete 2>/dev/null || true
while uci -q show fstab 2>/dev/null | grep -q "target='/data'"; do
  sid=$(uci -q show fstab | awk -F"[.=]" "/target='\\/data'/{print \$2; exit}")
  [ -n "$sid" ] || break
  uci -q delete "fstab.$sid"
done
uci -q commit fstab
echo prep-ok
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
echo === log ===
cat /tmp/lede-data-setup.log
echo === lsblk ===
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT
echo === mount ===
mount | grep ' /data ' || echo '/data NOT mounted'
echo === df ===
df -h /data
echo === marker ===
ls -la /data/.lede-data /etc/.lede-data-init.done 2>&1
END_REMOTE
)"
router_print
