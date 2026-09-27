#!/bin/sh
# macOS port of diag-data-91.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-data-91.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.9.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo "=== mounts ==="
mount
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
echo "=== blkid ==="
blkid
echo "=== proc mounts root ==="
awk '$2=="/"{print}' /proc/mounts
echo "=== mountinfo root ==="
awk '$5=="/"{print}' /proc/self/mountinfo
echo "=== scripts ==="
ls -la /usr/libexec/lede-data-setup /etc/init.d/lede-data /etc/uci-defaults/10-lede-data-enable 2>&1
echo "=== setup log ==="
cat /tmp/lede-data-setup.log 2>&1
echo "=== logread ==="
logread | grep lede-data || true
echo "=== tools ==="
command -v parted; command -v blkid; command -v mkfs.ext4; command -v partprobe; command -v partx
echo "=== parted free ==="
parted -m -s /dev/sda unit MiB print free 2>&1
echo "=== fstab ==="
uci show fstab 2>&1
echo "=== lede-data enabled ==="
/etc/init.d/lede-data enabled; echo exit=$?
END_REMOTE
)"
router_print
