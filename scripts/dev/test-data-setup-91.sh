#!/bin/sh
# macOS port of test-data-setup-91.ps1. Talks to the router over LuCI ubus.
# Usage: ./test-data-setup-91.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=300

# Test lede-data-setup on 192.168.9.1 (offline gdisk install + one-shot run).

router_open "${1:-192.168.9.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

IPK=$(mktemp)
trap 'rm -f "$IPK"' EXIT
curl -fsSL -o "$IPK" 'https://mirrors.tencent.com/lede/releases/24.10.5/packages/x86_64/packages/gdisk_1.0.10-r1_x86_64.ipk'
router_put "$IPK" '/tmp/gdisk.ipk'

router_put "$ROOT/files/usr/libexec/lede-data-setup" '/usr/libexec/lede-data-setup'

router_sh "$(cat <<'END_REMOTE'
rm -f /etc/.lede-data-init.done
rm -f /var/lock/opkg.lock
killall -9 opkg 2>/dev/null || true
opkg install /tmp/gdisk.ipk >/tmp/opkg-install.log 2>&1
echo opkg-install-exit=$?
tail -10 /tmp/opkg-install.log
command -v sgdisk || echo sgdisk=MISSING
END_REMOTE
)"
router_print
if ! printf '%s\n' "$(router_stdout)" | grep -q '/sgdisk'; then
	echo "ERROR: sgdisk not installed" >&2
	exit 1
fi
router_sh "$(cat <<'END_REMOTE'
/usr/libexec/lede-data-setup; echo setup-exit=$?
echo "=== init done marker ==="
ls -la /etc/.lede-data-init.done 2>&1
echo "=== script retired? ==="
ls -la /usr/libexec/lede-data-setup 2>&1
echo "=== log ==="
cat /tmp/lede-data-setup.log 2>&1
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
echo "=== df /data ==="
df -h /data 2>&1 || echo no-data
echo "=== fstab data ==="
uci show fstab | grep -E 'target=.*/data|uuid=.*' || uci show fstab
echo "=== marker ==="
ls -la /data/.lede-data 2>&1
END_REMOTE
)"
router_print
